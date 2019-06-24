DROP FUNCTION IF EXISTS deleteProject(INTEGER) CASCADE;

CREATE OR REPLACE FUNCTION deleteProject(pPrjid INTEGER) RETURNS INTEGER AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE
  _result INTEGER;
BEGIN

  UPDATE ophead SET ophead_prj_id=NULL 
  WHERE  ophead_prj_id=pPrjid;

  SELECT quhead_id INTO _result
    FROM quhead
   WHERE (quhead_prj_id=pPrjid)
   LIMIT 1;
  IF (FOUND) THEN
    RETURN -1;
  END IF;

  SELECT cohead_id INTO _result
    FROM cohead
   WHERE (cohead_prj_id=pPrjid)
   LIMIT 1;
  IF (FOUND) THEN
    RETURN -2;
  END IF;

  SELECT wo_id INTO _result
    FROM wo
   WHERE (wo_prj_id=pPrjid)
   LIMIT 1;
  IF (FOUND) THEN
    RETURN -3;
  END IF;

  SELECT pr_id INTO _result
    FROM pr
   WHERE (pr_prj_id=pPrjid)
   LIMIT 1;
  IF (FOUND) THEN
    RETURN -4;
  END IF;

  SELECT poitem_id INTO _result
    FROM poitem
   WHERE (poitem_prj_id=pPrjid)
   LIMIT 1;
  IF (FOUND) THEN
    RETURN -5;
  END IF;

  SELECT invchead_id INTO _result
    FROM invchead
   WHERE (invchead_prj_id=pPrjid)
   LIMIT 1;
  IF (FOUND) THEN
    RETURN -6;
  END IF;

  UPDATE prj
     SET prj_recurring_prj_id=null
   WHERE(prj_recurring_prj_id=pPrjid);

  DELETE FROM prj
   WHERE (prj_id=pPrjid);
  RETURN pPrjid;
END;
$$ LANGUAGE 'plpgsql';

