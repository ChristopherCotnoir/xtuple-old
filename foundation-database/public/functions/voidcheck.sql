CREATE OR REPLACE FUNCTION voidCheck(INTEGER) RETURNS INTEGER AS $$
-- Copyright (c) 1999-2014 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  pCheckid ALIAS FOR $1;

BEGIN

  IF ( SELECT (checkhead_void OR checkhead_posted OR checkhead_replaced)
       FROM checkhead
       WHERE (checkhead_id=pCheckid) ) THEN
    RAISE EXCEPTION 'Cannot void this Payment because either it has already been voided, posted, or replaced, or it has been transmitted electronically. If this Payment has been posted, try Void Posted Payment with the Payment Register window. [xtuple: voidCheck, -1]';
  END IF;

  UPDATE checkhead
  SET checkhead_void=TRUE
  WHERE (checkhead_id=pCheckid);

  RETURN 1;

END;
$$ LANGUAGE 'plpgsql';
