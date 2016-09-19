
CREATE OR REPLACE FUNCTION deleteAccount(integer) RETURNS integer
    AS $$
-- Copyright (c) 1999-2014 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  pAccntid ALIAS FOR $1;
  _check INTEGER;

BEGIN

--  Check to see if the passed accnt is used in a Cost Category
  SELECT costcat_id INTO _check
  FROM costcat
  WHERE ( (costcat_asset_accnt_id=pAccntid)
     OR   (costcat_liability_accnt_id=pAccntid)
     OR   (costcat_adjustment_accnt_id=pAccntid)
     OR   (costcat_matusage_accnt_id=pAccntid)
     OR   (costcat_purchprice_accnt_id=pAccntid)
     OR   (costcat_scrap_accnt_id=pAccntid)
     OR   (costcat_invcost_accnt_id=pAccntid)
     OR   (costcat_wip_accnt_id=pAccntid)
     OR   (costcat_shipasset_accnt_id=pAccntid)
     OR   (costcat_mfgscrap_accnt_id=pAccntid)
     OR   (costcat_transform_accnt_id=pAccntid)
     OR   (costcat_freight_accnt_id=pAccntid)
     OR   (costcat_exp_accnt_id=pAccntid) )
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Ledger Account cannot be deleted as it is currently used in one or more Cost Categories.  You must reassign these Cost Category assignments before you may delete the selected Ledger Account. [xtuple: deleteAccount, -1]';
  END IF;

  IF (fetchMetricText('Application') = 'Standard') THEN
    SELECT costcat_id INTO _check
    FROM costcat
    WHERE ( (costcat_toliability_accnt_id=pAccntid)
       OR   (costcat_laboroverhead_accnt_id=pAccntid) )
    LIMIT 1;
    IF (FOUND) THEN
      RAISE EXCEPTION 'The selected Ledger Account cannot be deleted as it is currently used in one or more Cost Categories.  You must reassign these Cost Category assignments before you may delete the selected Ledger Account. [xtuple: deleteAccount, -1]';
    END IF;
  END IF;

--  Check to see if the passed accnt is used in a Sales Account Assignment
  SELECT salesaccnt_id INTO _check
  FROM salesaccnt
  WHERE ( (salesaccnt_sales_accnt_id=pAccntid)
     OR   (salesaccnt_credit_accnt_id=pAccntid)
     OR   (salesaccnt_cos_accnt_id=pAccntid) )
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Ledger Account cannot be deleted as it is currently used in one or more Sales Account Assignment. You must reassign these Sales Account Assignments before you may delete the selected Ledger Account. [xtuple: deleteAccount, -2]';
  END IF;

  IF (fetchMetricText('Application') = 'Standard') THEN
    SELECT salesaccnt_id INTO _check
    FROM salesaccnt
    WHERE ( (salesaccnt_returns_accnt_id=pAccntid)
       OR   (salesaccnt_cor_accnt_id=pAccntid)
       OR   (salesaccnt_cow_accnt_id=pAccntid) )
    LIMIT 1;
    IF (FOUND) THEN
      RAISE EXCEPTION 'The selected Ledger Account cannot be deleted as it is currently used in one or more Sales Account Assignment. You must reassign these Sales Account Assignments before you may delete the selected Ledger Account. [xtuple: deleteAccount, -2]';
    END IF;
  END IF;

--  Check to see if the passed accnt is used in a Sales Category
  SELECT salescat_id INTO _check
  FROM salescat
  WHERE ( (salescat_sales_accnt_id=pAccntid)
     OR   (salescat_prepaid_accnt_id=pAccntid)
     OR   (salescat_ar_accnt_id=pAccntid) )
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Ledger Account cannot be deleted as it is currently used in one or more Sales Account Assignment. You must reassign these Sales Account Assignments before you may delete the selected Ledger Account. [xtuple: deleteAccount, -2]';
  END IF;

--  Check to see if the passed accnt is used in a A/R Account Assignment
  SELECT araccnt_id INTO _check
  FROM araccnt
  WHERE ( (araccnt_freight_accnt_id=pAccntid)
     OR   (araccnt_ar_accnt_id=pAccntid)
     OR   (araccnt_prepaid_accnt_id=pAccntid)
     OR   (araccnt_deferred_accnt_id=pAccntid)
     OR   (araccnt_discount_accnt_id=pAccntid) )
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Ledger Account cannot be deleted as it is currently used in one or more Customer A/R Account assignments. You must reassign these Customer A/R Account assignments before you may delete the selected Ledger Account. [xtuple: deleteAccount, -3]';
  END IF;

--  Check to see if the passed accnt is used in a Warehouse
  IF EXISTS (SELECT 1
               FROM whsinfo
              WHERE (warehous_default_accnt_id=pAccntid)) THEN
    RAISE EXCEPTION 'The selected Ledger Account cannot be deleted as it is currently used as the default Account one or more Sites. You must reassign the default Account for these Sites before you may delete the selected Ledger Account. [xtuple: deleteAccount, -4]';
  END IF;

