DROP FUNCTION IF EXISTS public.calcSalesOrderAmt(INTEGER);
DROP FUNCTION IF EXISTS public.calcSalesOrderAmt(INTEGER, TEXT);

CREATE OR REPLACE FUNCTION calcSalesOrderAmt(pCoheadid INTEGER,
                                             pType TEXT DEFAULT 'T') RETURNS NUMERIC STABLE AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
BEGIN

  RETURN calcSalesOrderAmt(pCoheadid, pType, NULL, NULL, NULL, NULL, NULL, FALSE);

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION calcSalesOrderAmt(pCoheadid INTEGER, pTaxzoneId INTEGER, pOrderDate DATE, pCurrId INTEGER, pFreight NUMERIC, pMisc NUMERIC) RETURNS NUMERIC STABLE AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
BEGIN

  RETURN calcSalesOrderAmt(pCoheadid, 'T', pTaxzoneId, pOrderDate, pCurrId, pFreight, pMisc);

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION calcSalesOrderAmt(pCoheadid INTEGER,
                                             pType TEXT, pTaxzoneId INTEGER, pOrderDate DATE, pCurrId INTEGER, pFreight NUMERIC, pMisc NUMERIC, pQuick BOOLEAN DEFAULT TRUE) RETURNS NUMERIC STABLE AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  _subtotal NUMERIC := 0.0;
  _cost NUMERIC := 0.0;
  _tax NUMERIC := 0.0;
  _freight NUMERIC := 0.0;
  _misc NUMERIC := 0.0;
  _credit NUMERIC := 0.0;
  _amount NUMERIC := 0.0;

BEGIN

  -- pType: S = line item subtotal
  --        T = total
  --        B = balance due
  --        C = allocated credits
  --        X = tax
  --        M = margin
  --        P = margin percent

  -- force consistent results regardless of pType
  -- there's probably a better way to get this than a separate query
  IF NOT EXISTS(SELECT 1 FROM cohead WHERE cohead_id = pCoheadid) THEN
    RETURN NULL;
  END IF;

  SELECT COALESCE(SUM(ROUND((coitem_qtyord * coitem_qty_invuomratio) *
                            (coitem_price / coitem_price_invuomratio), 2)), 0.0),
         COALESCE(SUM(ROUND((coitem_qtyord * coitem_qty_invuomratio) *
                            (CASE WHEN (coitem_subnumber > 0) THEN 0.0 ELSE coitem_unitcost END
                             / coitem_price_invuomratio), 2)), 0.0)
         INTO _subtotal, _cost
  FROM coitem
  WHERE (coitem_cohead_id=pCoheadid)
    AND (coitem_status != 'X');

  IF (pType IN ('T', 'B', 'X')) THEN
    _tax := getOrderTax('S', pCoheadid);
  END IF;

  IF (pQuick) THEN
    IF (pType IN ('T', 'B', 'C')) THEN
      SELECT COALESCE(pFreight, 0), COALESCE(pMisc, 0),
             COALESCE((SELECT SUM(currToCurr(aropenalloc_curr_id, pCurrId,
                                             aropenalloc_amount, pOrderDate))
                         FROM aropenalloc
                        WHERE (aropenalloc_doctype='S' AND aropenalloc_doc_id=pCoheadid)), 0) +
             COALESCE((SELECT SUM(currToCurr(invchead_curr_id, pCurrId,
                                             calcInvoiceAmt(invchead_id), pOrderDate))
                         FROM invchead
                        WHERE invchead_id IN (SELECT invchead_id
                                                FROM coitem
                                                JOIN invcitem ON invcitem_coitem_id=coitem_id
                                                JOIN invchead ON invcitem_invchead_id=invchead_id
                                               WHERE coitem_cohead_id=pCoheadid
                                                 AND invchead_posted)), 0)
             INTO _freight, _misc, _credit;
    END IF;
  ELSE
    IF (pType IN ('T', 'B', 'C')) THEN
      SELECT COALESCE(cohead_freight, 0), COALESCE(cohead_misc, 0),
             COALESCE((SELECT SUM(currToCurr(aropenalloc_curr_id, cohead_curr_id,
                                             aropenalloc_amount, cohead_orderdate))
                         FROM aropenalloc
                        WHERE (aropenalloc_doctype='S' AND aropenalloc_doc_id=cohead_id)), 0) +
             COALESCE((SELECT SUM(currToCurr(invchead_curr_id, cohead_curr_id,
                                             calcInvoiceAmt(invchead_id), cohead_orderdate))
                         FROM invchead
                        WHERE invchead_id IN (SELECT invchead_id
                                                FROM coitem
                                                JOIN invcitem ON invcitem_coitem_id=coitem_id
                                                JOIN invchead ON invcitem_invchead_id=invchead_id
                                               WHERE coitem_cohead_id=cohead_id
                                                 AND invchead_posted)), 0)
             INTO _freight, _misc, _credit
      FROM cohead
      WHERE (cohead_id=pCoheadid);
    END IF;
  END IF;

  _amount := CASE WHEN pType = 'S' THEN (_subtotal)
                  WHEN pType = 'T' THEN (_subtotal + _tax + _freight + _misc)
                  WHEN pType = 'B' THEN (_subtotal + _tax + _freight + _misc - _credit)
                  WHEN pType = 'C' THEN (_credit)
                  WHEN pType = 'X' THEN (_tax)
                  WHEN pType = 'M' AND _subtotal != 0.0 THEN (_subtotal - _cost)
                  WHEN pType = 'P' AND _subtotal != 0.0 THEN ((_subtotal - _cost) / _subtotal)
                  ELSE 0.0
             END;

  RETURN _amount;

END;
$$ LANGUAGE plpgsql;
