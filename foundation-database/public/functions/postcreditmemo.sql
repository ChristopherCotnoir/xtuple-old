
CREATE OR REPLACE FUNCTION postCreditMemo(pCmheadid INTEGER, pItemlocSeries INTEGER) RETURNS INTEGER AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.
BEGIN
  RETURN postCreditMemo(pCmheadid, fetchJournalNumber('AR-CM'), pItemlocSeries);
END;
$$ LANGUAGE 'plpgsql';

DROP FUNCTION IF EXISTS postCreditMemo(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION postCreditMemo(pCmheadid INTEGER, 
                                          pJournalNumber INTEGER, 
                                          pItemlocSeries INTEGER,
                                          pPreDistributed BOOLEAN DEFAULT FALSE) RETURNS INTEGER AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE
  _r RECORD;
  _p RECORD;
  _aropenid INTEGER;
  _cohistid INTEGER;
  _sequence INTEGER;
  _itemlocSeries INTEGER := COALESCE(pItemlocSeries, NEXTVAL('itemloc_series_seq'));
  _invhistid INTEGER;
  _invcheadid INTEGER;
  _test INTEGER;
  _totalAmount NUMERIC   := 0;
  _commissionDue NUMERIC := 0;
  _toApply NUMERIC;
  _toClose BOOLEAN;
  _glDate	DATE;
  _taxBaseValue	NUMERIC	:= 0;
  _hasControlledItems BOOLEAN := FALSE;

BEGIN
  IF (_itemlocSeries <= 0) THEN
    _itemlocSeries := NEXTVAL('itemloc_series_seq');
  END IF;

--  Cache some parameters
  SELECT cmhead.*,
         findARAccount(cmhead_cust_id) AS ar_accnt_id,
         ( SELECT COALESCE(SUM(taxdetail_tax), 0)
           FROM taxhead
           JOIN taxline ON taxhead_id = taxline_taxhead_id
           JOIN taxdetail ON taxline_id = taxdetail_taxline_id
           WHERE taxhead_doc_type = 'CM'
             AND taxhead_doc_id = cmhead_id
             AND taxline_line_type = 'A' ) AS adjtax
         INTO _p
  FROM cmhead
  WHERE (cmhead_id=pCmheadid);

  IF (_p.cmhead_invcnumber IS NOT NULL AND _p.cmhead_invcnumber != '-1') THEN
    SELECT invchead_id INTO _invcheadid
      FROM invchead
     WHERE invchead_invcnumber = _p.cmhead_invcnumber;
  END IF;

  IF (_p.cmhead_posted) THEN
    RETURN -10;
  END IF;

  IF (_p.cmhead_hold) THEN
    RETURN -11;
  END IF;

  _glDate := COALESCE(_p.cmhead_gldistdate, _p.cmhead_docdate);

  SELECT fetchGLSequence() INTO _sequence;

--  Start by handling taxes
  FOR _r IN SELECT tax_sales_accnt_id, 
              round(sum(taxdetail_tax),2) AS tax,
              currToBase(_p.cmhead_curr_id, round(sum(taxdetail_tax),2), _p.cmhead_docdate) AS taxbasevalue
            FROM taxhead
            JOIN taxline ON taxhead_id = taxline_taxhead_id
            JOIN taxdetail ON taxline_id = taxdetail_taxline_id
            LEFT OUTER JOIN tax ON taxdetail_tax_id = tax_id
            WHERE taxhead_doc_type = 'CM'
              AND taxhead_doc_id = pCmheadid
	    GROUP BY tax_id, tax_sales_accnt_id LOOP

    PERFORM insertIntoGLSeries( _sequence, 'A/R', 'CM', _p.cmhead_number,
                                CASE WHEN fetchMetricText('TaxService') = 'A'
                                     THEN fetchMetricValue('AvalaraSalesAccountId')::INTEGER
                                     ELSE _r.tax_sales_accnt_id
                                 END,
                                _r.taxbasevalue * -1,
                                _glDate, _p.cmhead_billtoname );

    _totalAmount := _totalAmount + _r.tax;
  END LOOP;

-- Update tax records with posting data
  UPDATE taxhead SET 
    taxhead_date=_p.cmhead_docdate,
    taxhead_distdate=_glDate,
    taxhead_curr_id=_p.cmhead_curr_id,
    taxhead_curr_rate=curr_rate,
    taxhead_journalnumber=pJournalNumber
  FROM curr_rate
  WHERE taxhead_doc_type = 'CM'
    AND taxhead_doc_id = pCmheadid
    AND (_p.cmhead_curr_id=curr_id)
    AND (_p.cmhead_docdate BETWEEN curr_effective 
                           AND curr_expires);

-- Process Non-Misc. C/M Items
-- Always use std cost
  FOR _r IN SELECT *, stdCost(item_id) AS std_cost
            FROM creditmemoitem
            JOIN itemsite ON cmitem_itemsite_id = itemsite_id
            WHERE ( (cmitem_cmhead_id=pCmheadid)
              AND   (cmitem_qtycredit <> 0 ) ) LOOP

    IF (_r.itemsite_costmethod = 'A') THEN
      -- Get cost from original shipment if it exists
      SELECT COALESCE(SUM(shipitem_value) / SUM(shipitem_qty), _r.std_cost) INTO _r.std_cost
        FROM cmitem
        JOIN itemsite ON cmitem_itemsite_id = itemsite_id
        JOIN cmhead ON cmitem_cmhead_id = cmhead_id
        JOIN invchead ON cmhead_invcnumber = invchead_invcnumber
        JOIN invcitem ON invchead_id = invcitem_invchead_id
                     AND itemsite_item_id = invcitem_item_id
                     AND itemsite_warehous_id = invcitem_warehous_id
        JOIN shipitem ON invcitem_id = shipitem_invcitem_id
       WHERE cmitem_id=_r.cmitem_id;
    END IF;

--  Calculate the Commission to be debited
    _commissionDue := (_commissionDue + (_r.extprice * _p.cmhead_commission));

    IF (_r.extprice <> 0) THEN
--  Debit the Sales Account for the current cmitem
      SELECT insertIntoGLSeries( _sequence, 'A/R', 'CM', _p.cmhead_number,
                                 CASE WHEN (_r.cmitem_rev_accnt_id IS NOT NULL) THEN
                                   getPrjAccntId(_p.cmhead_prj_id, _r.cmitem_rev_accnt_id)
                                 WHEN (_p.cmhead_rahead_id IS NULL) THEN
                                   getPrjAccntId(_p.cmhead_prj_id, salesaccnt_credit_accnt_id)
                                 ELSE
                                   getPrjAccntId(_p.cmhead_prj_id, salesaccnt_returns_accnt_id)
                                 END,
                               round(currToBase(_p.cmhead_curr_id,
                                                _r.extprice * -1,
                                                _p.cmhead_docdate), 2),
                                 _glDate, _p.cmhead_billtoname) INTO _test
      FROM salesaccnt
      WHERE (salesaccnt_id=findSalesAccnt(_r.cmitem_itemsite_id, 'IS', _p.cmhead_cust_id,
                                          _p.cmhead_saletype_id, _p.cmhead_shipzone_id));
      IF (NOT FOUND) THEN
        PERFORM deleteGLSeries(_sequence);
        RETURN -12;
      END IF;
    END IF;

--  Record Sales History for this C/M Item
    SELECT nextval('cohist_cohist_id_seq') INTO _cohistid;
    INSERT INTO cohist
    ( cohist_id, cohist_cust_id, cohist_itemsite_id, cohist_shipto_id,
      cohist_shipdate, cohist_shipvia,
      cohist_ordernumber, cohist_ponumber, cohist_orderdate,
      cohist_doctype, cohist_invcnumber, cohist_invcdate,
      cohist_qtyshipped, cohist_unitprice, cohist_unitcost,
      cohist_salesrep_id, cohist_commission, cohist_commissionpaid,
      cohist_billtoname, cohist_billtoaddress1,
      cohist_billtoaddress2, cohist_billtoaddress3,
      cohist_billtocity, cohist_billtostate, cohist_billtozip,
      cohist_billtocountry, cohist_shiptocountry,
      cohist_shiptoname, cohist_shiptoaddress1,
      cohist_shiptoaddress2, cohist_shiptoaddress3,
      cohist_shiptocity, cohist_shiptostate, cohist_shiptozip,
      cohist_curr_id, cohist_taxtype_id, cohist_taxzone_id,
      cohist_shipzone_id, cohist_saletype_id, cohist_invchead_id )
    VALUES
    ( _cohistid, _p.cmhead_cust_id, _r.cmitem_itemsite_id, _p.cmhead_shipto_id,
      _p.cmhead_docdate, '',
      _p.cmhead_number, _p.cmhead_custponumber, _p.cmhead_docdate,
      'C', _p.cmhead_invcnumber, _p.cmhead_docdate,
      (_r.qty * -1), _r.unitprice, _r.std_cost,
      _p.cmhead_salesrep_id, (_p.cmhead_commission * _r.extprice * -1), FALSE,
      _p.cmhead_billtoname, _p.cmhead_billtoaddress1,
      _p.cmhead_billtoaddress2, _p.cmhead_billtoaddress3,
      _p.cmhead_billtocity, _p.cmhead_billtostate, _p.cmhead_billtozip,
      _p.cmhead_billtocountry, _p.cmhead_shipto_country,
      _p.cmhead_shipto_name, _p.cmhead_shipto_address1,
      _p.cmhead_shipto_address2, _p.cmhead_shipto_address3,
      _p.cmhead_shipto_city, _p.cmhead_shipto_state, _p.cmhead_shipto_zipcode,
      _p.cmhead_curr_id, _r.cmitem_taxtype_id, _p.cmhead_taxzone_id,
      _p.cmhead_shipzone_id, _p.cmhead_saletype_id, _invcheadid );

    _totalAmount := _totalAmount + round(_r.extprice, 2);

  END LOOP;

--  March through the Misc. C/M Items
  FOR _r IN SELECT *
            FROM creditmemoitem
            JOIN salescat ON (salescat_id = cmitem_salescat_id)
            WHERE ( (cmitem_cmhead_id=pCmheadid)
              AND   (cmitem_qtycredit <> 0 )
              AND   (cmitem_itemsite_id IS NULL ) ) LOOP

--  Calculate the Commission to be debited
    _commissionDue := (_commissionDue + (_r.extprice * _p.cmhead_commission));

    IF (_r.extprice <> 0) THEN
--  Debit the Sales Account for the current cmitem
      SELECT insertIntoGLSeries( _sequence, 'A/R', 'CM', _p.cmhead_number,
                                 getPrjAccntId(_p.cmhead_prj_id, 
                                 COALESCE(_r.cmitem_rev_accnt_id,_r.salescat_sales_accnt_id)), 
                                 round(currToBase(_p.cmhead_curr_id,
                                                _r.extprice * -1,
                                                _p.cmhead_docdate), 2),
                                 _glDate, _p.cmhead_billtoname ) INTO _test;
      IF (_test < 0) THEN
        PERFORM deleteGLSeries(_sequence);
        RAISE EXCEPTION 'Could not debit the sales account for the credit memo line item [xtuple: postcreditmemo, -12, %1, %2]',
          _p.cmhead_number, _r.cmitem_itemsite_id;
      END IF;

    END IF;

--  Record Sales History for this Misc. C/M Item
    SELECT nextval('cohist_cohist_id_seq') INTO _cohistid;
    INSERT INTO cohist
    ( cohist_id, cohist_cust_id, cohist_itemsite_id, cohist_shipto_id,
      cohist_misc_type, cohist_misc_descrip,
      cohist_shipdate, cohist_shipvia,
      cohist_ordernumber, cohist_ponumber, cohist_orderdate,
      cohist_doctype, cohist_invcnumber, cohist_invcdate,
      cohist_qtyshipped, cohist_unitprice, cohist_unitcost,
      cohist_salesrep_id, cohist_commission, cohist_commissionpaid,
      cohist_billtoname, cohist_billtoaddress1,
      cohist_billtoaddress2, cohist_billtoaddress3,
      cohist_billtocity, cohist_billtostate, cohist_billtozip,
      cohist_billtocountry, cohist_shiptocountry,
      cohist_shiptoname, cohist_shiptoaddress1,
      cohist_shiptoaddress2, cohist_shiptoaddress3,
      cohist_shiptocity, cohist_shiptostate, cohist_shiptozip,
      cohist_curr_id, cohist_taxtype_id, cohist_taxzone_id,
      cohist_shipzone_id, cohist_saletype_id, cohist_invchead_id )
    VALUES
    ( _cohistid, _p.cmhead_cust_id, _r.cmitem_itemsite_id, _p.cmhead_shipto_id,
      'M', (_r.cmitem_number || '-' || _r.cmitem_descrip),
      _p.cmhead_docdate, '',
      _p.cmhead_number, _p.cmhead_custponumber, _p.cmhead_docdate,
      'C', _p.cmhead_invcnumber, _p.cmhead_docdate,
      (_r.qty * -1), _r.unitprice, 0,
      _p.cmhead_salesrep_id, (_p.cmhead_commission * _r.extprice * -1), FALSE,
      _p.cmhead_billtoname, _p.cmhead_billtoaddress1,
      _p.cmhead_billtoaddress2, _p.cmhead_billtoaddress3,
      _p.cmhead_billtocity, _p.cmhead_billtostate, _p.cmhead_billtozip,
      _p.cmhead_billtocountry, _p.cmhead_shipto_country,
      _p.cmhead_shipto_name, _p.cmhead_shipto_address1,
      _p.cmhead_shipto_address2, _p.cmhead_shipto_address3,
      _p.cmhead_shipto_city, _p.cmhead_shipto_state, _p.cmhead_shipto_zipcode,
      _p.cmhead_curr_id, _r.cmitem_taxtype_id, _p.cmhead_taxzone_id,
      _p.cmhead_shipzone_id, _p.cmhead_saletype_id, _invcheadid );

    _totalAmount := _totalAmount + round(_r.extprice, 2);
    
  END LOOP;
  
--  Credit the Misc. Account for Miscellaneous Charges
  IF (_p.cmhead_misc <> 0) THEN
    SELECT insertIntoGLSeries( _sequence, 'A/R', 'CM', _p.cmhead_number,
                               getPrjAccntId(_p.cmhead_prj_id, accnt_id), round(currToBase(_p.cmhead_curr_id,
                                                          _p.cmhead_misc * -1,
                                                          _p.cmhead_docdate), 2),
                               _glDate, _p.cmhead_billtoname) INTO _test
    FROM accnt
    WHERE (accnt_id=_p.cmhead_misc_accnt_id);

--  If the Misc. Charges Account was not found then punt
    IF (NOT FOUND) THEN
      PERFORM deleteGLSeries(_sequence);
      RETURN -14;
    END IF;

--  Record the Sales History for any Misc. Charge
    INSERT INTO cohist
    ( cohist_cust_id, cohist_itemsite_id, cohist_shipto_id,
      cohist_misc_type, cohist_misc_descrip, cohist_misc_id,
      cohist_shipdate, cohist_shipvia,
      cohist_ordernumber, cohist_ponumber, cohist_orderdate,
      cohist_doctype, cohist_invcnumber, cohist_invcdate,
      cohist_qtyshipped, cohist_unitprice, cohist_unitcost,
      cohist_salesrep_id, cohist_commission, cohist_commissionpaid,
      cohist_billtoname, cohist_billtoaddress1,
      cohist_billtoaddress2, cohist_billtoaddress3,
      cohist_billtocity, cohist_billtostate, cohist_billtozip,
      cohist_billtocountry, cohist_shiptocountry,
      cohist_shiptoname, cohist_shiptoaddress1,
      cohist_shiptoaddress2, cohist_shiptoaddress3,
      cohist_shiptocity, cohist_shiptostate, cohist_shiptozip,
      cohist_curr_id,
      cohist_shipzone_id, cohist_saletype_id, cohist_invchead_id )
    VALUES
    ( _p.cmhead_cust_id, -1, _p.cmhead_shipto_id,
      'M', _p.cmhead_misc_descrip, _p.cmhead_misc_accnt_id,
      _p.cmhead_docdate, '',
      _p.cmhead_number, _p.cmhead_custponumber, _p.cmhead_docdate,
      'C', _p.cmhead_invcnumber, _p.cmhead_docdate,
      1, (_p.cmhead_misc * -1), (_p.cmhead_misc * -1),
      _p.cmhead_salesrep_id, 0, FALSE,
      _p.cmhead_billtoname, _p.cmhead_billtoaddress1,
      _p.cmhead_billtoaddress2, _p.cmhead_billtoaddress3,
      _p.cmhead_billtocity, _p.cmhead_billtostate, _p.cmhead_billtozip,
      _p.cmhead_billtocountry, _p.cmhead_shipto_country,
      _p.cmhead_shipto_name, _p.cmhead_shipto_address1,
      _p.cmhead_shipto_address2, _p.cmhead_shipto_address3,
      _p.cmhead_shipto_city, _p.cmhead_shipto_state, _p.cmhead_shipto_zipcode,
      _p.cmhead_curr_id,
      _p.cmhead_shipzone_id, _p.cmhead_saletype_id, _invcheadid );

--  Cache the Misc. Amount distributed
    _totalAmount := _totalAmount + _p.cmhead_misc;
  END IF;

  -- Credit Tax Adjustments
  IF (_p.adjtax <> 0) THEN
  --  Record the Sales History for Tax Adjustment
    SELECT nextval('cohist_cohist_id_seq') INTO _cohistid;
    INSERT INTO cohist
    ( cohist_id, cohist_cust_id, cohist_itemsite_id, cohist_shipto_id,
      cohist_misc_type, cohist_misc_descrip,
      cohist_shipdate, cohist_shipvia,
      cohist_ordernumber, cohist_ponumber, cohist_orderdate,
      cohist_doctype, cohist_invcnumber, cohist_invcdate,
      cohist_qtyshipped, cohist_unitprice, cohist_unitcost,
      cohist_salesrep_id, cohist_commission, cohist_commissionpaid,
      cohist_billtoname, cohist_billtoaddress1,
      cohist_billtoaddress2, cohist_billtoaddress3,
      cohist_billtocity, cohist_billtostate, cohist_billtozip,
      cohist_billtocountry, cohist_shiptocountry,
      cohist_shiptoname, cohist_shiptoaddress1,
      cohist_shiptoaddress2, cohist_shiptoaddress3,
      cohist_shiptocity, cohist_shiptostate, cohist_shiptozip,
      cohist_curr_id, cohist_taxtype_id, cohist_taxzone_id,
      cohist_shipzone_id, cohist_saletype_id, cohist_invchead_id )
    VALUES
    ( _cohistid, _p.cmhead_cust_id, -1, _p.cmhead_shipto_id,
      'T', 'Misc Tax Adjustment',
      _p.cmhead_docdate, '',
      _p.cmhead_number, _p.cmhead_custponumber, _p.cmhead_docdate,
      'C', _p.cmhead_invcnumber, _p.cmhead_docdate,
      0, 0, 0,
      _p.cmhead_salesrep_id, 0, FALSE,
      _p.cmhead_billtoname, _p.cmhead_billtoaddress1,
      _p.cmhead_billtoaddress2, _p.cmhead_billtoaddress3,
      _p.cmhead_billtocity, _p.cmhead_billtostate, _p.cmhead_billtozip,
      _p.cmhead_billtocountry, _p.cmhead_shipto_country,
      _p.cmhead_shipto_name, _p.cmhead_shipto_address1,
      _p.cmhead_shipto_address2, _p.cmhead_shipto_address3,
      _p.cmhead_shipto_city, _p.cmhead_shipto_state, _p.cmhead_shipto_zipcode,
      _p.cmhead_curr_id, getAdjustmentTaxtypeId(), _p.cmhead_taxzone_id,
      _p.cmhead_shipzone_id, _p.cmhead_saletype_id, _invcheadid );
  END IF;

--  Debit the Freight Account
  IF (_p.cmhead_freight <> 0) THEN
    SELECT insertIntoGLSeries( _sequence, 'A/R', 'CM', _p.cmhead_number,
                               getPrjAccntId(_p.cmhead_prj_id, accnt_id),
                               round(currToBase(_p.cmhead_curr_id,
                                                _p.cmhead_freight * -1,
                                                _p.cmhead_docdate), 2),
                               _glDate, _p.cmhead_billtoname) INTO _test
    FROM accnt
    WHERE (accnt_id=findFreightAccount(_p.cmhead_cust_id));

--  If the Freight Charges Account was not found then punt
    IF (NOT FOUND) THEN
      PERFORM deleteGLSeries(_sequence);
      RETURN -16;
    END IF;

--  Cache the Amount Distributed to Freight
    _totalAmount := _totalAmount + _p.cmhead_freight;

--  Record the Sales History for any Freight
    SELECT nextval('cohist_cohist_id_seq') INTO _cohistid;
    INSERT INTO cohist
    ( cohist_id, cohist_cust_id, cohist_itemsite_id, cohist_shipto_id,
      cohist_misc_type, cohist_misc_descrip,
      cohist_shipdate, cohist_shipvia,
      cohist_ordernumber, cohist_ponumber, cohist_orderdate,
      cohist_doctype, cohist_invcnumber, cohist_invcdate,
      cohist_qtyshipped, cohist_unitprice, cohist_unitcost,
      cohist_salesrep_id, cohist_commission, cohist_commissionpaid,
      cohist_billtoname, cohist_billtoaddress1,
      cohist_billtoaddress2, cohist_billtoaddress3,
      cohist_billtocity, cohist_billtostate, cohist_billtozip,
      cohist_billtocountry, cohist_shiptocountry,
      cohist_shiptoname, cohist_shiptoaddress1,
      cohist_shiptoaddress2, cohist_shiptoaddress3,
      cohist_shiptocity, cohist_shiptostate, cohist_shiptozip,
      cohist_curr_id, cohist_taxtype_id, cohist_taxzone_id,
      cohist_shipzone_id, cohist_saletype_id, cohist_invchead_id )
    VALUES
    ( _cohistid, _p.cmhead_cust_id, -1, _p.cmhead_shipto_id,
      'F', 'Freight Charge',
      _p.cmhead_docdate, '',
      _p.cmhead_number, _p.cmhead_custponumber, _p.cmhead_docdate,
      'C', _p.cmhead_invcnumber, _p.cmhead_docdate,
      1, (_p.cmhead_freight * -1), (_p.cmhead_freight * -1),
      _p.cmhead_salesrep_id, 0, FALSE,
      _p.cmhead_billtoname, _p.cmhead_billtoaddress1,
      _p.cmhead_billtoaddress2, _p.cmhead_billtoaddress3,
      _p.cmhead_billtocity, _p.cmhead_billtostate, _p.cmhead_billtozip,
      _p.cmhead_billtocountry, _p.cmhead_shipto_country,
      _p.cmhead_shipto_name, _p.cmhead_shipto_address1,
      _p.cmhead_shipto_address2, _p.cmhead_shipto_address3,
      _p.cmhead_shipto_city, _p.cmhead_shipto_state, _p.cmhead_shipto_zipcode,
      _p.cmhead_curr_id, getFreightTaxtypeId(), _p.cmhead_taxzone_id,
      _p.cmhead_shipzone_id, _p.cmhead_saletype_id, _invcheadid );
  END IF;

  _totalAmount := _totalAmount;

--  Credit the A/R for the total Amount
  IF (_totalAmount <> 0) THEN
    IF (_p.ar_accnt_id != -1) THEN
      PERFORM insertIntoGLSeries( _sequence, 'A/R', 'CM', _p.cmhead_number,
                                  _p.ar_accnt_id,
                                  round(currToBase(_p.cmhead_curr_id,
                                                   _totalAmount,
                                                   _p.cmhead_docdate), 2),
                                  _glDate, _p.cmhead_billtoname);
    ELSE
      PERFORM deleteGLSeries(_sequence);
      RETURN -18;
    END IF;
  END IF;

--  Commit the GLSeries;
  PERFORM postGLSeries(_sequence, pJournalNumber);

--  Create the Invoice aropen item
  SELECT NEXTVAL('aropen_aropen_id_seq') INTO _aropenid;
  INSERT INTO aropen
  ( aropen_id, aropen_username, aropen_journalnumber,
    aropen_open, aropen_posted,
    aropen_cust_id, aropen_ponumber,
    aropen_docnumber,
    aropen_applyto, aropen_doctype,
    aropen_docdate, aropen_duedate, aropen_distdate, aropen_terms_id,
    aropen_amount, aropen_paid,
    aropen_salesrep_id, aropen_commission_due, aropen_commission_paid,
    aropen_ordernumber, aropen_notes,
    aropen_rsncode_id, aropen_curr_id )
  SELECT _aropenid, getEffectiveXtUser(), pJournalNumber,
         TRUE, FALSE,
         cmhead_cust_id, cmhead_custponumber,
         cmhead_number,
         CASE WHEN (cmhead_invcnumber='-1') THEN 'OPEN'
              ELSE (cmhead_invcnumber::TEXT)
         END,
         'C',
         cmhead_docdate, cmhead_docdate, _glDate, -1,
         _totalAmount, 0,
         cmhead_salesrep_id, (_commissionDue * -1), FALSE,
         cmhead_number::TEXT, cmhead_comments,
         cmhead_rsncode_id, cmhead_curr_id
  FROM cmhead
  WHERE (cmhead_id=pCmheadid);

-- Handle the Inventory and G/L Transactions for any returned Inventory where cmitem_updateinv is true
  FOR _r IN SELECT itemsite_id, itemsite_costmethod,
                   item_number, stdCost(item_id) AS std_cost,
                   costcat_asset_accnt_id,
                   SUM(cmitem_qtyreturned * cmitem_qty_invuomratio) AS qty,
                   isControlledItemsite(itemsite_id) AS controlled,
                   cmhead_id, cmitem_id
            FROM cmhead JOIN cmitem ON (cmitem_cmhead_id=cmhead_id)
                        JOIN itemsite ON (itemsite_id=cmitem_itemsite_id)
                        JOIN item ON (item_id=itemsite_item_id)
                        JOIN costcat ON (costcat_id=itemsite_costcat_id)
            WHERE ( (cmitem_qtyreturned <> 0)
             AND (cmitem_updateinv)
             AND (cmhead_id=pCmheadid) )
            GROUP BY cmhead_id, cmitem_id, itemsite_id, itemsite_costmethod,
                     item_number, item_id,
                     costcat_asset_accnt_id 
            ORDER BY itemsite_id LOOP

--  Return credited stock to inventory
    IF (_r.itemsite_costmethod != 'J') THEN

      IF (_r.controlled) THEN 
        _hasControlledItems := TRUE;
      END IF;

      IF (_r.itemsite_costmethod = 'A') THEN
        -- Get cost from original shipment if it exists
        SELECT COALESCE(SUM(shipitem_value) / SUM(shipitem_qty), _r.std_cost) INTO _r.std_cost
          FROM cmitem
          JOIN itemsite ON cmitem_itemsite_id = itemsite_id
          JOIN cmhead ON cmitem_cmhead_id = cmhead_id
          JOIN invchead ON cmhead_invcnumber = invchead_invcnumber
          JOIN invcitem ON invchead_id = invcitem_invchead_id
                       AND itemsite_item_id = invcitem_item_id
                       AND itemsite_warehous_id = invcitem_warehous_id
          JOIN shipitem ON invcitem_id = shipitem_invcitem_id
         WHERE cmitem_id=_r.cmitem_id;
      END IF;

      SELECT postInvTrans(_r.itemsite_id, 'RS', _r.qty,
                         'S/O', 'CM', _p.cmhead_number, '',
                         ('Credit Return ' || _r.item_number),
                         _r.costcat_asset_accnt_id,
                         getPrjAccntId(_p.cmhead_prj_id, resolveCOSAccount(_r.itemsite_id, _p.cmhead_cust_id, _p.cmhead_saletype_id, _p.cmhead_shipzone_id)), 
                         _itemlocSeries, _glDate, (_r.std_cost * _r.qty), NULL, NULL, pPreDistributed, _r.cmhead_id, _r.cmitem_id) INTO _invhistid;
    ELSE
      RAISE DEBUG 'postCreditMemo(%, %, %) tried to postInvTrans a %-costed item',
                  pCmheadid, pJournalNumber, pItemlocSeries,
                  _r.itemsite_costmethod;
    END IF;

  END LOOP;

--  Update coitem to reflect the returned qty where cmitem_updateinv is true
  FOR _r IN SELECT cmitem_qtyreturned, cmitem_itemsite_id, cohead_id
            FROM cmitem, cmhead, invchead, cohead
            WHERE ( (cmitem_cmhead_id=cmhead_id)
             AND (cmhead_invcnumber=invchead_invcnumber)
             AND (invchead_ordernumber=cohead_number)
             AND (cmitem_qtyreturned <> 0)
             AND (cmitem_updateinv)
             AND (cmhead_id=pCmheadid) ) LOOP
    UPDATE coitem
    SET coitem_qtyreturned = (coitem_qtyreturned + _r.cmitem_qtyreturned)
    WHERE coitem_id IN ( SELECT coitem_id
                         FROM coitem
                         WHERE ( (coitem_cohead_id=_r.cohead_id)
                          AND (coitem_itemsite_id = _r.cmitem_itemsite_id) )
                         LIMIT 1 );
  END LOOP;

--  Mark the cmhead as posted
  UPDATE cmhead
  SET cmhead_posted=TRUE, cmhead_gldistdate=_glDate
  WHERE (cmhead_id=pCmheadid);

--  Find the apply-to document and make the application
  SELECT cmhead_number, cmhead_curr_id, cmhead_docdate,
         aropen_id, aropen_cust_id, aropen_docnumber,
         currToCurr(aropen_curr_id, cmhead_curr_id, aropen_amount - aropen_paid,
                    cmhead_docdate) AS balance INTO _p
  FROM aropen, cmhead
  WHERE ( (aropen_doctype='I')
   AND (aropen_docnumber=cmhead_invcnumber)
   AND (cmhead_id=pCmheadid) );
  IF (FOUND) THEN

    IF round(_totalAmount, 2) <= round(_p.balance, 2) THEN
      _toApply = _totalAmount;
    ELSE
      _toApply = _p.balance;
    END IF;

    UPDATE aropen
    SET aropen_paid = round(aropen_paid + currToCurr(_p.cmhead_curr_id,
                                                     aropen_curr_id, _toApply,
                                                     _p.cmhead_docdate), 2)
    WHERE (aropen_id=_p.aropen_id);

--  Alter the new A/R Open Item to reflect the application
    UPDATE aropen
    SET aropen_paid = round(currToCurr(_p.cmhead_curr_id, aropen_curr_id,
                                       _toApply, _p.cmhead_docdate), 2)
    WHERE (aropen_id=_aropenid);

--  Record the application
    INSERT INTO arapply
    ( arapply_cust_id,
      arapply_source_aropen_id, arapply_source_doctype, arapply_source_docnumber,
      arapply_target_aropen_id, arapply_target_doctype, arapply_target_docnumber,
      arapply_fundstype, arapply_refnumber,
      arapply_applied, arapply_closed,
      arapply_postdate, arapply_distdate, arapply_journalnumber, arapply_curr_id )
    VALUES
    ( _p.aropen_cust_id,
      _aropenid, 'C', _p.cmhead_number,
      _p.aropen_id, 'I', _p.aropen_docnumber,
      '', '',
      round(_toApply, 2), _toClose,
      CURRENT_DATE, _p.cmhead_docdate, 0, _p.cmhead_curr_id );

  END IF;

  IF (pPreDistributed) THEN
    IF (postDistDetail(_itemlocSeries) <= 0 AND _hasControlledItems) THEN
      RAISE EXCEPTION 'Posting Distribution Detail Returned 0 Results [xtuple: postCreditMemo, -6]';
    END IF;
  END IF;
    
  RETURN _itemlocSeries;

END;
$$ LANGUAGE plpgsql;

