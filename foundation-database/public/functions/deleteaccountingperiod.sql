
CREATE OR REPLACE FUNCTION deleteAccountingPeriod(INTEGER) RETURNS INTEGER AS $$
-- Copyright (c) 1999-2014 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  pPeriodid ALIAS FOR $1;
  _check RECORD;

BEGIN

--  Check to make sure that the passed period is not closed
  IF ( ( SELECT period_closed
         FROM period
         WHERE (period_id=pPeriodid) ) ) THEN
    RAISE EXCEPTION '[xtuple: deleteAccountingPeriod, -1]';
  END IF;

--  Check to make sure that there are not any posted G/L Transactions
--  in the period.
  SELECT gltrans_id INTO _check
  FROM gltrans, period
  WHERE ( (gltrans_date BETWEEN period_start AND period_end)
   AND (gltrans_posted)
   AND (period_id=pPeriodid) )
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Accounting Period has G/L Transactions posted against it and, thus, cannot be deleted. [xtuple: deleteAccountingPeriod, -4]';
  END IF;

  SELECT b.period_id INTO _check
    FROM period AS a, period AS b
   WHERE((a.period_id=pPeriodid)
     AND (a.period_end < b.period_start))
   LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Accounting Period is not the last accounting period and cannot be deleted. [xtuple: deleteAccountingPeriod, -5]';
  END IF;

--  Delete the period
  DELETE FROM period
  WHERE (period_id=pPeriodid);

--  Also Delete the period from TrialBalance
  DELETE FROM trialbal
  WHERE (trialbal_period_id=pPeriodid);

  RETURN 1;

END;
$$ LANGUAGE 'plpgsql';

