CREATE OR REPLACE FUNCTION correctProduction(INTEGER, NUMERIC, BOOLEAN, BOOLEAN) RETURNS INTEGER AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/CPAL for the full text of the software license.
BEGIN
  RAISE WARNING 'correctProduction(INTEGER, NUMERIC, BOOLEAN, BOOLEAN) has been deprecated. Use corrrectProduction(INTEGER, NUMERIC, BOOLEAN, INTEGER) or a package-specific version instead.';
  RETURN  correctProduction($1, $2, $3, 0, now());
END;
$$ LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION correctProduction(INTEGER, NUMERIC, BOOLEAN, BOOLEAN, INTEGER) RETURNS INTEGER AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/CPAL for the full text of the software license.
BEGIN
  RAISE WARNING 'correctProduction(INTEGER, NUMERIC, BOOLEAN, BOOLEAN, INTEGER) has been deprecated. Use corrrectProduction(INTEGER, NUMERIC, BOOLEAN, INTEGER) or a package-specific version instead.';
  RETURN correctProduction($1, $2, $3, $5, now());
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION correctProduction(INTEGER, NUMERIC, BOOLEAN, INTEGER, TIMESTAMP WITH TIME ZONE) RETURNS INTEGER AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  pWoid          ALIAS FOR $1;
  pQty           ALIAS FOR $2;
  pBackflush     ALIAS FOR $3;
  pItemlocSeries ALIAS FOR $4;
  pGlDistTS      ALIAS FOR $5;
BEGIN
  RETURN correctProduction($1, $2, $3, $4, $5, NULL);
END;
$$ LANGUAGE 'plpgsql';

DROP FUNCTION IF EXISTS correctProduction(INTEGER, NUMERIC, BOOLEAN, INTEGER, TIMESTAMP WITH TIME ZONE, INTEGER);
CREATE OR REPLACE FUNCTION correctProduction(pWoid INTEGER, 
                                             pQty NUMERIC, 
                                             pBackflush BOOLEAN, 
                                             pItemlocSeries INTEGER, 
                                             pGlDistTS TIMESTAMP WITH TIME ZONE, 
                                             pInvhistId INTEGER,
                                             pPreDistributed BOOLEAN DEFAULT FALSE)
RETURNS INTEGER AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  _invhistid        INTEGER;
  _itemlocSeries    INTEGER := COALESCE(pItemlocseries, NEXTVAL('itemloc_series_seq'));
  _r                RECORD;
  _parentWIPAccntid INTEGER;
  _parentQty        NUMERIC;
  _qty              NUMERIC;
  _wipPost          NUMERIC;
  _sense            TEXT;
  _status           TEXT;
  _type             TEXT;
  _qtyfxd           NUMERIC := 0;
  _controlled       BOOLEAN := FALSE;
  _hasControlledMaterialItems BOOLEAN := FALSE;

