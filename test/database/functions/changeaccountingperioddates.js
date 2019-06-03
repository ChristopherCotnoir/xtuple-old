var _      = require('underscore'),
    assert = require('chai').assert,
    dblib  = require('../dblib');

(function () {
  'use strict';

  describe('changeAccountingPeriodDates()', function () {

    var adminCred  = dblib.adminCred,
        datasource = dblib.datasource,
        periodfail,
        periodsucceed,
        periodsucceedstart,
        periodsucceedend,
        startfail,
        periodfail2,
        periodfail2end,
        startfail2,
        startsucceed,
        endfail,
        endsucceed
        ;

    it("needs a failing period record", function(done) {
      var sql = "SELECT period_id" +
                " FROM period" +
                " WHERE period_closed" +
                " LIMIT 1;";
      datasource.query(sql, adminCred, function (err, res) {
        assert.isNull(err);
        periodfail = res.rows[0].period_id;
        done();
      });
    });

    it("needs a succeeding period record", function(done) {
      var sql = "SELECT period_id, period_start, period_end FROM period this"
              + " WHERE NOT period_closed"
              + "   AND NOT EXISTS(SELECT 1 FROM gltrans"
              + "                   WHERE gltrans_date=period_start"
              + "                      OR gltrans_date=period_end)"
              + "   AND EXISTS(SELECT 1 FROM gltrans"
              + "               WHERE gltrans_date BETWEEN period_start AND period_end)"
              + "   AND EXISTS(SELECT 1 FROM period older"
              + "               WHERE older.period_start < this.period_start)"
              + "   AND EXISTS(SELECT 1 FROM period newer"
              + "               WHERE newer.period_start > this.period_start)"
              + " LIMIT 1;";
      datasource.query(sql, adminCred, function (err, res) {
        assert.isNull(err);
        periodsucceed = res.rows[0].period_id;
        periodsucceedstart = res.rows[0].period_start;
        periodsucceedend = res.rows[0].period_end;
        done();
      });
    });

    it("needs a failing start date", function(done) {
      var sql = "SELECT max(period_end) - interval '1 day' AS date" +
                "  FROM period" +
                " WHERE period_end < (SELECT period_start FROM period WHERE period_id=$1);",
          cred = _.extend({}, adminCred, { parameters: [ periodsucceed ] });

      datasource.query(sql, cred, function (err, res) {
        assert.isNull(err);
        startfail = res.rows[0].date;
        done();
      });
    });

    it("needs another failing start date due to existing G/L trans", function(done) {
      var sql = "SELECT"
              + "  period_id,"
              + "  period_end,"
              + "  MIN(gltrans_date) + 1 AS date"
              + "   FROM period JOIN gltrans ON gltrans_date BETWEEN period_start AND period_end"
              + "  WHERE NOT period_closed"
              + "  GROUP BY "
              + "  period_id,"
              + "  period_start,"
              + "  period_end"
              + "  LIMIT 1;";

      datasource.query(sql, adminCred, function (err, res) {
        assert.isNull(err);
        assert.isNotNull(res.rows[0].date);
        periodfail2 = res.rows[0].period_id;
        periodfail2end = res.rows[0].period_end;
        startfail2 = res.rows[0].date;
        done();
      });
    });

    it("needs a succeeding start date", function(done) {
      var sql = "SELECT period_start+1 AS date" +
                " FROM period" +
                " WHERE period_id=$1",
          cred = _.extend({}, adminCred,
                          { parameters: [ periodsucceed ] });

      datasource.query(sql, cred, function (err, res) {
        assert.isNull(err);
        startsucceed = res.rows[0].date;
        done();
      });
    });

    it("needs a failing end date", function(done) {
      var sql = "SELECT MIN(period_start) + 1 AS date" +
                "  FROM period" +
                " WHERE period_start > (SELECT period_end FROM period WHERE period_id = $1);",
          cred = _.extend({}, adminCred,
                          { parameters: [ periodsucceed ] });

      datasource.query(sql, cred, function (err, res) {
        assert.isNull(err);
        endfail = res.rows[0].date;
        done();
      });
    });

    it("needs a succeeding end date", function(done) {
      var sql = "SELECT period_end-1 AS date" +
                " FROM period" +
                " WHERE period_id=$1",
          cred = _.extend({}, adminCred,
                          { parameters: [ periodsucceed ] });

      datasource.query(sql, cred, function (err, res) {
        assert.isNull(err);
        endsucceed = res.rows[0].date;
        done();
      });
    });

    it("should fail for closed periods", function(done) {
      var sql = "SELECT changeAccountingPeriodDates($1, $2, $3) AS result;",
          cred = _.extend({}, adminCred,
                          { parameters: [ periodfail,
                                          startsucceed,
                                          endsucceed ] });

      datasource.query(sql, cred, function (err, res) {
        dblib.assertErrorCode(err, res, "changeAccountingPeriodDates", -1);
        done();
      });
    });

    it("should fail if the start date falls in another period", function(done) {
      var sql = "SELECT changeAccountingPeriodDates($1, $2, $3) AS result;",
          cred = _.extend({}, adminCred,
                          { parameters: [ periodsucceed,
                                          startfail,
                                          endsucceed ] });

      datasource.query(sql, cred, function (err, res) {
        dblib.assertErrorCode(err, res, "changeAccountingPeriodDates", -2);
        done();
      });
    });

    it("should fail if the end date falls in another period", function(done) {
      var sql = "SELECT changeAccountingPeriodDates($1, $2, $3) AS result;",
          cred = _.extend({}, adminCred,
                          { parameters: [ periodsucceed,
                                          startsucceed,
                                          endfail ] });

      datasource.query(sql, cred, function (err, res) {
        dblib.assertErrorCode(err, res, "changeAccountingPeriodDates", -3);
        done();
      });
    });

    it("should fail if new dates would orphan a posted G/L transaction", function(done) {
      var sql = "SELECT changeAccountingPeriodDates($1, $2, $3) AS result;",
          cred = _.extend({}, adminCred,
                          { parameters: [ periodfail2,
                                          startfail2,
                                          periodfail2end ] });

      datasource.query(sql, cred, function (err, res) {
        dblib.assertErrorCode(err, res, "changeAccountingPeriodDates", -4);
        done();
      });
    });

    it("should run without error", function (done) {
      var sql = "SELECT changeAccountingPeriodDates($1, $2, $3) AS result;",
          cred = _.extend({}, adminCred,
                          { parameters: [ periodsucceed,
                                          startsucceed,
                                          endsucceed ] });

      datasource.query(sql, cred, function (err, res) {
        assert.isNull(err);
        assert.equal(res.rows[0].result, 1);
        done();
      });
    });

    after(function (done) {
      var sql = "SELECT changeAccountingPeriodDates($1, $2, $3) AS result;",
          cred = _.extend({}, adminCred,
                          { parameters: [ periodsucceed,
                                          periodsucceedstart,
                                          periodsucceedend ] });

      datasource.query(sql, cred, function (err, res) {
        assert.isNull(err);
        assert.equal(res.rows[0].result, 1);
        done();
      });
    });

  });
})();
