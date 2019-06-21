CREATE OR REPLACE FUNCTION replaceVoidedAPCheck(INTEGER) RETURNS INTEGER AS '
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/EULA for the full text of the software license.
BEGIN
  RAISE WARNING ''replaceVoidedAPCheck() is deprecated - use replaceVoidedCheck()'';
  RETURN replaceVoidedCheck($1);
END;
' LANGUAGE 'plpgsql';