BEGIN
  -- Qty is positive for Assembly W/O
  -- Qty is negative for Disassembly W/O
  IF (pQty = 0) THEN
    RETURN pItemlocseries;
  ELSIF (pQty > 0) THEN
    _sense := 'from';
  ELSE
    _sense := 'to';
  END IF;

  IF (pPreDistributed AND pItemlocseries IS NULL) THEN
    RAISE EXCEPTION 'ItemlocSeries is required when pPreDistributed [xtuple: correctProduction, -3]';
  ELSIF (_itemlocSeries = 0) THEN
    _itemlocSeries := NEXTVAL('itemloc_series_seq');
  END IF;

  SELECT item_type, roundQty(item_fractional, pQty), wo_status, isControlledItemsite(wo_itemsite_id)
    INTO _type, _parentQty, _status, _controlled
    FROM wo JOIN itemsite ON (itemsite_id=wo_itemsite_id)
            JOIN item ON (item_id=itemsite_item_id)
            JOIN costcat ON costcat_id=itemsite_costcat_id
   WHERE (wo_id=pWoid);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Missing cost category [xtuple: correctProduction, -4]';
  END IF;

  IF (_status != 'I') THEN
    RAISE EXCEPTION 'Can not correct production for WO with status % [xtuple: correctProduction, -1, %]', _status, _status;
  END IF;

  IF (_type = 'J') THEN
    RAISE EXCEPTION 'Correct production does not support Job costed items [xtuple: correctProduction, -2]';
  END IF;

  --  Calculate the WIP to correct
  SELECT CASE WHEN (wo_cosmethod = 'D') THEN wo_postedvalue
              ELSE  round(((wo_postedvalue - wo_wipvalue) / wo_qtyrcv * _parentQty), 2)
         END INTO _wipPost
  FROM wo
  WHERE (wo_id=pWoid);

  --  Post the inventory transaction
  SELECT postInvTrans( itemsite_id, 'RM', (_parentQty * -1.0),
                       'W/O', 'WO', formatwonumber(pWoid), '',
                       ('Correct Receive Inventory ' || item_number || ' ' || _sense || ' Manufacturing'),
                       costcat_asset_accnt_id, getPrjAccntId(wo_prj_id, costcat_wip_accnt_id), _itemlocSeries, pGlDistTS,
                       (_wipPost * -1.0), -- only used when cost is average
                       pInvhistId, NULL, pPreDistributed, pWoid) INTO _invhistid
  FROM wo JOIN itemsite ON (itemsite_id=wo_itemsite_id)
          JOIN item ON (item_id=itemsite_item_id)
          JOIN costcat ON (costcat_id=itemsite_costcat_id)
  WHERE (wo_id=pWoid);

  --  Decrease this W/O's qty. received and increase its WIP value
  UPDATE wo
  SET wo_qtyrcv = (wo_qtyrcv - _parentQty),
      wo_wipvalue = (wo_wipvalue + (CASE WHEN(itemsite_costmethod IN ('A','J'))
                                              THEN _wipPost
                                         WHEN(itemsite_costmethod='S')
                                              THEN stdcost(itemsite_item_id) * _parentQty
                                         ELSE 0.0 END))
  FROM itemsite
  WHERE ( (wo_itemsite_id=itemsite_id)
   AND (wo_id=pWoid) );

  IF (pBackflush) THEN
    FOR _r IN SELECT item_id, item_fractional,
                      itemsite_id, itemsite_warehous_id,
                      itemsite_controlmethod, itemsite_loccntrl,
                      itemsite_costmethod, isControlledItemsite(itemsite_id) AS controlled,
                      wo_qtyrcv, wo_prj_id,
                      womatl_id, womatl_qtyfxd, womatl_qtyper,
                      womatl_scrap, womatl_issuemethod, womatl_uom_id
               FROM wo JOIN womatl ON (womatl_wo_id=wo_id AND womatl_issuemethod='L')
                       JOIN itemsite ON (itemsite_id=womatl_itemsite_id)
                       JOIN item ON (item_id=itemsite_item_id)
               WHERE (wo_id=pWoid) 
               ORDER BY womatl_id LOOP

      IF (_r.controlled) THEN 
        _hasControlledMaterialItems := true;
      END IF;

      --  Cache the qty to be issued
      -- If going back to beginning, unissue fixed qty as well
      IF (_r.wo_qtyrcv - _parentQty > 0) THEN
        _qtyfxd := 0;
      ELSE
        _qtyfxd := _r.womatl_qtyfxd;
      END IF;

      _qty = roundQty(_r.item_fractional, (_qtyfxd + _parentQty * _r.womatl_qtyper) * (1 + _r.womatl_scrap));

      IF (_qty > 0) THEN
        SELECT returnWoMaterial(_r.womatl_id, _qty, _itemlocSeries, pGlDistTS, NULL, pPreDistributed, FALSE) INTO _itemlocSeries;
      END IF;

    END LOOP;

  	--  BEGIN ROB Decrease this W/O's WIP value for custom costing
	  UPDATE wo
	  SET wo_wipvalue = (wo_wipvalue - (itemcost_stdcost * _parentQty))
	FROM costelem, itemcost, costcat, itemsite, item
	WHERE
	  ((wo_id=pWoid) AND
	  (wo_itemsite_id=itemsite_id) AND
	  (itemsite_item_id=item_id) AND
	  (costelem_id = itemcost_costelem_id) AND
	  (itemcost_item_id = itemsite_item_id) AND
	  (itemsite_costcat_id = costcat_id) AND
	  (costelem_exp_accnt_id) IS NOT NULL  AND
	  (costelem_sys = false));

	--  ROB Distribute to G/L - create Cost Variance, debit WIP
	  PERFORM insertGLTransaction( 'W/O', 'WO', formatwonumber(pWoid),
				       ('Correct Post Other Cost ' || item_number || ' ' || _sense || ' Manufacturing'),
				       getPrjAccntId(wo_prj_id, costelem_exp_accnt_id),
				       getPrjAccntId(wo_prj_id, costcat_wip_accnt_id), _invhistid,
				       ((itemcost_stdcost * _parentQty)* -1),
				       CURRENT_DATE )
	FROM wo, costelem, itemcost, costcat, itemsite, item
	WHERE
	  ((wo_id=pWoid) AND
	  (wo_itemsite_id=itemsite_id) AND
	  (itemsite_item_id=item_id) AND
	  (costelem_id = itemcost_costelem_id) AND
	  (itemcost_item_id = itemsite_item_id) AND
	  (itemsite_costcat_id = costcat_id) AND
	  (costelem_exp_accnt_id) IS NOT NULL  AND
	  (costelem_sys = false));
  --End ROB

  END IF;

  -- Post distribution detail regardless of loc/control methods because postItemlocSeries is required.
  -- However, if pinvhist IS NOT NULL then postItemlocSeries will have already occured in postInvTrans.
  IF (pPreDistributed AND pInvhistId IS NULL) THEN
    -- If it is a controlled item or has controlled items and the results were 0 something is wrong.
    IF (postDistDetail(_itemlocSeries) <= 0 AND (_controlled OR _hasControlledMaterialItems)) THEN
      RAISE EXCEPTION 'Posting Distribution Detail Returned 0 Results, [xtuple: correctProduction, -5]';
    END IF;
  END IF;

  RETURN _itemlocSeries;

END;
$$ LANGUAGE plpgsql;
