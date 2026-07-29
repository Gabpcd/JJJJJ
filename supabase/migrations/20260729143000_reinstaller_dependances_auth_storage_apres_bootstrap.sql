-- DROP SCHEMA public CASCADE est utilisé uniquement pour reconstruire le
-- staging depuis le dump canonique de production. PostgreSQL supprime alors
-- aussi les objets des schémas gérés qui dépendent de public, alors que le
-- dump Supabase n'exporte ni auth, ni storage, ni les données des buckets.
-- Cette migration rend ces dépendances reproductibles et reste idempotente
-- lors de son application normale en production.

BEGIN;

-- Le bucket n'est jamais rendu public et aucun objet n'est copié.
INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
VALUES
  (
    'attestations-heures-externes',
    'attestations-heures-externes',
    false,
    10485760,
    ARRAY[
      'application/pdf',
      'image/jpeg',
      'image/png'
    ]::text[]
  ),
  (
    'contrats-signes',
    'contrats-signes',
    false,
    5242880,
    ARRAY[
      'text/html',
      'application/pdf'
    ]::text[]
  ),
  (
    'jolene-documents',
    'jolene-documents',
    false,
    26214400,
    ARRAY[
      'application/pdf',
      'application/xml',
      'image/heic',
      'image/heif',
      'image/jpeg',
      'image/png',
      'image/webp',
      'text/xml'
    ]::text[]
  ),
  (
    'justificatifs',
    'justificatifs',
    false,
    10485760,
    ARRAY[
      'application/pdf',
      'image/jpeg',
      'image/png',
      'image/webp'
    ]::text[]
  )
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- La fonction est restaurée par le dump public, mais son trigger sur la table
-- gérée auth.users est supprimé par la cascade et doit être rattaché.
DROP TRIGGER IF EXISTS trg_auth_user_deleted_cleanup ON auth.users;
CREATE TRIGGER trg_auth_user_deleted_cleanup
  AFTER DELETE ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_auth_user_deleted_cleanup_soignant();

-- Les huit policies sont l'état exact audité en production le 29 juillet
-- 2026. Toutes exigent un compte actif et restent limitées à authenticated.
DROP POLICY IF EXISTS pol_storage_jolene_insert ON storage.objects;
CREATE POLICY pol_storage_jolene_insert ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'jolene-documents'
  AND public.fn_compte_auth_actif()
  AND public.fn_peut_gerer_objet_jolene(name)
);

DROP POLICY IF EXISTS pol_storage_jolene_select ON storage.objects;
CREATE POLICY pol_storage_jolene_select ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'jolene-documents'
  AND public.fn_compte_auth_actif()
  AND public.fn_peut_lire_objet_jolene(name)
);

DROP POLICY IF EXISTS justificatifs_insert_auth ON storage.objects;
CREATE POLICY justificatifs_insert_auth ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'justificatifs'
  AND public.fn_compte_auth_actif()
  AND public.fn_peut_deposer_justificatif(name)
);

DROP POLICY IF EXISTS justificatifs_select_auth ON storage.objects;
CREATE POLICY justificatifs_select_auth ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'justificatifs'
  AND public.fn_compte_auth_actif()
  AND public.fn_peut_lire_justificatif(name)
);

DROP POLICY IF EXISTS pol_contrats_signes_select ON storage.objects;
CREATE POLICY pol_contrats_signes_select ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'contrats-signes'
  AND public.fn_compte_auth_actif()
  AND (
    public.est_admin()
    OR EXISTS (
      SELECT 1
        FROM public.contrats_mission cm
       WHERE cm.storage_path = storage.objects.name
         AND (
           cm.soignant_id = (SELECT auth.uid())
           OR cm.etablissement_id = public.mon_etablissement_id()
         )
    )
  )
);

DROP POLICY IF EXISTS soignant_lit_ses_attestations ON storage.objects;
CREATE POLICY soignant_lit_ses_attestations ON storage.objects
FOR SELECT TO authenticated
USING (
  public.fn_compte_auth_actif()
  AND bucket_id = 'attestations-heures-externes'
  AND (
    (storage.foldername(name))[1] = auth.uid()::text
    OR public.est_admin()
  )
);

