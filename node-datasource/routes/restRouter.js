/*jshint node:true, indent:2, curly:false, eqeqeq:true, immed:true, latedef:true, newcap:true,
noarg:true, regexp:true, undef:true, strict:true, trailing:true, white:true */
/*global XT:true, X:true, _:true */

var routes = require("./routes"),
  _ = require("underscore"),
  restQueryFormat = require("../lib/rest-query-format");

/**
 * @class RestRouter
 * @singleton
 */
module.exports = (function () {
  "use strict";

  var getIsRestORMsStore,
    getResourcesStore,
    getServicesStore,
    handlers = {

      /**
       * @private
       * Requests a representation of the specified resource.
       */
      GET: function (req, res, session, options) {
        var callback = options.callback,
          payload = {
            nameSpace: "XM",
            type: options.ormType
          },
          error;

        if (options.id) {
          payload.id = options.id;
          return routes.queryDatabase("get", payload, session, callback);
        } else {
          // Format a complex REST API query structure into an xTuple's datasource database query.
          payload.query = restQueryFormat(payload.nameSpace + "." + payload.type, req.url, req.query);
          if (payload.query) {
            return routes.queryDatabase("get", payload, session, callback);
          } else {
            error = {message: "Bad Request", code: 400};
          }
        }

        return res.json(error.code, error.message);
      },

      /**
       * @private
       * Requests that the server accept the entity enclosed in the request as a
       * new subordinate of the web resource identified by the URI.
       * POST method can also call dispatch functions for "Service" endpoints.
       */
      POST: function (req, res, session, options) {
        var body = _.clone(req.body),
          serviceModel = options.serviceModel,
          services = options.services,
          id = options.id ? options.id.camelize() : null,
          ormType = options.ormType,
          callback = options.callback,
          payload = {};

        if (serviceModel) {
          payload = {
            nameSpace: "XM",
            type: ormType,
            dispatch: serviceModel && {
              functionName: id,
              parameters: req.body.attributes
            }
          };
        } else {

          if (!req.body) {
            return res.send(400, "Bad Request");
          }

          payload = {
            nameSpace: "XM",
            type: ormType,
            data: req.body
          };
        }

        routes.queryDatabase("post", payload, session, callback);
      },

      /**
       * @private
       * TODO implement
       */
      PUT: null,

      /**
       * Deletes the specified resource.
       * @private
       */
      DELETE: function (req, res, session, options) {
        var id = options.id,
          ormType = options.ormType,
          callback = options.callback,
          payload = { };
        if (!id) {
          return res.send(404, "Not Found");
        }

        payload.nameSpace = "XM";
        payload.type = ormType;
        payload.id = id + "";

        routes.queryDatabase("delete", payload, session, callback);
      },

      /**
       * Apply partial modifications to a resource.
       * @private
       */
      PATCH: function (req, res, session, options) {
        var id = options.id,
          ormType = options.ormType,
          callback = options.callback,
          payload = { };

        if (!id || !req.body || !req.body.etag || !req.body.patches) {
          return res.send(404, "Not Found");
        }

        payload.nameSpace = "XM";
        payload.type = ormType;
        payload.id = id + "";
        payload.etag = req.body.etag;
        payload.patches = req.body.patches;

        routes.queryDatabase("patch", payload, session, callback);
      },

      /**
       * Returns the HTTP methods that the server supports for specified URL.
       * This can be used to check the functionality of a web server by requesting "*" instead
       * of a specific resource.
       * TODO - call options method.
       * @private
       */
      OPTIONS: function (req, res, session, options) {
        var ormType = options.ormType;
        return res.send("REST API OPTIONS call to ormType: " + ormType);
      },

      /**
       * Asks for the response identical to the one that would correspond to a GET request,
       * but without the response body. This is useful for retrieving meta-information written
       * in response headers, without having to transport the entire content.
       * TODO - call head method.
       * @private
       */
      HEAD: function (req, res, session, options) {
        return res.send();
      }
    },

    /**
     * @private
     */
    _getResources = function (req, res, next, orms) {
      var rootUrl = req.protocol + "://" + req.host + "/",
        session = getSession(req, next),
        payload = {
          nameSpace: "XT",
          type: "Discovery",
          dispatch: {
            functionName: "getResources",
            parameters: [null, rootUrl]
          }
        },
        callback = function (result) {
          if (result.isError) {
            return next(new Error("Invalid Request."));
          }

          getResourcesStore = result.data;
          _getServices(req, res, next, orms, result.data);
        };

      if (getResourcesStore) {
        _getServices(req, res, next, orms, getResourcesStore);
      } else {
        routes.queryDatabase("post", payload, session, callback);
      }
    },

    /**
     * @private
     */
    _getServices = function (req, res, next, orms, resources) {
      var rootUrl = req.protocol + "://" + req.host + "/",
        payload = {
          nameSpace: "XT",
          type: "Discovery",
          dispatch: {
            functionName: "getServices",
            parameters: [null, rootUrl, true]
          }
        },
        session = getSession(req, next),
        callback = function (result) {
          if (result.isError) {
            return next(new Error("Invalid Request."));
          }

          getServicesStore = result.data;
          routeCall(req, res, next, orms, resources, result.data);
        };

      if (getServicesStore) {
        routeCall(req, res, next, orms, resources, getServicesStore);
      } else {
        routes.queryDatabase("post", payload, session, callback);
      }
    },

    /**
     * @private
     */
    routeCall = function (req, res, next, orms, resources, services) {
      var ormType,
        resourceModel,
        serviceModel,
        session = getSession(req, next),
        callback = function (resp) {
          if (resp.isError) {
            // Google style error object. TODO functionize this
            return res.json(resp.status.code, {
              error: {
                code: resp.status.code,
                message: resp.status.message,
                errors: [ { message: resp.status.message } ]
              }
            });
          } else {
            return res.json(resp.status.code, resp);
          }
        };

      if (!req.params.model && !req.params.service) {
        return res.send(404, "Not Found");
      }

      if (req.params.model) {
        ormType = req.params.model.camelize().capitalize();
        resourceModel = _.findWhere(orms, { orm_type: ormType });
      } else if (req.params.service) {
        ormType = req.params.service.camelize().capitalize();
        serviceModel  = _.contains(_.keys(services), ormType);
      }

      if (!(resourceModel || serviceModel)) {
        return res.send(404, "Not Found");
      }

      // handle request
      // TODO express naturally handles request method routing
      var handler = handlers[req.method];
      if (!_.isFunction(handler)) {
        return res.send(405, "Method Not Allowed");
      }
      else {
        handler(req, res, session, {
          ormType: ormType,
          id: req.params.id,
          serviceModel: serviceModel || null,
          services: services,
          callback: callback
        });
      }
    };

  /**
   * @public
   */
  function getIsRestORMs(req, res, next) {
    var payload = {
        nameSpace: "XT",
        type: "Discovery",
        dispatch: {
          functionName: "getIsRestORMs"
        }
      },
      session = getSession(req, next),
      callback = function (result) {
        if (result.isError) {
          return next(new Error("Invalid Request."));
        }

        getIsRestORMsStore = result.data;
        _getResources(req, res, next, result.data);
      };

    if (getIsRestORMsStore) {
      _getResources(req, res, next, getIsRestORMsStore);
    } else {
      routes.queryDatabase("post", payload, session, callback);
    }
  }

  /**
   * Create a datasource session object
   */
  function getSession(req, next) {
    return {
      passport: getPassport(req.user.get("username") ? req.user : req.session.passport.user, next)
    };
  }

  /**
   * Create a session passport object given a req.user
   */
  function getPassport(user, next) {
    if (!user) return next(new Error("user is not defined"));
    return {
      user: {
        id: user.get ? user.get("username") : user.username,
        username: user.get ? user.get("username") : user.username,
        organization: user.get ? user.get("organization") : user.organization
      }
    };
  }

  return {
    router: [getIsRestORMs]
  };
})();
