CREATE OR REPLACE FUNCTION ipsPrice(pItemId     INTEGER,
                                    pWarehousId INTEGER DEFAULT NULL,
                                    pListprice  BOOLEAN DEFAULT FALSE,
                                    pEffective  DATE    DEFAULT CURRENT_DATE,
                                    pAsOf       DATE    DEFAULT CURRENT_DATE,
                                    pQty        NUMERIC DEFAULT NULL,
                                    pPriceUom   INTEGER DEFAULT NULL,
                                    pCurrId     INTEGER DEFAULT baseCurrId(),
                                    pCustId     INTEGER DEFAULT NULL,
                                    pShiptoId   INTEGER DEFAULT NULL,
                                    pShipzoneId INTEGER DEFAULT NULL,
                                    pSaletypeId INTEGER DEFAULT NULL)
RETURNS itemprice AS $$
-- Copyright (c) 1999-2018 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  _listprice NUMERIC;
  _r         RECORD;

BEGIN

  IF NOT pListprice THEN
    _listprice := listPrice(pItemid, pCustid, pShiptoid, pSiteid);
  END IF;

  FOR _r IN
  SELECT ipshead_id,
         qtybreak,
         currToCurr(ipshead_curr_id,
                    pCurrId,
                    itemuomtouom(pItemId, item_price_uom_id, COALESCE(pPriceUom, item_price_uom_id),
                                 calcIpsitemPrice(ipsitem_id, pItemid, pSiteid,
                                                   _listprice, pEffective)),
                    pEffective) AS price
    INTO _r
    FROM (
          SELECT ipsitem_id,
                 CASE WHEN ipsitem_item_id=pItemId
                      THEN itemuomtouom(pItemId, ipsitem_qty_uom_id, NULL, ipsitem_qtybreak)
                      ELSE ipsitem_qtybreak
                  END AS qtybreak
            FROM ipshead
            JOIN ipsiteminfo ON ipsitem_ipshead_id=ipshead_id
                            AND ipsitem_item_id = pItemId
                            AND (ipsitem_warehous_id IS NULL OR ipsitem_warehous_id = pWarehousId)
            JOIN item ON ipsitem_item_id = item_id
           WHERE ipshead_id IN priceSchedule(pItemid, pAsOf, pListPrice, pSiteid,
                                             pCustid, pShiptoid, pShipzoneId, pSaletypeId)
         )
   WHERE pQty IS NULL OR qtybreak <= pQty
   ORDER BY qtybreak DESC, price
   LOOP

END
$$ language plpgsql;
