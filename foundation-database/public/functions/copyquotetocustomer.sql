CREATE OR REPLACE FUNCTION copyquotetocustomer(pQuheadid integer, pCustomerid integer, pSchedDate date)
  RETURNS integer AS
$BODY$
-- Copyright (c) 1999-2019 by OpenMFG LLC  d/b/a xTuple.
-- See www.xtuple.com/EULA for the full text of the software license.
DECLARE
  _isCustomer BOOLEAN;
  _quotecustomer INTEGER;
  _quheadid INTEGER;
  _qunumber TEXT;
  _b     RECORD;

BEGIN

  SELECT NEXTVAL('quhead_quhead_id_seq') INTO _quheadid;
  IF (fetchMetricText('QUNumberGeneration') = 'S') THEN
    SELECT fetchSoNumber() INTO _qunumber;
  ELSE
    SELECT fetchQuNumber() INTO _qunumber;
  END IF;

  SELECT * INTO _b FROM (
    SELECT cust_name as name,  addr_line1, addr_line2, addr_line3, addr_city, addr_state, addr_postalcode, addr_country,
       cntct_id, cntct_honorific, cntct_first_name, cntct_middle, cntct_last_name, cntct_suffix, 
       getcontactphone(cntct_id, 'Office') AS contact_phone, 
       getcontactphone(cntct_id, 'Fax') AS contact_fax, 
       cntct_title, cntct_email 
      FROM custinfo 
      LEFT JOIN cntct ON (cust_cntct_id = cntct_id)
      LEFT JOIN addr ON (cntct_addr_id = addr_id)
      WHERE cust_id = pCustomerid
    UNION
    SELECT prospect_name AS name,  addr_line1, addr_line2, addr_line3, addr_city, addr_state, addr_postalcode, addr_country,
        cntct_id, cntct_honorific, cntct_first_name, cntct_middle, cntct_last_name, cntct_suffix, 
        getcontactphone(cntct_id, 'Office') AS contact_phone, 
        getcontactphone(cntct_id, 'Fax') AS contact_fax, 
        cntct_title, cntct_email
      FROM prospect
      LEFT JOIN cntct ON (cntct_id=getcrmaccountcontact(prospect_crmacct_id))
      LEFT JOIN addr ON (cntct_addr_id = addr_id)  
      WHERE prospect_id = pCustomerid ) data;

  IF (NOT FOUND) THEN
    RAISE EXCEPTION 'Invalid Customer supplied: %', pCustomerid;
  END IF;  
  
  INSERT INTO quhead
  ( quhead_id,  quhead_number,  quhead_cust_id,  quhead_prj_id,
    quhead_quotedate,  quhead_packdate,  quhead_fob,
    quhead_warehous_id,  quhead_terms_id,  quhead_salesrep_id,
    quhead_custponumber,  quhead_shipvia,
    quhead_shipto_id,  
    quhead_misc_accnt_id,  quhead_misc_descrip,  quhead_misc,  quhead_freight,  quhead_commission,
    quhead_ordercomments,  quhead_shipcomments,
    quhead_imported,  quhead_curr_id,  quhead_taxzone_id,  quhead_freight_taxtype_id,
    quhead_misc_taxtype_id,  quhead_misc_discount, quhead_tax_exemption, quhead_ophead_id,  quhead_status,
    quhead_shipto_cntct_id,  quhead_billto_cntct_id,  quhead_billto_cntct_honorific,
    quhead_billto_cntct_first_name,  quhead_billto_cntct_middle,  quhead_billto_cntct_last_name,  quhead_billto_cntct_suffix,
    quhead_billto_cntct_phone,  quhead_billto_cntct_title,  quhead_billto_cntct_fax,  quhead_billto_cntct_email )
  SELECT _quheadid,  _qunumber,
         pCustomerid,  -- use new customer or prospect
         quhead_prj_id,
         CURRENT_DATE,  COALESCE(pSchedDate,  quhead_packdate),  quhead_fob,
         quhead_warehous_id,  quhead_terms_id,  quhead_salesrep_id,
         quhead_custponumber,  quhead_shipvia,
         NULL,    -- shipto_id         
 
         quhead_misc_accnt_id,  quhead_misc_descrip,  quhead_misc,  quhead_freight,  quhead_commission,
         quhead_ordercomments,  quhead_shipcomments,
         FALSE,  quhead_curr_id,  quhead_taxzone_id,  quhead_freight_taxtype_id,
         quhead_misc_taxtype_id,  quhead_misc_discount, quhead_tax_exemption,  quhead_ophead_id,  'O',
         
 	 NULL, -- quhead_shipto_cntct_id,
	
         _b.cntct_id,			-- quhead_billto_cntct_id,
         _b.cntct_honorific,	-- quhead_billto_cntct_honorific,
         _b.cntct_first_name,	-- quhead_billto_cntct_first_name,
         _b.cntct_middle,		-- quhead_billto_cntct_middle,
         _b.cntct_last_name,	-- quhead_billto_cntct_last_name,
         _b.cntct_suffix,		-- quhead_billto_cntct_suffix,
         _b.contact_phone,		-- quhead_billto_cntct_phone,
         _b.cntct_title,		-- quhead_billto_cntct_title,
         _b.contact_fax,			-- quhead_billto_cntct_fax,
         _b.cntct_email		-- quhead_billto_cntct_email
  FROM quhead 
  WHERE (quhead_id=pquheadid);

  PERFORM copyTax('Q', pQuheadid, 'Q', _quheadid);
  
  INSERT INTO quitem
  ( quitem_quhead_id,  quitem_linenumber,  quitem_itemsite_id,
    quitem_scheddate,  quitem_promdate,  quitem_qtyord,
    quitem_price,  quitem_custprice,  quitem_unitcost,
    quitem_qty_uom_id,  quitem_price_uom_id,
    quitem_qty_invuomratio,  quitem_price_invuomratio,
    quitem_memo,  quitem_custpn,  quitem_imported,  quitem_taxtype_id,
    quitem_createorder,  quitem_order_warehous_id,  quitem_item_id,  quitem_prcost,
    quitem_dropship,  quitem_itemsrc_id,  quitem_pricemode, quitem_tax_exemption )
  SELECT _quheadid,  quitem_linenumber,  quitem_itemsite_id,
         COALESCE(pSchedDate,  quitem_scheddate),
         quitem_promdate,
         quitem_qtyord,
         quitem_price,  quitem_custprice,
         CASE WHEN fetchMetricBool('WholesalePriceCosting') THEN (select (item_listcost) from item where item_id=quitem_item_id) ELSE stdCost(itemsite_item_id) END,
         quitem_qty_uom_id,  quitem_price_uom_id,
         quitem_qty_invuomratio,  quitem_price_invuomratio,
         quitem_memo,  quitem_custpn,  FALSE,  quitem_taxtype_id,
         quitem_createorder,  quitem_order_warehous_id,  quitem_item_id,  quitem_prcost,
         quitem_dropship,  quitem_itemsrc_id,  quitem_pricemode, quitem_tax_exemption
  FROM quitem,  itemsite
  WHERE ( (quitem_itemsite_id=itemsite_id)
   AND (quitem_quhead_id=pQuheadid));

  PERFORM copyTax('Q', old.quitem_id, 'Q', new.quitem_id, _quheadid)
     FROM quitem new
     JOIN quitem old ON old.quitem_quhead_id = pQuheadid
                    AND new.quitem_linenumber = old.quitem_linenumber
                    AND new.quitem_subnumber = old.quitem_subnumber
    WHERE new.quitem_quhead_id = _quheadid;

  INSERT INTO charass
        (charass_target_type,  charass_target_id,
         charass_char_id,  charass_value)
  SELECT charass_target_type, b.quitem_id,
         charass_char_id, charass_value
    FROM quitem a, charass, quitem b
   WHERE ((charass_target_type='QI')
     AND  (charass_target_id=a.quitem_id)
     AND  (a.quitem_quhead_id=pquheadid)
     AND  (b.quitem_quhead_id=_quheadid)
     AND  (a.quitem_linenumber=b.quitem_linenumber)
     );

  RETURN _quheadid;

END;
$BODY$
  LANGUAGE plpgsql;
