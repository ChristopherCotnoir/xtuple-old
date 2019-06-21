CREATE OR REPLACE FUNCTION releasePrNumber(INTEGER) RETURNS BOOLEAN AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.
  SELECT releaseNumber('PrNumber', $1) > 0;
$$ LANGUAGE 'sql';
