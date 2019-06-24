CREATE OR REPLACE FUNCTION calculateTax(pOrderType        TEXT,
                                        pOrderNumber      TEXT,
                                        pTaxZoneId        INTEGER,
                                        pFromLine1        TEXT,
                                        pFromLine2        TEXT,
                                        pFromLine3        TEXT,
                                        pFromCity         TEXT,
                                        pFromState        TEXT,
                                        pFromZip          TEXT,
                                        pFromCountry      TEXT,
                                        pToLine1          TEXT,
                                        pToLine2          TEXT,
                                        pToLine3          TEXT,
                                        pToCity           TEXT,
                                        pToState          TEXT,
                                        pToZip            TEXT,
                                        pToCountry        TEXT,
                                        pSingleLocation   BOOLEAN,
                                        pCust             TEXT,
                                        pUsage            TEXT,
                                        pTaxReg           TEXT,
                                        pCurrId           INTEGER,
                                        pDocDate          DATE,
                                        pOrigDate         DATE,
                                        pOrigOrder        TEXT,
                                        pFreight          NUMERIC,
                                        pMisc             NUMERIC,
                                        pMiscDescrip      TEXT,
                                        pFreightTaxtypeId INTEGER,
                                        pMiscTaxtypeId    INTEGER,
                                        pMiscDiscount     BOOLEAN,
                                        pFreightLine1     TEXT[],
                                        pFreightLine2     TEXT[],
                                        pFreightLine3     TEXT[],
                                        pFreightCity      TEXT[],
                                        pFreightState     TEXT[],
                                        pFreightZip       TEXT[],
                                        pFreightCountry   TEXT[],
                                        pFreightSplit     NUMERIC[],
                                        pLines            TEXT[],
                                        pLineCodes        TEXT[],
                                        pLineUpc          TEXT[],
                                        pLineDescrips     TEXT[],
                                        pQtys             NUMERIC[],
                                        pTaxTypes         INTEGER[],
                                        pAmounts          NUMERIC[],
                                        pUsages           TEXT[],
                                        pLineLine1        TEXT[],
                                        pLineLine2        TEXT[],
                                        pLineLine3        TEXT[],
                                        pLineCity         TEXT[],
                                        pLineState        TEXT[],
                                        pLineZip          TEXT[],
                                        pLineCountry      TEXT[],
                                        pTaxPaid          NUMERIC,
                                        pRecord           BOOLEAN) RETURNS JSONB AS
$$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE
  _service TEXT;
  _taxtypeid INTEGER;
  _taxtypes TEXT[] := ARRAY[]::TEXT[];
  _freighttaxtype TEXT;
  _misctaxtype TEXT;

BEGIN

  _service := fetchMetricText('TaxService');

  IF COALESCE(_service, 'N') != 'N' THEN
    FOREACH _taxtypeid IN ARRAY pTaxTypes
    LOOP
      _taxtypes := _taxtypes || (SELECT taxtype_external_code
                                   FROM taxtype
                                  WHERE taxtype_id = _taxtypeid);
    END LOOP;

    SELECT taxtype_external_code
      INTO _freighttaxtype
      FROM taxtype
     WHERE taxtype_id = pFreightTaxtypeId;

    SELECT taxtype_external_code
      INTO _misctaxtype
      FROM taxtype
     WHERE taxtype_id = pMiscTaxtypeId;
  END IF;

  IF _service = 'A' THEN
    RETURN formatAvaTaxPayload(pOrderType, pOrderNumber, pFromLine1, pFromLine2, pFromLine3,
                               pFromCity, pFromState, pFromZip, pFromCountry, pToLine1, pToLine2,
                               pToLine3, pToCity, pToState, pToZip, pToCountry, pSingleLocation,
                               pCust, pUsage, pTaxReg, pCurrId, pDocDate, pOrigDate, pOrigOrder,
                               pFreight, pMisc, pMiscDescrip, _freighttaxtype, _misctaxtype,
                               pMiscDiscount, pFreightLine1, pFreightLine2, pFreightLine3,
                               pFreightCity, pFreightState, pFreightZip, pFreightCountry,
                               pFreightSplit, pLines, pLineCodes, pLineUpc, pLineDescrips, pQtys,
                               _taxtypes, pAmounts, pUsages, pLineLine1, pLineLine2, pLineLine3,
                               pLineCity, pLineState, pLineZip, pLineCountry, pTaxPaid, pRecord);
  ELSE
    RETURN calculateTax(pTaxZoneId, pCurrId, pDocDate, pFreight, pMisc, pFreightTaxtypeId,
                        pMiscTaxtypeId, pMiscDiscount, pLines, pTaxTypes, pAmounts);
  END IF;

END
$$ language plpgsql;

