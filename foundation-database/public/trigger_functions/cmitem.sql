CREATE OR REPLACE FUNCTION _cmitemBeforeDeleteTrigger() RETURNS TRIGGER AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.
BEGIN
  IF NOT checkPrivilege('MaintainCreditMemos') THEN
    RAISE EXCEPTION 'You do not have privileges to maintain Credit Memos.';
  END IF;

  UPDATE taxhead
     SET taxhead_valid = FALSE
   WHERE taxhead_doc_type = 'CM'
     AND taxhead_doc_id = OLD.cmitem_cmhead_id;

  RETURN OLD;
END;
$$ LANGUAGE plpgsql;
ALTER FUNCTION public._cmitemBeforeDeleteTrigger() OWNER TO admin;

SELECT dropIfExists('TRIGGER', 'cmitemBeforeDeleteTrigger');
CREATE TRIGGER cmitemBeforeDeleteTrigger BEFORE DELETE ON cmitem FOR EACH ROW EXECUTE PROCEDURE _cmitemBeforeDeleteTrigger();

CREATE OR REPLACE FUNCTION _cmitemBeforeTrigger() RETURNS "trigger" AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE
  _id INTEGER;
BEGIN
  IF NOT checkPrivilege('MaintainCreditMemos') THEN
    RAISE EXCEPTION 'You do not have privileges to maintain Credit Memos.';
  END IF;

  IF (TG_OP = 'INSERT') THEN
    IF ( (NEW.cmitem_qtycredit IS NULL) OR (NEW.cmitem_qtycredit = 0) ) THEN
      RAISE EXCEPTION 'Quantity to Credit must be greater than zero.';
    END IF;
    SELECT cmitem_id INTO _id
    FROM cmitem
    WHERE ( (cmitem_cmhead_id=NEW.cmitem_cmhead_id) AND (cmitem_linenumber=NEW.cmitem_linenumber) );
    IF (FOUND) THEN
      RAISE EXCEPTION 'The Memo Line Number is already in use.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

SELECT dropIfExists('TRIGGER', 'cmitembeforetrigger');
CREATE TRIGGER cmitembeforetrigger
  BEFORE INSERT OR UPDATE
  ON cmitem
  FOR EACH ROW
  EXECUTE PROCEDURE _cmitemBeforeTrigger();


CREATE OR REPLACE FUNCTION _cmitemTrigger() RETURNS "trigger" AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE
  _ext NUMERIC;
  _r RECORD;

BEGIN
  IF (TG_OP = 'DELETE') THEN

--  If this was created by a return, reset return values
    IF (OLD.cmitem_raitem_id) IS NOT NULL THEN
      _ext := ROUND((OLD.cmitem_qtycredit * OLD.cmitem_qty_invuomratio) *  (OLD.cmitem_unitprice / OLD.cmitem_price_invuomratio),2);
      UPDATE raitem SET
        raitem_status = 'O',
        raitem_qtycredited = raitem_qtycredited-OLD.cmitem_qtycredit,
        raitem_amtcredited = raitem_amtcredited-_ext
      WHERE (raitem_id=OLD.cmitem_raitem_id);
    END IF;
    RETURN OLD;
  END IF;

  IF (TG_OP = 'INSERT' OR
      TG_OP = 'UPDATE' AND
      (NEW.cmitem_qtycredit != OLD.cmitem_qtycredit OR
       NEW.cmitem_qty_invuomratio != OLD.cmitem_qty_invuomratio OR
       NEW.cmitem_unitprice != OLD.cmitem_unitprice OR
       NEW.cmitem_price_invuomratio != OLD.cmitem_price_invuomratio OR
       NEW.cmitem_taxtype_id != OLD.cmitem_taxtype_id OR
       (fetchMetricText('TaxService') != 'N' AND
        (NEW.cmitem_itemsite_id != OLD.cmitem_itemsite_id OR
         NEW.cmitem_tax_exemption != OLD.cmitem_tax_exemption)))) THEN
    UPDATE taxhead
       SET taxhead_valid = FALSE
     WHERE taxhead_doc_type = 'CM'
       AND taxhead_doc_id = NEW.cmitem_cmhead_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

SELECT dropIfExists('TRIGGER', 'cmitemtrigger');
CREATE TRIGGER cmitemtrigger
  AFTER INSERT OR UPDATE OR DELETE
  ON cmitem
  FOR EACH ROW
  EXECUTE PROCEDURE _cmitemTrigger();
