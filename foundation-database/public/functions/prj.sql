CREATE OR REPLACE FUNCTION prj() RETURNS SETOF prj AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE
  _priv TEXT;
  _grant BOOLEAN;

BEGIN
  -- This query will give us the most permissive privilege the user has been granted
  SELECT privilege, granted INTO _priv, _grant
  FROM privgranted 
  WHERE privilege IN ('MaintainAllProjects','ViewAllProjects','MaintainPersonalProjects','ViewPersonalProjects')
  ORDER BY granted DESC, sequence
  LIMIT 1;

  -- If have an 'All' privilege return all results
  IF (_priv ~ 'All' AND _grant) THEN
    RETURN QUERY SELECT * FROM prj;
  -- Otherwise if have any other grant, must be personal privilege.
  ELSIF (_grant) THEN
    RETURN QUERY SELECT * FROM prj 
                  WHERE getEffectiveXtUser() IN (prj_owner_username, prj_username);
  END IF;

  RETURN;

END;
$$ LANGUAGE 'plpgsql';

COMMENT ON FUNCTION prj() IS 'A table function that returns Project results according to privilege settings.';
