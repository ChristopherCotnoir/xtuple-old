DROP FUNCTION IF EXISTS createardebitmemo(integer, integer, integer, text, text, date, numeric, text, integer, integer, integer, date, integer, integer, numeric, integer);

DROP FUNCTION IF EXISTS createARDebitmemo(integer, integer, integer, text, text, date, numeric, text, integer, integer, integer, date, integer, integer, numeric, integer, integer);

CREATE OR REPLACE FUNCTION createARDebitMemo( pId            INTEGER,
                                              pCustid        INTEGER,
                                              pJournalNumber INTEGER,
                                              pDocNumber     TEXT,
                                              pOrderNumber   TEXT,
                                              pDocDate       DATE,
                                              pAmount        NUMERIC,
                                              pNotes         TEXT,
                                              pRsncodeid     INTEGER,
                                              pSalescatid    INTEGER,
                                              pAccntid       INTEGER,
                                              pDueDate       DATE,
                                              pTermsid       INTEGER,
                                              pSalesrepid    INTEGER,
                                              pCommissiondue NUMERIC = 0,
                                              pCurrId        INTEGER = baseCurrId(),
                                              pTaxZoneid     INTEGER = NULL,
                                              pPaid          NUMERIC = 0) RETURNS INTEGER AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE
  _custName TEXT;
  _journalNumber INTEGER;
  _arAccntid INTEGER;
  _prepaidAccntid INTEGER;
  _salescatid INTEGER;
  _accntid INTEGER;
  _glSequence INTEGER;
  _aropenid INTEGER;
  _cohistid INTEGER;
  _tmp INTEGER;
  _test INTEGER;
  _taxBaseValue NUMERIC;

