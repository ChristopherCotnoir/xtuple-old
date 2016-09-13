CREATE OR REPLACE FUNCTION attachQuoteToOpportunity(INTEGER, INTEGER) RETURNS INTEGER AS $$
-- Copyright (c) 1999-2014 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  pQuheadid	ALIAS FOR $1;
  pOpheadid	ALIAS FOR $2;
BEGIN

-- Check Quote
  IF (NOT EXISTS(SELECT quhead_id
                 FROM quhead
                 WHERE (quhead_id=pQuheadid))) THEN
    RAISE EXCEPTION 'The selected Quote cannot be attached because the Quote cannot be found. [xtuple: attachQuoteToOpportunity, -1]';
  END IF;

-- Check Opportunity
  IF (NOT EXISTS(SELECT ophead_id
                 FROM ophead
                 WHERE (ophead_id=pOpheadid))) THEN
    RAISE EXCEPTION 'The selected Quote cannot be attached because the Opportunity cannot be found. [xtuple: attachQuoteToOpportunity, -2]';
  END IF;

-- Cannot attach if already attached
  IF (EXISTS(SELECT quhead_id
	     FROM quhead
	     WHERE ((quhead_id=pQuheadid)
	       AND  (quhead_ophead_id IS NOT NULL)))) THEN
    RAISE EXCEPTION 'The selected Quote cannot be attached because it is already associated with an Opportunity.  You must detach this Quote before you may attach it. [xtuple: attachQuoteToOpportunity, -3]';
  END IF;

  UPDATE quhead SET quhead_ophead_id=pOpheadid
  WHERE (quhead_id=pQuheadid);

  RETURN 0;

END;
$$ LANGUAGE 'plpgsql';
