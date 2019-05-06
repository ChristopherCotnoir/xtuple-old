#!/usr/bin/env node

/*jshint node:true, indent:2, curly:false, eqeqeq:true, immed:true, latedef:true, newcap:true, noarg:true,
regexp:true, undef:true, strict:true, trailing:true, white:true */
/*global X:true, Backbone:true, _:true, XM:true, XT:true, SYS:true, jsonpatch:true*/
process.chdir(__dirname);

Backbone = require("backbone");
_ = require("underscore");
jsonpatch = require("json-patch");
SYS = {};
XT = { };

var express = require('express'),
  async = require("async"),
  app;

(function () {
  "use strict";

  var options = require("./lib/options"),
    fs = require('fs'),
    schemaSessionOptions = {},
    privSessionOptions = {};

  /**
   * Include the X framework.
   */
  require("./xt");

  // Loop through files and load the dependencies.
  // Apes the enyo package process
  // TODO: it would be nice to use a more standardized way
  // of loading our libraries (tools and backbone-x) here
  // in node.
  X.relativeDependsPath = "";
  X.depends = function () {
    var dir = X.relativeDependsPath,
      files = X.$A(arguments),
      pathBeforeRecursion;

    _.each(files, function (file) {
      if (X.fs.statSync(X.path.join(dir, file)).isDirectory()) {
        pathBeforeRecursion = X.relativeDependsPath;
        X.relativeDependsPath = X.path.join(dir, file);
        X.depends("package.js");
        X.relativeDependsPath = pathBeforeRecursion;
      } else {
        require(X.path.join(dir, file));
      }
    });
  };


  // Load other xTuple libraries using X.depends above.
  require("backbone-relational");
  X.relativeDependsPath = X.path.join(process.cwd(), "../lib/tools/source");
  require("../lib/tools");
  X.relativeDependsPath = X.path.join(process.cwd(), "../lib/backbone-x/source");
  require("../lib/backbone-x");
  Backbone.XM = XM;

  // Argh!!! Hack because `XT` has it's own string format function that
  // is incompatible with `X`....
  String.prototype.f = function () {
    return X.String.format.apply(this, arguments);
  };

  // Another hack: quiet the logs here.
  XT.log = function () {};

  // Set the options.
  X.setup(options);

  // load some more required files
  var datasource = require("./lib/ext/datasource");
  require("./lib/ext/models");
  require("./lib/ext/smtp_transport");

  datasource.setupPgListeners(X.options.datasource.databases, {
    email: X.smtpTransport.sendMail
  });

  // load the encryption key, or create it if it doesn't exist
  // it should created just once, the very first time the datasoruce starts
  var encryptionKeyFilename = X.options.datasource.encryptionKeyFile || './lib/private/encryption_key.txt';
  X.fs.exists(encryptionKeyFilename, function (exists) {
    if (exists) {
      X.options.encryptionKey = X.fs.readFileSync(encryptionKeyFilename, "utf8");
    } else {
      X.options.encryptionKey = Math.random().toString(36).slice(2);
      X.fs.writeFile(encryptionKeyFilename, X.options.encryptionKey);
    }
  });

  XT.session = Object.create(XT.Session);
  XT.session.schemas.SYS = false;

  var getExtensionDir = function (extension) {
    var dirMap = {
      "/private-extensions": X.path.join(__dirname, "../..", extension.location, "source", extension.name),
      "/xtuple-extensions": X.path.join(__dirname, "../..", extension.location, "source", extension.name),
      "npm": X.path.join(__dirname, "../node_modules", extension.name)
    };

    if (dirMap[extension.location]) {
      return dirMap[extension.location];
    } else if (extension.location !== 'not-applicable') {
      return X.path.join(__dirname, "../..", extension.location);
    } else {
      X.err("Cannot get a path for extension: " + extension.name + " Invalid location: " + extension.location);
      return;
    }
  };
  var loadExtensionServerside = function (extension) {
    var packagePath = X.path.join(getExtensionDir(extension), "package.json");
    var packageJson = X.fs.existsSync(packagePath) ? require(packagePath) : undefined;
    var manifestPath = X.path.join(getExtensionDir(extension), "database/source/manifest.js");
    var manifest = X.fs.existsSync(manifestPath) ? JSON.parse(X.fs.readFileSync(manifestPath)) : {};
    var version = packageJson ? packageJson.version : manifest.version;
    X.versions[extension.name] = version || "none"; // XXX the "none" is temporary until we have core extensions in npm

    // TODO: be able to define routes in package.json
    _.each(manifest.routes || [], function (routeDetails) {
      var verb = (routeDetails.verb || "all").toLowerCase(),
        filePath = X.path.join(getExtensionDir(extension), "node-datasource", routeDetails.filename),
        func = routeDetails.functionName ? require(filePath)[routeDetails.functionName] : null;

      if (_.contains(["all", "get", "post", "patch", "delete", "use"], verb)) {
        if (func) {
          app[verb]('/:org/' + routeDetails.path, func);
        } else {
          _.each(X.options.datasource.databases, function (orgValue, orgKey, orgList) {
            app[verb]("/" + orgValue + "/" + routeDetails.path, express.static(filePath, { maxAge: 86400000 }));
          });
        }
      } else if (verb === "no-route") {
        func();
      } else {
        console.log("Invalid verb (" + verb + ") for extension-defined route " + routeDetails.path);
      }
    });
  };

  schemaSessionOptions.username = X.options.databaseServer.user;
  schemaSessionOptions.database = X.options.datasource.databases[0];
  // XXX note that I'm not addressing an underlying bug that we don't wait to
  // listen on the port until all the setup is done
  schemaSessionOptions.success = function () {
    if (!SYS) {
      return;
    }
    var extensions = new SYS.ExtensionCollection();
    extensions.fetch({
      database: X.options.datasource.databases[0],
      success: function (coll, results, options) {
        if (!app) {
          // XXX time bomb: assuming app has been initialized, below, by now
          XT.log("Could not load extension routes or client-side code because the app has not started");
          process.exit(1);
          return;
        }
        _.each(results, loadExtensionServerside);
      }
    });
  };
  XT.session.loadSessionObjects(XT.session.SCHEMA, schemaSessionOptions);

  privSessionOptions.username = X.options.databaseServer.user;
  privSessionOptions.database = X.options.datasource.databases[0];
  XT.session.loadSessionObjects(XT.session.PRIVILEGES, privSessionOptions);

  var cacheCount = 0;
  var cacheShareUsersWarmed = function (err, result) {
    if (err) {
      X.log("Share Users Cache warming errors:", err);
      console.trace("Share Users Cache warming errors:");
    } else {
      cacheCount++;
      if (cacheCount === X.options.datasource.databases.length) {
        X.log("All Share Users Caches have been warmed.");
      }
    }
  };

  var warmCacheShareUsers = function (dbVal, callback) {
    var cacheShareUsersOptions = {
      user: X.options.databaseServer.user,
      port: X.options.databaseServer.port,
      hostname: X.options.databaseServer.hostname,
      database: dbVal,
      password: X.options.databaseServer.password
    };

    X.log("Warming Share Users Cache for database " + dbVal + "...");
    datasource.api.query('select xt.refresh_share_user_cache()', cacheShareUsersOptions, cacheShareUsersWarmed);
  };

  async.map(X.options.datasource.databases, warmCacheShareUsers);

}());


