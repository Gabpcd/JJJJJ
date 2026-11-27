-- ═══════════════════════════════════════════════════════════════════════════
-- Suppression du compte soignant avec pièces vérifiées (migration 20261127100000).
--
-- ⚠️  JAMAIS EN PROD. Staging CI : job « sql-transaction » de validate-pr.yml,
--     après les migrations candidates, sous SAVEPOINT puis ROLLBACK global ;
--     PostgreSQL 17 éphémère et PGlite : tests/postgres/suppression-compte-soignant-preuves.pg17.mjs.
--     Vraies routines et vrais déclencheurs ; profils fictifs ; zéro persistance.
--
-- Ce qu'il prouve :
--   A. un soignant qui a des pièces VERIFIE supprime son compte par le chemin
--      réel (fn_supprimer_compte_rate_limited, en session utilisateur) : succès,
--      profil anonymisé, pièces marquées supprimées, reçu privé, aucune demande
--      de re-vérification ; une seconde demande est reconnue comme déjà faite ;
--   B. un changement d'identité hors suppression invalide toujours les pièces
--      (EN_ATTENTE, drapeaux remis à faux, audit) ;
--   C. un profil déjà marqué supprimé (suspension) qui change d'identité voit
--      toujours ses pièces invalidées ;
--   D. un utilisateur ne peut pas forger la transition de suppression (supprime_le
--      rétabli) et la protection des preuves refuse toujours, en session
--      utilisateur, l'invalidation comme l'écriture directe d'une pièce (42501).
-- ═══════════════════════════════════════════════════════════════════════════
BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claim.role', '', true);
SELECT set_config('request.jwt.claims', '', true);

DO $suppression_preuves_suite$
DECLARE
  v_s1 constant uuid := 'a5f1d001-0000-4000-8000-000000000001';  -- supprime son compte
  v_s2 constant uuid := 'a5f1d001-0000-4000-8000-000000000002';  -- change d'identité hors suppression
  v_s3 constant uuid := 'a5f1d001-0000-4000-8000-000000000003';  -- déjà marqué supprimé, change d'identité
  v_s4 constant uuid := 'a5f1d001-0000-4000-8000-000000000004';  -- tente de forger la suppression
  v_res jsonb;
  v_msg text;
  v_etat text;
