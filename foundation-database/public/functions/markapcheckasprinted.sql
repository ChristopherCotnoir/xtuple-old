CREATE OR REPLACE FUNCTION markAPCheckAsPrinted(INTEGER) RETURNS INTEGER AS '
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/EULA for the full text of the software license.
BEGIN
  RAISE WARNING ''markAPCheckAsPrinted() is deprecated - use markCheckAsPrinted()'';
  RETURN markCheckAsPrinted($1);
END;
' LANGUAGE 'plpgsql';