/**
  Grab the version number from the package.json file.
 */

var packageJson = X.fs.readFileSync("../package.json");
X.versions = {
  core: JSON.parse(packageJson).version
};

/**
 * Module dependencies.
 */
var passport = require('passport'),
  oauth2 = require('./oauth2/oauth2'),
  routes = require('./routes/routes'),
  utils = require('./oauth2/utils'),
  user = require('./oauth2/user'),
  destroySession;

// TODO - for testing. remove...
//http://stackoverflow.com/questions/13091037/node-js-heap-snapshots-and-google-chrome-snapshot-viewer
//var heapdump = require("heapdump");
// Use it!: https://github.com/c4milo/node-webkit-agent
//var agent = require('webkit-devtools-agent');

/**
 * ###################################################
 * Overrides section.
 *
 * Sometimes we need to change how an npm packages works.
 * Don't edit the packages directly, override them here.
 * ###################################################
 */

/**
  Define our own authentication criteria for passport. Passport itself defines
  its authentication function here:
  https://github.com/jaredhanson/passport/blob/master/lib/passport/http/request.js#L74
  We are stomping on that method with our own special business logic.
  The ensureLoggedIn function will not need to be changed, because that calls this.
 */
require('http').IncomingMessage.prototype.isAuthenticated = function () {
  "use strict";

  var creds = this.session.passport.user;

  if (creds && creds.id && creds.username && creds.organization) {
    return true;
  } else {
    destroySession(this.sessionID, this.session);
    return false;
  }
};

// Stomping on express/connect's Cookie.prototype to only update the expires property
// once a minute. Otherwise it's hit on every session check. This cuts down on chatter.
// See more details here: https://github.com/senchalabs/connect/issues/670
require('express/node_modules/connect/lib/middleware/session/cookie').prototype.__defineSetter__("expires", require('./stomps/expires').expires);