BEGIN
  _aropenid=pId;
  
  IF (pAmount <= 0) THEN
    RETURN 0;
  END IF;

  SELECT findARAccount(pCustid) INTO _arAccntid;
  SELECT findPrepaidAccount(pCustid) INTO _prepaidAccntid;

  _accntid := pAccntid;
  _salescatid := pSalescatid;

  SELECT cust_name INTO _custName
  FROM custinfo
  WHERE (cust_id=pCustid);
  
  PERFORM accnt_id
     FROM accnt
    WHERE (accnt_id=_accntid);
  IF (FOUND) THEN
    _prepaidAccntid := _accntid;
  ELSE
    _accntid := -1;
  END IF;

  SELECT accnt_id INTO _tmp
    FROM salescat, accnt
   WHERE ((salescat_prepaid_accnt_id=accnt_id)
     AND  (salescat_id=_salescatid));
  IF (FOUND) THEN
    _accntid := -1;
    _prepaidAccntid := _tmp;
  ELSE
    _salescatid = -1;
  END IF;

  IF (pJournalNumber IS NULL) THEN
    _journalNumber := fetchJournalNumber('AR-MISC');
  ELSE
    _journalNumber := pJournalNumber;
  END IF;

  SELECT fetchGLSequence() INTO _glSequence;

  -- CreatelUpdate aropen for full amount
  IF (_aropenid IS NOT NULL) THEN
    UPDATE aropen SET
      aropen_username=getEffectiveXtUser(), aropen_journalnumber=_journalNumber,
      aropen_cust_id=pCustid, aropen_docnumber=pDocNumber, aropen_doctype='D', 
      aropen_ordernumber=pOrderNumber,aropen_docdate=pDocDate, aropen_duedate=pDueDate, 
      aropen_distdate=pDocDate, aropen_terms_id=pTermsid, 
      aropen_salesrep_id=pSalesrepid, aropen_amount=round(pAmount, 2), aropen_paid=pPaid, 
      aropen_commission_due=pCommissiondue, aropen_commission_paid=FALSE,
      aropen_applyto='', aropen_ponumber='', aropen_cobmisc_id=-1,
      aropen_open=TRUE, aropen_notes=pNotes, aropen_rsncode_id=pRsncodeid,
      aropen_salescat_id=_salescatid, aropen_accnt_id=_accntid, aropen_curr_id=pCurrId,
      aropen_curr_rate=currrate(pCurrId, pDocDate),
      aropen_taxzone_id=pTaxZoneid
    WHERE aropen_id = pId;
  ELSE
    SELECT NEXTVAL('aropen_aropen_id_seq') INTO _aropenid;
    INSERT INTO aropen
    ( aropen_id, aropen_username, aropen_journalnumber,
      aropen_cust_id, aropen_docnumber, aropen_doctype, aropen_ordernumber,
      aropen_docdate, aropen_duedate, aropen_distdate, aropen_terms_id, aropen_salesrep_id,
      aropen_amount, aropen_paid, aropen_commission_due, aropen_commission_paid,
      aropen_applyto, aropen_ponumber, aropen_cobmisc_id,
      aropen_open, aropen_notes, aropen_rsncode_id,
      aropen_salescat_id, aropen_accnt_id, aropen_curr_id, aropen_curr_rate, aropen_taxzone_id )
    VALUES
    ( _aropenid, getEffectiveXtUser(), _journalNumber,
      pCustid, pDocNumber, 'D', pOrderNumber,
      pDocDate, pDueDate, pDocDate, pTermsid, pSalesrepid,
      round(pAmount, 2), pPaid, pCommissiondue, FALSE,
      '', '', -1,
      TRUE, pNotes, pRsncodeid,
      _salescatid, _accntid, pCurrId, currrate(pCurrId, pDocDate), pTaxZoneid );
  END IF;

  -- Debit the A/R account for the full amount
  SELECT insertIntoGLSeries ( _glSequence, 'A/R', 'DM',
                              pDocNumber, _arAccntid,
                              round(currToBase(pCurrId, pAmount, pDocDate) * -1, 2),
                              pDocDate, (_custName || ' ' || pNotes)) INTO _test;

  -- Credit the Tax account for the tax amount
  _taxBaseValue := addTaxToGLSeries(_glSequence,
				      'A/R', 'DM', pDocNumber,
				      pCurrId, pDocDate, pDocDate,
                                      'AR', _aropenid,
                                      (_custName || ' ' || pNotes));

  UPDATE taxhead SET taxhead_journalnumber = _journalNumber
  WHERE taxhead_doc_type = 'AR'
    AND taxhead_doc_id = _aropenid;

  -- Credit the Prepaid account for the basis amount
  SELECT insertIntoGLSeries ( _glSequence, 'A/R', 'DM',
                              pDocNumber, _prepaidAccntid,
                              round(currToBase(pCurrId, (pAmount), pDocDate), 2) - _taxBaseValue,
                              pDocDate, (_custName || ' ' || pNotes)) INTO _test;

  --  Commit the GLSeries;
  SELECT postGLSeries(_glSequence, _journalNumber) INTO _test;
  IF (_test < 0) THEN
    DELETE FROM aropen WHERE (aropen_id=_aropenid);
    PERFORM deleteGLSeries(_glSequence);
    RAISE EXCEPTION 'postGLSeries commit failed with %', _test;
  END IF;

  --  Record Sales History
  SELECT nextval('cohist_cohist_id_seq') INTO _cohistid;
  INSERT INTO cohist
  ( cohist_id, cohist_cust_id, cohist_itemsite_id, cohist_shipto_id,
    cohist_misc_type, cohist_misc_descrip,
    cohist_shipdate, cohist_shipvia,
    cohist_ordernumber, cohist_ponumber, cohist_orderdate,
    cohist_doctype, cohist_invcnumber, cohist_invcdate,
    cohist_qtyshipped, cohist_unitprice, cohist_unitcost,
    cohist_salesrep_id, cohist_commission, cohist_commissionpaid,
    cohist_curr_id, cohist_sequence )
  VALUES
  ( _cohistid, pCustid, -1, -1,
    'M', 'A/R Misc Debit Memo',
    pDocDate, '',
    '', '', pDocDate,
    'D', pDocNumber, pDocDate,
    1, (pAmount - _taxBaseValue), 0,
    pSalesrepid, pCommissiondue, FALSE,
    pCurrId, _glSequence );

  RETURN _aropenid;

END;
$$ LANGUAGE 'plpgsql';

