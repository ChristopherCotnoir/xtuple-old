CREATE OR REPLACE FUNCTION formatbytea(pField bytea) RETURNS text AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.
BEGIN
  RETURN convert_from(pField, 'UTF8');
END;
$$ LANGUAGE plpgsql;
