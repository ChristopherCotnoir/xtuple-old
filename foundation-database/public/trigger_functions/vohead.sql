DROP TRIGGER IF EXISTS voheadBeforeTrigger ON public.vohead;
DROP TRIGGER IF EXISTS voheadAfterTrigger  ON public.vohead;

CREATE OR REPLACE FUNCTION _voheadBeforeTrigger() RETURNS "trigger" AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE
  _recurid     INTEGER;
  _newparentid INTEGER;

BEGIN
  IF (TG_OP = 'DELETE') THEN
    IF (OLD.vohead_posted) THEN
      RAISE EXCEPTION 'Cannot delete a posted voucher';
    END IF;

    /* TODO: is setting recv_invoiced and poreject_invoiced to FALSE correct?
             this behavior is inherited from the now-defunct deleteVoucher.
     */
    UPDATE recv SET recv_vohead_id = NULL,
                    recv_voitem_id = NULL,
                    recv_invoiced  = FALSE
     WHERE recv_vohead_id = OLD.vohead_id;

    UPDATE poreject SET poreject_vohead_id = NULL,
                        poreject_voitem_id = NULL,
                        poreject_invoiced  = FALSE
     WHERE poreject_vohead_id = OLD.vohead_id;

    DELETE FROM vodist    WHERE vodist_vohead_id  = OLD.vohead_id;
    DELETE FROM voitem    WHERE voitem_vohead_id  = OLD.vohead_id;

    SELECT recur_id INTO _recurid
      FROM recur
     WHERE ((recur_parent_id=OLD.vohead_id)
        AND (recur_parent_type='V'));
    IF (_recurid IS NOT NULL) THEN
      SELECT vohead_id INTO _newparentid
        FROM vohead
       WHERE ((vohead_recurring_vohead_id=OLD.vohead_id)
          AND (vohead_id!=OLD.vohead_id))
       ORDER BY vohead_docdate
       LIMIT 1;

      IF (_newparentid IS NULL) THEN
        DELETE FROM recur WHERE recur_id=_recurid;
      ELSE
        UPDATE recur SET recur_parent_id=_newparentid
         WHERE recur_id=_recurid;
        UPDATE vohead SET vohead_recurring_vohead_id=_newparentid
         WHERE vohead_recurring_vohead_id=OLD.vohead_id
           AND vohead_id!=OLD.vohead_id;
      END IF;
    END IF;

    RETURN OLD;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER voheadBeforeTrigger
  BEFORE INSERT OR UPDATE OR DELETE
  ON vohead
  FOR EACH ROW
  EXECUTE PROCEDURE _voheadBeforeTrigger();

CREATE OR REPLACE FUNCTION _voheadAfterTrigger() RETURNS "trigger" AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/EULA for the full text of the software license.
BEGIN
  IF (TG_OP = 'DELETE') THEN
    PERFORM releaseVoNumber(CAST(OLD.vohead_number AS INTEGER));
    RETURN OLD;
  END IF;

  IF (TG_OP = 'UPDATE' AND
      (NEW.vohead_docdate != OLD.vohead_docdate OR
       NEW.vohead_curr_id != OLD.vohead_curr_id OR
       NEW.vohead_freight != OLD.vohead_freight OR
       NEW.vohead_freight_taxtype_id != OLD.vohead_freight_taxtype_id OR
       (fetchMetricText('TaxService') = 'N' AND
        NEW.vohead_taxzone_id != OLD.vohead_taxzone_id) OR
       (fetchMetricText('TaxService') != 'N' AND
        NEW.vohead_tax_exemption != OLD.vohead_tax_exemption))) THEN
    UPDATE taxhead
       SET taxhead_valid = FALSE
     WHERE taxhead_doc_type = 'VCH'
       AND taxhead_doc_id = NEW.vohead_id;
  END IF;

  IF (TG_OP = 'INSERT') THEN
    PERFORM clearNumberIssue('VcNumber', NEW.vohead_number);
    PERFORM postComment('ChangeLog', 'VCH', NEW.vohead_id, 'Created');
    RETURN NEW;
  END IF;

  IF (TG_OP = 'UPDATE') THEN
    -- Touch any Misc Tax Distributions so voucher tax is recalculated
    IF (NEW.vohead_docdate <> OLD.vohead_docdate) THEN
      UPDATE vodist SET vodist_vohead_id=NEW.vohead_id
      WHERE ( (vodist_vohead_id=OLD.vohead_id)
        AND   (vodist_tax_id <> -1) );
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER voheadAfterTrigger
  AFTER INSERT OR UPDATE OR DELETE
  ON vohead
  FOR EACH ROW
  EXECUTE PROCEDURE _voheadAfterTrigger();

CREATE OR REPLACE FUNCTION _voheadAfterDeleteTrigger() RETURNS TRIGGER AS $$
-- Copyright (c) 1999-2019 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE

BEGIN

  DELETE
  FROM charass
  WHERE charass_target_type = 'VCH'
    AND charass_target_id = OLD.vohead_id;

  DELETE FROM taxhead
   WHERE taxhead_doc_type = 'VCH'
     AND taxhead_doc_id = OLD.vohead_id;

  RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';

DROP TRIGGER IF EXISTS voheadAfterDeleteTrigger ON public.vohead;
CREATE TRIGGER voheadAfterDeleteTrigger
  AFTER DELETE
  ON vohead
  FOR EACH ROW
  EXECUTE PROCEDURE _voheadAfterDeleteTrigger();
