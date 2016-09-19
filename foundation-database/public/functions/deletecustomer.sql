
CREATE OR REPLACE FUNCTION deleteCustomer(INTEGER) RETURNS INTEGER AS $$
-- Copyright (c) 1999-2014 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  pCustid ALIAS FOR $1;

BEGIN

  PERFORM shipto_id
  FROM shiptoinfo
  WHERE (shipto_cust_id=pCustid)
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Customer cannot be deleted as there are still Ship-Tos assigned to it. You must delete all of the selected Customer''s Ship-Tos before you may delete it. [xtuple: deleteCustomer, -1]';
  END IF;

  PERFORM cohead_id
  FROM cohead
  WHERE (cohead_cust_id=pCustid)
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Customer cannot be deleted as there has been Sales History recorded for this Customer. You may Edit the selected Customer and set its status to inactive. [xtuple: deleteCustomer, -2]';
  END IF;

  PERFORM cmhead_id
  FROM cmhead
  WHERE (cmhead_cust_id=pCustid)
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION '[xtuple: deleteCustomer, -3]';
  END IF;

  PERFORM cohist_id
  FROM cohist
  WHERE (cohist_cust_id=pCustid)
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION '[xtuple: deleteCustomer, -4]';
  END IF;

  PERFORM aropen_id
  FROM aropen
  WHERE (aropen_cust_id=pCustid)
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION '[xtuple: deleteCustomer, -5]';
  END IF;

  PERFORM checkhead_recip_id
    FROM checkhead
   WHERE ((checkhead_recip_id=pCustid)
     AND  (checkhead_recip_type='C'))
   LIMIT 1;
   IF (FOUND) THEN
     RAISE EXCEPTION 'The selected Customer cannot be deleted as Payments have been written to it. [xtuple: deleteCustomer, -6]';
   END IF;

  PERFORM invchead_id
     FROM invchead
    WHERE(invchead_cust_id=pCustid)
    LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Customer cannot be deleted as there are still Invoices assigned to it. You must delete all of the selected Customer''s Invoices before you may delete it [xtuple: deleteCustomer, -7]';
  END IF;

  PERFORM quhead_id
     FROM quhead
    WHERE(quhead_cust_id=pCustid)
    LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Customer cannot be deleted as there are still Quotes assigned to it. You must delete all of the selected Customer''s Quotes before you may delete it [xtuple: deleteCustomer, -8]';
  END IF;

  DELETE FROM taxreg
   WHERE ((taxreg_rel_type='C')
     AND  (taxreg_rel_id=pCustid));

  DELETE FROM ipsass
  WHERE (ipsass_cust_id=pCustid);

  DELETE FROM custinfo
  WHERE (cust_id=pCustid);

  UPDATE crmacct SET crmacct_cust_id = NULL
  WHERE (crmacct_cust_id=pCustid);

  RETURN 0;

END;
$$ LANGUAGE 'plpgsql';

