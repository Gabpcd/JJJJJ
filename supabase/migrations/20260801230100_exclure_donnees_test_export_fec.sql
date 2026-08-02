BEGIN;

-- Compatibilité : le nom historique de la RPC est conservé, mais son résultat
-- est explicitement un JOURNAL DES VENTES au format technique 18 colonnes.
-- Il ne doit pas être présenté comme le FEC réglementaire complet, qui doit
-- regrouper tous les journaux comptables de l'exercice.
DROP FUNCTION IF EXISTS public.fn_export_fec(integer);

CREATE FUNCTION public.fn_export_fec(p_annee integer)
RETURNS TABLE(
  "JournalCode" text,
  "JournalLib" text,
  "EcritureNum" text,
  "EcritureDate" text,
  "CompteNum" text,
  "CompteLib" text,
  "CompAuxNum" text,
  "CompAuxLib" text,
  "PieceRef" text,
  "PieceDate" text,
  "EcritureLib" text,
  "Debit" numeric,
  "Credit" numeric,
  "EcritureLet" text,
  "DateLet" text,
  "ValidDate" text,
  "Montantdevise" numeric,
  "Idevise" text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF NOT public.est_admin() THEN
    RETURN;
  END IF;

  -- Aucun export silencieusement déséquilibré : si une facture de production
  -- comptabilisée ne respecte pas HT + TVA = TTC au centime, l'export s'arrête.
  IF EXISTS (
    SELECT 1
    FROM public.factures f
    JOIN public.etablissements e ON e.id = f.etablissement_id
    WHERE EXTRACT(
            YEAR FROM f.date_emission AT TIME ZONE 'Europe/Paris'
          ) = p_annee
      AND e.est_compte_test IS FALSE
      AND f.statut NOT IN ('BROUILLON', 'ANNULEE')
      AND f.numero_facture IS NOT NULL
      AND f.date_emission IS NOT NULL
      AND (
        f.montant_ht IS NULL
        OR f.montant_tva IS NULL
        OR f.montant_ttc IS NULL
        OR pg_catalog.round(pg_catalog.abs(f.montant_ttc), 2) <= 0
        OR pg_catalog.round(pg_catalog.abs(f.montant_ttc), 2)
           <> pg_catalog.round(pg_catalog.abs(f.montant_ht), 2)
              + pg_catalog.round(pg_catalog.abs(f.montant_tva), 2)
      )
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22000',
      MESSAGE = 'Export journal des ventes interrompu : montants HT, TVA ou TTC incohérents.';
  END IF;

  RETURN QUERY
  WITH documents_bruts AS (
    SELECT
      f.numero_facture,
      (f.date_emission AT TIME ZONE 'Europe/Paris')::date AS date_comptable,
      e.siret::text AS siret,
      e.nom AS etablissement_nom,
      f.type_document = 'AVOIR'
        OR COALESCE(f.montant_signe, f.montant_ht, 0) < 0 AS est_avoir,
      pg_catalog.round(pg_catalog.abs(f.montant_ht), 2)::numeric AS montant_ht,
      pg_catalog.round(pg_catalog.abs(f.montant_tva), 2)::numeric AS montant_tva,
      pg_catalog.round(pg_catalog.abs(f.montant_ttc), 2)::numeric AS montant_ttc
    FROM public.factures f
    JOIN public.etablissements e ON e.id = f.etablissement_id
    WHERE EXTRACT(
            YEAR FROM f.date_emission AT TIME ZONE 'Europe/Paris'
          ) = p_annee
      AND e.est_compte_test IS FALSE
      AND f.statut NOT IN ('BROUILLON', 'ANNULEE')
      AND f.numero_facture IS NOT NULL
      AND f.date_emission IS NOT NULL
  ),
  documents AS (
    SELECT
      d.*,
      'VE-' || p_annee::text || '-'
        || pg_catalog.lpad(
          pg_catalog.row_number() OVER (
            ORDER BY d.date_comptable, d.numero_facture
          )::text,
          8,
          '0'
        ) AS ecriture_num
    FROM documents_bruts d
  )
  SELECT
    'VE'::text,
    'Ventes'::text,
    d.ecriture_num,
    pg_catalog.to_char(d.date_comptable, 'YYYYMMDD'),
    l.compte_num,
    l.compte_lib,
    CASE WHEN l.ordre = 1 THEN d.siret ELSE ''::text END,
    CASE WHEN l.ordre = 1 THEN d.etablissement_nom ELSE ''::text END,
    d.numero_facture,
    pg_catalog.to_char(d.date_comptable, 'YYYYMMDD'),
    CASE WHEN d.est_avoir THEN 'Avoir commission Jolene' ELSE 'Commission Jolene' END,
    l.debit,
    l.credit,
    ''::text,
    ''::text,
    pg_catalog.to_char(d.date_comptable, 'YYYYMMDD'),
    NULL::numeric,
    NULL::text
  FROM documents d
  CROSS JOIN LATERAL (
    VALUES
      (
        1,
        '411000'::text,
        'Clients'::text,
        CASE WHEN d.est_avoir THEN 0::numeric ELSE d.montant_ttc END,
        CASE WHEN d.est_avoir THEN d.montant_ttc ELSE 0::numeric END
      ),
      (
        2,
        '706000'::text,
        'Prestations de services'::text,
        CASE WHEN d.est_avoir THEN d.montant_ht ELSE 0::numeric END,
        CASE WHEN d.est_avoir THEN 0::numeric ELSE d.montant_ht END
      ),
      (
        3,
        '445710'::text,
        'TVA collectée'::text,
        CASE WHEN d.est_avoir THEN d.montant_tva ELSE 0::numeric END,
        CASE WHEN d.est_avoir THEN 0::numeric ELSE d.montant_tva END
      )
  ) AS l(ordre, compte_num, compte_lib, debit, credit)
  WHERE l.debit <> 0 OR l.credit <> 0
  ORDER BY d.date_comptable, d.ecriture_num, l.ordre;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_export_fec(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_export_fec(integer)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_export_fec(integer) IS
  'Nom historique conservé pour compatibilité : export du seul journal des ventes au format 18 colonnes, non assimilable au FEC réglementaire complet; production uniquement.';

INSERT INTO private.security_definer_inventory (
  signature,
  categorie,
  definition_md5,
  justification,
  recense_le
)
SELECT
  'fn_export_fec(integer)',
  'ADMIN_EST_ADMIN_VALIDE',
  pg_catalog.md5(p.prosrc),
  'RPC administrateur: journal des ventes 18 colonnes équilibré, limité aux établissements de production et aux documents comptabilisés.',
  pg_catalog.now()
FROM pg_catalog.pg_proc p
WHERE p.oid = 'public.fn_export_fec(integer)'::pg_catalog.regprocedure
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;

DO $assert_fn_export_fec_inventory$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM private.security_definer_inventory i
    JOIN pg_catalog.pg_proc p
      ON p.oid = 'public.fn_export_fec(integer)'::pg_catalog.regprocedure
    WHERE i.signature = 'fn_export_fec(integer)'
      AND i.definition_md5 = pg_catalog.md5(p.prosrc)
  ) THEN
    RAISE EXCEPTION
      'Inventaire SECURITY DEFINER non synchronisé pour fn_export_fec(integer)';
  END IF;
END;
$assert_fn_export_fec_inventory$;

COMMIT;
