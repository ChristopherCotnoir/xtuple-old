
CREATE OR REPLACE FUNCTION deleteOpportunity(INTEGER) RETURNS INTEGER AS '
-- Copyright (c) 1999-2014 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  pOpheadid ALIAS FOR $1;
  _test INTEGER;
BEGIN

  SELECT todoitem_id INTO _test
    FROM todoitem
   WHERE(todoitem_ophead_id=pOpheadid)
   LIMIT 1;
  IF(FOUND) THEN
    RAISE EXCEPTION 'The selected Opportunity cannot be deleted because there are ToDo Items assigned to it.  You must delete or reassign these ToDo Items before you may delete it. [xtuple: deleteOpportunity, -1]';
  END IF;

  SELECT quhead_id INTO _test
    FROM quhead
   WHERE(quhead_ophead_id=pOpheadid)
   LIMIT 1;
  IF(FOUND) THEN
    RAISE EXCEPTION 'The selected Opportunity cannot be deleted because there are Quotes assigned to it.  You must delete or reassign these Quotes before you may delete it. [xtuple: deleteOpportunity, -2]';
  END IF;

  SELECT cohead_id INTO _test
    FROM cohead
   WHERE(cohead_ophead_id=pOpheadid)
   LIMIT 1;
  IF(FOUND) THEN
    RAISE EXCEPTION 'The selected Opportunity cannot be deleted because there are Sales Orders assigned to it.  You must delete or reassign these Sales Orders before you may delete it. [xtuple: deleteOpportunity, -3]';
  END IF;

  DELETE
    FROM charass
   WHERE((charass_target_type=''OPP'')
     AND (charass_target_id=pOpheadid));

  DELETE
    FROM comment
   WHERE((comment_source=''OPP'')
     AND (comment_source_id=pOpheadid));

  DELETE
    FROM ophead
   WHERE(ophead_id=pOpheadid);
  
  return 0;
END;
' LANGUAGE 'plpgsql';