CREATE OR REPLACE FUNCTION calculateTax(pTaxZoneId INTEGER,
                                        pCurrId INTEGER,
                                        pDocDate DATE,
                                        pFreight NUMERIC,
                                        pMisc NUMERIC,
                                        pFreightTaxtypeId INTEGER,
                                        pMiscTaxtypeId INTEGER,
                                        pMiscDiscount BOOLEAN,
                                        pLines TEXT[],
                                        pTaxTypes INTEGER[],
                                        pAmounts NUMERIC[]) RETURNS JSONB AS
$$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE
  _precision INTEGER := 2;
  _includemisc BOOLEAN;
  _taxtypes INTEGER[] := ARRAY[]::INTEGER[];
  _amounts NUMERIC[] := ARRAY[]::NUMERIC[];
  _numlines NUMERIC;
  _line INTEGER;
  _linetotal NUMERIC;
  _prevlinetotal NUMERIC;
  _prevseq INTEGER;
  _linedetail TEXT;
  _total NUMERIC := 0;
  _first BOOLEAN;
  _anytaxzone BOOLEAN;
  _anytaxtype BOOLEAN;
  _tax RECORD;
  _taxdetail TEXT;
  _amount NUMERIC;
  _freight TEXT;
  _misc TEXT;
  _lines TEXT := '';
  _result TEXT;

