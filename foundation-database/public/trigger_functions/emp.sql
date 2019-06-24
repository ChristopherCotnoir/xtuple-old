CREATE OR REPLACE FUNCTION _empBeforeTrigger () RETURNS TRIGGER AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/EULA for the full text of the software license.
BEGIN

  IF NOT (checkPrivilege('MaintainEmployees')) THEN
    RAISE EXCEPTION 'You do not have privileges to maintain Employees. [xtuple: _empBeforeTrigger, -1]';
  END IF;

  IF (NEW.emp_code IS NULL) THEN
    RAISE EXCEPTION 'You must supply a valid Employee Code. [xtuple: _empBeforeTrigger, -2]';
  END IF;

  IF (NEW.emp_number IS NULL) THEN
    RAISE EXCEPTION 'You must supply a valid Employee Number.  [xtuple: _empBeforeTrigger, -3]';
  END IF;

  IF (NEW.emp_id = NEW.emp_mgr_emp_id) THEN
    RAISE EXCEPTION 'An Employee may not be his or her own Manager. [xtuple: _empBeforeTrigger, -4]';
  END IF;

  IF (NEW.emp_image_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM image WHERE image_id=NEW.emp_image_id)) THEN
    RAISE EXCEPTION 'An invalid image was selected. [xtuple: _empBeforeTrigger, -5]';
  END IF;

  -- ERROR:  cannot use column references in default expression
  IF (NEW.emp_name IS NULL) THEN
    NEW.emp_name = COALESCE(formatCntctName(NEW.emp_cntct_id), NEW.emp_number);
  END IF;

  IF (TG_OP = 'INSERT' AND fetchMetricText('CRMAccountNumberGeneration') IN ('A','O')) THEN
    PERFORM clearNumberIssue('CRMAccountNumber', NEW.emp_number);
  END IF;

  NEW.emp_code := UPPER(NEW.emp_code);

  -- deprecated column emp_username
  IF (TG_OP = 'UPDATE' AND
      LOWER(NEW.emp_username) != LOWER(NEW.emp_code) AND
      EXISTS(SELECT 1
               FROM crmacct
              WHERE crmacct_id = NEW.emp_crmacct_id
                AND crmacct_usr_username IS NOT NULL)) THEN
    NEW.emp_username = LOWER(NEW.emp_code);
  END IF;

  IF (TG_OP = 'INSERT') THEN
    LOOP
      UPDATE crmacct SET crmacct_name=NEW.emp_name
       WHERE crmacct_number=NEW.emp_code
       RETURNING crmacct_id INTO NEW.emp_crmacct_id;
      IF (FOUND) THEN
        EXIT;
      END IF;
      BEGIN
        INSERT INTO crmacct(crmacct_number,  crmacct_name, crmacct_active, crmacct_type)
                    VALUES (NEW.emp_code,    NEW.emp_name, NEW.emp_active, 'I')
        RETURNING crmacct_id INTO NEW.emp_crmacct_id;

        INSERT INTO crmacctcntctass (crmacctcntctass_crmacct_id, crmacctcntctass_cntct_id, 
                                     crmacctcntctass_crmrole_id)
        SELECT NEW.emp_crmacct_id, NEW.emp_cntct_id, getcrmroleid()
          WHERE NEW.emp_cntct_id IS NOT NULL;
        EXIT;
      EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
      END;
    END LOOP;

    /* TODO: default characteristic assignments based on empgrp? */
  END IF;

  -- Timestamps
  IF (TG_OP = 'INSERT') THEN
    NEW.emp_created := now();
  ELSIF (TG_OP = 'UPDATE') THEN
    NEW.emp_lastupdated := now();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

SELECT dropIfExists('TRIGGER', 'empBeforeTrigger');
CREATE TRIGGER empBeforeTrigger
  BEFORE INSERT OR UPDATE
  ON emp
  FOR EACH ROW
  EXECUTE PROCEDURE _empBeforeTrigger();

CREATE OR REPLACE FUNCTION _empAfterTrigger () RETURNS TRIGGER AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE
  _newcrmacctname TEXT;
  _crmacctid  INTEGER;
