CREATE OR REPLACE FUNCTION priceScheduleMatch(pIpsheadId  INTEGER,
                                              pAsOf       DATE,
                                              pCustId     INTEGER,
                                              pShiptoId   INTEGER,
                                              pShipzoneId INTEGER DEFAULT NULL,
                                              pSaletypeId INTEGER DEFAULT NULL)
RETURNS INTEGER AS $$
-- Copyright (c) 1999-2018 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  _cust   RECORD;
  _shipto RECORD;
  _match  INTEGER;

BEGIN

  SELECT cust_id, custtype_id, custtype_code INTO _cust
    FROM custinfo
    JOIN custtype ON cust_custtype_id = custtype_id
   WHERE cust_id = pCustId;

  SELECT shipto_id, shipto_num INTO _shipto
    FROM shiptoinfo
   WHERE shipto_id = pShiptoId;

  -- Price Schedule Assignment Order of Precedence
  -- 1. Specific Customer Shipto Id
  -- 2. Specific Customer Shipto Pattern
  -- 3. Any Customer Shipto Pattern
  -- 4. Specific Customer
  -- 5. Customer Type
  -- 6. Customer Type Pattern
  -- 7. Shipping Zone
  -- 8. Sale Type 

  SELECT MIN(CASE WHEN sale_id IS NOT NULL                                         THEN 0
                  WHEN COALESCE(_shipto.shipto_id, -1)   = ipsass_shipto_id        THEN 1
                  WHEN COALESCE(shipto_num, '')          ~ ipsass_shipto_pattern
                   AND COALESCE(_cust.cust_id, -1)       = ipsass_cust_id          THEN 2
                  WHEN COALESCE(shipto_num, '')          ~ ipsass_shipto_pattern   THEN 3
                  WHEN COALESCE(_cust.cust_id, -1)       = ipsass_cust_id          THEN 4
                  WHEN COALESCE(_cust.custtype_id, -1)   = ipsass_custtype_id      THEN 5
                  WHEN COALESCE(_cust.custtype_code, '') ~ ipsass_custtype_pattern THEN 6
                  WHEN COALESCE(pShipZoneId, -1)         = ipsass_shipzone_id      THEN 7
                  WHEN COALESCE(pSaleTypeId, -1)         = ipsass_saletype_id      THEN 8
              END)
    INTO _match
    FROM ipshead
    JOIN ipsass ON ipshead_id = ipsass_ipshead_id
    LEFT OUTER JOIN sale ON ipshead_id = sale_ipshead_id
   WHERE ipshead_id = pIpsheadId
     AND pAsOf BETWEEN COALESCE(sale_startdate, ipsass_effective)
                   AND COALESCE(sale_enddate, ipsass_expires - 1);

  RETURN _match;

END
$$ language plpgsql;
