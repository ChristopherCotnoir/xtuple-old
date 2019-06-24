
CREATE OR REPLACE FUNCTION freightDetail(text,integer,integer,integer,date,text,integer)
  RETURNS SETOF freightData AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE
  pOrderType ALIAS FOR $1;
  pOrderId ALIAS FOR $2;
  pCustId ALIAS FOR $3;
  pShiptoId ALIAS FOR $4;
  pOrderDate ALIAS FOR $5;
  pShipVia ALIAS FOR $6;
  pCurrId ALIAS FOR $7;

  _row freightData%ROWTYPE;
  _cohead RECORD;
  _order RECORD;
  _weights RECORD;
  _includepkgweight BOOLEAN := FALSE;
  _qry TEXT;
  _debug BOOLEAN := FALSE;

BEGIN
  IF (_debug) THEN
    RAISE NOTICE 'pOrderType = %', pOrderType;
    RAISE NOTICE 'pOrderId = %', pOrderId;
    RAISE NOTICE 'pCustId = %', pCustId;
    RAISE NOTICE 'pShiptoId = %', pShiptoId;
    RAISE NOTICE 'pOrderDate = %', pOrderDate;
    RAISE NOTICE 'pShipVia = %', pShipVia;
    RAISE NOTICE 'pCurrId = %', pCurrId;
  END IF;

  SELECT fetchMetricBool('IncludePackageWeight') INTO _includepkgweight;

  --Get the order header information need to match
  --against price schedules
  IF (pOrderType = 'SO') THEN
    SELECT
      cust_id AS cust_id,
      custtype_id,
      custtype_code,
      COALESCE(shipto_id, -1) AS shipto_id,
      COALESCE(shipto_num, '') AS shipto_num,
      COALESCE(pOrderDate, cohead_orderdate) AS orderdate,
      COALESCE(pShipVia, cohead_shipvia) AS shipvia,
      shipto_shipzone_id AS shipzone_id,
      COALESCE(pCurrId, cohead_curr_id) AS curr_id,
      currConcat(COALESCE(pCurrId, cohead_curr_id)) AS currAbbr
    INTO _order
      FROM cohead
      JOIN custinfo ON (cust_id=COALESCE(pCustId, cohead_cust_id))
      JOIN custtype ON (custtype_id=cust_custtype_id)
      LEFT OUTER JOIN shiptoinfo ON (shipto_id=COALESCE(pShiptoId, cohead_shipto_id))
    WHERE (cohead_id=pOrderId);

  ELSIF (pOrderType = 'QU') THEN
    SELECT
      quhead_cust_id AS cust_id,
      custtype_id,
      custtype_code,
      COALESCE(shipto_id, -1) AS shipto_id,
      COALESCE(shipto_num, '') AS shipto_num,
      quhead_quotedate AS orderdate,
      quhead_shipvia AS shipvia,
      shipto_shipzone_id AS shipzone_id,
      quhead_curr_id AS curr_id,
      currConcat(quhead_curr_id) AS currAbbr
    INTO _order
      FROM quhead
      LEFT OUTER JOIN custinfo ON (cust_id=quhead_cust_id)
      LEFT OUTER JOIN custtype ON (custtype_id=cust_custtype_id)
      LEFT OUTER JOIN shiptoinfo ON (shipto_id=quhead_shipto_id)
    WHERE (quhead_id=pOrderId);

  ELSIF (pOrderType = 'CM') THEN
    IF EXISTS(SELECT 1
                FROM pg_class
                JOIN pg_namespace on relnamespace = pg_namespace.oid
               WHERE nspname = 'public'
                 AND relname = 'rahead') THEN
      SELECT cohead_orderdate, cohead_shipvia, cohead_curr_id
        INTO _cohead
        FROM cmhead
        JOIN rahead ON cmhead_rahead_id = rahead_id
        JOIN cohead ON rahead_orig_cohead_id = cohead_id
       WHERE cmhead_id = pOrderId;
    ELSE
      SELECT NULL::DATE AS cohead_orderdate, NULL::TEXT AS cohead_shipvia, NULL::INTEGER AS cohead_curr_id
        INTO _cohead;
    END IF;

    SELECT
      cust_id AS cust_id,
      custtype_id,
      custtype_code,
      COALESCE(shipto_id, -1) AS shipto_id,
      COALESCE(shipto_num, '') AS shipto_num,
      COALESCE(pOrderDate, invchead_orderdate, _cohead.cohead_orderdate, cmhead_docdate) AS orderdate,
      COALESCE(pShipVia, invchead_shipvia, _cohead.cohead_shipvia, cmhead_shipvia) AS shipvia,
      shipto_shipzone_id AS shipzone_id,
      COALESCE(pCurrId, invchead_curr_id, _cohead.cohead_curr_id, cmhead_curr_id) AS curr_id,
      currConcat(COALESCE(pCurrId, invchead_curr_id, _cohead.cohead_curr_id, cmhead_curr_id)) AS currAbbr
    INTO _order
      FROM cmhead
      JOIN custinfo ON (cust_id=COALESCE(pCustId, cmhead_cust_id))
      JOIN custtype ON (custtype_id=cust_custtype_id)
      LEFT OUTER JOIN shiptoinfo ON (shipto_id=COALESCE(pShiptoId, cmhead_shipto_id))
      LEFT OUTER JOIN invchead ON cmhead_invcnumber = invchead_invcnumber
    WHERE (cmhead_id=pOrderId);

  ELSIF (pOrderType = 'RA') THEN
    SELECT
      cust_id AS cust_id,
      custtype_id,
      custtype_code,
      COALESCE(shipto_id, -1) AS shipto_id,
      COALESCE(shipto_num, '') AS shipto_num,
      COALESCE(pOrderDate, cohead_orderdate, rahead_authdate) AS orderdate,
      COALESCE(pShipVia, cohead_shipvia, rahead_shipvia) AS shipvia,
      shipto_shipzone_id AS shipzone_id,
      COALESCE(pCurrId, cohead_curr_id, rahead_curr_id) AS curr_id,
      currConcat(COALESCE(pCurrId, cohead_curr_id, rahead_curr_id)) AS currAbbr
    INTO _order
      FROM rahead
      JOIN custinfo ON (cust_id=COALESCE(pCustId, rahead_cust_id))
      JOIN custtype ON (custtype_id=cust_custtype_id)
      LEFT OUTER JOIN shiptoinfo ON (shipto_id=COALESCE(pShiptoId, rahead_shipto_id))
      LEFT OUTER JOIN cohead ON rahead_orig_cohead_id = cohead_id
    WHERE (rahead_id=pOrderId);

  ELSE
    RAISE EXCEPTION 'Invalid order type.';
  END IF;

  IF (_debug) THEN
    RAISE NOTICE 'cust_id = %', _order.cust_id;
    RAISE NOTICE 'custtype_id = %', _order.custtype_id;
    RAISE NOTICE 'shipto_id = %', _order.shipto_id;
    RAISE NOTICE 'shipto_num = %', _order.shipto_num;
    RAISE NOTICE 'orderdate = %', _order.orderdate;
    RAISE NOTICE 'shipvia = %', _order.shipvia;
    RAISE NOTICE 'shipzone_id = %', _order.shipzone_id;
    RAISE NOTICE 'curr_id = %', _order.curr_id;
    RAISE NOTICE 'currAbbr = %', _order.currAbbr;
  END IF;

  --Get a list of aggregated weights from sites and
  --freight classes used on order lines

  IF (_includePkgWeight) THEN
    _qry := 'SELECT SUM(orderitem_qty_ordered * orderitem_qty_invuomratio * (item_prodweight + item_packweight)) AS weight, ';
  ELSE
    _qry := 'SELECT SUM(orderitem_qty_ordered * orderitem_qty_invuomratio * item_prodweight) AS weight, ';
  END IF;

  _qry := _qry || 'itemsite_warehous_id, COALESCE(item_freightclass_id, -1) AS item_freightclass_id
    FROM orderitem
    JOIN itemsite ON (itemsite_id=orderitem_itemsite_id)
    JOIN item ON (item_id=itemsite_item_id) ';

  IF (pOrderType = 'RA') THEN
    _qry := _qry || 'JOIN raitem ON ((orderitem_id=raitem_id)
    AND (raitem_disposition IN (''C'',''R'',''P'')))
    JOIN rahead ON orderitem_orderhead_id=rahead_id
    AND rahead_creditmethod!=''N'' ';
  END IF;

  _qry := _qry || '
    WHERE ( (orderitem_orderhead_type=' || quote_literal(pOrderType) || ')
      AND (orderitem_orderhead_id=' || quote_literal(pOrderId) || ')
      AND (orderitem_status <> ''X'') )
    GROUP BY itemsite_warehous_id, item_freightclass_id;';

  IF pOrderType = 'CM' THEN
    IF (_includePkgWeight) THEN
      _qry := 'SELECT SUM(cmitem_qtycredit * cmitem_qty_invuomratio * (item_prodweight + item_packweight)) AS weight, ';
    ELSE
      _qry := 'SELECT SUM(cmitem_qtycredit * cmitem_qty_invuomratio * item_prodweight) AS weight, ';
    END IF;

    _qry := _qry || 'itemsite_warehous_id, COALESCE(item_freightclass_id, -1) AS item_freightclass_id
      FROM cmitem
      JOIN itemsite ON (itemsite_id=cmitem_itemsite_id)
      JOIN item ON (item_id=itemsite_item_id)
      WHERE ( (cmitem_cmhead_id=' || quote_literal(pOrderId) || ') )
      GROUP BY itemsite_warehous_id, item_freightclass_id;';
  END IF;

  FOR _weights IN
    EXECUTE _qry LOOP

    _row := calculateFreightDetail(
      _order.cust_id, --pCustId
      _order.custtype_id, --pCustTypeId
      _order.custtype_code, --pCustTypeCode
      _order.shipto_id, --pShiptoId
      _order.shipzone_id, --pShipZoneId
      _order.shipto_num, --pShiptoNum
      _order.orderdate, --pOrderDate
      _order.shipvia, --pShipVia
      _order.curr_id, --pCurrId
      _order.currAbbr, --pCurrAbbr
      _weights.itemsite_warehous_id, --pItemSiteWhsId
      _weights.item_freightclass_id, --pItemFreightclassId
      _weights.weight --pWeight
      );

    RETURN NEXT _row;

  END LOOP;
  RETURN;
END;
$$ LANGUAGE 'plpgsql';