// Stomp on Express's cookie serialize() to not send an "expires" value to the browser.
// This makes the browser cooke a "session" cookie that will never expire and only
// gets removed when the user closes the browser. We still set express.session.cookie.maxAge
// below so our persisted session gets an expires value, but not the browser cookie.
// See this issue for more details: https://github.com/senchalabs/connect/issues/328
require('express/node_modules/cookie').serialize = require('./stomps/cookie').serialize;

// Stomp on Connect's session.
// https://github.com/senchalabs/connect/issues/641
function stompSessionLoad() {
  "use strict";
  return require('./stomps/session');
}
require('express/node_modules/connect').middleware.__defineGetter__('session', stompSessionLoad);
require('express/node_modules/connect').__defineGetter__('session', stompSessionLoad);
require('express').__defineGetter__('session', stompSessionLoad);

/**
 * ###################################################
 * END Overrides section.
 * ###################################################
 */

//
// Load the ssl data
//
var sslOptions = {};

sslOptions.key = X.fs.readFileSync(X.options.datasource.keyFile);
if (X.options.datasource.caFile) {
  sslOptions.ca = _.map(X.options.datasource.caFile, function (obj) {
    "use strict";

    return X.fs.readFileSync(obj);
  });
}
sslOptions.cert = X.fs.readFileSync(X.options.datasource.certFile);

/**
 * Express configuration.
 */
app = express();

var server = X.https.createServer(sslOptions, app),
  parseSignedCookie = require('express/node_modules/connect').utils.parseSignedCookie,
  //MemoryStore = express.session.MemoryStore,
  XTPGStore = require('./oauth2/db/connect-xt-pg')(express),
  //sessionStore = new MemoryStore(),
  sessionStore = new XTPGStore({ hybridCache: X.options.datasource.requireCache || false }),
  Session = require('express/node_modules/connect/lib/middleware/session').Session,
  Cookie = require('express/node_modules/connect/lib/middleware/session/cookie'),
  cookie = require('express/node_modules/cookie'),
  privateSalt = X.fs.readFileSync(X.options.datasource.saltFile).toString() || 'somesecret';

// Conditionally load express.session(). REST API endpoints using OAuth tokens do not get sessions.
var conditionalExpressSession = function (req, res, next) {
  "use strict";

  var key;

  // REST API endpoints start with "/api" in their path.
  // The 'assets' folder and login page are sessionless.
  if ((/^api/i).test(req.path.split("/")[2]) ||
      (/^\/assets/i).test(req.path) ||
      (/^\/javascript/i).test(req.path) ||
      (/^\/stylesheets/i).test(req.path) ||
      req.path === '/' ||
      req.path === '/favicon.ico' ||
      req.path === '/forgot-password' ||
      req.path === '/assets' ||
      req.path === '/recover') {

    next();
  } else {
    if (req.path === "/login") {
      // TODO - Add check against X.options database array
      key = req.body.database + ".sid";
    } else if (req.path.split("/")[1]) {
      key = req.path.split("/")[1] + ".sid";
    } else {
      // TODO - Dynamically name the cookie after the database.
      console.log("### FIX ME ### setting cookie name to 'connect.sid' for path = ", JSON.stringify(req.path));
      console.log("### FIX ME ### cookie name should match database name!!!");
      console.trace("### At this location ###");
      key = 'connect.sid';
    }

    // Instead of doing app.use(express.session()) we call the package directly
    // which returns a function (req, res, next) we can call to do the same thing.
    var init_session = express.session({
        key: key,
        store: sessionStore,
        secret: privateSalt,
        // See cookie stomp above for more details on how this session cookie works.
        cookie: {
          path: '/',
          httpOnly: true,
          secure: true,
          maxAge: (X.options.datasource.sessionTimeout * 60 * 1000) || 3600000
        },
        sessionIDgen: function () {
          // TODO: Stomp on connect's sessionID generate.
          // https://github.com/senchalabs/connect/issues/641
          return key.split(".")[0] + "." + utils.generateUUID();
        }
      });

    init_session(req, res, next);
  }
};

// Conditionally load passport.session(). REST API endpoints using OAuth tokens do not get sessions.
var conditionalPassportSession = function (req, res, next) {
  "use strict";

  // REST API endpoints start with "/api" in their path.
  // The 'assets' folder and login page are sessionless.
  if ((/^api/i).test(req.path.split("/")[2]) ||
    (/^\/assets/i).test(req.path) ||
    req.path === "/" ||
    req.path === "/favicon.ico"
    ) {

    next();
  } else {
    // Instead of doing app.use(passport.session())
    var init_passportSessions = passport.session();

    init_passportSessions(req, res, next);
  }
};