BEGIN

  IF (TG_OP = 'UPDATE' AND OLD.emp_crmacct_id=NEW.emp_crmacct_id) THEN
    UPDATE crmacct SET crmacct_number = NEW.emp_code
    WHERE ((crmacct_id=NEW.emp_crmacct_id)
      AND  (crmacct_number!=NEW.emp_code));

    UPDATE crmacct SET crmacct_name = NEW.emp_name
    WHERE ((crmacct_id=NEW.emp_crmacct_id)
      AND  (crmacct_name!=NEW.emp_name));

  END IF;

  IF (fetchMetricBool('EmployeeChangeLog')) THEN
    IF (TG_OP = 'INSERT') THEN
      PERFORM postComment('ChangeLog', 'EMP', NEW.emp_id, 'Created');

    ELSIF (TG_OP = 'UPDATE') THEN

      IF (OLD.emp_number <> NEW.emp_number) THEN
        PERFORM postComment('ChangeLog', 'EMP', NEW.emp_id, 'Number',
                            OLD.emp_number, NEW.emp_number);
      END IF;

      IF (OLD.emp_code <> NEW.emp_code) THEN
        PERFORM postComment('ChangeLog', 'EMP', NEW.emp_id, 'Code',
                            OLD.emp_code, NEW.emp_code);
      END IF;

      IF (OLD.emp_active <> NEW.emp_active) THEN
        PERFORM postComment('ChangeLog', 'EMP', NEW.emp_id,
                            CASE WHEN NEW.emp_active THEN 'Activated'
                                 ELSE 'Deactivated' END);
      END IF;

      IF (COALESCE(OLD.emp_dept_id, -1) <> COALESCE(NEW.emp_dept_id, -1)) THEN
        PERFORM postComment('ChangeLog', 'EMP', NEW.emp_id, 'Department',
                            COALESCE((SELECT dept_number FROM dept
                                       WHERE dept_id=OLD.emp_dept_id), ''),
                            COALESCE((SELECT dept_number FROM dept
                                       WHERE dept_id=NEW.emp_dept_id), ''));
      END IF;

      IF (COALESCE(OLD.emp_shift_id, -1) <> COALESCE(NEW.emp_shift_id, -1)) THEN
        PERFORM postComment('ChangeLog', 'EMP', NEW.emp_id, 'Shift',
                            COALESCE((SELECT shift_number FROM shift
                                       WHERE shift_id=OLD.emp_shift_id), ''),
                            COALESCE((SELECT shift_number FROM shift
                                       WHERE shift_id=NEW.emp_shift_id), ''));
      END IF;

    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

SELECT dropIfExists('TRIGGER', 'empAfterTrigger');
CREATE TRIGGER empAfterTrigger
  AFTER INSERT OR UPDATE
  ON emp
  FOR EACH ROW
  EXECUTE PROCEDURE _empAfterTrigger();

CREATE OR REPLACE FUNCTION _empBeforeDeleteTrigger() RETURNS TRIGGER AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/EULA for the full text of the software license.
BEGIN
  IF NOT (checkPrivilege('MaintainEmployees')) THEN
    RAISE EXCEPTION 'You do not have privileges to maintain Employees.';
  END IF;

  DELETE FROM docass WHERE docass_source_id = OLD.emp_id AND docass_source_type = 'EMP';
  DELETE FROM docass WHERE docass_target_id = OLD.emp_id AND docass_target_type = 'EMP';
  DELETE FROM empgrpitem WHERE groupsitem_reference_id = OLD.emp_id;

  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

SELECT dropIfExists('TRIGGER', 'empBeforeDeleteTrigger');
CREATE TRIGGER empBeforeDeleteTrigger
  BEFORE DELETE
  ON emp
  FOR EACH ROW
  EXECUTE PROCEDURE _empBeforeDeleteTrigger();

CREATE OR REPLACE FUNCTION _empAfterDeleteTrigger() RETURNS TRIGGER AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/EULA for the full text of the software license.
BEGIN
  IF (fetchMetricBool('EmployeeChangeLog')) THEN
    PERFORM postComment('ChangeLog', 'EMP', OLD.emp_id,
                        ('Deleted "' || OLD.emp_code || '"'));
  END IF;

  DELETE
  FROM charass
  WHERE charass_target_type = 'EMP'
    AND charass_target_id = OLD.emp_id;

  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

SELECT dropIfExists('TRIGGER', 'empAfterDeleteTrigger');
CREATE TRIGGER empAfterDeleteTrigger
  AFTER DELETE
  ON emp
  FOR EACH ROW
  EXECUTE PROCEDURE _empAfterDeleteTrigger();
