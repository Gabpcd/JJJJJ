BEGIN;

-- L'ancien export portait le nom FEC mais ne produisait qu'une ligne crédit
-- par facture. Il incluait en plus les comptes test et les documents annulés.
-- La nouvelle signature retourne les 18 colonnes réglementaires et des
-- écritures équilibrées client / produit / TVA pour factures comme avoirs.
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

  RETURN QUERY
  WITH documents AS (
    SELECT
      f.numero_facture,
      f.date_emission,
      e.siret::text AS siret,
      e.nom AS etablissement_nom,
      f.type_document = 'AVOIR'
        OR COALESCE(f.montant_signe, f.montant_ht, 0) < 0 AS est_avoir,
      abs(COALESCE(f.montant_signe, f.montant_ht, 0))::numeric AS montant_ht,
      abs(COALESCE(f.montant_ttc, 0))::numeric AS montant_ttc
    FROM public.factures f
    JOIN public.etablissements e ON e.id = f.etablissement_id
    WHERE EXTRACT(YEAR FROM f.date_emission) = p_annee
      AND e.est_compte_test IS FALSE
      AND f.statut NOT IN ('BROUILLON', 'ANNULEE')
      AND f.numero_facture IS NOT NULL
      AND f.date_emission IS NOT NULL
  )
  SELECT
    'VE'::text,
    'Ventes'::text,
    d.numero_facture,
    pg_catalog.to_char(d.date_emission, 'YYYYMMDD'),
    l.compte_num,
    l.compte_lib,
    CASE WHEN l.ordre = 1 THEN d.siret ELSE ''::text END,
    CASE WHEN l.ordre = 1 THEN d.etablissement_nom ELSE ''::text END,
    d.numero_facture,
    pg_catalog.to_char(d.date_emission, 'YYYYMMDD'),
    CASE WHEN d.est_avoir THEN 'Avoir commission Jolene' ELSE 'Commission Jolene' END,
    l.debit,
    l.credit,
    ''::text,
    ''::text,
    pg_catalog.to_char(d.date_emission, 'YYYYMMDD'),
    l.montant_devise,
    'EUR'::text
  FROM documents d
  CROSS JOIN LATERAL (
    VALUES
      (
        1,
        '411000'::text,
        'Clients'::text,
        CASE WHEN d.est_avoir THEN 0::numeric ELSE d.montant_ttc END,
        CASE WHEN d.est_avoir THEN d.montant_ttc ELSE 0::numeric END,
        d.montant_ttc
      ),
      (
        2,
        '706000'::text,
        'Prestations de services'::text,
        CASE WHEN d.est_avoir THEN d.montant_ht ELSE 0::numeric END,
        CASE WHEN d.est_avoir THEN 0::numeric ELSE d.montant_ht END,
        d.montant_ht
      ),
      (
        3,
        '445710'::text,
        'TVA collectée'::text,
        CASE WHEN d.est_avoir THEN greatest(d.montant_ttc - d.montant_ht, 0::numeric) ELSE 0::numeric END,
        CASE WHEN d.est_avoir THEN 0::numeric ELSE greatest(d.montant_ttc - d.montant_ht, 0::numeric) END,
        greatest(d.montant_ttc - d.montant_ht, 0::numeric)
      )
  ) AS l(ordre, compte_num, compte_lib, debit, credit, montant_devise)
  WHERE l.montant_devise > 0
  ORDER BY d.date_emission, d.numero_facture, l.ordre;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_export_fec(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_export_fec(integer)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_export_fec(integer) IS
  'FEC à 18 colonnes réservé aux administrateurs; écritures équilibrées et limitées aux documents comptabilisés des établissements de production.';

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
  'RPC administrateur: FEC 18 colonnes équilibré, limité aux établissements de production et aux documents comptabilisés.',
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
