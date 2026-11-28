-- Suppression du compte soignant : fichiers des pièces effacés, noms lus par l'IA effacés.
--
-- Constat (production relue en lecture seule le 28/11/2026, corps LIVE de
-- public.fn_supprimer_mon_compte md5 f3af23aeeb4e30aba07e422c0e819aeb) : la
-- suppression d'un compte soignant (edge delete-account →
-- fn_supprimer_compte_rate_limited → fn_supprimer_mon_compte) marque seulement
-- les pièces supprimées (documents_soignants.supprime_le). Restent après la
-- suppression :
--   * les fichiers dans Supabase Storage (bucket jolene-documents : pièces,
--     versions remplacées non référencées, attestations d'heures externes ;
--     bucket attestations-heures-externes ; bucket justificatifs :
--     réclamations et annulations de candidature) ;
--   * les noms et prénoms lus par l'IA et leurs champs dérivés :
--     documents_soignants.resultat_ia, nom_extrait_ia, prenom_extrait_ia,
--     coherence_nom, score_confiance_ia, motif_rejet (texte rédigé par l'IA),
--     nom_fichier et s3_cle (nom de fichier d'origine), libelle,
--     revoque_raison ; heures_externes_soignants (résultat IA, nom de
--     l'employeur, fichier) ; file de revue manuelle (motif repris du texte IA,
--     chemins et instantanés en données d'origine) et décisions de revue.
-- Production au 28/11/2026 : aucun compte soignant supprimé, donc aucun résidu
-- existant ; le rattrapage ci-dessous est sans effet en production.
--
-- Décision (docs/CONFORMITE.md §6, sources primaires citées) :
--   * effacés : les fichiers ci-dessus et les données lues par l'IA (RGPD
--     art. 17.1 a : données plus nécessaires à la vérification, finalité
--     épuisée ; aucune obligation légale de conservation de ces copies) ;
--   * conservés, rattachés au seul identifiant d'un profil anonymisé : la trace
--     de vérification de chaque pièce (type, statut, dates de vérification et de
--     validité), sans copie ni contenu lu (art. 17.3 e, preuve de la
--     vérification) ; les factures, avoirs, contrats signés, bulletins et
--     relevés de rétrocession (art. 17.3 b et e) ; le journal d'audit,
--     immuable ;
--   * un dossier de stockage inconnu sous le préfixe du soignant n'est jamais
--     effacé à l'aveugle : alerte CRITICAL (aucun nom de fichier dans l'alerte).
--
-- Mécanisme (aucune suppression SQL de storage.objects) :
--   1. private.rgpd_purges_stockage : file durable des fichiers à effacer
--      (chemin effacé après purge confirmée ; empreinte SHA-256 conservée pour
--      l'idempotence et la preuve d'effacement).
--   2. private.fn_rgpd_effacer_pieces_soignant(uuid, text) : met les fichiers en
--      file, efface le contenu des pièces (ligne pseudonyme conservée), supprime
--      les attestations d'heures externes, anonymise la file de revue ;
--      post-condition fail-closed (exception si un résidu subsiste). Appelée
--      par fn_supprimer_mon_compte dans la transaction de l'anonymisation.
--   3. Edge purge-stockage-rgpd (secret d'automatisation) : réserve un lot
--      (public.fn_rgpd_purges_stockage_reserver), efface par l'API Storage,
--      puis confirme (public.fn_rgpd_purges_stockage_confirmer), qui ne tient
--      un fichier pour effacé que s'il a disparu de storage.objects, et écrit
--      l'audit RGPD_SUPPRESSION_DONNEES. Appelée toutes les heures par le cron
--      jolene_rgpd_purge_stockage (private.fn_lancer_purge_stockage_rgpd, pg_net),
--      qui alerte (CRITICAL) si un fichier attend depuis plus de 24 h ou si
--      l'appel est impossible. Aucun appel réseau dans la transaction de
--      suppression du compte.
--   4. public.fn_rgpd_purge_automatique_inactifs (non planifiée) est
--      verrouillée : elle anonymisait bien moins que la suppression de compte et
--      écrasait le chemin des pièces (fichiers alors introuvables). Erreur
--      explicite renvoyant à docs/CONFORMITE.md §6.5 jusqu'à son réalignement.
--
-- Redéfinition de fn_supprimer_mon_compte : corps LIVE relu le 28/11/2026 (md5
-- f3af23aeeb4e30aba07e422c0e819aeb, identique à supabase/schema/public.sql),
-- trois ajouts seulement (variable, appel de l'effacement à la place de
-- l'UPDATE des pièces, détail de l'audit). En-tête,
-- SECURITY DEFINER, search_path, propriétaire et ACL conservés par CREATE OR
-- REPLACE. Préflight fail-closed sur les corps LIVE et les déclencheurs de
-- protection des pièces ; post-condition sur md5(prosrc) de chaque corps
-- installé, les droits et l'inventaire SECURITY DEFINER.
--
-- Contrôles : tests/security/suppression-compte-soignant-effacement.test.sql
-- (staging, ROLLBACK ; même suite sur PostgreSQL 17 et PGlite par
-- tests/postgres/suppression-compte-soignant-effacement.pg17.mjs), garde
-- statique tests/node/suppression-compte-soignant-effacement.node.mjs, boucle
-- de purge tests/node/rgpd-purge-stockage.node.mjs.
-- B9 (suppression de données personnelles, SECURITY DEFINER) : go écrit de Gabrielle du 24/11/2026.
-- Aucun BEGIN/COMMIT : la CLI ou le banc appelant possède la transaction.
SET LOCAL lock_timeout = '5s';

-- ── 0. Préflight fail-closed : corps LIVE et déclencheurs de protection ─────
DO $effacement_pieces_avant$
DECLARE
  v_attendu record;
  v_proc record;
BEGIN
  FOR v_attendu IN
    SELECT * FROM (VALUES
      ('public.fn_supprimer_mon_compte()', 'f3af23aeeb4e30aba07e422c0e819aeb', 'search_path=public, extensions', true),
      ('public.fn_rgpd_purge_automatique_inactifs()', '5f23570c269b42d088b7e4ed5482660d', 'search_path=public', false),
      ('public.fn_proteger_ecriture_document_soignant()', 'c490ce823768b0a23cd264ab17601155', 'search_path=pg_catalog, public', true),
      ('public.fn_proteger_document_verification()', '3d0a5c7f64f8e8e13cc08d16c5fc73a3', 'search_path=pg_catalog, public', true),
      ('public.dec_proteger_validation_documents()', 'ca164f7e032b08f791132e2f691a8024', 'search_path=pg_catalog, public', true),
      ('public.fn_proteger_heures_externes_soignants()', '42712bf3859e84061bbf0bf2e531ee75', 'search_path=pg_catalog, public', true),
      ('public.fn_invalider_preuves_identite_sur_changement()', 'bb93c49d6187ee007b964acab6bf0809', 'search_path=pg_catalog, public', true)
    ) AS t(signature, empreinte, config, definer)
  LOOP
    SELECT p.prosrc, p.prosecdef, p.proconfig, pg_catalog.pg_get_userbyid(p.proowner) AS proprietaire
      INTO v_proc
      FROM pg_catalog.pg_proc p
     WHERE p.oid = pg_catalog.to_regprocedure(v_attendu.signature);
    IF NOT FOUND
      OR pg_catalog.md5(v_proc.prosrc) IS DISTINCT FROM v_attendu.empreinte
      OR v_proc.prosecdef IS DISTINCT FROM v_attendu.definer
      OR v_proc.proconfig IS DISTINCT FROM ARRAY[v_attendu.config]::text[]
      OR v_proc.proprietaire IS DISTINCT FROM 'postgres'
    THEN
      RAISE EXCEPTION 'EFFACEMENT_PIECES_SOURCE_DIVERGENTE : % en base (md5 %) ne correspond plus au corps LIVE relu le 28/11/2026 (md5 %). Redéfinition refusée : repartir de la définition LIVE (CLAUDE.md, garde-fous 9.0 n°2).',
        v_attendu.signature, COALESCE(pg_catalog.md5(v_proc.prosrc), 'fonction absente'), v_attendu.empreinte;
    END IF;
  END LOOP;
  -- Les écritures de l'effacement passent les protections des pièces par leurs
  -- drapeaux serveur : tout autre déclencheur BEFORE UPDATE sur les pièces, ou
  -- un déclencheur BEFORE DELETE sur les heures externes, doit être revu avant.
  IF (SELECT pg_catalog.array_agg(t.tgname::text ORDER BY t.tgname)
        FROM pg_catalog.pg_trigger t
       WHERE t.tgrelid = 'public.documents_soignants'::pg_catalog.regclass AND NOT t.tgisinternal
         AND t.tgenabled <> 'D' AND (t.tgtype & 2) <> 0 AND (t.tgtype & 16) <> 0)
     IS DISTINCT FROM ARRAY['dec_proteger_valid_docs', 'trg_proteger_document_verification',
                            'trg_proteger_ecriture_document_soignant', 'trg_proteger_proprietaire_attestation_ordre',
                            'trg_proteger_tentative_verification_document']
     OR EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
                 WHERE t.tgrelid = 'public.heures_externes_soignants'::pg_catalog.regclass AND NOT t.tgisinternal
                   AND t.tgenabled <> 'D' AND (t.tgtype & 2) <> 0 AND (t.tgtype & 8) <> 0)
     OR (SELECT pg_catalog.count(*) FROM pg_catalog.pg_trigger t
          WHERE t.tgrelid = 'public.file_revue_manuelle'::pg_catalog.regclass AND NOT t.tgisinternal) <> 0
  THEN
    RAISE EXCEPTION 'EFFACEMENT_PIECES_DECLENCHEURS_DIVERGENTS : déclencheurs de protection des pièces, des heures externes ou de la file de revue inattendus.';
  END IF;
END
$effacement_pieces_avant$;

-- ── 1. File durable des fichiers à effacer ─────────────────────────────────
CREATE TABLE IF NOT EXISTS private.rgpd_purges_stockage (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL,
  bucket text NOT NULL,
  chemin text,
  empreinte text NOT NULL,
  origine text NOT NULL,
  motif text NOT NULL,
  demande_le timestamptz NOT NULL DEFAULT now(),
  reserve_jusqua timestamptz,
  tentatives integer NOT NULL DEFAULT 0,
  derniere_erreur text,
  purge_le timestamptz,
  CONSTRAINT rgpd_purges_stockage_empreinte_key UNIQUE (empreinte),
  CONSTRAINT rgpd_purges_stockage_empreinte_check CHECK (empreinte ~ '^[0-9a-f]{64}$'),
  CONSTRAINT rgpd_purges_stockage_origine_check CHECK (origine IN ('DOCUMENT', 'HEURES_EXTERNES', 'PREFIXE')),
  CONSTRAINT rgpd_purges_stockage_motif_check CHECK (motif IN ('SUPPRESSION_COMPTE', 'RATTRAPAGE_SUPPRESSION_COMPTE')),
  CONSTRAINT rgpd_purges_stockage_chemin_check CHECK ((purge_le IS NULL) = (chemin IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS rgpd_purges_stockage_en_attente_idx
  ON private.rgpd_purges_stockage (demande_le) WHERE purge_le IS NULL;
CREATE INDEX IF NOT EXISTS rgpd_purges_stockage_soignant_idx
  ON private.rgpd_purges_stockage (soignant_id);

ALTER TABLE private.rgpd_purges_stockage ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.rgpd_purges_stockage FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.rgpd_purges_stockage FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE private.rgpd_purges_stockage IS
  'Fichiers Storage d''un compte soignant supprimé, à effacer par l''edge purge-stockage-rgpd (API Storage). Chemin effacé après purge confirmée ; empreinte SHA-256 conservée (preuve, idempotence). docs/CONFORMITE.md §6. Migration 20261128140100.';

-- ── 2. Classement d'un objet du préfixe soignant ───────────────────────────
-- Une seule source : EFFACER (copie fournie par le soignant, aucune obligation
-- de conservation), CONSERVER (pièce justificative financière), INCONNU (jamais
-- effacé à l'aveugle, alerte), NULL (hors du préfixe ou d'un bucket examiné).
CREATE OR REPLACE FUNCTION private.fn_rgpd_decision_objet_soignant(p_bucket text, p_nom text, p_soignant_id uuid)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $fn_rgpd_decision_objet_soignant$
  SELECT CASE
    WHEN p_bucket IS NULL OR p_nom IS NULL OR p_soignant_id IS NULL
      OR p_bucket NOT IN ('jolene-documents', 'attestations-heures-externes', 'justificatifs')
      OR NOT pg_catalog.starts_with(p_nom, p_soignant_id::text || '/') THEN NULL
    WHEN p_bucket = 'attestations-heures-externes' THEN 'EFFACER'
    WHEN pg_catalog.strpos(pg_catalog.substr(p_nom, 38), '/') = 0 THEN 'INCONNU'
    WHEN p_bucket = 'jolene-documents'
      AND pg_catalog.split_part(p_nom, '/', 2) IN ('documents', 'heures-externes') THEN 'EFFACER'
    WHEN p_bucket = 'justificatifs'
      AND pg_catalog.split_part(p_nom, '/', 2) IN ('reclamations', 'annulations-candidature') THEN 'EFFACER'
    WHEN p_bucket = 'justificatifs'
      AND pg_catalog.split_part(p_nom, '/', 2) = 'retrocession' THEN 'CONSERVER'
    ELSE 'INCONNU'
  END
$fn_rgpd_decision_objet_soignant$;

-- ── 3. Alerte (une ligne active par type, occurrences comptées) ────────────
CREATE OR REPLACE FUNCTION private.fn_rgpd_signaler_purge_stockage(p_type text, p_message text, p_details jsonb)
RETURNS void
LANGUAGE sql
SET search_path TO ''
AS $fn_rgpd_signaler_purge_stockage$
  INSERT INTO public.alertes_systeme AS a (type_alerte, severite, source, message, details)
  VALUES (p_type, 'CRITICAL', 'rgpd-purge-stockage', p_message, COALESCE(p_details, '{}'::jsonb))
  ON CONFLICT (source, type_alerte) WHERE resolu_le IS NULL
  DO UPDATE SET occurrences = a.occurrences + 1,
                derniere_occurrence = pg_catalog.now(),
                details = EXCLUDED.details;
$fn_rgpd_signaler_purge_stockage$;

-- ── 4. Effacement des pièces d'un compte soignant supprimé ─────────────────
CREATE OR REPLACE FUNCTION private.fn_rgpd_effacer_pieces_soignant(p_soignant_id uuid, p_motif text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn_rgpd_effacer_pieces_soignant$
DECLARE
  v_document_server_update text := COALESCE(pg_catalog.current_setting('jolene.document_server_update', true), '');
  v_system_update text := COALESCE(pg_catalog.current_setting('jolene.system_update', true), '');
  v_documents uuid[];
  v_revues uuid[];
  v_pieces integer := 0;
  v_heures integer := 0;
  v_nb_revues integer := 0;
  v_en_file integer := 0;
  v_conserves integer := 0;
  v_inconnus integer := 0;
BEGIN
  IF p_soignant_id IS NULL OR p_motif IS NULL
     OR p_motif NOT IN ('SUPPRESSION_COMPTE', 'RATTRAPAGE_SUPPRESSION_COMPTE') THEN
    RAISE EXCEPTION 'RGPD_EFFACEMENT_PIECES_PARAMETRES : soignant et motif requis.' USING ERRCODE = '22023';
  END IF;
  -- L'effacement suit l'anonymisation du profil, jamais l'inverse.
  IF NOT EXISTS (SELECT 1 FROM public.soignants s WHERE s.id = p_soignant_id AND s.supprime_le IS NOT NULL) THEN
    RAISE EXCEPTION 'RGPD_EFFACEMENT_PIECES_PROFIL_ACTIF : l''effacement des pièces suit l''anonymisation du profil (supprime_le posé), docs/CONFORMITE.md §6.'
      USING ERRCODE = '55000';
  END IF;

  SELECT pg_catalog.array_agg(d.id) INTO v_documents
    FROM public.documents_soignants d WHERE d.soignant_id = p_soignant_id;

  -- 1. Fichiers en file : pièces référencées (toutes versions, y compris
  --    remplacées ou déjà supprimées), attestations d'heures externes, objets
  --    des dossiers à effacer du préfixe (versions orphelines).
  INSERT INTO private.rgpd_purges_stockage (soignant_id, bucket, chemin, empreinte, origine, motif)
  SELECT p_soignant_id, f.bucket, f.chemin,
         pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(f.bucket || '/' || f.chemin, 'UTF8')), 'hex'),
         f.origine, p_motif
    FROM (
      SELECT d.s3_bucket AS bucket, d.s3_cle AS chemin, 'DOCUMENT'::text AS origine
        FROM public.documents_soignants d
       WHERE d.soignant_id = p_soignant_id
         AND NULLIF(pg_catalog.btrim(d.s3_bucket), '') IS NOT NULL
         AND NULLIF(pg_catalog.btrim(d.s3_cle), '') IS NOT NULL
         AND d.s3_cle <> 'PURGE'
         AND d.s3_cle IS DISTINCT FROM (p_soignant_id::text || '/documents/efface/' || d.id::text)
      UNION
      SELECT CASE WHEN pg_catalog.strpos(h.attestation_url, '/heures-externes/') > 0
                  THEN 'jolene-documents' ELSE 'attestations-heures-externes' END,
             h.attestation_url, 'HEURES_EXTERNES'
        FROM public.heures_externes_soignants h
       WHERE h.soignant_id = p_soignant_id
         AND NULLIF(pg_catalog.btrim(h.attestation_url), '') IS NOT NULL
         AND pg_catalog.strpos(h.attestation_url, '://') = 0
      UNION
      SELECT o.bucket_id, o.name, 'PREFIXE'
        FROM storage.objects o
       WHERE o.bucket_id IN ('jolene-documents', 'attestations-heures-externes', 'justificatifs')
         AND pg_catalog.starts_with(o.name, p_soignant_id::text || '/')
         AND private.fn_rgpd_decision_objet_soignant(o.bucket_id, o.name, p_soignant_id) = 'EFFACER'
    ) f
  ON CONFLICT (empreinte) DO NOTHING;

  SELECT pg_catalog.count(*) FILTER (WHERE x.decision = 'CONSERVER'),
         pg_catalog.count(*) FILTER (WHERE x.decision = 'INCONNU')
    INTO v_conserves, v_inconnus
    FROM (SELECT private.fn_rgpd_decision_objet_soignant(o.bucket_id, o.name, p_soignant_id) AS decision
            FROM storage.objects o
           WHERE o.bucket_id IN ('jolene-documents', 'attestations-heures-externes', 'justificatifs')
             AND pg_catalog.starts_with(o.name, p_soignant_id::text || '/')) x;
  v_inconnus := v_inconnus + (SELECT pg_catalog.count(*)::integer FROM public.heures_externes_soignants h
                               WHERE h.soignant_id = p_soignant_id AND pg_catalog.strpos(h.attestation_url, '://') > 0);
  IF v_inconnus > 0 THEN
    -- Aucun nom de fichier dans l'alerte : il peut contenir le nom de la personne.
    PERFORM private.fn_rgpd_signaler_purge_stockage('RGPD_PURGE_STOCKAGE_DOSSIER_INCONNU',
      'Fichiers d''un compte soignant supprimé hors des dossiers connus : conservés, à classer (docs/CONFORMITE.md §6).',
      pg_catalog.jsonb_build_object('soignant_id', p_soignant_id, 'objets', v_inconnus, 'motif', p_motif));
  END IF;

  -- 2. Pièces : contenu effacé, trace de vérification pseudonyme conservée ;
  --    attestations d'heures externes supprimées.
  PERFORM pg_catalog.set_config('jolene.document_server_update', 'true', true);
  PERFORM pg_catalog.set_config('jolene.system_update', 'true', true);
  BEGIN
    UPDATE public.documents_soignants d
       SET supprime_le = COALESCE(d.supprime_le, pg_catalog.now()),
           s3_cle = p_soignant_id::text || '/documents/efface/' || d.id::text,
           s3_version_id = NULL,
           nom_fichier = 'fichier-efface',
           libelle = NULL,
           motif_rejet = NULL,
           revoque_raison = NULL,
           resultat_ia = NULL,
           nom_extrait_ia = NULL,
           prenom_extrait_ia = NULL,
           coherence_nom = NULL,
           score_confiance_ia = NULL,
           modifie_le = pg_catalog.now()
     WHERE d.soignant_id = p_soignant_id;
    GET DIAGNOSTICS v_pieces = ROW_COUNT;
    DELETE FROM public.heures_externes_soignants h WHERE h.soignant_id = p_soignant_id;
    GET DIAGNOSTICS v_heures = ROW_COUNT;
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_catalog.set_config('jolene.system_update', v_system_update, true);
    PERFORM pg_catalog.set_config('jolene.document_server_update', v_document_server_update, true);
    RAISE;
  END;
  PERFORM pg_catalog.set_config('jolene.system_update', v_system_update, true);
  PERFORM pg_catalog.set_config('jolene.document_server_update', v_document_server_update, true);

  -- 3. File de revue manuelle et décisions : motifs (repris du texte IA),
  --    données d'origine (chemins, instantanés) et notes effacés ; revue close.
  SELECT pg_catalog.array_agg(f.id) INTO v_revues
    FROM public.file_revue_manuelle f
   WHERE f.id_entite = p_soignant_id
      OR f.id_entite = ANY (COALESCE(v_documents, '{}'::uuid[]))
      OR (f.donnees_originales ->> 'soignant_id') = p_soignant_id::text;
  UPDATE public.file_revue_manuelle f
     SET motif_echec = 'Compte supprimé : contenu effacé (RGPD art. 17).',
         donnees_originales = pg_catalog.jsonb_build_object('rgpd_efface_le', pg_catalog.now()),
         notes_resolution = NULL,
         statut = CASE WHEN f.statut IN ('EN_ATTENTE', 'EN_COURS_REVUE', 'ESCALADE') THEN 'EXPIRE' ELSE f.statut END
   WHERE f.id = ANY (COALESCE(v_revues, '{}'::uuid[]));
  GET DIAGNOSTICS v_nb_revues = ROW_COUNT;
  UPDATE private.revue_manuelle_decisions r
     SET motif = 'Compte supprimé : motif effacé (RGPD art. 17).',
         source_snapshot = '{}'::jsonb
   WHERE r.revue_id = ANY (COALESCE(v_revues, '{}'::uuid[]))
      OR r.id_entite = p_soignant_id
      OR r.id_entite = ANY (COALESCE(v_documents, '{}'::uuid[]));

  -- 4. Post-condition : aucun contenu lu, aucun nom de fichier, aucune
  --    attestation d'heures ne subsiste ; sinon toute la suppression est annulée.
  IF EXISTS (SELECT 1 FROM public.documents_soignants d
              WHERE d.soignant_id = p_soignant_id
                AND (d.supprime_le IS NULL
                     OR d.nom_fichier IS DISTINCT FROM 'fichier-efface'
                     OR d.s3_cle IS DISTINCT FROM (p_soignant_id::text || '/documents/efface/' || d.id::text)
                     OR pg_catalog.num_nonnulls(d.resultat_ia, d.nom_extrait_ia, d.prenom_extrait_ia, d.coherence_nom,
                          d.score_confiance_ia, d.motif_rejet, d.libelle, d.revoque_raison, d.s3_version_id) > 0))
     OR EXISTS (SELECT 1 FROM public.heures_externes_soignants h WHERE h.soignant_id = p_soignant_id)
  THEN
    RAISE EXCEPTION 'RGPD_EFFACEMENT_PIECES_INCOMPLET : contenu de pièce ou attestation d''heures conservé après effacement (docs/CONFORMITE.md §6).'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT pg_catalog.count(*)::integer INTO v_en_file
    FROM private.rgpd_purges_stockage q WHERE q.soignant_id = p_soignant_id AND q.purge_le IS NULL;
  RETURN pg_catalog.jsonb_build_object(
    'pieces', v_pieces,
    'attestations_heures', v_heures,
    'revues', v_nb_revues,
    'fichiers_en_file', v_en_file,
    'fichiers_conserves', v_conserves,
    'fichiers_hors_perimetre', v_inconnus
  );
END;
$fn_rgpd_effacer_pieces_soignant$;

-- ── 5. Cron horaire : appel de l'edge purge-stockage-rgpd, alertes ─────────
-- Aucun appel réseau dans la transaction de suppression du compte (garde de
-- tests/security/suppression-compte-historique-financier.test.sql) : la purge
-- part du cron, au plus une heure après la suppression.
CREATE OR REPLACE FUNCTION private.fn_lancer_purge_stockage_rgpd()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn_lancer_purge_stockage_rgpd$
DECLARE
  v_attente integer;
  v_plus_ancienne timestamptz;
  v_tentatives integer;
  v_url text;
  v_secret text;
  v_requete bigint;
BEGIN
  SELECT pg_catalog.count(*)::integer, pg_catalog.min(q.demande_le), pg_catalog.max(q.tentatives)
    INTO v_attente, v_plus_ancienne, v_tentatives
    FROM private.rgpd_purges_stockage q WHERE q.purge_le IS NULL;
  IF v_attente = 0 THEN
    RETURN pg_catalog.jsonb_build_object('en_attente', 0);
  END IF;
  IF v_plus_ancienne < pg_catalog.now() - interval '24 hours' THEN
    PERFORM private.fn_rgpd_signaler_purge_stockage('RGPD_PURGE_STOCKAGE_EN_RETARD',
      'Effacement RGPD de fichiers en attente depuis plus de 24 h (docs/CONFORMITE.md §6).',
      pg_catalog.jsonb_build_object('en_attente', v_attente, 'plus_ancienne_demande', v_plus_ancienne,
        'tentatives_max', v_tentatives));
  END IF;
  IF pg_catalog.to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') IS NOT NULL THEN
    SELECT pg_catalog.rtrim(ds.decrypted_secret, '/') INTO v_url
      FROM vault.decrypted_secrets ds WHERE ds.name = 'supabase_url' LIMIT 1;
    SELECT ds.decrypted_secret INTO v_secret
      FROM vault.decrypted_secrets ds WHERE ds.name = 'cron_automations_key' LIMIT 1;
  END IF;
  IF COALESCE(v_url, '') <> '' AND COALESCE(v_secret, '') <> '' THEN
    -- Incident 09/11/2026 : séquence pg_net repartie de 1 après redémarrage.
    IF pg_catalog.to_regprocedure('private.fn_resynchroniser_sequence_pg_net()') IS NOT NULL THEN
      PERFORM private.fn_resynchroniser_sequence_pg_net();
    END IF;
    SELECT net.http_post(
      url := v_url || '/functions/v1/purge-stockage-rgpd',
      body := pg_catalog.jsonb_build_object('origine', 'CRON'),
      headers := pg_catalog.jsonb_build_object(
        'Content-Type', 'application/json',
        'x-jolene-cron-secret', v_secret,
        'x-jolene-cron-probe', 'execute'
      ),
      timeout_milliseconds := 55000
    ) INTO v_requete;
  END IF;
  IF v_requete IS NULL THEN
    PERFORM private.fn_rgpd_signaler_purge_stockage('RGPD_PURGE_STOCKAGE_CONFIGURATION',
      'Effacement RGPD de fichiers non déclenché : pg_net ou Vault (supabase_url, cron_automations_key) indisponible.',
      pg_catalog.jsonb_build_object('en_attente', v_attente));
  END IF;
  RETURN pg_catalog.jsonb_build_object('en_attente', v_attente, 'requete', v_requete);
END;
$fn_lancer_purge_stockage_rgpd$;

-- ── 6. RPC du rôle de service (edge purge-stockage-rgpd) ───────────────────
CREATE OR REPLACE FUNCTION public.fn_rgpd_purges_stockage_reserver(p_limite integer DEFAULT 100)
RETURNS TABLE(id uuid, bucket text, chemin text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn_rgpd_purges_stockage_reserver$
#variable_conflict use_column
BEGIN
  IF COALESCE(auth.role(), '') IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Rôle de service requis' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  WITH choisis AS (
    SELECT q.id
      FROM private.rgpd_purges_stockage q
     WHERE q.purge_le IS NULL
       AND (q.reserve_jusqua IS NULL OR q.reserve_jusqua < pg_catalog.now())
     ORDER BY q.demande_le, q.id
     LIMIT LEAST(GREATEST(COALESCE(p_limite, 100), 1), 500)
     FOR UPDATE SKIP LOCKED
  )
  UPDATE private.rgpd_purges_stockage q
     SET reserve_jusqua = pg_catalog.now() + interval '10 minutes',
         tentatives = q.tentatives + 1
    FROM choisis c
   WHERE q.id = c.id
  RETURNING q.id, q.bucket, q.chemin;
END;
$fn_rgpd_purges_stockage_reserver$;

CREATE OR REPLACE FUNCTION public.fn_rgpd_purges_stockage_confirmer(p_ids uuid[], p_erreur text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn_rgpd_purges_stockage_confirmer$
DECLARE
  v_effaces uuid[];
  v_echecs integer := 0;
BEGIN
  IF COALESCE(auth.role(), '') IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Rôle de service requis' USING ERRCODE = '42501';
  END IF;
  IF p_ids IS NULL OR pg_catalog.cardinality(p_ids) = 0 THEN
    RETURN pg_catalog.jsonb_build_object('confirmes', 0, 'en_echec', 0);
  END IF;
  -- Effacement constaté côté base : l'objet a disparu de storage.objects.
  -- La réponse de l'API Storage ne suffit jamais à elle seule.
  WITH confirmes AS (
    UPDATE private.rgpd_purges_stockage q
       SET purge_le = pg_catalog.now(),
           chemin = NULL,
           reserve_jusqua = NULL,
           derniere_erreur = NULL
     WHERE q.id = ANY (p_ids)
       AND q.purge_le IS NULL
       AND NOT EXISTS (SELECT 1 FROM storage.objects o WHERE o.bucket_id = q.bucket AND o.name = q.chemin)
    RETURNING q.soignant_id
  )
  SELECT pg_catalog.array_agg(c.soignant_id) INTO v_effaces FROM confirmes c;

  UPDATE private.rgpd_purges_stockage q
     SET reserve_jusqua = NULL,
         derniere_erreur = pg_catalog.left(COALESCE(NULLIF(pg_catalog.btrim(p_erreur), ''), 'OBJET_TOUJOURS_PRESENT'), 200)
   WHERE q.id = ANY (p_ids) AND q.purge_le IS NULL;
  GET DIAGNOSTICS v_echecs = ROW_COUNT;

  INSERT INTO public.journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  SELECT t.soignant_id, 'SYSTEME', 'RGPD_SUPPRESSION_DONNEES', 'soignant', t.soignant_id,
         pg_catalog.jsonb_build_object(
           'source', 'purge-stockage-rgpd',
           'stockage_objets_effaces', t.n,
           'stockage_objets_restants', (SELECT pg_catalog.count(*) FROM private.rgpd_purges_stockage r
                                         WHERE r.soignant_id = t.soignant_id AND r.purge_le IS NULL))
    FROM (SELECT e.soignant_id, pg_catalog.count(*) AS n
            FROM pg_catalog.unnest(COALESCE(v_effaces, '{}'::uuid[])) AS e(soignant_id)
           GROUP BY e.soignant_id) t;

  RETURN pg_catalog.jsonb_build_object(
    'confirmes', COALESCE(pg_catalog.cardinality(v_effaces), 0),
    'en_echec', v_echecs
  );
END;
$fn_rgpd_purges_stockage_confirmer$;

-- ── 7. Suppression du compte soignant (corps LIVE + trois ajouts) ──────────
CREATE OR REPLACE FUNCTION public.fn_supprimer_mon_compte()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn_supprimer_mon_compte$
DECLARE
    v_missions_futures INTEGER;
    v_hash TEXT;
    v_uid UUID := auth.uid();
    v_supprime_le timestamptz;
    v_system_update text := COALESCE(current_setting('jolene.system_update', true), '');
    v_bank_update text := COALESCE(current_setting('jolene.bank_server_update', true), '');
    v_liberal_transition text := COALESCE(current_setting('jolene.liberal_transition', true), '');
    v_siret_reset text := COALESCE(current_setting('jolene.siret_liberal_reset', true), '');
    v_effacement jsonb;
BEGIN
    IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
    SELECT supprime_le INTO v_supprime_le FROM public.soignants WHERE id = v_uid FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Aucun profil soignant lié à ce compte'); END IF;
    IF private.fn_anonymisation_compte_confirmee(v_uid,'SOIGNANT') THEN
      RETURN jsonb_build_object('success', true, 'deja_anonymise', true);
    END IF;
    SELECT COUNT(*) INTO v_missions_futures FROM missions
    WHERE soignant_assigne_id = v_uid AND statut IN ('ASSIGNEE','EN_COURS') AND fin_le > NOW();
    IF v_missions_futures > 0 THEN
        RETURN jsonb_build_object('error', 'Vous avez ' || v_missions_futures || ' mission(s) en cours.');
    END IF;
    v_hash := encode(digest(v_uid::TEXT || NOW()::TEXT, 'sha256'), 'hex');
    PERFORM set_config('jolene.system_update', 'true', true);
    PERFORM set_config('jolene.bank_server_update', 'true', true);
    PERFORM set_config('jolene.liberal_transition', 'true', true);
    PERFORM set_config('jolene.siret_liberal_reset', 'true', true);
    BEGIN
    UPDATE soignants SET
        prenom = 'Soignant', nom = 'Supprimé',
        email = v_hash || '@supprime.jolene.app',
        telephone = NULL, adresse_rue = NULL, adresse_ville = NULL,
        adresse_code_postal = NULL, numero_secu = NULL,
        numero_securite_sociale = NULL,
        lieu_naissance_commune = NULL, lieu_naissance_departement = NULL,
        pays_naissance = NULL, nationalite = NULL, sexe = NULL,
        date_naissance = NULL, siret_liberal = NULL,
        numero_tva = NULL, bio = NULL, specialites = NULL,
        avatar_url = NULL, adresse_lat = NULL, adresse_lng = NULL,
        numero_rpps = NULL, numero_adeli = NULL,
        iban_last4 = NULL, iban_virement = NULL, iban_titulaire = NULL,
        iban_source_document_id = NULL, iban_identite_document_id = NULL,
        iban_source_s3_cle = NULL, iban_empreinte_sha256 = NULL,
        iban_verifie_le = NULL, iban_titulaire_coherent = false,
        stripe_account_id = NULL,
        rpps_verifie = false, adeli_verifie = false,
        identite_verifiee = false, diplome_verifie = false, tous_documents_valides = false,
        siret_liberal_verifie = false, siret_liberal_verifie_le = NULL,
        siret_liberal_raison_sociale = NULL, siret_liberal_coherence_identite = NULL,
        psc_sub = NULL, psc_linked_le = NULL, psc_last_login = NULL,
        mandat_facturation_signe = FALSE, mandat_facturation_signe_le = NULL,
        sms_actif = FALSE, sms_consent_le = NULL,
        supprime_le = NOW()
    WHERE id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('jolene.system_update', v_system_update, true);
      PERFORM set_config('jolene.bank_server_update', v_bank_update, true);
      PERFORM set_config('jolene.liberal_transition', v_liberal_transition, true);
      PERFORM set_config('jolene.siret_liberal_reset', v_siret_reset, true);
      RAISE;
    END;
    PERFORM set_config('jolene.system_update', v_system_update, true);
    PERFORM set_config('jolene.bank_server_update', v_bank_update, true);
    PERFORM set_config('jolene.liberal_transition', v_liberal_transition, true);
    PERFORM set_config('jolene.siret_liberal_reset', v_siret_reset, true);
    -- Une suppression ne peut jamais annoncer un succès avec un profil encore actif.
    IF NOT EXISTS (SELECT 1 FROM public.soignants WHERE id=v_uid AND supprime_le IS NOT NULL) THEN
      RAISE EXCEPTION 'Anonymisation non confirmée';
    END IF;
    UPDATE evaluations SET commentaire = NULL WHERE evaluateur_id = v_uid OR evalue_id = v_uid;
    DELETE FROM tokens_push WHERE utilisateur_id = v_uid;
    DELETE FROM tokens_calendrier WHERE soignant_id = v_uid;
    UPDATE messages_mission SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;
    UPDATE messages_chat SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;
    DELETE FROM attestations_heures_externes WHERE soignant_id = v_uid;
    DELETE FROM favoris_soignant_etab WHERE soignant_id = v_uid;
    DELETE FROM reclamations_scoring WHERE soignant_id = v_uid;
    DELETE FROM notifications WHERE destinataire_id = v_uid;
    UPDATE parrainages SET parrain_id = NULL WHERE parrain_id = v_uid;
    UPDATE parrainages SET filleul_id = NULL WHERE filleul_id = v_uid;
    UPDATE presences SET
        arrivee_lat = NULL, arrivee_lng = NULL, depart_lat = NULL, depart_lng = NULL,
        arrivee_precision_gps_m = NULL, depart_precision_gps_m = NULL,
        arrivee_id_terminal = NULL, depart_id_terminal = NULL,
        arrivee_modele_terminal = NULL, depart_modele_terminal = NULL
    WHERE soignant_id = v_uid;
    DELETE FROM pings_gps_mission WHERE soignant_id = v_uid;
    DELETE FROM consentements_ping_gps WHERE soignant_id = v_uid;
    UPDATE scans_pointage SET
        latitude = NULL, longitude = NULL, precision_gps_m = NULL,
        id_terminal = NULL, ip_address = NULL, distance_etablissement_m = NULL
    WHERE soignant_id = v_uid;
    -- Pièces (migration 20261128140100) : fichiers mis en file d'effacement,
    -- contenu lu par l'IA et champs dérivés effacés, attestations d'heures
    -- externes supprimées, revues anonymisées. Lève si un résidu subsiste.
    v_effacement := private.fn_rgpd_effacer_pieces_soignant(v_uid, 'SUPPRESSION_COMPTE');
    UPDATE partages_rib SET actif = FALSE WHERE soignant_id = v_uid;
    UPDATE stripe_connect_onboarding SET
        stripe_account_id = 'SUPPRIME_' || LEFT(v_hash, 20), iban_last4 = NULL, erreur_onboarding = NULL
    WHERE soignant_id = v_uid;
    UPDATE candidatures SET message = NULL WHERE soignant_id = v_uid;
    UPDATE contrats_mission SET
        signature_ip_soignant = NULL, signature_navigateur_soignant = NULL, signature_image_soignant = NULL
    WHERE soignant_id = v_uid;
    DELETE FROM conversions_liberal WHERE soignant_id = v_uid;
    DELETE FROM heures_externes WHERE soignant_id = v_uid;
    DELETE FROM pauses_presence WHERE soignant_id = v_uid;
    DELETE FROM souscriptions_prevoyance WHERE soignant_id = v_uid;
    DELETE FROM suivi_conversion_3200h WHERE soignant_id = v_uid;
    DELETE FROM mandats_facturation_signatures WHERE soignant_id = v_uid;
    DELETE FROM cessions_creance WHERE soignant_id = v_uid;
    UPDATE factures_honoraires SET soignant_id = v_uid WHERE soignant_id = v_uid;
    DELETE FROM factor_advances WHERE soignant_id = v_uid;
    -- Une tentative PSC est anonyme jusqu'au callback et n'appartient pas
    -- à ce compte. Son expiration est traitée par le nettoyeur PSC dédié.
    -- La suppression d'un soignant ne doit interrompre aucune autre connexion.
    DELETE FROM email_queue WHERE destinataire_id = v_uid;
    UPDATE sms_envoyes SET telephone = 'SUPPRIME', destinataire_id = NULL WHERE destinataire_id = v_uid;
    DELETE FROM cotisations_sociales WHERE soignant_id = v_uid;
    DELETE FROM conformite_travail WHERE soignant_id = v_uid;
    UPDATE messages_litige SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;
    -- Le profil est anonymisé et conservé par son id. Les références des pièces
    -- et règlements restent inchangées : aucune réattribution de l’historique.
    -- Les deux colonnes soignant_id sont NOT NULL ; aucune écriture ici.
    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (v_uid, 'SOIGNANT', 'RGPD_SUPPRESSION_COMPTE', 'soignant', v_uid,
        jsonb_build_object('anonymise', true, 'tables_nettoyees', ARRAY[
            'soignants','evaluations','tokens_push','tokens_calendrier','messages_mission','messages_chat',
            'attestations_heures_externes','favoris','reclamations_scoring','parrainages','notifications',
            'presences','pings_gps_mission','consentements_ping_gps','scans_pointage',
            'documents_soignants','partages_rib','stripe_connect_onboarding','candidatures',
            'contrats_mission','conversions_liberal','heures_externes','pauses_presence',
            'souscriptions_prevoyance','suivi_conversion_3200h',
            'mandats_facturation_signatures','cessions_creance','factures_honoraires','factor_advances',
            'email_queue','sms_envoyes','cotisations_sociales','conformite_travail',
            'messages_litige','heures_externes_soignants','file_revue_manuelle'],
            'pieces', v_effacement,
            'tables_financieres_conservees', ARRAY['stripe_transfers','paiements_soignant']));
    INSERT INTO private.suppressions_compte_confirmees(utilisateur_id,type_profil,anonymise_le,email_anonymise)
    SELECT id,'SOIGNANT',supprime_le,email FROM public.soignants WHERE id=v_uid
    ON CONFLICT(utilisateur_id,type_profil) DO UPDATE SET anonymise_le=excluded.anonymise_le,email_anonymise=excluded.email_anonymise;
    IF NOT private.fn_anonymisation_compte_confirmee(v_uid,'SOIGNANT') THEN RAISE EXCEPTION 'Anonymisation soignant non confirmée'; END IF;
    RETURN jsonb_build_object('success', true, 'message', 'Votre compte a été supprimé et vos données anonymisées.');
END;
$fn_supprimer_mon_compte$;

-- ── 8. Purge des inactifs : verrou jusqu'au réalignement ───────────────────
CREATE OR REPLACE FUNCTION public.fn_rgpd_purge_automatique_inactifs()
RETURNS TABLE(soignant_purge_id uuid, derniere_activite timestamp with time zone, action_effectuee text)
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn_rgpd_purge_automatique_inactifs$
BEGIN
  -- Verrou (migration 20261128140100) : l'ancien corps n'effaçait ni le numéro
  -- de sécurité sociale, ni l'IBAN, ni l'adresse, ni les pièces, et écrasait le
  -- chemin des pièces (s3_cle = 'PURGE'), rendant leurs fichiers introuvables.
  -- Fonction non planifiée au 28/11/2026 : erreur nette plutôt qu'une purge
  -- partielle silencieuse.
  RAISE EXCEPTION 'RGPD_PURGE_INACTIFS_VERROUILLEE : purge des soignants inactifs à réaligner sur la suppression de compte (fn_supprimer_mon_compte) avant toute planification ; docs/CONFORMITE.md §6.5.'
    USING ERRCODE = '0A000';
END;
$fn_rgpd_purge_automatique_inactifs$;

-- ── 9. Droits ──────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION private.fn_rgpd_decision_objet_soignant(text, text, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.fn_rgpd_signaler_purge_stockage(text, text, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.fn_rgpd_effacer_pieces_soignant(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.fn_lancer_purge_stockage_rgpd() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_rgpd_purges_stockage_reserver(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_rgpd_purges_stockage_confirmer(uuid[], text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_rgpd_purges_stockage_reserver(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_rgpd_purges_stockage_confirmer(uuid[], text) TO service_role;

-- ── 10. Inventaire SECURITY DEFINER ────────────────────────────────────────
UPDATE private.security_definer_inventory i
   SET definition_md5 = pg_catalog.md5(p.prosrc),
       recense_le = pg_catalog.now()
  FROM pg_catalog.pg_proc p
 WHERE i.signature = 'fn_supprimer_mon_compte()'
   AND p.oid = 'public.fn_supprimer_mon_compte()'::pg_catalog.regprocedure;

INSERT INTO private.security_definer_inventory (signature, categorie, definition_md5, justification, recense_le)
SELECT v.signature, 'SERVICE_ONLY_REVOQUE', pg_catalog.md5(p.prosrc), v.justification, pg_catalog.now()
  FROM (VALUES
    ('private.fn_rgpd_effacer_pieces_soignant(uuid,text)',
     'Appelée par fn_supprimer_mon_compte (et le rattrapage) après anonymisation du profil : fichiers en file, contenu des pièces effacé, heures externes supprimées, revues anonymisées ; refuse un profil actif. EXECUTE retiré à PUBLIC, anon, authenticated, service_role. Source : 20261128140100_suppression_compte_soignant_effacement_pieces.sql'),
    ('private.fn_lancer_purge_stockage_rgpd()',
     'Cron horaire : appel pg_net de l''edge purge-stockage-rgpd (URL et secret lus dans Vault) si la file n''est pas vide, alertes à 24 h et si l''appel est impossible. EXECUTE retiré à PUBLIC, anon, authenticated, service_role. Source : 20261128140100_suppression_compte_soignant_effacement_pieces.sql'),
    ('fn_rgpd_purges_stockage_reserver(integer)',
     'Rôle de service exigé (auth.role) : réservation d''un lot de la file d''effacement, SKIP LOCKED. EXECUTE au seul service_role. Source : 20261128140100_suppression_compte_soignant_effacement_pieces.sql'),
    ('fn_rgpd_purges_stockage_confirmer(uuid[],text)',
     'Rôle de service exigé (auth.role) : confirmation seulement si l''objet a disparu de storage.objects, audit RGPD_SUPPRESSION_DONNEES. EXECUTE au seul service_role. Source : 20261128140100_suppression_compte_soignant_effacement_pieces.sql')
  ) AS v(signature, justification)
  JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(
    CASE WHEN v.signature LIKE 'private.%' THEN v.signature ELSE 'public.' || v.signature END)
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;

-- ── 11. Rattrapage des comptes déjà supprimés (aucun en production) ────────
DO $effacement_pieces_rattrapage$
DECLARE
  v_compte record;
BEGIN
  FOR v_compte IN
    SELECT c.utilisateur_id
      FROM private.suppressions_compte_confirmees c
      JOIN public.soignants s ON s.id = c.utilisateur_id
     WHERE c.type_profil = 'SOIGNANT' AND s.supprime_le IS NOT NULL
     ORDER BY c.utilisateur_id
  LOOP
    PERFORM private.fn_rgpd_effacer_pieces_soignant(v_compte.utilisateur_id, 'RATTRAPAGE_SUPPRESSION_COMPTE');
  END LOOP;
END
$effacement_pieces_rattrapage$;

-- ── 12. Cron horaire (garde pg_cron pour les branches) ─────────────────────
DO $effacement_pieces_cron$
DECLARE
  v_job record;
  v_jobid bigint;
  v_actif boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_cron') THEN
    RETURN;
  END IF;
  -- Actif seulement si d'autres crons le sont (production) ; inactif sur le
  -- staging fermé et les branches, dont les suites refusent tout cron actif.
  v_actif := EXISTS (SELECT 1 FROM cron.job j WHERE j.active AND j.jobname <> 'jolene_rgpd_purge_stockage');
  FOR v_job IN SELECT j.jobid FROM cron.job j WHERE j.jobname = 'jolene_rgpd_purge_stockage' LOOP
    PERFORM cron.unschedule(v_job.jobid);
  END LOOP;
  v_jobid := cron.schedule('jolene_rgpd_purge_stockage', '41 * * * *',
    $job$SELECT private.fn_lancer_purge_stockage_rgpd()$job$);
  PERFORM cron.alter_job(job_id := v_jobid, active := v_actif);
END
$effacement_pieces_cron$;

-- ── 13. Post-condition ─────────────────────────────────────────────────────
DO $effacement_pieces_apres$
DECLARE
  v_attendu record;
BEGIN
  FOR v_attendu IN
    SELECT * FROM (VALUES
      ('public.fn_supprimer_mon_compte()', 'bd8df04463ed3b683de237d78b6ecea3', true),
      ('public.fn_rgpd_purge_automatique_inactifs()', 'f843b17f0b27a40a632bd0afe458ed4a', false),
      ('private.fn_rgpd_decision_objet_soignant(text,text,uuid)', 'abd7447ec585b6124ff994666041575e', false),
      ('private.fn_rgpd_signaler_purge_stockage(text,text,jsonb)', '36de9ed067b8c6bea3b73ae74127bee5', false),
      ('private.fn_rgpd_effacer_pieces_soignant(uuid,text)', 'bcc0304b6b669591774299f97b8e790a', true),
      ('private.fn_lancer_purge_stockage_rgpd()', '3b73447190e48ad1c885b024873991bf', true),
      ('public.fn_rgpd_purges_stockage_reserver(integer)', 'bc4e7456f0d65e860c6cba82cb166378', true),
      ('public.fn_rgpd_purges_stockage_confirmer(uuid[],text)', '824984aea961efe24d74e1eada7a9475', true)
    ) AS t(signature, empreinte, definer)
  LOOP
    IF (SELECT pg_catalog.md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure(v_attendu.signature))
         IS DISTINCT FROM v_attendu.empreinte
       OR (SELECT p.prosecdef FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure(v_attendu.signature))
         IS DISTINCT FROM v_attendu.definer
       OR (SELECT pg_catalog.pg_get_userbyid(p.proowner) FROM pg_catalog.pg_proc p
            WHERE p.oid = pg_catalog.to_regprocedure(v_attendu.signature)) IS DISTINCT FROM 'postgres'
    THEN
      RAISE EXCEPTION 'EFFACEMENT_PIECES_POSTCONDITION : corps installé inattendu pour %.', v_attendu.signature;
    END IF;
  END LOOP;
  IF NOT pg_catalog.has_function_privilege('authenticated', 'public.fn_supprimer_mon_compte()', 'EXECUTE')
     OR pg_catalog.has_function_privilege('anon', 'public.fn_supprimer_mon_compte()', 'EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated', 'public.fn_rgpd_purge_automatique_inactifs()', 'EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated', 'private.fn_rgpd_effacer_pieces_soignant(uuid,text)', 'EXECUTE')
     OR pg_catalog.has_function_privilege('service_role', 'private.fn_rgpd_effacer_pieces_soignant(uuid,text)', 'EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated', 'private.fn_lancer_purge_stockage_rgpd()', 'EXECUTE')
     OR pg_catalog.has_function_privilege('service_role', 'private.fn_lancer_purge_stockage_rgpd()', 'EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated', 'private.fn_rgpd_signaler_purge_stockage(text,text,jsonb)', 'EXECUTE')
     OR pg_catalog.has_function_privilege('anon', 'public.fn_rgpd_purges_stockage_reserver(integer)', 'EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated', 'public.fn_rgpd_purges_stockage_reserver(integer)', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('service_role', 'public.fn_rgpd_purges_stockage_reserver(integer)', 'EXECUTE')
     OR pg_catalog.has_function_privilege('anon', 'public.fn_rgpd_purges_stockage_confirmer(uuid[],text)', 'EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated', 'public.fn_rgpd_purges_stockage_confirmer(uuid[],text)', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('service_role', 'public.fn_rgpd_purges_stockage_confirmer(uuid[],text)', 'EXECUTE')
     OR pg_catalog.has_table_privilege('authenticated', 'private.rgpd_purges_stockage', 'SELECT')
     OR pg_catalog.has_table_privilege('service_role', 'private.rgpd_purges_stockage', 'SELECT')
     OR NOT (SELECT c.relrowsecurity AND c.relforcerowsecurity FROM pg_catalog.pg_class c
              WHERE c.oid = 'private.rgpd_purges_stockage'::pg_catalog.regclass)
  THEN
    RAISE EXCEPTION 'EFFACEMENT_PIECES_POSTCONDITION : droits ou protections inattendus.';
  END IF;
  IF EXISTS (SELECT 1 FROM private.security_definer_inventory i
              JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(
                CASE WHEN i.signature LIKE 'private.%' THEN i.signature ELSE 'public.' || i.signature END)
             WHERE i.signature IN ('fn_supprimer_mon_compte()', 'private.fn_rgpd_effacer_pieces_soignant(uuid,text)',
                                   'private.fn_lancer_purge_stockage_rgpd()',
                                   'fn_rgpd_purges_stockage_reserver(integer)', 'fn_rgpd_purges_stockage_confirmer(uuid[],text)')
               AND i.definition_md5 IS DISTINCT FROM pg_catalog.md5(p.prosrc))
  THEN
    RAISE EXCEPTION 'EFFACEMENT_PIECES_POSTCONDITION : inventaire SECURITY DEFINER désaligné.';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_cron')
     AND (SELECT pg_catalog.count(*) FROM cron.job j
           WHERE j.jobname = 'jolene_rgpd_purge_stockage'
             AND j.command = 'SELECT private.fn_lancer_purge_stockage_rgpd()') <> 1
  THEN
    RAISE EXCEPTION 'EFFACEMENT_PIECES_POSTCONDITION : cron jolene_rgpd_purge_stockage absent ou dupliqué.';
  END IF;
END
$effacement_pieces_apres$;
