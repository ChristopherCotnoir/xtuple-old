
CREATE OR REPLACE FUNCTION deleteForm(INTEGER) RETURNS INTEGER AS '
-- Copyright (c) 1999-2014 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  pFormid ALIAS FOR $1;
  _key TEXT;
  _check INTEGER;

BEGIN

--  Cache the key of the passed form
  SELECT form_key INTO _key
  FROM form
  WHERE (form_id=pFormid);
  IF (NOT(FOUND)) THEN
    RETURN 0;
  END IF;

--  Handle checks based on the type of the form
  IF (_key=''Chck'') THEN
    SELECT bankaccnt_id INTO _check
    FROM bankaccnt
    WHERE (bankaccnt_check_form_id=pFormid)
    LIMIT 1;
    IF (FOUND) THEN
      RAISE EXCEPTION 'The selected Check Format cannot be deleted as it is used by one or more Bank Accounts. You must reassign these Bank Accounts before you may delete the selected Check Form. [xtuple: deleteForm, -1]';
    END IF;

  END IF;

--  Delete the form
  DELETE FROM form
  WHERE (form_id=pFormid);

  RETURN pFormid;

END;
' LANGUAGE 'plpgsql';

