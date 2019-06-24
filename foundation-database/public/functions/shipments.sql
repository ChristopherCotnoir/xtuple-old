CREATE OR REPLACE FUNCTION shipments(TEXT) RETURNS BOOLEAN AS '
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE
  pTransType ALIAS FOR $1;

BEGIN
  IF (pTransType IN (''SC'', ''SV'', ''SH'', ''RS'', ''TS'')) THEN
    RETURN TRUE;
  ELSE
    RETURN FALSE;
  END IF;

END;
' LANGUAGE 'plpgsql';
