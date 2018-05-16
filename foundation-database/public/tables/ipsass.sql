SELECT xt.create_table('ipsass', 'public');

ALTER TABLE public.ipsass DISABLE TRIGGER ALL;

SELECT xt.add_column('ipsass', 'ipsass_id',               'SERIAL',  'PRIMARY KEY', 'public');
SELECT xt.add_column('ipsass', 'ipsass_ipshead_id',       'INTEGER', 'NOT NULL',    'public');
SELECT xt.add_column('ipsass', 'ipsass_cust_id',          'INTEGER', 'NULL',        'public');
SELECT xt.add_column('ipsass', 'ipsass_custtype_id',      'INTEGER', 'NULL',        'public');
SELECT xt.add_column('ipsass', 'ipsass_custtype_pattern', 'TEXT',    'NULL',        'public');
SELECT xt.add_column('ipsass', 'ipsass_shipto_id',        'INTEGER', 'NULL',        'public');
SELECT xt.add_column('ipsass', 'ipsass_shipto_pattern',   'TEXT',    'NULL',        'public');
SELECT xt.add_column('ipsass', 'ipsass_shipzone_id',      'INTEGER', 'NULL',        'public');
SELECT xt.add_column('ipsass', 'ipsass_saletype_id',      'INTEGER', 'NULL',        'public');

ALTER TABLE ipsass DROP CONSTRAINT IF EXISTS ipsass_ipsass_ipshead_id_key;
SELECT xt.add_constraint('ipsass', 'ipsass_pkey', 'PRIMARY KEY (ipsass_id)', 'public');

DO $$
DECLARE
  _r               RECORD;
  _custid          INTEGER := NULL;
  _custtypeid      INTEGER := NULL;
  _custtypepattern TEXT    := NULL;
  _shiptoid        INTEGER := NULL;
  _shiptopattern   TEXT    := NULL;
  _shipzoneid      INTEGER := NULL;
  _saletypeid      INTEGER := NULL;

BEGIN

  FOR _r IN SELECT ipsass_id, ipsass_cust_id, ipsass_custtype_id, ipsass_custtype_pattern,
                   ipsass_shipto_id, ipsass_shipto_pattern, ipsass_shipzone_id, ipass_saletype_id
              FROM ipsass
  LOOP
    IF (COALESCE(_r.ipsass_cust_id, -1) > 0) THEN
      _custid := _r.ipasass_cust_id;
    ELSIF (COALESCE(_r.ipsass_custtype_id, -1) > 0) THEN
      _custtypeid := _r.ipsass_custtype_id;
    ELSIF (COALESCE(_r.ipsass_custtype_pattern, '') != '') THEN
      _custtypepattern := _r.ipsass_custtype_pattern;
    ELSIF (COALESCE(_r.ipsass_shipto_id, -1) > 0) THEN
      _shiptoid := _r.ipsass_shipto_id;
    ELSIF (COALESCE(_r.ipsass_shipto_pattern, '') != '') THEN
      _shiptopattern := _r.ipsass_shipto_pattern;
    ELSIF (COALESCE(_r.ipsass_shipzone_id, -1) > 0) THEN
      _shipzoneid := _r.ipsass_shipzone_id;
    ELSIF (COALESCE(_r.ipsass_saletype_id, -1) > 0) THEN
      _saletypeid := _r.ipsass_saletype_id;
    ELSE
      _shiptopattern := '';
    END IF;

    UPDATE ipsass
       SET ipsass_cust_id = _custid
           ipsass_custtype_id = _custtypeid
           ipsass_custtype_pattern = _custtypepattern
           ipsass_shipto_id = _shiptoid
           ipsass_shipto_pattern = _shiptopattern
           ipsass_shipzone_id = _shipzoneid
           ipsass_saletype_id = _saletypeid
     WHERE ipsass_id = _r.ipsass_id;
  END LOOP;

END
$$ language plpgsql;

SELECT xt.add_constraint('ipsass', 'ipsass_ipsass_ipshead_id_fkey',
                         'FOREIGN KEY (ipsass_ipshead_id) REFERENCES ipshead (ipshead_id)
                          ON DELETE CASCADE', 'public');
SELECT xt.add_constraint('ipsass', 'ipsass_ipsass_cust_id_fkey',
                         'FOREIGN KEY (ipsass_cust_id) REFERENCES custinfo (cust_id)
                          ON DELETE CASCADE', 'public');
SELECT xt.add_constraint('ipsass', 'ipsass_ipsass_custtype_id_fkey',
                         'FOREIGN KEY (ipsass_custtype_id) REFERENCES custtype (custtype_id)
                          ON DELETE CASCADE', 'public');
SELECT xt.add_constraint('ipsass', 'ipsass_ipsass_shipto_id_fkey',
                         'FOREIGN KEY (ipsass_shipto_id) REFERENCES shiptoinfo (shipto_id)
                          ON DELETE CASCADE', 'public');
SELECT xt.add_constraint('ipsass', 'ipsass_ipsass_shipzone_id_fkey',
                         'FOREIGN KEY (ipsass_shipzone_id) REFERENCES shipzone (shipzone_id)
                          ON DELETE CASCADE', 'public');
SELECT xt.add_constraint('ipsass', 'ipsass_ipsass_saletype_id_fkey';
                         'FOREIGN KEY (ipsass_saletype_id) REFERENCES saletype (saletype_id)
                          ON DELETE CASCADE', 'public');
SELECT xt.add_constraint('ipsass', 'ipsass_ipsass_ipshead_id_key',
                         'UNIQUE (ipsass_ipshead_id, ipsass_cust_id, ipsass_custtype_id, 
                                  ipsass_custtype_pattern, ipsass_shipto_id, ipsass_shipto_pattern,
                                  ipsass_shipzone_id, ipsass_saletype_id)', 'public');
SELECT xt.add_constraint('ipsass', 'ipsass_match_check',
                         'CHECK ((ipsass_cust_id IS NOT NULL)::INTEGER +
                                 (ipsass_custtype_id IS NOT NULL)::INTEGER +
                                 (ipsass_custtype_pattern IS NOT NULL)::INTEGER +
                                 (ipsass_shipto_id IS NOT NULL)::INTEGER +
                                 (ipsass_shipto_pattern IS NOT NULL)::INTEGER +
                                 (ipsass_shipzone_id IS NOT NULL)::INTEGER +
                                 (ipsass_saletype_id IS NOT NULL)::INTEGER = 1)', 'public');

ALTER TABLE public.ipsass ENABLE TRIGGER ALL;

COMMENT ON TABLE ipsass IS 'Pricing Schedule assignment information';