DROP POLICY IF EXISTS soignant_supprime_ses_attestations ON storage.objects;
CREATE POLICY soignant_supprime_ses_attestations ON storage.objects
FOR DELETE TO authenticated
USING (
  public.fn_compte_auth_actif()
  AND bucket_id = 'attestations-heures-externes'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS soignant_upload_ses_attestations ON storage.objects;
CREATE POLICY soignant_upload_ses_attestations ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  public.fn_compte_auth_actif()
  AND bucket_id = 'attestations-heures-externes'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Vue hors public également supprimée par la cascade. Elle n'est exposée à
-- aucun rôle applicatif, conformément à l'état de production.
CREATE OR REPLACE VIEW extensions.vm_fiabilite_soignants AS
SELECT
  s.id AS soignant_id,
  s.prenom,
  s.nom,
  s.profession,
  s.total_missions_terminees,
  s.total_missions_annulees,
  s.total_retards_pointage,
  s.total_absences,
  greatest(
    0::numeric,
    least(
      100::numeric,
      50.0
      + s.total_missions_terminees::numeric * 2.0
      - s.total_missions_annulees::numeric * 8.0
      - s.total_absences::numeric * 25.0
      - s.total_retards_pointage::numeric * 3.0
      + CASE WHEN s.total_missions_terminees > 20 THEN 10.0 ELSE 0::numeric END
      + CASE
          WHEN s.total_absences = 0
           AND s.total_missions_terminees > 5
          THEN 5.0
          ELSE 0::numeric
        END
      + CASE WHEN s.prevoyance_inscrit THEN 3.0 ELSE 0::numeric END
    )
  ) AS score_calcule,
  CASE
    WHEN s.total_absences >= 3 THEN 'LISTE_NOIRE'::text
    WHEN s.total_missions_terminees < 3 THEN 'NOUVEAU'::text
    ELSE 'ACTIF'::text
  END AS categorie_soignant,
  s.tous_documents_valides,
  s.derniere_activite_le
FROM public.soignants s
WHERE s.supprime_le IS NULL;

REVOKE ALL ON extensions.vm_fiabilite_soignants
  FROM PUBLIC, anon, authenticated;

-- Les adhésions Realtime sont des données de publication, pas des objets du
-- dump public. On restaure uniquement les cinq tables effectivement publiées
-- en production, sans élargir la surface temps réel.
DO $reconcilier_realtime$
DECLARE
  v_table text;
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_catalog.pg_publication
     WHERE pubname = 'supabase_realtime'
  ) THEN
    RAISE EXCEPTION 'Publication supabase_realtime absente';
  END IF;

  FOREACH v_table IN ARRAY ARRAY[
    'messages_chat',
    'messages_mission',
    'notifications',
    'presence_status',
    'typing_status'
  ]::text[]
  LOOP
    IF NOT EXISTS (
      SELECT 1
        FROM pg_catalog.pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = v_table
    ) THEN
      EXECUTE format(
        'ALTER PUBLICATION supabase_realtime ADD TABLE public.%I',
        v_table
      );
    END IF;
  END LOOP;
END
$reconcilier_realtime$;

-- Le bootstrap staging désinscrit tous les anciens jobs avant le restore afin
-- qu'aucune migration fantôme ne survive. Cette primitive versionnée recrée
-- exclusivement les huit traitements de lancement et leur monitor, inactifs.
DO $reconcilier_crons$
DECLARE
  v_resultat jsonb;
BEGIN
  v_resultat := private.fn_reconcilier_crons_edge_critiques_inactifs();
  IF (v_resultat ->> 'success')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Réconciliation cron impossible : %', v_resultat;
  END IF;
END
$reconcilier_crons$;

DO $assertions_dependances_gerees$
DECLARE
  v_policies integer;
  v_buckets integer;
  v_realtime integer;
  v_crons integer;
  v_crons_actifs integer;
BEGIN
  SELECT count(*)
    INTO v_policies
    FROM pg_catalog.pg_policies
   WHERE schemaname = 'storage'
     AND tablename = 'objects'
     AND policyname = ANY (ARRAY[
       'pol_storage_jolene_insert',
       'pol_storage_jolene_select',
       'justificatifs_insert_auth',
       'justificatifs_select_auth',
       'pol_contrats_signes_select',
       'soignant_lit_ses_attestations',
       'soignant_supprime_ses_attestations',
       'soignant_upload_ses_attestations'
     ]::text[]);

  SELECT count(*)
    INTO v_buckets
    FROM storage.buckets b
   WHERE b.id = ANY (ARRAY[
     'attestations-heures-externes',
     'contrats-signes',
     'jolene-documents',
     'justificatifs'
     ]::text[])
     AND b.public IS FALSE;

  SELECT count(*)
    INTO v_realtime
    FROM pg_catalog.pg_publication_tables
   WHERE pubname = 'supabase_realtime'
     AND schemaname = 'public'
     AND tablename = ANY (ARRAY[
       'messages_chat',
       'messages_mission',
       'notifications',
       'presence_status',
       'typing_status'
     ]::text[]);

  SELECT count(*), count(*) FILTER (WHERE active IS TRUE)
    INTO v_crons, v_crons_actifs
    FROM cron.job
   WHERE jobname = ANY (ARRAY[
     'litige-escalation-cron',
     'email-cron-hourly-immediate',
     'email-cron-daily',
     'process-stripe-refunds-15min',
     'escrow-debit-echeance',
     'escrow-release',
     'jolene_process_externalisations',
     'weekly-invoicing-cron',
     'jolene-monitor-crons-edge-critiques'
   ]::text[]);

  IF v_policies <> 8 THEN
    RAISE EXCEPTION 'Policies Storage Jolene incomplètes : %/8', v_policies;
  END IF;
  IF v_buckets <> 4 THEN
    RAISE EXCEPTION 'Buckets privés Jolene incomplets : %/4', v_buckets;
  END IF;
  IF v_realtime <> 5 THEN
    RAISE EXCEPTION 'Tables Realtime Jolene incomplètes : %/5', v_realtime;
  END IF;
  IF v_crons <> 9 OR v_crons_actifs <> 0 THEN
    RAISE EXCEPTION
      'Crons lancement incohérents : %/9 présents, % actifs',
      v_crons,
      v_crons_actifs;
  END IF;
  IF NOT EXISTS (
    SELECT 1
      FROM pg_catalog.pg_trigger t
      JOIN pg_catalog.pg_class c ON c.oid = t.tgrelid
      JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'auth'
       AND c.relname = 'users'
       AND t.tgname = 'trg_auth_user_deleted_cleanup'
       AND t.tgisinternal IS FALSE
  ) THEN
    RAISE EXCEPTION 'Trigger Auth de nettoyage soignant absent';
  END IF;
  IF to_regclass('extensions.vm_fiabilite_soignants') IS NULL THEN
    RAISE EXCEPTION 'Vue extensions.vm_fiabilite_soignants absente';
  END IF;
END
$assertions_dependances_gerees$;

COMMIT;
