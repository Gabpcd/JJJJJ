-- ═══════════════════════════════════════════════════════════════════════════
-- Suppression du compte soignant : fichiers et noms lus par l'IA effacés
-- (migrations 20261128140000 et 20261128140100).
--
-- ⚠️  JAMAIS EN PROD. Staging CI : job « sql-transaction » de validate-pr.yml,
--     après les migrations candidates, sous SAVEPOINT puis ROLLBACK global ;
--     PostgreSQL 17 éphémère et PGlite : tests/postgres/suppression-compte-soignant-effacement.pg17.mjs.
--     Vraies routines et vrais déclencheurs ; profils et fichiers fictifs
--     (lignes storage.objects créées puis retirées dans la transaction, comme
--     l'API Storage le ferait) ; zéro persistance.
--
-- Marqueurs : NOMIAMARQUEUR / PRENOMIAMARQUEUR figurent dans les noms lus par
-- l'IA, le texte de rejet, le nom de fichier d'origine, les chemins, la revue
-- manuelle et sa décision du soignant supprimé ; TEMOINMARQUEUR dans ceux d'un
-- soignant témoin qui ne supprime rien.
--
-- Ce qu'il prouve :
--   A. la suppression du compte par le chemin réel (fn_supprimer_compte_rate_limited,
--      session utilisateur) efface le contenu lu des pièces, les noms de
--      fichier, les attestations d'heures externes, la revue et sa décision ;
--      met en file exactement les fichiers à effacer (pièces, version
--      orpheline, heures externes, réclamation) et pas ceux à conserver
--      (relevé de rétrocession) ni les inconnus (alerte sans nom de fichier) ;
--      l'audit IDENTITE_PROFIL_MODIFIEE est désormais écrit ; le témoin est
--      intact ;
--   B. la purge par le rôle de service ne confirme qu'un fichier disparu de
--      storage.objects, puis efface le chemin de la file et écrit l'audit ;
--      aucun marqueur ne subsiste nulle part ; RPC refusées à un utilisateur ;
--   C. un changement d'identité hors suppression écrit l'audit IDENTITE_PROFIL_MODIFIEE ;
--   D. l'effacement refuse un profil actif ; la purge des inactifs est verrouillée ;
--   E. le cron relance la file en attente et alerte au-delà de 24 h.
-- ═══════════════════════════════════════════════════════════════════════════
BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claim.role', '', true);
SELECT set_config('request.jwt.claims', '', true);

DO $effacement_suite$
DECLARE
  v_s1 constant uuid := 'a5f1d002-0000-4000-8000-000000000001';  -- supprime son compte
  v_s2 constant uuid := 'a5f1d002-0000-4000-8000-000000000002';  -- témoin, ne supprime rien
  v_s3 constant uuid := 'a5f1d002-0000-4000-8000-000000000003';  -- change d'identité hors suppression
  v_d1 constant uuid := 'a5f1d002-0000-4000-8000-0000000000d1';  -- pièce d'identité vérifiée de s1
  v_d2 constant uuid := 'a5f1d002-0000-4000-8000-0000000000d2';  -- diplôme rejeté de s1
  v_d3 constant uuid := 'a5f1d002-0000-4000-8000-0000000000d3';  -- ancienne version déjà supprimée de s1
  v_d4 constant uuid := 'a5f1d002-0000-4000-8000-0000000000d4';  -- pièce du témoin
  v_r1 constant uuid := 'a5f1d002-0000-4000-8000-0000000000e1';  -- revue de la pièce d1
  v_res jsonb;
  v_msg text;
  v_etat text;
  v_ids uuid[];
  v_attendus text[];
  v_trouves text[];
  v_purge jsonb;
  v_net bigint;
  v_net_apres bigint;
  v_requete record;
BEGIN
  -- ── 1. Contexte isolé ──────────────────────────────────────────────────────
  IF session_user NOT IN ('postgres', 'supabase_admin') OR auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'EFFACEMENT_PIECES : maintenance isolée requise (postgres, sans identité)';
  END IF;
  IF EXISTS (SELECT 1 FROM auth.users WHERE id::text LIKE 'a5f1d002%')
     OR EXISTS (SELECT 1 FROM public.soignants WHERE id::text LIKE 'a5f1d002%')
     OR EXISTS (SELECT 1 FROM storage.objects WHERE name LIKE 'a5f1d002%')
  THEN RAISE EXCEPTION 'EFFACEMENT_PIECES : identifiants de fixture déjà présents'; END IF;

  -- ── 2. Catalogue candidat ──────────────────────────────────────────────────
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.fn_supprimer_mon_compte()'::regprocedure)
       IS DISTINCT FROM 'bd8df04463ed3b683de237d78b6ecea3'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'private.fn_rgpd_effacer_pieces_soignant(uuid,text)'::regprocedure)
       IS DISTINCT FROM 'bcc0304b6b669591774299f97b8e790a'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.fn_rgpd_purges_stockage_confirmer(uuid[],text)'::regprocedure)
       IS DISTINCT FROM '824984aea961efe24d74e1eada7a9475'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.fn_rgpd_purges_stockage_reserver(integer)'::regprocedure)
       IS DISTINCT FROM 'bc4e7456f0d65e860c6cba82cb166378'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.fn_invalider_preuves_identite_sur_changement()'::regprocedure)
       IS DISTINCT FROM 'bb93c49d6187ee007b964acab6bf0809'
     OR (SELECT md5(pg_get_constraintdef(oid)) FROM pg_constraint WHERE conname = 'journaux_audit_action_check'
          AND conrelid = 'public.journaux_audit'::regclass) IS DISTINCT FROM 'd34d197dbf9da68e8ba340e0824ce765'
  THEN RAISE EXCEPTION 'EFFACEMENT_PIECES : corps ou contrainte candidats inattendus'; END IF;
  IF has_function_privilege('authenticated', 'public.fn_rgpd_purges_stockage_reserver(integer)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.fn_rgpd_purges_stockage_confirmer(uuid[],text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.fn_rgpd_effacer_pieces_soignant(uuid,text)', 'EXECUTE')
     OR has_table_privilege('authenticated', 'private.rgpd_purges_stockage', 'SELECT')
     OR NOT has_function_privilege('service_role', 'public.fn_rgpd_purges_stockage_confirmer(uuid[],text)', 'EXECUTE')
  THEN RAISE EXCEPTION 'EFFACEMENT_PIECES : droits inattendus'; END IF;
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
     AND NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'jolene_rgpd_purge_stockage'
                      AND command = 'SELECT private.fn_lancer_purge_stockage_rgpd()')
  THEN RAISE EXCEPTION 'EFFACEMENT_PIECES : cron jolene_rgpd_purge_stockage absent'; END IF;

  -- ── 3. Fixtures (SQL Auth direct, contexte système) ────────────────────────
  INSERT INTO storage.buckets (id, name)
  SELECT b, b FROM unnest(ARRAY['jolene-documents', 'attestations-heures-externes', 'justificatifs']) b
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO auth.users (id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at)
  SELECT s, '00000000-0000-0000-0000-000000000000', 'effacement-pieces-' || right(s::text, 1) || '@example.invalid',
         'authenticated', 'authenticated', '{"role":"SOIGNANT"}'::jsonb, now()
    FROM unnest(ARRAY[v_s1, v_s2, v_s3]) s;
  INSERT INTO public.soignants (id, prenom, nom, email, profession, date_naissance)
  SELECT s, 'Fixture', 'Effacement ' || right(s::text, 1), 'effacement-pieces-' || right(s::text, 1) || '@example.invalid',
         'IDE', date '1990-01-15'
    FROM unnest(ARRAY[v_s1, v_s2, v_s3]) s;
  INSERT INTO public.documents_soignants (id, soignant_id, type_document, s3_cle, nom_fichier, libelle, statut_verification,
    est_critique, motif_rejet, resultat_ia, nom_extrait_ia, prenom_extrait_ia, coherence_nom, score_confiance_ia, supprime_le)
  VALUES
    (v_d1, v_s1, 'CARTE_IDENTITE', v_s1 || '/documents/CARTE_IDENTITE/1700000000000-NOMIAMARQUEUR.pdf', 'NOMIAMARQUEUR.pdf',
     'CNI NOMIAMARQUEUR', 'VERIFIE', true, NULL,
     '{"nom_extrait":"NOMIAMARQUEUR","prenom_extrait":"PRENOMIAMARQUEUR","date_naissance_extraite":"1990-01-15"}',
     'NOMIAMARQUEUR', 'PRENOMIAMARQUEUR', true, 0.97, NULL),
    (v_d2, v_s1, 'DIPLOME', v_s1 || '/documents/DIPLOME/1700000000001-diplome-NOMIAMARQUEUR.pdf', 'diplome-NOMIAMARQUEUR.pdf',
     NULL, 'REJETE', true, 'Le nom lu (NOMIAMARQUEUR PRENOMIAMARQUEUR) ne correspond pas au profil.',
     '{"nom_extrait":"NOMIAMARQUEUR","verdict":"REJETE"}', 'NOMIAMARQUEUR', 'PRENOMIAMARQUEUR', false, 0.4, NULL),
    (v_d3, v_s1, 'RIB', v_s1 || '/documents/RIB/1690000000000-rib-NOMIAMARQUEUR.pdf', 'rib-NOMIAMARQUEUR.pdf',
     NULL, 'REJETE', false, NULL, '{"nom_extrait":"NOMIAMARQUEUR"}', 'NOMIAMARQUEUR', NULL, false, 0.5, now() - interval '30 days'),
    (v_d4, v_s2, 'CARTE_IDENTITE', v_s2 || '/documents/CARTE_IDENTITE/1700000000002-TEMOINMARQUEUR.pdf', 'TEMOINMARQUEUR.pdf',
     NULL, 'VERIFIE', true, NULL, '{"nom_extrait":"TEMOINMARQUEUR"}', 'TEMOINMARQUEUR', 'TEMOINMARQUEUR', true, 0.95, NULL);
  UPDATE public.soignants SET identite_verifiee = true WHERE id IN (v_s1, v_s2);
  PERFORM set_config('jolene.heures_externes_server_update', 'true', true);
  INSERT INTO public.heures_externes_soignants (soignant_id, etablissement_nom, date_debut, date_fin, heures_declarees,
    attestation_url, attestation_nom_fichier, resultat_ia, heures_extraites_ia)
  VALUES (v_s1, 'Clinique NOMIAMARQUEUR', date '2026-01-01', date '2026-03-31', 120,
          v_s1 || '/heures-externes/1700000000003-attestation-NOMIAMARQUEUR.pdf', 'attestation-NOMIAMARQUEUR.pdf',
          '{"nom_extrait":"NOMIAMARQUEUR","employeur":"Clinique NOMIAMARQUEUR"}', 120);
  PERFORM set_config('jolene.heures_externes_server_update', '', true);
  INSERT INTO public.file_revue_manuelle (id, type_entite, id_entite, service_en_echec, motif_echec, donnees_originales, statut, priorite)
  VALUES (v_r1, 'TELEVERSEMENT_DOCUMENT', v_d1, 'VERIFY_DOCUMENT', 'Nom lu NOMIAMARQUEUR à confirmer.',
          jsonb_build_object('document_id', v_d1, 'soignant_id', v_s1,
            'source_s3_key', v_s1 || '/documents/CARTE_IDENTITE/1700000000000-NOMIAMARQUEUR.pdf'), 'EN_ATTENTE', 3);
  INSERT INTO private.revue_manuelle_decisions (revue_id, decision, motif, acteur_id, service, type_entite, id_entite,
    jeton_cas, source_snapshot)
  VALUES (v_r1, 'APPROUVER', 'Identité NOMIAMARQUEUR confirmée par l''équipe.', v_s2, 'VERIFY_DOCUMENT',
          'TELEVERSEMENT_DOCUMENT', v_d1, repeat('a', 64), jsonb_build_object('nom_extrait_ia', 'NOMIAMARQUEUR'));
  INSERT INTO storage.objects (bucket_id, name) VALUES
    ('jolene-documents', v_s1 || '/documents/CARTE_IDENTITE/1700000000000-NOMIAMARQUEUR.pdf'),
    ('jolene-documents', v_s1 || '/documents/DIPLOME/1700000000001-diplome-NOMIAMARQUEUR.pdf'),
    ('jolene-documents', v_s1 || '/documents/RIB/1690000000000-rib-NOMIAMARQUEUR.pdf'),
    ('jolene-documents', v_s1 || '/documents/RIB/1680000000000-orpheline-NOMIAMARQUEUR.pdf'),
    ('jolene-documents', v_s1 || '/heures-externes/1700000000003-attestation-NOMIAMARQUEUR.pdf'),
    ('attestations-heures-externes', v_s1 || '/ancienne-NOMIAMARQUEUR.pdf'),
    ('justificatifs', v_s1 || '/reclamations/' || v_d2 || '/1700000000004_NOMIAMARQUEUR.pdf'),
    ('justificatifs', v_s1 || '/retrocession/' || v_d2 || '/1700000000005-releve.pdf'),
    ('jolene-documents', v_s1 || '/dossier-inconnu/piece.pdf'),
    ('jolene-documents', v_s1 || '/fichier-a-la-racine.pdf'),
    ('jolene-documents', v_s2 || '/documents/CARTE_IDENTITE/1700000000002-TEMOINMARQUEUR.pdf');
  v_attendus := ARRAY[
    'attestations-heures-externes/' || v_s1 || '/ancienne-NOMIAMARQUEUR.pdf',
    'jolene-documents/' || v_s1 || '/documents/CARTE_IDENTITE/1700000000000-NOMIAMARQUEUR.pdf',
    'jolene-documents/' || v_s1 || '/documents/DIPLOME/1700000000001-diplome-NOMIAMARQUEUR.pdf',
    'jolene-documents/' || v_s1 || '/documents/RIB/1680000000000-orpheline-NOMIAMARQUEUR.pdf',
    'jolene-documents/' || v_s1 || '/documents/RIB/1690000000000-rib-NOMIAMARQUEUR.pdf',
    'jolene-documents/' || v_s1 || '/heures-externes/1700000000003-attestation-NOMIAMARQUEUR.pdf',
    'justificatifs/' || v_s1 || '/reclamations/' || v_d2 || '/1700000000004_NOMIAMARQUEUR.pdf'];
  SELECT array_agg(a ORDER BY a COLLATE "C") INTO v_attendus FROM unnest(v_attendus) a;

  -- Constat de l'audit d'identité : sans la migration 20261128140000, cette
  -- ligne est refusée par le CHECK et l'erreur avalée (aucune ligne écrite).
  IF EXISTS (SELECT 1 FROM public.journaux_audit WHERE id_ressource IN (v_s1, v_s3) AND action = 'IDENTITE_PROFIL_MODIFIEE')
  THEN RAISE EXCEPTION 'EFFACEMENT_PIECES : audit d''identité de fixture déjà présent'; END IF;

  -- ── A. Suppression du compte par le soignant ───────────────────────────────
  -- Aucun appel réseau dans la transaction de suppression (file pg_net relue si présente).
  IF to_regclass('net.http_request_queue') IS NOT NULL THEN
    EXECUTE 'SELECT count(*) FROM net.http_request_queue' INTO v_net;
  END IF;
  PERFORM set_config('request.jwt.claim.sub', v_s1::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_s1, 'role', 'authenticated')::text, true);
  BEGIN
    v_res := public.fn_supprimer_compte_rate_limited();
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT, v_etat = RETURNED_SQLSTATE;
    RAISE EXCEPTION 'EFFACEMENT_PIECES A1 : la suppression du compte échoue (% : %)', v_etat, v_msg;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  IF (v_res->>'success')::boolean IS NOT TRUE OR private.fn_anonymisation_compte_confirmee(v_s1, 'SOIGNANT') IS NOT TRUE
  THEN RAISE EXCEPTION 'EFFACEMENT_PIECES A1 : suppression refusée ou anonymisation non confirmée (%)', v_res; END IF;
  IF to_regclass('net.http_request_queue') IS NOT NULL THEN
    EXECUTE 'SELECT count(*) FROM net.http_request_queue' INTO v_net_apres;
    IF v_net_apres IS DISTINCT FROM v_net THEN
      RAISE EXCEPTION 'EFFACEMENT_PIECES A9 : tentative réseau dans la transaction de suppression';
    END IF;
  END IF;

  -- Pièces : trace de vérification conservée, contenu et noms effacés.
  IF (SELECT count(*) FROM public.documents_soignants WHERE soignant_id = v_s1) <> 3
     OR EXISTS (SELECT 1 FROM public.documents_soignants d WHERE d.soignant_id = v_s1 AND (
          d.supprime_le IS NULL OR d.nom_fichier IS DISTINCT FROM 'fichier-efface'
          OR d.s3_cle IS DISTINCT FROM v_s1 || '/documents/efface/' || d.id
          OR num_nonnulls(d.resultat_ia, d.nom_extrait_ia, d.prenom_extrait_ia, d.coherence_nom, d.score_confiance_ia,
                          d.motif_rejet, d.libelle, d.revoque_raison) > 0))
     OR (SELECT statut_verification::text || '/' || type_document::text FROM public.documents_soignants WHERE id = v_d1)
          IS DISTINCT FROM 'VERIFIE/CARTE_IDENTITE'
     OR (SELECT supprime_le FROM public.documents_soignants WHERE id = v_d3) > now() - interval '29 days'
  THEN RAISE EXCEPTION 'EFFACEMENT_PIECES A2 : contenu de pièce conservé ou trace de vérification perdue'; END IF;
  IF EXISTS (SELECT 1 FROM public.heures_externes_soignants WHERE soignant_id = v_s1)
  THEN RAISE EXCEPTION 'EFFACEMENT_PIECES A3 : attestation d''heures externes conservée'; END IF;
  IF (SELECT statut || '|' || motif_echec || '|' || donnees_originales::text FROM public.file_revue_manuelle WHERE id = v_r1)
       NOT LIKE 'EXPIRE|Compte supprimé : contenu effacé (RGPD art. 17).|{"rgpd_efface_le":%'
     OR (SELECT motif || source_snapshot::text FROM private.revue_manuelle_decisions WHERE revue_id = v_r1)
       IS DISTINCT FROM 'Compte supprimé : motif effacé (RGPD art. 17).{}'
  THEN RAISE EXCEPTION 'EFFACEMENT_PIECES A4 : revue manuelle ou décision non anonymisée'; END IF;

  -- File : exactement les fichiers à effacer de s1.
  SELECT array_agg(bucket || '/' || chemin ORDER BY bucket || '/' || chemin COLLATE "C") INTO v_trouves
    FROM private.rgpd_purges_stockage WHERE soignant_id = v_s1 AND purge_le IS NULL;
  IF v_trouves IS DISTINCT FROM v_attendus
     OR EXISTS (SELECT 1 FROM private.rgpd_purges_stockage WHERE soignant_id IN (v_s2, v_s3))
     OR EXISTS (SELECT 1 FROM private.rgpd_purges_stockage q WHERE q.soignant_id = v_s1
                 AND q.empreinte IS DISTINCT FROM encode(sha256(convert_to(q.bucket || '/' || q.chemin, 'UTF8')), 'hex'))
  THEN RAISE EXCEPTION 'EFFACEMENT_PIECES A5 : file d''effacement inattendue (%)', v_trouves; END IF;
  IF (SELECT (details->>'objets')::int FROM public.alertes_systeme
       WHERE source = 'rgpd-purge-stockage' AND type_alerte = 'RGPD_PURGE_STOCKAGE_DOSSIER_INCONNU'
         AND resolu_le IS NULL AND details->>'soignant_id' = v_s1::text) IS DISTINCT FROM 2
     OR EXISTS (SELECT 1 FROM public.alertes_systeme WHERE source = 'rgpd-purge-stockage'
                 AND (details::text LIKE '%MARQUEUR%' OR details::text LIKE '%inconnu%' OR details::text LIKE '%racine%'))
  THEN RAISE EXCEPTION 'EFFACEMENT_PIECES A6 : alerte des fichiers hors périmètre absente ou nominative'; END IF;

  -- Audits : identité désormais journalisée, détail de l'effacement dans la suppression.
  IF NOT EXISTS (SELECT 1 FROM public.journaux_audit WHERE id_ressource = v_s1 AND action = 'IDENTITE_PROFIL_MODIFIEE'
                  AND type_acteur = 'SOIGNANT')
     OR (SELECT (details->'pieces'->>'fichiers_en_file')::int FROM public.journaux_audit
          WHERE id_ressource = v_s1 AND action = 'RGPD_SUPPRESSION_COMPTE') IS DISTINCT FROM 7
  THEN RAISE EXCEPTION 'EFFACEMENT_PIECES A7 : audit d''identité ou de suppression absent'; END IF;

  -- Témoin intact.
  IF (SELECT nom_extrait_ia || nom_fichier || s3_cle FROM public.documents_soignants WHERE id = v_d4)
       IS DISTINCT FROM 'TEMOINMARQUEUR' || 'TEMOINMARQUEUR.pdf' || v_s2 || '/documents/CARTE_IDENTITE/1700000000002-TEMOINMARQUEUR.pdf'
     OR (SELECT supprime_le FROM public.documents_soignants WHERE id = v_d4) IS NOT NULL
     OR NOT EXISTS (SELECT 1 FROM storage.objects WHERE name = v_s2 || '/documents/CARTE_IDENTITE/1700000000002-TEMOINMARQUEUR.pdf')
  THEN RAISE EXCEPTION 'EFFACEMENT_PIECES A8 : soignant témoin modifié'; END IF;

  -- ── B. Purge par le rôle de service ────────────────────────────────────────
  -- Un utilisateur ne peut ni réserver ni confirmer.
  PERFORM set_config('request.jwt.claim.sub', v_s2::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_s2, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.fn_rgpd_purges_stockage_reserver(10);
    RAISE EXCEPTION 'EFFACEMENT_PIECES B1 : réservation acceptée pour un utilisateur';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  BEGIN
    PERFORM public.fn_rgpd_purges_stockage_confirmer(ARRAY[gen_random_uuid()], NULL);
    RAISE EXCEPTION 'EFFACEMENT_PIECES B1 : confirmation acceptée pour un utilisateur';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);

  -- Réponse de l'API seule insuffisante : tant que l'objet existe, échec consigné.
  SELECT array_agg(r.id) INTO v_ids FROM public.fn_rgpd_purges_stockage_reserver(500) r
    JOIN private.rgpd_purges_stockage q ON q.id = r.id WHERE q.soignant_id = v_s1;
  IF cardinality(v_ids) IS DISTINCT FROM 7 THEN RAISE EXCEPTION 'EFFACEMENT_PIECES B2 : réservation incomplète (%)', cardinality(v_ids); END IF;
  IF EXISTS (SELECT 1 FROM public.fn_rgpd_purges_stockage_reserver(500) r WHERE r.id = ANY (v_ids))
  THEN RAISE EXCEPTION 'EFFACEMENT_PIECES B2 : fichier réservé deux fois'; END IF;
  v_purge := public.fn_rgpd_purges_stockage_confirmer(v_ids, NULL);
  IF v_purge IS DISTINCT FROM '{"confirmes": 0, "en_echec": 7}'::jsonb
     OR EXISTS (SELECT 1 FROM private.rgpd_purges_stockage WHERE id = ANY (v_ids)
                 AND (purge_le IS NOT NULL OR chemin IS NULL OR derniere_erreur IS DISTINCT FROM 'OBJET_TOUJOURS_PRESENT'
                      OR reserve_jusqua IS NOT NULL OR tentatives <> 1))
  THEN RAISE EXCEPTION 'EFFACEMENT_PIECES B3 : fichier encore présent tenu pour effacé (%)', v_purge; END IF;

  -- L'API Storage retire les objets (simulée ici), puis la confirmation aboutit.
  SELECT array_agg(r.id) INTO v_ids FROM public.fn_rgpd_purges_stockage_reserver(500) r
    JOIN private.rgpd_purges_stockage q ON q.id = r.id WHERE q.soignant_id = v_s1;
  PERFORM set_config('storage.allow_delete_query', 'true', true);
  DELETE FROM storage.objects o USING private.rgpd_purges_stockage q
   WHERE q.id = ANY (v_ids) AND o.bucket_id = q.bucket AND o.name = q.chemin;
  PERFORM set_config('storage.allow_delete_query', 'false', true);
  v_purge := public.fn_rgpd_purges_stockage_confirmer(v_ids, NULL);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  IF v_purge IS DISTINCT FROM '{"confirmes": 7, "en_echec": 0}'::jsonb
     OR EXISTS (SELECT 1 FROM private.rgpd_purges_stockage WHERE soignant_id = v_s1
                 AND (purge_le IS NULL OR chemin IS NOT NULL OR derniere_erreur IS NOT NULL))
     OR (SELECT (details->>'stockage_objets_effaces')::int || '/' || (details->>'stockage_objets_restants')
           FROM public.journaux_audit WHERE id_ressource = v_s1 AND action = 'RGPD_SUPPRESSION_DONNEES'
            AND details->>'source' = 'purge-stockage-rgpd') IS DISTINCT FROM '7/0'
  THEN RAISE EXCEPTION 'EFFACEMENT_PIECES B4 : purge non confirmée ou audit absent (%)', v_purge; END IF;
  -- Ne restent sous le préfixe que le relevé conservé et les fichiers inconnus.
  SELECT array_agg(bucket_id || '/' || name ORDER BY bucket_id || '/' || name COLLATE "C") INTO v_trouves
    FROM storage.objects WHERE name LIKE v_s1 || '/%';
  IF v_trouves IS DISTINCT FROM ARRAY[
       'jolene-documents/' || v_s1 || '/dossier-inconnu/piece.pdf',
       'jolene-documents/' || v_s1 || '/fichier-a-la-racine.pdf',
       'justificatifs/' || v_s1 || '/retrocession/' || v_d2 || '/1700000000005-releve.pdf']
  THEN RAISE EXCEPTION 'EFFACEMENT_PIECES B5 : objets restants inattendus (%)', v_trouves; END IF;

  -- Aucun marqueur du soignant supprimé ne subsiste en base.
  IF EXISTS (SELECT 1 FROM public.documents_soignants d WHERE d.soignant_id = v_s1 AND to_jsonb(d)::text LIKE '%IAMARQUEUR%')
     OR EXISTS (SELECT 1 FROM public.soignants s WHERE s.id = v_s1 AND to_jsonb(s)::text LIKE '%IAMARQUEUR%')
     OR EXISTS (SELECT 1 FROM public.heures_externes_soignants h WHERE to_jsonb(h)::text LIKE '%IAMARQUEUR%')
     OR EXISTS (SELECT 1 FROM public.file_revue_manuelle f WHERE to_jsonb(f)::text LIKE '%IAMARQUEUR%')
     OR EXISTS (SELECT 1 FROM private.revue_manuelle_decisions r WHERE to_jsonb(r)::text LIKE '%IAMARQUEUR%')
     OR EXISTS (SELECT 1 FROM private.rgpd_purges_stockage q WHERE to_jsonb(q)::text LIKE '%IAMARQUEUR%')
     OR EXISTS (SELECT 1 FROM public.journaux_audit j WHERE j.id_ressource = v_s1 AND to_jsonb(j)::text LIKE '%IAMARQUEUR%')
     OR EXISTS (SELECT 1 FROM public.alertes_systeme a WHERE to_jsonb(a)::text LIKE '%IAMARQUEUR%')
  THEN RAISE EXCEPTION 'EFFACEMENT_PIECES B6 : nom lu par l''IA ou nom de fichier conservé'; END IF;

  -- ── C. Changement d'identité hors suppression (le soignant corrige son nom) ─
  -- fn_ecrire_audit_safe refuse un appelant sans identité ni rôle de service :
  -- le cas réel est la session du soignant (ou un admin, ou le rôle de service).
  PERFORM set_config('request.jwt.claim.sub', v_s3::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_s3, 'role', 'authenticated')::text, true);
  UPDATE public.soignants SET nom = 'Effacement corrigé' WHERE id = v_s3;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  IF NOT EXISTS (SELECT 1 FROM public.journaux_audit WHERE id_ressource = v_s3 AND action = 'IDENTITE_PROFIL_MODIFIEE'
                  AND type_acteur = 'SOIGNANT' AND acteur_id = v_s3 AND details->'champs_modifies' = '["nom"]'::jsonb)
     OR (SELECT nom FROM public.soignants WHERE id = v_s3) IS DISTINCT FROM 'Effacement corrigé'
  THEN RAISE EXCEPTION 'EFFACEMENT_PIECES C1 : changement d''identité non journalisé'; END IF;

  -- ── D. Verrous ─────────────────────────────────────────────────────────────
  BEGIN
    PERFORM private.fn_rgpd_effacer_pieces_soignant(v_s2, 'SUPPRESSION_COMPTE');
    RAISE EXCEPTION 'EFFACEMENT_PIECES D1 : pièces d''un profil actif effacées';
  EXCEPTION WHEN SQLSTATE '55000' THEN NULL;
  END;
  BEGIN
    PERFORM * FROM public.fn_rgpd_purge_automatique_inactifs();
    RAISE EXCEPTION 'EFFACEMENT_PIECES D2 : purge des inactifs exécutée';
  EXCEPTION WHEN SQLSTATE '0A000' THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'RGPD_PURGE_INACTIFS_VERROUILLEE : %docs/CONFORMITE.md §6.5.' THEN RAISE; END IF;
  END;

  -- ── E. Cron : relance de la file, alerte au-delà de 24 h ───────────────────
  INSERT INTO private.rgpd_purges_stockage (soignant_id, bucket, chemin, empreinte, origine, motif, demande_le)
  VALUES (v_s1, 'jolene-documents', v_s1 || '/documents/RIB/en-retard.pdf',
          encode(sha256(convert_to('jolene-documents/' || v_s1 || '/documents/RIB/en-retard.pdf', 'UTF8')), 'hex'),
          'PREFIXE', 'SUPPRESSION_COMPTE', now() - interval '25 hours');
  v_res := private.fn_lancer_purge_stockage_rgpd();
  IF (v_res->>'en_attente')::int < 1
     OR NOT EXISTS (SELECT 1 FROM public.alertes_systeme WHERE source = 'rgpd-purge-stockage'
                     AND type_alerte = 'RGPD_PURGE_STOCKAGE_EN_RETARD' AND resolu_le IS NULL)
     OR (v_res->>'requete' IS NULL AND NOT EXISTS (SELECT 1 FROM public.alertes_systeme WHERE source = 'rgpd-purge-stockage'
                     AND type_alerte = 'RGPD_PURGE_STOCKAGE_CONFIGURATION' AND resolu_le IS NULL))
  THEN RAISE EXCEPTION 'EFFACEMENT_PIECES E1 : cron sans alerte (%)', v_res; END IF;
  -- Appel observé (file pg_net) : la bonne edge, le secret d'automatisation, aucune donnée de soignant.
  IF v_res->>'requete' IS NOT NULL AND to_regclass('net.http_request_queue') IS NOT NULL THEN
    EXECUTE 'SELECT url, headers, convert_from(body, ''UTF8'') AS corps FROM net.http_request_queue WHERE id = $1'
      INTO v_requete USING (v_res->>'requete')::bigint;
    IF v_requete.url NOT LIKE '%/functions/v1/purge-stockage-rgpd'
       OR NOT (v_requete.headers ? 'x-jolene-cron-secret')
       OR v_requete.corps::jsonb IS DISTINCT FROM '{"origine": "CRON"}'::jsonb
    THEN RAISE EXCEPTION 'EFFACEMENT_PIECES E2 : appel de purge inattendu'; END IF;
  END IF;

  RAISE NOTICE 'EFFACEMENT_PIECES : suppression sans résidu (pièces, noms lus, fichiers, heures externes, revues), purge confirmée par la base, audit d''identité écrit, verrous et alertes vérifiés.';
END
$effacement_suite$;
ROLLBACK;
