var _      = require('underscore'),
    assert = require('chai').assert,
    dblib  = require('../dblib');

(function () {
  'use strict';

  describe('applyARCreditMemoToBalance()', function () {

    var adminCred  = dblib.adminCred,
        datasource = dblib.datasource,
        aropensucceed
        ;

    it("needs a failing aropen record", function(done) {
      var sql = "INSERT INTO aropen (" +
                " aropen_docdate, aropen_duedate, aropen_docnumber," +
                " aropen_amount, aropen_paid," +
                " aropen_curr_rate)" +
                " VALUES (" +
                " CURRENT_DATE, CURRENT_DATE, '1'," +
                " 1.0, 2.0," +
                " 1.0)" +
                " RETURNING aropen_id;";
      datasource.query(sql, adminCred, function (err, res) {
        dblib.assertErrorCode(err, res, "_aropenTrigger", -5);
        done();
      });
    });

    it("needs a succeeding aropen record", function(done) {
      var sql = "SELECT aropen_id FROM aropen" +
                " LIMIT 1;";
      datasource.query(sql, adminCred, function (err, res) {
        assert.isNull(err);
        aropensucceed = res.rows[0].aropen_id;
        done();
      });
    });

    it("should run without error", function (done) {
      var sql = "SELECT applyARCreditMemoToBalance($1) AS result;",
          cred = _.extend({}, adminCred,
                          { parameters: [ aropensucceed ] });

      datasource.query(sql, cred, function (err, res) {
        assert.isNull(err);
        assert.equal(res.rows[0].result, 1);
        done();
      });
    });
  });
})();
