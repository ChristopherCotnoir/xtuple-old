
CREATE OR REPLACE FUNCTION deleteShipto(INTEGER) RETURNS INTEGER AS '
-- Copyright (c) 1999-2014 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  pShiptoid ALIAS FOR $1;

BEGIN

  PERFORM asohist_id
  FROM asohist
  WHERE (asohist_shipto_id=pShiptoid)
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Shipto cannot be deleted as there is still Archived Sales History assigned to it. You must delete all of the selected Customer's Ship-Tos before you may delete it. [xtuple: deleteShipto, -1]';
  END IF;

  PERFORM cohead_id
  FROM cohead
  WHERE (cohead_shipto_id=pShiptoid)
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Shipto cannot be deleted as there has been Sales History recorded for this Shipto. You may Edit the selected Shipto and set its status to inactive. [xtuple: deleteShipto, -2]';
  END IF;

  PERFORM cmhead_id
  FROM cmhead
  WHERE (cmhead_shipto_id=pShiptoid)
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Shipto cannot be deleted as there has been Returns recorded for this Shipto. You may Edit the selected Shipto and set its status to inactive. [xtuple: deleteShipto, -3]';
  END IF;

  PERFORM cohist_id
  FROM cohist
  WHERE (cohist_shipto_id=pShiptoid)
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Shipto cannot be deleted as there has been Sales History recorded for this Shipto. You may Edit the selected Shipto and set its status to inactive. [xtuple: deleteShipto, -4]';
  END IF;

  PERFORM quhead_id
  FROM quhead
  WHERE (quhead_shipto_id=pShiptoid)
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Shipto cannot be deleted as there has been Quote History recorded for this Shipto. You may Edit the selected Shipto and set its status to inactive. [xtuple: deleteShipto, -5]';
  END IF;

  PERFORM invchead_id
  FROM invchead
  WHERE (invchead_shipto_id=pShiptoid)
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Shipto cannot be deleted as there has been Invoice History recorded for this Shipto. You may Edit the selected Shipto and set its status to inactive. [xtuple: deleteShipto, -6]';
  END IF;

  DELETE FROM ipsass
  WHERE (ipsass_shipto_id=pShiptoid);

  DELETE FROM shiptoinfo
  WHERE (shipto_id=pShiptoid);

  RETURN 0;

END;
' LANGUAGE 'plpgsql';