BEGIN
  -- ── 1. Contexte isolé ──────────────────────────────────────────────────────
  IF session_user NOT IN ('postgres', 'supabase_admin') OR auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'SUPPRESSION_PREUVES : maintenance isolée requise (postgres, sans identité)';
  END IF;
  IF EXISTS (SELECT 1 FROM auth.users WHERE id::text LIKE 'a5f1d001%')
     OR EXISTS (SELECT 1 FROM public.soignants WHERE id::text LIKE 'a5f1d001%')
  THEN RAISE EXCEPTION 'SUPPRESSION_PREUVES : identifiants de fixture déjà présents'; END IF;

  -- ── 2. Catalogue candidat ──────────────────────────────────────────────────
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.fn_invalider_preuves_identite_sur_changement()'::regprocedure)
       IS DISTINCT FROM '377be655911e3223b2a22cfdf3956991'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.fn_proteger_ecriture_document_soignant()'::regprocedure)
       IS DISTINCT FROM 'c490ce823768b0a23cd264ab17601155'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.fn_protect_soignant_verification()'::regprocedure)
       IS DISTINCT FROM 'ff5e753f785f2c7ca08ae22771812e95'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.fn_supprimer_mon_compte()'::regprocedure)
       IS DISTINCT FROM 'f3af23aeeb4e30aba07e422c0e819aeb'
  THEN RAISE EXCEPTION 'SUPPRESSION_PREUVES : corps candidat ou protection inattendus'; END IF;
  IF (SELECT count(*) FROM pg_trigger t WHERE t.tgenabled = 'O' AND NOT t.tgisinternal AND (
        (t.tgname = 'trg_invalider_preuves_identite_sur_changement'
         AND t.tgfoid = 'public.fn_invalider_preuves_identite_sur_changement()'::regprocedure)
        OR (t.tgname = 'trg_protect_soignant_verification' AND t.tgfoid = 'public.fn_protect_soignant_verification()'::regprocedure)
        OR (t.tgname = 'trg_proteger_ecriture_document_soignant'
            AND t.tgfoid = 'public.fn_proteger_ecriture_document_soignant()'::regprocedure))) <> 3
     OR has_function_privilege('authenticated', 'public.fn_invalider_preuves_identite_sur_changement()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.fn_invalider_preuves_identite_sur_changement()', 'EXECUTE')
  THEN RAISE EXCEPTION 'SUPPRESSION_PREUVES : déclencheurs ou droits inattendus'; END IF;

  -- ── 3. Fixtures (SQL Auth direct, contexte système) ────────────────────────
  INSERT INTO auth.users (id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at)
  SELECT s, '00000000-0000-0000-0000-000000000000', 'suppression-preuves-' || right(s::text, 1) || '@example.invalid',
         'authenticated', 'authenticated', '{"role":"SOIGNANT"}'::jsonb, now()
    FROM unnest(ARRAY[v_s1, v_s2, v_s3, v_s4]) s;
  INSERT INTO public.soignants (id, prenom, nom, email, profession, date_naissance)
  SELECT s, 'Fixture', 'Preuves ' || right(s::text, 1), 'suppression-preuves-' || right(s::text, 1) || '@example.invalid',
         'IDE', date '1990-01-15'
    FROM unnest(ARRAY[v_s1, v_s2, v_s3, v_s4]) s;
  INSERT INTO public.documents_soignants (soignant_id, type_document, s3_cle, nom_fichier, statut_verification,
    est_critique, valide_jusqua, resultat_ia)
  SELECT s, d.type_document::public.type_document, 'tests/suppression-preuves/' || s || '/' || lower(d.type_document),
         lower(d.type_document) || '.pdf', 'VERIFIE', true, d.valide_jusqua, d.resultat_ia::jsonb
    FROM unnest(ARRAY[v_s1, v_s2, v_s3, v_s4]) s,
         (VALUES ('CARTE_IDENTITE', current_date + 365, '{}'), ('DIPLOME', NULL::date, '{"profession_certifiee":"IDE"}'))
           AS d(type_document, valide_jusqua, resultat_ia);
  UPDATE public.soignants SET identite_verifiee = true, diplome_verifie = true WHERE id IN (v_s1, v_s2, v_s3, v_s4);
  UPDATE public.soignants SET supprime_le = now() - interval '1 day' WHERE id = v_s3;
  IF (SELECT count(*) FROM public.documents_soignants
       WHERE soignant_id IN (v_s1, v_s2, v_s3, v_s4) AND statut_verification = 'VERIFIE' AND supprime_le IS NULL) <> 8
     OR (SELECT count(*) FROM public.soignants WHERE id IN (v_s1, v_s2, v_s4) AND supprime_le IS NULL AND identite_verifiee) <> 3
  THEN RAISE EXCEPTION 'SUPPRESSION_PREUVES : fixtures inattendues'; END IF;

  -- ── A. Suppression du compte par le soignant, pièces vérifiées ─────────────
  PERFORM set_config('request.jwt.claim.sub', v_s1::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_s1, 'role', 'authenticated')::text, true);
  BEGIN
    v_res := public.fn_supprimer_compte_rate_limited();
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT, v_etat = RETURNED_SQLSTATE;
    RAISE EXCEPTION 'SUPPRESSION_PREUVES A1 : la suppression du compte d''un soignant aux pièces vérifiées échoue (% : %)', v_etat, v_msg;
  END;
  IF (v_res->>'success')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'SUPPRESSION_PREUVES A1 : suppression refusée (%)', v_res;
  END IF;
  -- Seconde demande (reprise de l'edge) : reconnue, sans nouveau traitement.
  v_res := public.fn_supprimer_compte_rate_limited();
  IF (v_res->>'deja_anonymise')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'SUPPRESSION_PREUVES A2 : reprise non reconnue (%)', v_res;
  END IF;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  IF (SELECT supprime_le FROM public.soignants WHERE id = v_s1) IS NULL
     OR (SELECT prenom || ' ' || nom FROM public.soignants WHERE id = v_s1) IS DISTINCT FROM 'Soignant Supprimé'
     OR (SELECT date_naissance FROM public.soignants WHERE id = v_s1) IS NOT NULL
     OR (SELECT identite_verifiee OR diplome_verifie OR tous_documents_valides FROM public.soignants WHERE id = v_s1)
     OR EXISTS (SELECT 1 FROM public.documents_soignants WHERE soignant_id = v_s1 AND supprime_le IS NULL)
     OR private.fn_anonymisation_compte_confirmee(v_s1, 'SOIGNANT') IS NOT TRUE
  THEN RAISE EXCEPTION 'SUPPRESSION_PREUVES A3 : anonymisation incomplète'; END IF;
  IF EXISTS (SELECT 1 FROM public.journaux_audit WHERE id_ressource = v_s1 AND action = 'IDENTITE_PROFIL_MODIFIEE')
     OR EXISTS (SELECT 1 FROM public.documents_soignants WHERE soignant_id = v_s1 AND statut_verification = 'EN_ATTENTE')
  THEN RAISE EXCEPTION 'SUPPRESSION_PREUVES A4 : la suppression a demandé une re-vérification des preuves'; END IF;

  -- ── B. Changement d'identité hors suppression : pièces invalidées ──────────
  UPDATE public.soignants SET nom = 'Preuves corrigé' WHERE id = v_s2;
  IF (SELECT count(*) FROM public.documents_soignants WHERE soignant_id = v_s2 AND statut_verification = 'EN_ATTENTE'
        AND verifie_le IS NULL AND supprime_le IS NULL) <> 2
     OR EXISTS (SELECT 1 FROM public.documents_soignants WHERE soignant_id = v_s2 AND statut_verification = 'VERIFIE')
     OR (SELECT identite_verifiee OR diplome_verifie FROM public.soignants WHERE id = v_s2)
     OR (SELECT coherence_identite::text FROM public.soignants WHERE id = v_s2) IS DISTINCT FROM 'EN_ATTENTE_REVUE'
  THEN RAISE EXCEPTION 'SUPPRESSION_PREUVES B1 : un changement d''identité hors suppression n''invalide plus les pièces'; END IF;

  -- ── C. Profil déjà marqué supprimé (suspension) : pièces invalidées ────────
  UPDATE public.soignants SET date_naissance = date '1991-02-16' WHERE id = v_s3;
  IF EXISTS (SELECT 1 FROM public.documents_soignants WHERE soignant_id = v_s3 AND statut_verification = 'VERIFIE')
  THEN RAISE EXCEPTION 'SUPPRESSION_PREUVES C1 : un profil déjà supprimé change d''identité sans invalider ses pièces'; END IF;

  -- ── D. Session utilisateur : transition non forgeable, protection intacte ──
  PERFORM set_config('request.jwt.claim.sub', v_s4::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_s4, 'role', 'authenticated')::text, true);
  BEGIN
    UPDATE public.soignants SET nom = 'Preuves contournement', supprime_le = now() WHERE id = v_s4;
    RAISE EXCEPTION 'SUPPRESSION_PREUVES D1 : changement d''identité accepté en session utilisateur, pièces vérifiées conservées (supprime_le %)',
      (SELECT supprime_le FROM public.soignants WHERE id = v_s4);
  EXCEPTION WHEN SQLSTATE '42501' THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg IS DISTINCT FROM 'Modification de preuve ou de validation interdite' THEN RAISE; END IF;
  END;
  BEGIN
    -- Champ gardé par fn_proteger_ecriture_document_soignant seule (le statut l'est
    -- aussi par dec_proteger_validation_documents, qui passe avant).
    UPDATE public.documents_soignants SET nom_fichier = 'remplacee.pdf' WHERE soignant_id = v_s4;
    RAISE EXCEPTION 'SUPPRESSION_PREUVES D2 : la protection des preuves accepte une écriture utilisateur';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg IS DISTINCT FROM 'Modification de preuve ou de validation interdite' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  IF (SELECT supprime_le FROM public.soignants WHERE id = v_s4) IS NOT NULL
     OR (SELECT count(*) FROM public.documents_soignants WHERE soignant_id = v_s4 AND statut_verification = 'VERIFIE') <> 2
  THEN RAISE EXCEPTION 'SUPPRESSION_PREUVES D3 : état du profil modifié par une écriture refusée'; END IF;

  RAISE NOTICE 'SUPPRESSION_PREUVES : suppression avec pièces vérifiées, invalidation hors suppression, profil suspendu, protections vérifiées.';
END
$suppression_preuves_suite$;
ROLLBACK;
