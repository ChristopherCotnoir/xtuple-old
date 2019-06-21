CREATE OR REPLACE FUNCTION docSense(pDocType TEXT, pDocId INTEGER) RETURNS INTEGER AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.

  SELECT CASE WHEN pDocType = 'CM' THEN -1
              WHEN pDocType = 'AR' THEN aropenSense(pDocId)
              WHEN pDocType = 'AP' THEN apopenSense(pDocId)
              ELSE 1
          END;

$$ language sql;
