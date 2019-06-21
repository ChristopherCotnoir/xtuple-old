CREATE OR REPLACE FUNCTION apopenSense(pApopenId INTEGER) RETURNS INTEGER AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.

  SELECT CASE WHEN apopen_doctype IN ('C', 'R') THEN -1
              ELSE 1
          END
    FROM apopen
   WHERE apopen_id = pApopenId;

$$ language sql;
