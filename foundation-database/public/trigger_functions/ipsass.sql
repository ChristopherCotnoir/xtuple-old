CREATE OR REPLACE FUNCTION _ipsassBeforeTrigger() RETURNS TRIGGER AS $$
-- Copyright (c) 1999-2018 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
BEGIN

  IF NOT checkPrivilege('MaintainPricingSchedules') THEN
    RAISE EXCEPTION 'You do not have privileges to maintain Price Schedules.';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
  
END
$$ language plpgsql;

DROP TRIGGER IF EXISTS ipsassBeforeTrigger;
CREATE TRIGGER ipsassBeforeTrigger BEFORE INSERT OR UPDATE OR DELETE ON ipsass
FOR EACH ROW EXECUTE PROCEDURE _ipsassBeforeTrigger();
