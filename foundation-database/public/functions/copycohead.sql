CREATE OR REPLACE FUNCTION copycohead(pcoheadid INTEGER, pcodate TIMESTAMP WITH TIME ZONE) RETURNS INTEGER AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.

BEGIN
  IF packageIsEnabled('subscriptions') THEN
    --Check if this is a subscription and copy accordingly or do a standard copy.
    RETURN subscriptions.copySubscriptionSO(pcoheadid, pcodate);
  ELSE
    RETURN copyso(pcoheadid, null, pcodate::DATE);
  END IF;
END;
$$ LANGUAGE plpgsql;