app.configure(function () {
  "use strict";

  // gzip all static files served.
  app.use(express.compress());

  // Add a basic view engine that will render files from "views" directory.
  app.set('view engine', 'ejs');

  // TODO - This outputs access logs like apache2 and some other user things.
  //app.use(express.logger());

  app.use(express.cookieParser());
  if (X.options.datasource.useBodyParser) {
    X.warn('Starting insecure Express.js app() server using bodyParser().');
    X.warn('This should be avoided. Set "useBodyParser: false" in config.js');
    X.warn('See: https://groups.google.com/forum/#!msg/express-js/iP2VyhkypHo/5AXQiYN3RPcJ');

    app.use(express.bodyParser());
  } else {
    app.use(express.json({limit: X.options.datasource.jsonLimit || '1mb'}));
    app.use(express.urlencoded({limit: X.options.datasource.urlencodeLimit || '1mb'}));
  }

  // Conditionally load session packages. Based off these examples:
  // http://stackoverflow.com/questions/9348505/avoiding-image-logging-in-express-js/9351428#9351428
  // http://stackoverflow.com/questions/13516898/disable-csrf-validation-for-some-requests-on-express
  app.use(conditionalExpressSession);
  app.use(passport.initialize());
  app.use(conditionalPassportSession);

  app.use(app.router);
  app.use(express.errorHandler({ dumpExceptions: true, showStack: true }));
});

/**
 * Passport configuration.
 */
require('./oauth2/passport');

/**
 * Setup HTTP routes and handlers.
 */
var that = this;

/* Static assets */
app.use(express.favicon(__dirname + '/views/assets/favicon.ico'));
app.use('/assets', express.static('views/assets', { maxAge: 86400000 }));
app.use('/javascript', express.static('views/javascript', { maxAge: 86400000 }));
app.use('/stylesheets', express.static('views/stylesheets', { maxAge: 86400000 }));

app.get('/:org/dialog/authorize', oauth2.authorization);
app.post('/:org/dialog/authorize/decision', oauth2.decision);
app.post('/:org/oauth/token', oauth2.token);

app.get('/:org/discovery/v1alpha1/apis/v1alpha1/rest', routes.restDiscoveryGetRest);
app.get('/:org/discovery/v1alpha1/apis/:model/v1alpha1/rest', routes.restDiscoveryGetRest);
app.get('/:org/discovery/v1alpha1/apis', routes.restDiscoveryList);

app.get('/:org/api/userinfo', user.info);

app.post('/:org/api/v1alpha1/services/:service/:id', routes.restRouter);
app.all('/:org/api/v1alpha1/resources/:model/:id', routes.restRouter);
app.all('/:org/api/v1alpha1/resources/:model', routes.restRouter);
app.all('/:org/api/v1alpha1/resources/*', routes.restRouter);

app.get('/', routes.loginForm);
app.post('/login', routes.login);
app.get('/forgot-password', routes.forgotPassword);
app.post('/recover', routes.recoverPassword);
app.get('/:org/recover/reset/:id/:token', routes.verifyRecoverPassword);
app.post('/:org/recover/resetUpdate', routes.resetRecoveredPassword);
app.get('/login/scope', routes.scopeForm);
app.post('/login/scopeSubmit', routes.scope);
app.get('/logout', routes.logout);
app.get('/:org/logout', routes.logout);

app.all('/:org/change-password', routes.changePassword);
app.all('/:org/email', routes.email);
app.get('/:org/reset-password', routes.resetPassword);
app.post('/:org/oauth/revoke-token', routes.revokeOauthToken);

// Set up the other servers we run on different ports.
var redirectServer = express();
redirectServer.get(/.*/, routes.redirect); // RegEx for "everything"
redirectServer.listen(X.options.datasource.redirectPort, X.options.datasource.bindAddress);

/**
 * Destroy a single session.
 * @param {Object} val - Session object.
 * @param {String} key - Session id.
 */
destroySession = function (key, val) {
  "use strict";

  var sessionID;

  sessionID = key.replace(sessionStore.prefix, '');

  // Destroy session here incase the client never hits /logout.
  sessionStore.destroy(sessionID, function (err) {
    //X.debug("Session destroied: ", key, " error: ", err);
  });
};

/**
 * Job loading section.
 *
 * The following are jobs that must be started at start up or scheduled to run periodically.
 */

// TODO - Check pid file to see if this is already running.
// Kill process or create new pid file.

// Run the expireSessions cleanup/garbage collection once a minute.
setInterval(function () {
    "use strict";

    //X.debug("session cleanup called at: ", new Date());
    sessionStore.expireSessions(destroySession);
  }, 60000);

server.listen(X.options.datasource.port, X.options.datasource.bindAddress);
X.log("Server listening at: ", X.options.datasource.bindAddress);
X.log("node-datasource started on port: ", X.options.datasource.port);
X.log("redirectServer started on port: ", X.options.datasource.redirectPort);
X.log("Databases accessible from this server: \n", JSON.stringify(X.options.datasource.databases, null, 2));
