-- Diagnostic uniquement : aucune suppression ni modification de catalogue.
-- Projection de l'empreinte du 30 septembre en retirant du calcul seulement
-- les trois FK entrantes ajoutées par 20261001201055, si leur forme est exacte.
WITH
relations AS (
  SELECT unnest(ARRAY[
    'auth.users'::regclass, 'public.soignants'::regclass,
    'public.etablissements'::regclass, 'public.missions'::regclass,
    'public.mission_creneaux'::regclass, 'public.candidatures'::regclass,
    'public.notifications'::regclass, 'public.preferences_notifications'::regclass,
    'public.rate_limits'::regclass, 'public.journaux_audit'::regclass
  ]) AS oid
),
attendues(nom,colonne,cible) AS (VALUES
  ('stripe_connect_avant_transfert_mission_id_fkey','mission_id','public.missions'),
  ('stripe_connect_avant_transfert_etablissement_id_fkey','etablissement_id','public.etablissements'),
  ('stripe_connect_avant_transfert_soignant_id_fkey','soignant_id','public.soignants')
),
fk AS (
  SELECT a.nom,a.colonne,a.cible,c.oid,
    coalesce(c.contype='f'
      AND c.confrelid=to_regclass(a.cible)
      AND c.conkey=ARRAY[src.attnum]::smallint[]
      AND c.confkey=ARRAY[dst.attnum]::smallint[]
      AND c.confdeltype='r' AND c.confupdtype='a' AND c.confmatchtype='s'
      AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
      AND c.conislocal AND c.coninhcount=0 AND c.conparentid=0,false) AS conforme,
    md5(pg_get_constraintdef(c.oid)) AS definition_md5
  FROM attendues a
  LEFT JOIN pg_constraint c
    ON c.conrelid=to_regclass('private.stripe_connect_avant_transfert') AND c.conname=a.nom
  LEFT JOIN pg_attribute src
    ON src.attrelid=c.conrelid AND src.attname=a.colonne AND NOT src.attisdropped
  LEFT JOIN pg_attribute dst
    ON dst.attrelid=to_regclass(a.cible) AND dst.attname='id' AND NOT dst.attisdropped
),
forme AS (SELECT count(*)=3 AND bool_and(conforme) AS exacte FROM fk),
colonnes AS (
  SELECT jsonb_agg(jsonb_build_array(a.attrelid::regclass::text,a.attname,
      format_type(a.atttypid,a.atttypmod),a.attnotnull,pg_get_expr(d.adbin,d.adrelid))
    ORDER BY a.attrelid::regclass::text,a.attnum) AS lignes
  FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
  WHERE a.attnum>0 AND NOT a.attisdropped AND a.attrelid IN(SELECT oid FROM relations)
),
contraintes AS (
  SELECT c.oid,c.conrelid::regclass::text AS relation,c.conname,
    jsonb_build_array(c.conrelid::regclass::text,c.conname,pg_get_constraintdef(c.oid)) AS ligne
  FROM pg_constraint c
  WHERE c.conrelid IN(SELECT oid FROM relations) OR c.confrelid IN(SELECT oid FROM relations)
),
empreintes AS (
  SELECT md5(jsonb_build_object(
    'colonnes',(SELECT lignes FROM colonnes),
    'contraintes',(SELECT jsonb_agg(ligne ORDER BY relation,conname) FROM contraintes)
  )::text) AS actuelle,
  CASE WHEN (SELECT exacte FROM forme) THEN md5(jsonb_build_object(
    'colonnes',(SELECT lignes FROM colonnes),
    'contraintes',(SELECT jsonb_agg(ligne ORDER BY relation,conname) FROM contraintes
      WHERE oid NOT IN(SELECT oid FROM fk WHERE conforme))
  )::text) ELSE NULL END AS sans_trois_fk
)
SELECT jsonb_build_object(
  'scope','D2_SCHEMA_EXPECTED_CONNECT_FK_PROJECTION_ONLY',
  'transaction_read_only',current_setting('transaction_read_only'),
  'expected_source_migration','20261001201055_reserver_remboursement_connect_avant_transfert.sql',
  'baseline_schema','c08ea254b6046c8e722425d54ca440f6',
  'current_schema',(SELECT actuelle FROM empreintes),
  'expected_fk_shapes_match',(SELECT exacte FROM forme),
  'schema_without_three_expected_fk',(SELECT sans_trois_fk FROM empreintes),
  'projection_matches_baseline',coalesce((SELECT sans_trois_fk='c08ea254b6046c8e722425d54ca440f6' FROM empreintes),false),
  'expected_fk',(SELECT jsonb_agg(jsonb_build_object(
    'name',nom,'column',colonne,'referenced_relation',cible,
    'found',oid IS NOT NULL,'shape_matches',conforme,'definition_md5',definition_md5
  ) ORDER BY nom) FROM fk)
) AS schema_projection;
