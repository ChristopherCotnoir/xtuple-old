DROP FUNCTION IF EXISTS listPriceSchedule(INTEGER, INTEGER, INTEGER, INTEGER, DATE);
CREATE OR REPLACE FUNCTION listPriceSchedule(pItemid    INTEGER,
                                             pCustid    INTEGER DEFAULT NULL,
                                             pShiptoid  INTEGER DEFAULT NULL,
                                             pSiteid    INTEGER DEFAULT NULL,
                                             pEffective DATE    DEFAULT CURRENT_DATE)
RETURNS TEXT AS $$
-- Copyright (c) 1999-2018 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  _ipsname TEXT;

BEGIN

  SELECT ipshead_name
    FROM ipshead
   WHERE ipshead_id = ipsPrice(pItemid, pSiteId, TRUE, pEffective, CURRENT_DATE, NULL, NULL, NULL
                               pCustid, pShiptoid, NULL, NULL, TRUE);

  RETURN COALESCE(_ipsname, '');

END
$$ language plpgsql;
