DROP FUNCTION IF EXISTS listPrice(INTEGER, INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION listPrice(pItemid    INTEGER,
                                     pCustid    INTEGER DEFAULT NULL,
                                     pShiptoid  INTEGER DEFAULT NULL,
                                     pSiteid    INTEGER DEFAULT NULL,
                                     pEffective DATE    DEFAULT CURRENT_DATE)
RETURNS NUMERIC AS $$
-- Copyright (c) 1999-2018 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  _listprice NUMERIC;
  _price     NUMERIC;

BEGIN

-- Returns the list price of an item by either selecting from an
-- assigned List Price Schedule or the item_listprice.
-- List price always returned in base currency and price uom.

  SELECT item_listprice INTO _listprice
    FROM item
   WHERE item_id = pItemid;

-- Find the best List Price Schedule Price

  _price := ipsPrice(pItemId, pSiteId, TRUE, pEffective, CURRENT_DATE, NULL, NULL, NULL,
                     pCustId, pShiptoId);

  RETURN COALESCE(_price, _listprice);

END
$$ language plpgsql;