BEGIN
  _numlines := COALESCE(array_length(pLines, 1), 0);
  _includemisc := pMiscTaxtypeId IS NOT NULL;

  _taxtypes := pTaxTypes;
  IF (pFreightTaxtypeId IS NOT NULL) THEN
    _taxtypes := _taxtypes || pFreightTaxtypeId;
  END IF;
  IF _includemisc THEN
    _taxtypes := _taxtypes || pMiscTaxtypeId;
  END IF;

  IF pMiscDiscount AND pMisc < 0 THEN
    _amounts := distributeDiscount(pAmounts, pMisc * -1, _precision);
  ELSE
    _amounts := pAmounts;
  END IF;
  _amounts := _amounts || COALESCE(pFreight, 0);
  IF _includemisc IS NOT NULL THEN 
    _amounts := _amounts || COALESCE(pMisc, 0);
  END IF;

  FOR _line IN 1.._numlines + CASE WHEN _includemisc THEN 2 ELSE 1 END
  LOOP
    IF pTaxZoneId IS NULL OR _taxtypes[_line] IS NULL THEN
      IF _line <= _numlines THEN
        IF _line != 1 THEN
          _lines := _lines || ',';
        END IF;
        _lines := _lines || '{"line": "' || pLines[_line] || '", "taxtypeid": ' ||
                  COALESCE(_taxtypes[_line], -1) || ', "taxable": ' || _amounts[_line] ||
                  ', "tax": [] }';
      ELSIF _line = _numlines + 1 THEN
        _freight := '{"taxtypeid": ' || _taxtypes[_line] || ', "taxable": ' || _amounts[_line] ||
                    ', "tax": [] }';
      ELSIF _line = _numlines + 2 THEN
        _misc := '{"taxtypeid": ' || _taxtypes[_line] || ', "taxable": ' || _amounts[_line] ||
                 ', "tax": [] }';
      END IF;

      CONTINUE;
    END IF;

    IF _line = _numlines + 2 AND pMiscDiscount AND pMisc < 0 THEN
        _misc := '{"taxtypeid": ' || _taxtypes[_line] || ', "taxable": ' || _amounts[_line] ||
                 ', "tax": [] }';

      CONTINUE;
    END IF;

    _linetotal := 0;
    _prevlinetotal := 0;
    _prevseq := 0;

    IF _line <= _numlines THEN
      _linedetail := '{"line": "' || pLines[_line] || '", "taxtypeid": ' || _taxtypes[_line] ||
                     ', "taxable": ' || _amounts[_line] || ', "tax": [';
    ELSE
      _linedetail := '{"taxtypeid": ' || _taxtypes[_line] || ', "taxable": ' || _amounts[_line] ||
                     ', "tax": [';
    END IF;
    _first := true;

    SELECT taxass_taxzone_id IS NULL, taxass_taxtype_id IS NULL
      INTO _anytaxzone, _anytaxtype
      FROM taxass
     WHERE COALESCE(taxass_taxzone_id, pTaxZoneId) = pTaxZoneId
       AND COALESCE(taxass_taxtype_id, _taxtypes[_line]) = _taxtypes[_line]
     ORDER BY taxass_taxzone_id IS NULL, taxass_taxtype_id IS NULL
     LIMIT 1;

    FOR _tax IN
    SELECT tax_id, COALESCE(taxclass_sequence, 0) AS taxclass_sequence
      FROM taxass
      JOIN tax ON taxass_tax_id = tax_id
      LEFT OUTER JOIN taxclass ON tax_taxclass_id = taxclass_id
     WHERE CASE WHEN _anytaxzone THEN taxass_taxzone_id IS NULL
                ELSE taxass_taxzone_id = pTaxZoneId
            END
       AND CASE WHEN _anytaxtype THEN taxass_taxtype_id IS NULL
                ELSE taxass_taxtype_id = _taxtypes[_line]
            END
     ORDER BY COALESCE(taxclass_sequence, 0)
    LOOP
      IF _tax.taxclass_sequence != _prevseq THEN
        _prevlinetotal := _linetotal;
        _prevseq := _tax.taxclass_sequence;
      END IF;

      WITH RECURSIVE _taxamount AS
      (
       SELECT ROUND(taxrate_percent * (_prevlinetotal + _amounts[_line]) +
                    currToCurr(taxrate_curr_id, pCurrId, taxrate_amount, pDocDate), _precision)
              AS tax, tax_id, COALESCE(tax_basis_tax_id, -1) AS tax_basis_tax_id,
              COALESCE(taxclass_id, -1) AS taxclass_id,
              COALESCE(taxrate_percent, 0.0) AS taxrate_percent,
              COALESCE(currToCurr(taxrate_curr_id, pCurrId, taxrate_amount, pDocDate), 0.0)
              AS taxrate_amount
         FROM tax
         LEFT OUTER JOIN taxclass ON tax_taxclass_id = taxclass_id
         LEFT OUTER JOIN taxrate ON tax_id = taxrate_tax_id
                                AND pDocDate BETWEEN COALESCE(taxrate_effective, startOfTime())
                                                 AND COALESCE(taxrate_expires, endOfTime())
        WHERE tax_id = _tax.tax_id
       UNION
       SELECT ROUND(subtaxrate.taxrate_percent * _taxamount.tax +
                    currToCurr(subtaxrate.taxrate_curr_id, pCurrId, subtaxrate.taxrate_amount,
                               pDocDate), _precision) AS tax, subtax.tax_id AS tax_id,
              COALESCE(subtax.tax_basis_tax_id, -1) AS tax_basis_tax_id,
              COALESCE(subtaxclass.taxclass_id, -1) AS taxclass_id,
              COALESCE(subtaxrate.taxrate_percent, 0.0) AS taxrate_percent,
              COALESCE(currToCurr(subtaxrate.taxrate_curr_id, pCurrId, subtaxrate.taxrate_amount,
                                  pDocDate), 0.0) AS taxrate_amount
         FROM _taxamount
         JOIN tax subtax ON _taxamount.tax_id = subtax.tax_basis_tax_id
         LEFT OUTER JOIN taxclass subtaxclass ON subtax.tax_taxclass_id = subtaxclass.taxclass_id
         LEFT OUTER JOIN taxrate subtaxrate ON subtax.tax_id = subtaxrate.taxrate_tax_id
                                           AND pDocDate BETWEEN
                                                        COALESCE(subtaxrate.taxrate_effective,
                                                                 startOfTime())
                                                        AND
                                                        COALESCE(subtaxrate.taxrate_expires,
                                                                 endOfTime())
      )
      SELECT COALESCE(string_agg('{"taxid": ' || tax_id || ', "basistaxid": ' || tax_basis_tax_id ||
                                 ', "taxclassid": ' || taxclass_id || ', "sequence": ' ||
                                 _tax.taxclass_sequence || ', "percent": ' || taxrate_percent ||
                                 ', "amount": ' || taxrate_amount || ', "tax": ' || tax || '}',
                                 ','), ''), SUM(tax)
        INTO _taxdetail, _amount
        FROM _taxamount;

      IF NOT _first THEN
        _linedetail := _linedetail || ',';
      END IF;

      _first := false;

      _linedetail := _linedetail || _taxdetail;
      _linetotal := _linetotal + _amount;
    END LOOP;

    _linedetail := _linedetail || '] }';
    _total := _total + _linetotal;

    IF _line <= _numLines THEN
      IF _line != 1 THEN
        _lines := _lines || ',';
      END IF;
      _lines := _lines || _linedetail;
    ELSIF _line = _numlines + 1 THEN
      _freight := _linedetail;
    ELSIF _line = _numlines + 2 THEN
      _misc := _linedetail;
    END IF;
  END LOOP;

  _result := '{"currid": ' || pCurrId || ', "currrate": ' || currRate(pCurrId, pDocDate) ||
             ', "date": "' || pDocDate || '", "total": ' || _total || ', "discount": ' ||
             CASE WHEN pMiscDiscount AND pMisc < 0 THEN pMisc * -1 ELSE 0.0 END ||
             ', "lines": [' || _lines ||
             '], "freight": ' || _freight;

  IF _includemisc THEN
    _result := _result || ', "misc": ' || _misc;
  END IF;

  _result := _result || '}';

  RETURN _result::JSONB;

END
$$ language plpgsql;
