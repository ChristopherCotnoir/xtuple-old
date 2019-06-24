
CREATE OR REPLACE FUNCTION releaseCashRcptNumber(INTEGER) RETURNS BOOLEAN AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.
  SELECT releaseNumber('CashRcptNumber', $1) > 0;
$$ LANGUAGE 'sql';

