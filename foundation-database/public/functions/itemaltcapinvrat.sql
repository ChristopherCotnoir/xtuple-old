CREATE OR REPLACE FUNCTION itemAltCapInvRat(INTEGER) RETURNS NUMERIC STABLE AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE
  pItemid ALIAS FOR $1;

BEGIN
  RETURN itemUOMRatioByType(pItemid, 'AltCapacity');
END;
$$ LANGUAGE 'plpgsql';
