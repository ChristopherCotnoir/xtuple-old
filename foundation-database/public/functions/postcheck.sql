CREATE OR REPLACE FUNCTION postcheck(integer, integer)
  RETURNS integer AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE
  pcheckid		ALIAS FOR $1;
  _journalNumber	INTEGER := $2;
  _amount_base		NUMERIC := 0;
  _credit_glaccnt	INTEGER;
  _exchGain		NUMERIC := 0;
  _exchGainTmp		NUMERIC := 0;
  _gltransNote		TEXT;
  _p			RECORD;
  _r			RECORD;
  _t			RECORD;
  _tax			RECORD;
  _sequence		INTEGER;
  _test                 INTEGER;
  _cm                   BOOLEAN;
  _amount_check         NUMERIC := 0;
  _taxheadid            INTEGER;
  _taxlineid            INTEGER;

BEGIN

  _cm := FALSE;

  SELECT fetchGLSequence() INTO _sequence;
  IF (_journalNumber IS NULL) THEN
    _journalNumber := fetchJournalNumber('AP-CK');
  END IF;

  SELECT checkhead.*, bankaccnt_prnt_check,
         checkhead_amount / checkhead_curr_rate AS checkhead_amount_base,
         COALESCE(calculateinversetax(checkhead_taxzone_id, checkhead_taxtype_id, 
            checkhead_checkdate, checkhead_curr_id, checkhead_amount),0) as total_tax,
         bankaccnt_accnt_id AS bankaccntid 
  INTO _p
  FROM checkhead
   JOIN bankaccnt ON (checkhead_bankaccnt_id=bankaccnt_id)
  WHERE (checkhead_id=pcheckid);

  IF (FOUND) THEN
    IF (_p.checkhead_recip_type = 'V') THEN
      SELECT
        vend_number AS checkrecip_number,
        vend_name AS checkrecip_name,
        findAPAccount(vend_id) AS checkrecip_accnt_id,
        'A/P'::text AS checkrecip_gltrans_source
        INTO _t
      FROM vendinfo
      WHERE (vend_id=_p.checkhead_recip_id);
    ELSIF (_p.checkhead_recip_type = 'C') THEN
      SELECT
        cust_number AS checkrecip_number,
        cust_name AS checkrecip_name,
        findARAccount(cust_id) AS checkrecip_accnt_id,
        'A/R'::text AS checkrecip_gltrans_source
        INTO _t
      FROM custinfo
      WHERE (cust_id=_p.checkhead_recip_id); 
    ELSIF (_p.checkhead_recip_type = 'T') THEN
      SELECT
        taxauth_code AS checkrecip_number,
        taxauth_name AS checkrecip_name,
        taxauth_accnt_id AS checkrecip_accnt_id,
        'G/L'::text AS checkrecip_gltrans_source
        INTO _t
      FROM taxauth
      WHERE (taxauth_id=_p.checkhead_recip_id);
    ELSE
      RAISE EXCEPTION 'Error Retrieving Check Information [xtuple: postCheck, -11, %]', pcheckid;
    END IF;
  ELSE
    RAISE EXCEPTION 'Error Retrieving Check Information [xtuple: postCheck, -11, %]', pcheckid;
  END IF;

  IF (_p.bankaccnt_prnt_check AND NOT _p.checkhead_printed) THEN
    RAISE EXCEPTION 'This payment must be printed before posting [xtuple: postCheck, -9, %]', pcheckid;
  END IF;

  IF (_p.checkhead_posted) THEN
    RAISE EXCEPTION 'This payment has already been posted [xtuple: postCheck, -10, %]', pcheckid;
  END IF;

  IF (_p.checkhead_recip_type = 'C') THEN
    _cm := EXISTS(SELECT 1 FROM checkitem WHERE (checkitem_checkhead_id=pcheckid));
  END IF;

  _gltransNote := _t.checkrecip_number || '-' || _t.checkrecip_name ||
                  E'\n' || _p.checkhead_for || E'\n' || _p.checkhead_notes;

  IF (_p.checkhead_misc AND NOT _cm) THEN
    IF (COALESCE(_p.checkhead_expcat_id, -1) < 0) THEN
      IF (_p.checkhead_recip_type = 'V') THEN
	PERFORM createAPCreditMemo( _p.checkhead_recip_id, _journalNumber,
				    CAST(fetchAPMemoNumber() AS text), '',
				    _p.checkhead_checkdate, _p.checkhead_amount,
				    _gltransNote || ' ' || _p.checkhead_notes,
				    -1, _p.checkhead_checkdate,
				    -1, _p.checkhead_curr_id );
	_credit_glaccnt := findAPPrepaidAccount(_p.checkhead_recip_id);

      ELSIF (_p.checkhead_recip_type = 'C') THEN
	PERFORM createARDebitMemo(NULL, _p.checkhead_recip_id, NULL,
	  			     fetchARMemoNumber(), '',
				     _p.checkhead_checkdate, _p.checkhead_amount,
				     _gltransNote || ' ' || _p.checkhead_notes,
                                     -1, -1, -1, _p.checkhead_checkdate, -1, NULL, 0,
				     _p.checkhead_curr_id );
        _credit_glaccnt := findPrepaidAccount(_p.checkhead_recip_id);
      ELSIF (_p.checkhead_recip_type = 'T') THEN
	-- TODO: should we create a credit memo for the tax authority? how?
	_credit_glaccnt := _t.checkrecip_accnt_id;

      END IF; -- recip type

    ELSE
      SELECT expcat_exp_accnt_id INTO _credit_glaccnt
        FROM expcat
        WHERE (expcat_id=_p.checkhead_expcat_id);
        IF (NOT FOUND) THEN
          RAISE EXCEPTION 'Could not determine the Expense Account for this Expense Category [xtuple: postCheck, -12, %]', _p.checkhead_expcat_id;
        END IF;
    END IF;

    IF (COALESCE(_credit_glaccnt, -1) < 0) THEN
      RAISE EXCEPTION 'Could not determine the Credit GL Account [xtuple: postCheck, -13]';
    END IF;

    -- Expense Category posting
    PERFORM insertIntoGLSeries( _sequence, _t.checkrecip_gltrans_source, 'CK',
				CAST(_p.checkhead_number AS TEXT),
				_credit_glaccnt,
				round((_p.checkhead_amount_base - _p.total_tax), 2) * -1,
				_p.checkhead_checkdate, _gltransNote, pcheckid );

    IF (_p.total_tax > 0) THEN
      -- Now apply Expense Category taxation (if applicable)
          INSERT INTO taxhead (taxhead_status, taxhead_doc_type, taxhead_doc_id, taxhead_cust_id,
                               taxhead_date, taxhead_curr_id, taxhead_curr_rate,
                               taxhead_taxzone_id, taxhead_journalnumber)
          SELECT 'P', 'CK', pCheckId, _p.checkhead_recip_id,
                 _p.checkhead_checkdate, _p.checkhead_curr_id, _p.checkhead_curr_rate,
                 _p.checkhead_taxzone_id, _journalNumber
          RETURNING taxhead_id INTO _taxheadid;

          INSERT INTO taxline (taxline_taxhead_id, taxline_line_type, taxline_line_id,
                               taxline_taxtype_id, taxline_qty, taxline_amount,
                               taxline_extended)
          SELECT _taxheadid, 'L', pCheckId,
                 _p.checkhead_taxtype_id, 1.0, _p.checkhead_amount - _p.total_tax,
                 _p.checkhead_amount - _p.total_tax
          RETURNING taxline_id INTO _taxlineid;

          INSERT INTO taxdetail (taxdetail_taxline_id, taxdetail_taxable, taxdetail_tax_id,
                                 taxdetail_taxclass_id, taxdetail_sequence,
                                 taxdetail_basis_tax_id, taxdetail_amount,
                                 taxdetail_percent, taxdetail_tax)
          SELECT _taxlineid, _p.checkhead_amount - _p.total_tax, (value->>'taxid')::INTEGER,
                 NULLIF((value->>'taxclassid')::INTEGER, -1), (value->>'sequence')::INTEGER,
                 NULLIF((value->>'basistaxid')::INTEGER, -1), (value->>'amount')::NUMERIC,
                 (value->>'percent')::NUMERIC, (value->>'tax')::NUMERIC
            FROM jsonb_array_elements(calculatetax(_p.checkhead_taxzone_id,_p.checkhead_curr_id,
                                      _p.checkhead_checkdate, 0.0, 0.0, getFreightTaxtypeId(),
                                      getMiscTaxtypeId(), FALSE, ARRAY[''],
                                      ARRAY[_p.checkhead_taxtype_id],
                                      ARRAY[_p.checkhead_amount-_p.total_tax])->'lines'->0->'tax');
              
      PERFORM addTaxToGLSeries(_sequence,
		       _t.checkrecip_gltrans_source, 'CK', CAST(_p.checkhead_number AS TEXT),
		       _p.checkhead_curr_id, _p.checkhead_checkdate, _p.checkhead_checkdate,
                      'CK', pcheckid,
                      _gltransNote);      

    END IF;

    _amount_base := _p.checkhead_amount_base;

  ELSE
    FOR _r IN SELECT checkitem_amount, checkitem_discount,
                     CASE WHEN (checkitem_apopen_id IS NOT NULL AND apopen_doctype='C') THEN
                            checkitem_amount * -1.0
                          ELSE
                            checkitem_amount
                     END /
                     CASE WHEN (checkitem_apopen_id IS NOT NULL) THEN
                            apopen_curr_rate
                          ELSE
                            aropen_curr_rate
                     END AS checkitem_amount_base,
                     CASE WHEN (checkitem_apopen_id IS NOT NULL AND apopen_doctype='C') THEN
                            checkitem_amount * -1.0
                          ELSE checkitem_amount
                      END * checkhead_curr_rate / checkitem_curr_rate AS amount_check,
                     apopen_id, apopen_doctype, apopen_docnumber,
                     aropen_id, aropen_doctype, aropen_docnumber,
                     checkitem_curr_id, COALESCE(apopen_curr_rate, aropen_curr_rate) AS curr_rate,
                     checkitem_curr_rate, checkhead_curr_rate
              FROM (checkitem JOIN checkhead ON checkitem_checkhead_id=checkhead_id LEFT OUTER JOIN
		    apopen ON (checkitem_apopen_id=apopen_id)) LEFT OUTER JOIN
		    aropen ON (checkitem_aropen_id=aropen_id)
              WHERE (checkitem_checkhead_id=pcheckid) LOOP

      _exchGainTmp := 0;
      IF (_r.apopen_id IS NOT NULL) THEN
	--  take the discount if specified before we do anything else
        IF(_r.checkitem_discount > 0.0) THEN
          PERFORM createAPDiscount(_r.apopen_id, _r.checkitem_discount);
        END IF;

        UPDATE apopen

        SET apopen_paid = round(apopen_paid + _r.checkitem_amount, 2),
            apopen_open = round(apopen_amount, 2) >
			  round(apopen_paid + _r.checkitem_amount, 2),
            apopen_closedate = CASE WHEN (round(apopen_amount, 2) <=
			                  round(apopen_paid + _r.checkitem_amount, 2)) THEN _p.checkhead_checkdate END
        WHERE (apopen_id=_r.apopen_id);

	--  Post the application
        INSERT INTO apapply
        ( apapply_vend_id, apapply_postdate, apapply_username,
          apapply_source_apopen_id, apapply_source_doctype, apapply_source_docnumber,
          apapply_target_apopen_id, apapply_target_doctype, apapply_target_docnumber,
          apapply_journalnumber, apapply_amount, apapply_curr_id, apapply_target_paid, apapply_checkhead_id )
        VALUES
        ( _p.checkhead_recip_id, _p.checkhead_checkdate, getEffectiveXtUser(),
          -1, 'K', _p.checkhead_number,
          _r.apopen_id, _r.apopen_doctype, _r.apopen_docnumber,
          _journalNumber, _r.checkitem_amount, _r.checkitem_curr_id, _r.checkitem_amount, _p.checkhead_id );
      END IF; -- if check item's apopen_id is not null

      IF (_r.aropen_id IS NOT NULL) THEN

        UPDATE aropen
        SET aropen_paid = round(aropen_paid + _r.checkitem_amount, 2),
            aropen_open = round(aropen_amount, 2) >
			  round(aropen_paid + _r.checkitem_amount, 2),
            aropen_closedate = CASE WHEN (round(aropen_amount, 2) <=
			                  round(aropen_paid + _r.checkitem_amount, 2)) THEN _p.checkhead_checkdate END
        WHERE (aropen_id=_r.aropen_id);

	--  Post the application
        INSERT INTO arapply
        ( arapply_cust_id, arapply_postdate, arapply_distdate, arapply_username,
          arapply_source_aropen_id, arapply_source_doctype, arapply_source_docnumber,
          arapply_target_aropen_id, arapply_target_doctype, arapply_target_docnumber,
          arapply_journalnumber, arapply_applied, arapply_curr_id )
        VALUES
        ( _p.checkhead_recip_id, _p.checkhead_checkdate, _p.checkhead_checkdate, getEffectiveXtUser(),
          _r.aropen_id,_r.aropen_doctype, _r.aropen_docnumber,
          -1, 'K',_p.checkhead_number ,
          _journalNumber, _r.checkitem_amount, _r.checkitem_curr_id );

      END IF; -- if check item's aropen_id is not null

      SELECT currGain(_r.checkitem_amount, _r.curr_rate, _r.checkitem_curr_rate)
        INTO _exchGainTmp;

      IF (_r.apopen_doctype = 'C') THEN
        _exchGainTmp = _exchGainTmp * -1;
      END IF; 
      _exchGain := _exchGain + _exchGainTmp;

      PERFORM insertIntoGLSeries( _sequence, _t.checkrecip_gltrans_source,
                                  'CK', CAST(_p.checkhead_number AS TEXT),
                                  _t.checkrecip_accnt_id,
                                  round(_r.checkitem_amount_base, 2) * -1.0,
                                  _p.checkhead_checkdate, _gltransNote, pcheckid );
      IF (_exchGainTmp <> 0) THEN
	PERFORM insertIntoGLSeries( _sequence, _t.checkrecip_gltrans_source,
                                   'CK', CAST(_p.checkhead_number AS TEXT),
                                   getGainLossAccntId(_t.checkrecip_accnt_id),
                                   round(_exchGainTmp,2),
                                   _p.checkhead_checkdate, _gltransNote, pcheckid );
      END IF;

      _amount_check := (_amount_check + _r.amount_check);
      _amount_base := (_amount_base + _r.checkitem_amount_base);

    END LOOP;

    IF( (_amount_check - _p.checkhead_amount) <> 0.0 ) THEN 
      _exchGainTmp := (_amount_check - _p.checkhead_amount) / _p.checkhead_curr_rate;
      _exchGain := _exchGain + _exchGainTmp;
    END IF;
    --  ensure that the check balances, attribute rounding errors to gain/loss
    IF round(_amount_base, 2) - round(_exchGain, 2) <> round(_p.checkhead_amount_base, 2) THEN
      IF round(_amount_base - _exchGain, 2) = round(_p.checkhead_amount_base, 2) THEN
	PERFORM insertIntoGLSeries( _sequence, _t.checkrecip_gltrans_source,
				    'CK',
				    CAST(_p.checkhead_number AS TEXT),
                                    getGainLossAccntId(_p.bankaccntid),
				    round(_amount_base, 2) -
				      round(_exchGain, 2) -
				      round(_p.checkhead_amount_base, 2),
				    _p.checkhead_checkdate, _gltransNote, pcheckid );
      ELSE
	RAISE EXCEPTION 'checkhead_id % does not balance (% - % <> %)', pcheckid,
	      _amount_base, _exchGain, _p.checkhead_amount_base;
      END IF;
    END IF;
  END IF;

  PERFORM insertIntoGLSeries( _sequence, _t.checkrecip_gltrans_source, 'CK',
			      CAST(_p.checkhead_number AS TEXT),
                              _p.bankaccntid,
			      round(_p.checkhead_amount_base, 2),
                              _p.checkhead_checkdate, _gltransNote, pcheckid );

  -- Post any gain/loss from the alternate currency exchange rate
  IF (COALESCE(_p.checkhead_alt_curr_rate, 0.0) <> 0.0) THEN
    _exchGain := ROUND((_p.checkhead_curr_rate - _p.checkhead_alt_curr_rate) * _p.checkhead_amount_base, 2);

    IF (_exchGain <> 0) THEN
      PERFORM insertIntoGLSeries( _sequence, _t.checkrecip_gltrans_source, 'CK',
                          CAST(_p.checkhead_number AS TEXT),
                          _p.bankaccntid, (_exchGain * -1.0),
                          _p.checkhead_checkdate, _gltransNote, pcheckid );      
                          
      PERFORM insertIntoGLSeries( _sequence, _t.checkrecip_gltrans_source, 'CK',
                          CAST(_p.checkhead_number AS TEXT),
                          getGainLossAccntId(_p.bankaccntid), _exchGain,
                          _p.checkhead_checkdate, _gltransNote, pcheckid );      
    END IF;
  END IF;

  PERFORM postGLSeries(_sequence, _journalNumber);

  UPDATE checkhead
  SET checkhead_posted=TRUE,
      checkhead_journalnumber=_journalNumber
  WHERE (checkhead_id=pcheckid);

  RETURN _journalNumber;

END;
$$ LANGUAGE plpgsql;
