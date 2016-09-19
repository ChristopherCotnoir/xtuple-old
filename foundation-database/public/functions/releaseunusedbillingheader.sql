CREATE OR REPLACE FUNCTION releaseUnusedBillingHeader(INTEGER) RETURNS INTEGER AS '
-- Copyright (c) 1999-2014 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  pCobmiscid ALIAS FOR $1;
  _p RECORD;

BEGIN

  IF ( ( SELECT cobmisc_posted
         FROM cobmisc
         WHERE (cobmisc_id=pCobmiscid) ) ) THEN
    RAISE EXCEPTION ''Cannot release this Billing Header because it has already been posted. [xtuple: releaseUnusedBillingHeader, -1]'';
  END IF;

  SELECT cobill_id INTO _p
    FROM cobill
   WHERE (cobill_cobmisc_id=pCobmiscid)
   LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION ''Cannot release this Billing Header because it has Line Items. [xtuple: releaseUnusedBillingHeader, -2]'';
  END IF;

  DELETE FROM cobmisc
  WHERE (cobmisc_id=pCobmiscid);

  RETURN 0;
END;
' LANGUAGE 'plpgsql';
