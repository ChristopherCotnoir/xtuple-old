
CREATE OR REPLACE FUNCTION formatPrcnt(NUMERIC) RETURNS TEXT IMMUTABLE AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/EULA for the full text of the software license.
SELECT formatNumeric($1 * 100, 'percent')  AS result
$$ LANGUAGE 'sql';

