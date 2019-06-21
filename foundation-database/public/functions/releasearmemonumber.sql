
CREATE OR REPLACE FUNCTION releaseARMemoNumber(INTEGER) RETURNS BOOLEAN AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.
  select releaseNumber('ARMemoNumber', $1::INTEGER) > 0;
$$ LANGUAGE 'sql';

