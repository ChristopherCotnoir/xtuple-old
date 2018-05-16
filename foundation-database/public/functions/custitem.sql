DROP FUNCTION IF EXISTS custItem(INTEGER, INTEGER, DATE);
CREATE OR REPLACE FUNCTION custItem(pCustId   INTEGER,
                                    pShiptoId INTEGER DEFAULT NULL,
                                    pAsOf     DATE    DEFAULT CURRENT_DATE)
RETURNS SETOF INTEGER AS $$
-- Copyright (c) 1999-2018 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/CPAL for the full text of the software license.

  SELECT item_id
    FROM (
          -- Non Exclusive
          SELECT item_id, item_sold
            FROM item
           WHERE NOT item_exclusive
          UNION
          -- Exclusive
          SELECT item_id, item_sold
            FROM ipshead
            JOIN ipsiteminfo ON ipshead_id = ipsitem_ipshead_id
            JOIN item ON ipsitem_item_id = item_id
                      OR ipsitem_prodcat_id = item_prodcat_id
           WHERE item_exclusive
             AND priceScheduleMatch(ipshead_id, pAsOf, pCustId, pShiptoId) IS NOT NULL
         )
   WHERE item_sold;

$$ language sql;
