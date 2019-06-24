CREATE OR REPLACE FUNCTION detachCCPayFromSO(INTEGER, INTEGER, INTEGER)
  RETURNS INTEGER AS
'
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE
  pcoheadid		ALIAS FOR $1;
  pwarehousid		ALIAS FOR $2;
  pcustid		ALIAS FOR $3;

BEGIN
  RAISE WARNING ''detachCCPayFromSO(INTEGER, INTEGER, INTEGER): deprecated'';
  RETURN 0;
END;
'
LANGUAGE 'plpgsql';
