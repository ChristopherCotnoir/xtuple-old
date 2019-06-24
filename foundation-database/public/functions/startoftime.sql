
CREATE OR REPLACE FUNCTION startoftime() RETURNS DATE IMMUTABLE AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.
SELECT DATE('1970-01-01') AS return;
$$ LANGUAGE sql;

