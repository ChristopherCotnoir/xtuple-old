DROP FUNCTION IF EXISTS customerCanPurchase(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS customerCanPurchase(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION customerCanPurchase(pItemId   INTEGER,
                                               pCustId   INTEGER,
                                               pShiptoId INTEGER DEFAULT NULL,
                                               pAsOf     DATE    DEFAULT CURRENT_DATE)
RETURNS BOOLEAN AS $$
-- Copyright (c) 1999-2018 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
BEGIN

  RETURN pItemId IN custItem(pCustId, pShiptoId, pAsOf);

END
$$ language plpgsql;