--  Check to see if the passed accnt is used in a Bank Account
  SELECT bankaccnt_id INTO _check
  FROM bankaccnt
  WHERE (bankaccnt_accnt_id=pAccntid)
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Ledger Account cannot be deleted as it is currently used in one or more Bank Accounts. You must reassign these Bank Accounts before you may delete the selected Ledger Account. [xtuple: deleteAccount, -5]';
  END IF;

  SELECT bankadjtype_id INTO _check
  FROM bankadjtype
  WHERE (bankadjtype_accnt_id=pAccntid)
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Ledger Account cannot be deleted as it is currently used in one or more Bank Accounts. You must reassign these Bank Accounts before you may delete the selected Ledger Account. [xtuple: deleteAccount, -5]';
  END IF;

--  Check to see if the passed accnt is used in an Expense Category
  SELECT expcat_id INTO _check
  FROM expcat
  WHERE ( (expcat_exp_accnt_id=pAccntid)
     OR   (expcat_liability_accnt_id=pAccntid)
     OR   (expcat_purchprice_accnt_id=pAccntid)
     OR   (expcat_freight_accnt_id=pAccntid) )
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Ledger Account cannot be deleted as it is currently used in one or more Expense Categories. You must reassign these Expense Categories before you may delete the selected Ledger Account. [xtuple: deleteAccount, -6]';
  END IF;

--  Check to see if the passed accnt is used in a Tax Code
  SELECT tax_id INTO _check
  FROM tax
  WHERE ( (tax_sales_accnt_id=pAccntid)
     OR   (tax_dist_accnt_id=pAccntid) )
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Ledger Account cannot be deleted as it is currently used in one or more Tax Codes. You must reassign these Tax Codes before you may delete the selected Ledger Account. [xtuple: deleteAccount, -7]';
  END IF;

--  Check to see if the passed accnt is used in a Standard Journal Item
  SELECT stdjrnlitem_id INTO _check
  FROM stdjrnlitem
  WHERE (stdjrnlitem_accnt_id=pAccntid)
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Ledger Account cannot be deleted as it is currently used in one or more Standard Journals. You must reassign these Standard Journal Items before you may delete the selected Ledger Account. [xtuple: deleteAccount, -8]';
  END IF;

--  Check to see if the passed accnt is used in a A/P Account Assignment
  SELECT apaccnt_ap_accnt_id INTO _check
  FROM apaccnt
  WHERE ( (apaccnt_ap_accnt_id=pAccntid)
     OR   (apaccnt_prepaid_accnt_id=pAccntid)
     OR   (apaccnt_discount_accnt_id=pAccntid) )
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Ledger Account cannot be deleted as it is currently used in one or more Customer A/P Account assignments. You must reassign these Customer A/P Account assignments before you may delete the selected Ledger Account. [xtuple: deleteAccount, -9]';
  END IF;

--  Check to see if the passed accnt is used in an A/R Open Item record
  SELECT aropen_accnt_id INTO _check
    FROM aropen
   WHERE (aropen_accnt_id=pAccntid)
   LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Ledger Account cannot be deleted as it is currently used in one or more A/R Open Items. You must reassign these Currency definitions before you may delete the selected Ledger Account. [xtuple: deleteAccount, -11]';
  END IF;

--  Check to see if the passed accnt has been used in the G/L
  SELECT gltrans_accnt_id INTO _check
  FROM gltrans
  WHERE (gltrans_accnt_id=pAccntid)
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Ledger Account cannot be deleted as there have been Ledger Transactions posted against it. [xtuple: deleteAccount, -99]';
  END IF;

  SELECT glseries_accnt_id INTO _check
  FROM glseries
  WHERE (glseries_accnt_id=pAccntid)
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Ledger Account cannot be deleted as there have been Ledger Transactions posted against it. [xtuple: deleteAccount, -99]';
  END IF;

  SELECT trialbal_accnt_id INTO _check
  FROM trialbal
  WHERE (trialbal_accnt_id=pAccntid)
    AND (trialbal_beginning != 0 OR trialbal_ending != 0)
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Ledger Account cannot be deleted as there have been Ledger Transactions posted against it. [xtuple: deleteAccount, -99]';
  END IF;

  SELECT cashrcptmisc_accnt_id INTO _check
  FROM cashrcptmisc
  WHERE (cashrcptmisc_accnt_id=pAccntid)
  LIMIT 1;
  IF (FOUND) THEN
    RAISE EXCEPTION 'The selected Ledger Account cannot be deleted as there have been Ledger Transactions posted against it. [xtuple: deleteAccount, -99]';
  END IF;

--  Delete any non-critical use
  DELETE FROM flitem
  WHERE (flitem_accnt_id=pAccntid);

  -- only possible because of trialbal error-check above
  DELETE FROM trialbal
  WHERE (trialbal_accnt_id=pAccntid)
    AND (trialbal_beginning=0)
    AND (trialbal_ending=0);

--  Delete the Account
  DELETE FROM accnt
  WHERE (accnt_id=pAccntid);

  RETURN 0;

END;
$$ LANGUAGE 'plpgsql';

