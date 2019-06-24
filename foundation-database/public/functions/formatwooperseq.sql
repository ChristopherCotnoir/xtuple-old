CREATE OR REPLACE FUNCTION formatwooperseq(pWooperid INTEGER) RETURNS TEXT AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE
  _result    TEXT = '';

BEGIN
  IF packageIsEnabled('xtmfg') THEN
    SELECT wooper_seqnumber INTO _result
    FROM xtmfg.wooper
    WHERE (wooper_id=pWooperId);
  END IF;

  RETURN _result;
END;
$$ LANGUAGE 'plpgsql';
