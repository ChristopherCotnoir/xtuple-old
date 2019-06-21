CREATE OR REPLACE FUNCTION deleteMetaSQL(INTEGER) RETURNS INTEGER AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE
  pid ALIAS FOR $1;
BEGIN
  DELETE FROM metasql WHERE metasql_id = pid;
  RETURN 0;
END;
$$ LANGUAGE 'plpgsql';
