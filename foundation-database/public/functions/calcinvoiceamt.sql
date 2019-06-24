DROP FUNCTION IF EXISTS public.calcinvoiceamt(INTEGER);
DROP FUNCTION IF EXISTS public.calcinvoiceamt(INTEGER, TEXT);
DROP FUNCTION IF EXISTS public.calcinvoiceamt(INTEGER, TEXT, INTEGER);

CREATE OR REPLACE FUNCTION calcInvoiceAmt(pInvcheadid INTEGER,
                                          pType       TEXT    DEFAULT 'T',
                                          pInvcitemid INTEGER DEFAULT NULL) RETURNS NUMERIC STABLE AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE
  _subtotal NUMERIC := 0.0;
  _cost NUMERIC := 0.0;
  _tax NUMERIC := 0.0;
  _freight NUMERIC := 0.0;
  _misc NUMERIC := 0.0;
  _amount NUMERIC := 0.0;

BEGIN

  -- pType: S = line item subtotal
  --        T = total
  --        X = tax
  --        M = margin

  -- force consistent results regardless of pType
  -- there's probably a better way to get this than a separate query
  IF NOT EXISTS(SELECT 1 FROM invchead WHERE invchead_id = pInvcheadid) THEN
    RETURN NULL;
  END IF;

  SELECT COALESCE(SUM(ROUND((invcitem_billed * invcitem_qty_invuomratio) *
                            (invcitem_price / COALESCE(invcitem_price_invuomratio, 1.0)), 2)), 0.0),
         COALESCE(SUM(ROUND((invcitem_billed * invcitem_qty_invuomratio) *
                            (currtolocal(invchead_curr_id, COALESCE(coitem_unitcost, itemCost(itemsite_id), 0.0), invchead_invcdate)
                             / COALESCE(coitem_price_invuomratio, 1.0)), 2)), 0.0)
         INTO _subtotal, _cost
  FROM invcitem 
    JOIN invchead ON (invchead_id = invcitem_invchead_id)
    LEFT OUTER JOIN coitem ON (coitem_id=invcitem_coitem_id)
    LEFT OUTER JOIN itemsite ON (itemsite_item_id=invcitem_item_id AND
                                 itemsite_warehous_id=invcitem_warehous_id)
  WHERE (invcitem_invchead_id=pInvcheadid)
   AND CASE WHEN pinvcitemid IS NOT NULL THEN
        (invcitem_id=pInvcitemid) ELSE true END;

  IF (pType IN ('T', 'X')) THEN
    _tax := getOrderTax('INV', pInvcheadid);
  END IF;

  IF (pType = 'T') THEN
    SELECT COALESCE(invchead_freight, 0), COALESCE(invchead_misc_amount, 0)
           INTO _freight, _misc
    FROM invchead
    WHERE (invchead_id=pinvcheadid);
  END IF;

  _amount := CASE pType WHEN 'S' THEN (_subtotal)
                        WHEN 'T' THEN (_subtotal + _tax + _freight + _misc)
                        WHEN 'X' THEN (_tax)
                        WHEN 'M' THEN (_subtotal - _cost)
                        ELSE 0.0
             END;

  RETURN _amount;

END;
$$ LANGUAGE plpgsql;
