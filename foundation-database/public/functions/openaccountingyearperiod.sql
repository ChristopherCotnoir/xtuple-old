
CREATE OR REPLACE FUNCTION openAccountingYearPeriod(INTEGER) RETURNS INTEGER AS $$
-- Copyright (c) 1999-2014 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  pYearPeriodId ALIAS FOR $1;
  _r RECORD;

BEGIN

--  Check to make use that the yearperiod is closed
  IF ( ( SELECT (NOT yearperiod_closed)
         FROM yearperiod
         WHERE (yearperiod_id=pYearPeriodId) ) ) THEN
    RAISE EXCEPTION '[xtuple: openAccountingYearPeriod, -1]';
  END IF;

  IF ( ( SELECT (count(yearperiod_id) > 0)
           FROM yearperiod
          WHERE ((yearperiod_end> (
            SELECT yearperiod_end 
            FROM yearperiod 
            WHERE (yearperiod_id=pYearPeriodId))
          )
           AND (yearperiod_closed)) ) ) THEN
    RAISE EXCEPTION 'Cannot open this Accounting Year because subsequent years are closed. [xtuple: openAccountingYearPeriod, -2]';
  END IF;

--  Reset the yearperiod_closed flag
  UPDATE yearperiod
  SET yearperiod_closed=FALSE
  WHERE (yearperiod_id=pYearPeriodId);

  RETURN pYearPeriodid;

END;
$$ LANGUAGE 'plpgsql';

