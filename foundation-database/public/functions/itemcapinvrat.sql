CREATE OR REPLACE FUNCTION itemCapInvRat(INTEGER) RETURNS NUMERIC STABLE AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE
  pItemid ALIAS FOR $1;

BEGIN
  RETURN itemUOMRatioByType(pItemid, 'Capacity');
END;
$$ LANGUAGE 'plpgsql';
