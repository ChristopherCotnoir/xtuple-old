CREATE OR REPLACE FUNCTION userCanCreateUsers(TEXT) RETURNS BOOLEAN AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.
SELECT rolcreaterole OR rolsuper
  FROM pg_roles
 WHERE rolname=($1);
$$ LANGUAGE SQL;
