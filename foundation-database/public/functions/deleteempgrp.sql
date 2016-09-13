CREATE OR REPLACE FUNCTION deleteEmpGrp(INTEGER) RETURNS INTEGER AS $$
-- Copyright (c) 1999-2014 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  pempgrpid ALIAS FOR $1;

BEGIN
--  Check to see if any employees are assigned to the passed empgrp
  PERFORM empgrpitem_emp_id
  FROM empgrpitem
  WHERE (empgrpitem_empgrp_id=pempgrpid)
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Employee Group cannot be deleted as there are one or more Employees assigned to it. You must reassign these Employees before you may delete the selected Employee Group. [xtuple: deleteEmpGrp, -1]';
  END IF;

  DELETE FROM empgrp     WHERE (empgrp_id=pempgrpid);

  RETURN 0;
END;
$$ LANGUAGE 'plpgsql';
