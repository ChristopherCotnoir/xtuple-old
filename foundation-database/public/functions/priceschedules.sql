CREATE OR REPLACE FUNCTION priceSchedules(pItemId     INTEGER,
                                          pWarehousId INTEGER DEFAULT NULL,
                                          pListprice  BOOLEAN DEFAULT FALSE,
                                          pAsOf       DATE    DEFAULT CURRENT_DATE,
                                          pCustId     INTEGER DEFAULT NULL,
                                          pShiptoId   INTEGER DEFAULT NULL,
                                          pShipzoneId INTEGER DEFAULT NULL,
                                          pSaletypeId INTEGER DEFAULT NULL)
RETURNS SETOF INTEGER AS $$
-- Copyright (c) 1999-2018 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  _item            INTEGER;
  _r               RECORD;
  _prevassignseq   INTEGER;
  _previtemmatched BOOLEAN;

BEGIN

  SELECT item_id, item_prodcat_id
    INTO _item
    FROM item
   WHERE item_id = pItemId;

  FOR _r IN
  SELECT ipshead_id,
         priceScheduleMatch(ipshead_id, pAsOf,
                            pCustId, pShiptoId, pShipzoneId, pSaletypeId) AS assignseq,
         CASE WHEN fetchMetricBool('ItemPricingPrecedence')
              THEN ipsitem_item_id IS NOT NULL
          END AS itemmatched
    FROM ipshead
   WHERE ipshead_listprice = pListprice
     AND EXISTS(SELECT 1
                  FROM ipsiteminfo
                 WHERE ipsitem_ipshead_id = ipshead_id
                   AND (ipsitem_item_id    = _item.item_id
                        OR (ipsitem_prodcat_id = _item.item_prodcat_id AND NOT pListprice))
                   AND (ipsitem_warehous_id IS NULL OR ipsitem_warehous_id = pWarehousId))
   ORDER BY assignseq, itemmatched DESC
  LOOP
    IF _r.assignseq IS NULL THEN
      EXIT;
    END IF;

    IF COALESCE(_prevassignseq, 0) > 0 AND
       (_prevassignseq != _r.assignseq OR _previtemmatched IS DISTINCT FROM _r.itemmatched) THEN
      EXIT;
    END IF;

    IF _prevassignseq = 0 AND _r.assignseq = 0 AND
       _previtemmatched IS DISTINCT FROM _r.itemmatched THEN
      CONTINUE;
    END IF;

    RETURN NEXT _r.ipshead_id;

    _prevassignseq := _r.assignseq;
    _previtemmatched := _r.itemmatched;
  END LOOP;

END
$$ language plpgsql;
