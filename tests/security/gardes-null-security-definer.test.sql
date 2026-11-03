-- B9 gardes NULL des SECURITY DEFINER (migration 20261103013434).
-- Vraies fixtures, vrais helpers d'identité (mon_etablissement_id, est_admin,
-- est_admin_etablissement) et vraies RPC, appelées sous le JWT de chaque rôle.
-- Aucun trigger désactivé, aucune fonction remplacée ; tout est annulé.
--
-- Matrice : soignant assigné (S), soignant tiers (T), membre révoqué de
-- l'établissement A (R) — tous trois sans établissement actif, donc
-- mon_etablissement_id() NULL — RH d'un autre établissement (B), propriétaire
-- de A (A) et administrateur plateforme (ADM).
--   * refus : réponse de refus exacte, puis aucun effet (missions, présence,
--     contrat, événement de score, codes, QR, file escrow, factures,
--     réclamations, notifications identiques à l'instantané) ;
--   * appelant légitime : la garde laisse passer. Chaque cas est annulé par
--     une sentinelle. Toutes ces gardes refusent par RETURN et seules des
--     lectures de fixtures les précèdent : une exception levée après coup
--     (contrôle métier, conformité) prouve donc aussi le passage de la garde.
-- fn_soignants_urgence et fn_diffuser_pool_urgence : un refus (0 ligne, 0)
-- ne se distingue pas d'un pool vide ; seule l'absence d'effet est vérifiée,
-- la garde elle-même l'est par tests/node/gardes-null-security-definer.node.mjs.
-- fn_deposer_chorus : pas de fixture facture ici (même garde statique).
\set ON_ERROR_STOP on
BEGIN;

DO $gardes_null$
DECLARE
  e_a uuid := 'a7a10000-0000-4000-8000-000000000001';
  e_b uuid := 'a7a10000-0000-4000-8000-000000000002';
  u_s uuid := 'a7a10000-0000-4000-8000-000000000011';
  u_t uuid := 'a7a10000-0000-4000-8000-000000000012';
  u_r uuid := 'a7a10000-0000-4000-8000-000000000013';
  u_b uuid := 'a7a10000-0000-4000-8000-000000000014';
  u_a uuid := 'a7a10000-0000-4000-8000-000000000015';
  u_adm uuid := 'a7a10000-0000-4000-8000-000000000016';
  m_term uuid := 'a7a10000-0000-4000-8000-000000000021';
  m_ouv uuid := 'a7a10000-0000-4000-8000-000000000022';
  p_pres uuid := 'a7a10000-0000-4000-8000-000000000031';
  c_contrat uuid := 'a7a10000-0000-4000-8000-000000000041';
  evt uuid := 'a7a10000-0000-4000-8000-000000000051';
  serie uuid := 'a7a10000-0000-4000-8000-000000000061';
  c record;
  v_acteur text;
  v_uid uuid;
  v_avant jsonb;
  v_apres jsonb;
  v_etat text;
  v_msg text;
  r jsonb;
  n_refus integer := 0;
  n_passe integer := 0;
BEGIN
  -- Les 21 corps corrigés sont en place, l'inventaire suit, ACL inchangées.
  IF (SELECT count(*)
      FROM (VALUES
        ('fn_valider_alerte_presence(uuid)', '1ff0c4c48ccd906f161e1a9174034505'),
        ('fn_codes_pointage_mission(uuid)', '478bc3d59e15a1a1c844443863a86d49'),
        ('fn_generer_code_secours_mission(uuid,text)', '76c8e19c6f16a642b968d91a7850752b'),
        ('fn_generer_qr_mission(uuid,text)', '75869cf50e34d68dd982a6714c010c0b'),
        ('fn_soignants_urgence(uuid)', '9b8f736b8f7fd19729e26cc56f28d2c4'),
        ('fn_generer_donnees_dpae(uuid)', '1070a34cb7025565225d732ed7ac3906'),
        ('fn_enregistrer_numero_dpae(uuid,text)', '0d6fb5c6692759e3972746d8dbc196f9'),
        ('fn_rebooker_soignant(uuid,uuid,timestamp with time zone,timestamp with time zone)', '53a208f0c1ee8c78a6faab262f47eaa4'),
        ('fn_booster_mission(uuid)', 'e57ceb0273b02fab0215e2d33e251200'),
        ('fn_presences_detail_mission(uuid)', '1f653d7d432a87a356f3f62910a7ee38'),
        ('fn_activer_garantie_mission(uuid,boolean)', '00b0feecc9dfc4893a04bc94b584a013'),
        ('fn_deposer_chorus(uuid,text)', '8b310b8e4c6bbabd58b039a9e915c675'),
        ('fn_generer_facture(uuid)', '078777ead10a6a4d500694551299622b'),
        ('fn_diffuser_pool_urgence(uuid)', '07cd19c650da67e2b8128d32d0ffbfe6'),
        ('fn_etat_pointage_mission(uuid)', 'db898659563ee11cf461469f82d1fac7'),
        ('fn_etablissement_pour_mission(uuid)', '55493a7014ae20761ebf86fdab938f1c'),
        ('fn_annuler_serie(uuid)', '06255e7b0d58441d46ac69798276dfae'),
        ('fn_assigner_mission_admin(uuid,uuid,text)', '3a3523b9ac79ebd8e34a5ef58e749de3'),
        ('fn_creer_reclamation_score(uuid,text,text,text,text)', '18be67db062364dadbd298fb90884947'),
        ('fn_declarer_honoraires_retrocession(uuid,numeric,text)', '4223483a5500b8d865c4f529af6f1a99'),
        ('fn_definir_retrocession_mission(uuid,numeric)', '52393260c791cbb5093278f303a93ebd')
      ) AS v(signature, md5_apres)
      JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure('public.' || v.signature)
      JOIN private.security_definer_inventory i ON i.signature = v.signature
      WHERE p.prosecdef
        AND pg_catalog.md5(p.prosrc) = v.md5_apres
        AND i.definition_md5 = v.md5_apres
        AND NOT pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
        AND pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
        AND pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE')) <> 21 THEN
    RAISE EXCEPTION 'GARDES_NULL : corps, inventaire ou ACL non conformes à la migration';
  END IF;

  -- Sous-transaction sentinelle : fixtures, audits immuables et effets de bord
  -- sont annulés avant la suite suivante ; seul JGN01 est absorbé.
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', 'service_role', true);
    PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
    PERFORM set_config('jolene.admin_seed_override_reason', '', true);

    INSERT INTO public.etablissements (
      id, nom, siret, type, adresse_rue, adresse_ville,
      adresse_code_postal, email_contact, est_compte_test
    ) VALUES
      (e_a, 'Fixture gardes NULL A', '99177000000101', 'CLINIQUE_PRIVEE',
       '1 rue du Test', 'Paris', '75001', 'gardes-null-etab-a@example.invalid', true),
      (e_b, 'Fixture gardes NULL B', '99177000000102', 'CLINIQUE_PRIVEE',
       '2 rue du Test', 'Lyon', '69001', 'gardes-null-etab-b@example.invalid', true);

    INSERT INTO auth.users (
      id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
    ) VALUES
      (u_s, '00000000-0000-0000-0000-000000000000', 'gardes-null-s@example.invalid',
       'authenticated', 'authenticated', '{"role":"SOIGNANT"}', now()),
      (u_t, '00000000-0000-0000-0000-000000000000', 'gardes-null-t@example.invalid',
       'authenticated', 'authenticated', '{"role":"SOIGNANT"}', now()),
      (u_r, '00000000-0000-0000-0000-000000000000', 'gardes-null-r@example.invalid',
       'authenticated', 'authenticated', '{"role":"ETABLISSEMENT"}', now()),
      (u_b, '00000000-0000-0000-0000-000000000000', 'gardes-null-b@example.invalid',
       'authenticated', 'authenticated', '{"role":"ETABLISSEMENT"}', now()),
      (u_a, '00000000-0000-0000-0000-000000000000', 'gardes-null-a@example.invalid',
       'authenticated', 'authenticated', '{"role":"ETABLISSEMENT"}', now()),
      (u_adm, '00000000-0000-0000-0000-000000000000', 'gardes-null-adm@example.invalid',
       'authenticated', 'authenticated', '{"role":"ADMIN_PLATEFORME"}', now());

    INSERT INTO public.soignants (
      id, prenom, nom, email, profession, est_compte_test,
      rpps_verifie, disponible_urgence, tous_documents_valides
    ) VALUES
      (u_s, 'Fixture', 'Assigné', 'gardes-null-s@example.invalid', 'IDE', true, true, false, true),
      (u_t, 'Fixture', 'Tiers', 'gardes-null-t@example.invalid', 'IDE', true, true, false, true);

    INSERT INTO public.membres_etablissement (etablissement_id, user_id, role, actif) VALUES
      (e_a, u_a, 'PROPRIETAIRE', true),
      (e_a, u_r, 'RH', false),
      (e_b, u_b, 'RH', true);

    INSERT INTO public.equipe_admin (user_id, nom, prenom, email, actif, acces_groupes) VALUES
      (u_adm, 'Gardes NULL', 'Admin', 'gardes-null-adm@example.invalid', true,
       ARRAY['Dashboard', 'Utilisateurs', 'Missions', 'Litiges & contrats', 'Finances',
             'Messagerie', 'Conformité & Technique', 'Fondateur']::text[]);

    PERFORM set_config('jolene.admin_seed_override_reason',
      'Test transactionnel des gardes NULL SECURITY DEFINER', true);
    INSERT INTO public.missions (
      id, etablissement_id, intitule, profession_requise,
      debut_le, fin_le, duree_heures, taux_horaire_base, statut,
      type_contrat_recherche, mode_attribution, soignant_assigne_id,
      type_contrat_applique
    ) VALUES
      (m_term, e_a, 'Fixture gardes NULL terminée', 'IDE',
       now() + interval '1 day', now() + interval '2 days', 24, 20, 'TERMINEE',
       'SALARIE', 'CANDIDATURE', u_s, 'SALARIE'),
      (m_ouv, e_a, 'Fixture gardes NULL ouverte', 'IDE',
       now() + interval '3 days', now() + interval '4 days', 24, 20, 'OUVERTE',
       'SALARIE', 'CANDIDATURE', NULL, NULL);
    INSERT INTO public.contrats_mission (
      id, mission_id, etablissement_id, soignant_id, type_contrat, numero_contrat, statut
    ) VALUES (c_contrat, m_ouv, e_a, u_s, 'CDD', 'GARDES-NULL-FIXTURE-0001', 'BROUILLON');
    PERFORM set_config('jolene.admin_seed_override_reason', '', true);
    INSERT INTO public.presences (
      id, mission_id, soignant_id, perimetre_gps_valide,
      alerte_teleportation, valide_par_etablissement
    ) VALUES (p_pres, m_term, u_s, true, false, false);
    INSERT INTO public.evenements_score_etab (id, etablissement_id, type_evenement, points, motif)
    VALUES (evt, e_a, 'AUTRE', -1, 'Fixture gardes NULL');
    PERFORM set_config('request.jwt.claim.role', '', true);
    PERFORM set_config('request.jwt.claims', '{}', true);

    CREATE TEMP TABLE gardes_null_cas (
      ordre integer PRIMARY KEY,
      appel text NOT NULL,
      refus jsonb NOT NULL,
      refuses text[] NOT NULL,
      passants text[] NOT NULL,
      attendu jsonb
    ) ON COMMIT DROP;
    INSERT INTO gardes_null_cas VALUES
      (1, format('SELECT to_jsonb(public.fn_valider_alerte_presence(%L::uuid))', p_pres),
       jsonb_build_object('error', 'Accès refusé'), ARRAY['S','T','R','B'], ARRAY['A','ADM'], NULL),
      (2, format('SELECT to_jsonb(public.fn_codes_pointage_mission(%L::uuid))', m_ouv),
       jsonb_build_object('error', 'Accès interdit'), ARRAY['S','T','R','B'], ARRAY['A','ADM'], NULL),
      (3, format('SELECT to_jsonb(public.fn_generer_code_secours_mission(%L::uuid, %L))', m_ouv, 'UNIVERSEL'),
       jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE'), ARRAY['S','T','R','B'], ARRAY['A','ADM'], NULL),
      (4, format('SELECT to_jsonb(public.fn_generer_qr_mission(%L::uuid, %L))', m_term, 'UNIVERSEL'),
       jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE'), ARRAY['S','T','R','B'], ARRAY['A','ADM'],
       jsonb_build_object('success', false, 'error_code', 'MISSION_INACTIVE')),
      (5, format('SELECT to_jsonb(public.fn_regenerer_qr_mission(%L::uuid, %L))', m_term, 'UNIVERSEL'),
       jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE'), ARRAY['S','T','R','B'], ARRAY['A','ADM'],
       jsonb_build_object('success', false, 'error_code', 'MISSION_INACTIVE')),
      (6, format('SELECT to_jsonb(count(*)) FROM public.fn_soignants_urgence(%L::uuid)', m_ouv),
       to_jsonb(0), ARRAY['S','T','R','B'], ARRAY[]::text[], NULL),
      (7, format('SELECT to_jsonb(public.fn_generer_donnees_dpae(%L::uuid))', c_contrat),
       jsonb_build_object('success', false, 'error', 'Non autorisé'), ARRAY['S','T','R','B'], ARRAY['A','ADM'], NULL),
      (8, format('SELECT to_jsonb(public.fn_enregistrer_numero_dpae(%L::uuid, %L))', c_contrat, 'GNULL2026A1'),
       jsonb_build_object('success', false, 'error', 'Non autorisé'), ARRAY['S','T','R','B'], ARRAY['A','ADM'], NULL),
      (9, format('SELECT to_jsonb(public.fn_rebooker_soignant(%L::uuid, %L::uuid, now() - interval ''1 day'', now()))', u_s, m_ouv),
       jsonb_build_object('error', 'Non autorisé'), ARRAY['S','T','R','B'], ARRAY['A','ADM'],
       jsonb_build_object('error', 'Dates invalides (le début doit être dans le futur).')),
      (10, format('SELECT to_jsonb(public.fn_booster_mission(%L::uuid))', m_term),
       jsonb_build_object('error', 'Non autorisé'), ARRAY['S','T','R','B'], ARRAY['A','ADM'],
       jsonb_build_object('error', 'Seule une mission ouverte peut être boostée.')),
      (11, format('SELECT to_jsonb(public.fn_presences_detail_mission(%L::uuid))', m_term),
       jsonb_build_object('error', 'Accès refusé'), ARRAY['T','R','B'], ARRAY['S','A','ADM'], NULL),
      (12, format('SELECT to_jsonb(public.fn_activer_garantie_mission(%L::uuid, true))', m_term),
       jsonb_build_object('error', 'Non autorisé'), ARRAY['S','T','R','B'], ARRAY['A','ADM'],
       jsonb_build_object('error', 'La garantie ne peut être modifiée que sur une mission ouverte ou assignée.')),
      (13, format('SELECT to_jsonb(public.fn_generer_facture(%L::uuid))', m_ouv),
       '{"error":"Accès refusé"}'::jsonb, ARRAY['S','T','R','B'], ARRAY['A','ADM'],
       '{"error":"La mission doit être TERMINEE"}'::jsonb),
      (14, format('SELECT to_jsonb(public.fn_diffuser_pool_urgence(%L::uuid))', m_ouv),
       to_jsonb(0), ARRAY['S','T','R','B'], ARRAY[]::text[], NULL),
      (15, format('SELECT to_jsonb(public.fn_etat_pointage_mission(%L::uuid))', m_ouv),
       jsonb_build_object('error', 'Accès interdit'), ARRAY['S','T','R','B'], ARRAY['A','ADM'], NULL),
      (16, format('SELECT to_jsonb(public.fn_etat_pointage_mission(%L::uuid))', m_term),
       jsonb_build_object('error', 'Accès interdit'), ARRAY['T','R','B'], ARRAY['S','A','ADM'], NULL),
      (17, format('SELECT to_jsonb(public.fn_etablissement_pour_mission(%L::uuid))', e_b),
       jsonb_build_object('error', 'Accès refusé'), ARRAY['S','T','R','A'], ARRAY['B','ADM'], NULL),
      -- Une mission OUVERTE rend la fiche de A visible à tout compte : inchangé.
      (18, format('SELECT to_jsonb(public.fn_etablissement_pour_mission(%L::uuid))', e_a),
       jsonb_build_object('error', 'Accès refusé'), ARRAY[]::text[], ARRAY['S','T','R','B','A','ADM'], NULL),
      (19, format('SELECT to_jsonb(public.fn_annuler_serie(%L::uuid))', serie),
       '{"error":"Accès refusé"}'::jsonb, ARRAY['S','T','R'], ARRAY['A','B','ADM'],
       jsonb_build_object('success', true, 'missions_annulees', 0)),
      (20, format('SELECT to_jsonb(public.fn_assigner_mission_admin(%L::uuid, %L::uuid, NULL))', m_ouv, u_t),
       jsonb_build_object('error', 'Non autorisé'), ARRAY['S','T','R'], ARRAY['A','ADM'], NULL),
      (21, format('SELECT to_jsonb(public.fn_assigner_mission_admin(%L::uuid, %L::uuid, NULL))', m_ouv, u_t),
       jsonb_build_object('error', 'Cette mission n''appartient pas à votre établissement'), ARRAY['B'], ARRAY[]::text[], NULL),
      (22, format('SELECT to_jsonb(public.fn_creer_reclamation_score(%L::uuid, %L, %L, %L))', evt, 'ETAB', 'AUTRE',
                  'Réclamation de fixture pour la garde NULL, jamais persistée.'),
       jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE',
                          'error', 'Vous n''êtes pas concerné par cet événement'),
       ARRAY['S','T','R','B'], ARRAY['A'], NULL),
      (23, format('SELECT to_jsonb(public.fn_declarer_honoraires_retrocession(%L::uuid, 100, %L))', m_term, 'justificatif-fixture'),
       jsonb_build_object('error', 'Non autorisé'), ARRAY['S','T','R','B'], ARRAY['A','ADM'],
       jsonb_build_object('error', 'Cette mission n''est pas en rétrocession.')),
      (24, format('SELECT to_jsonb(public.fn_definir_retrocession_mission(%L::uuid, 50))', m_term),
       jsonb_build_object('error', 'Non autorisé'), ARRAY['S','T','R','B'], ARRAY['A','ADM'],
       jsonb_build_object('error', 'Modifiable uniquement sur une mission ouverte.'));

    -- Chaque rôle est bien celui annoncé : S, T et R n'ont aucun établissement.
    FOREACH v_acteur IN ARRAY ARRAY['S','T','R','B','A','ADM'] LOOP
      v_uid := CASE v_acteur WHEN 'S' THEN u_s WHEN 'T' THEN u_t WHEN 'R' THEN u_r
                             WHEN 'B' THEN u_b WHEN 'A' THEN u_a ELSE u_adm END;
      PERFORM set_config('request.jwt.claim.sub', v_uid::text, true);
      PERFORM set_config('request.jwt.claims',
        jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);
      IF public.mon_etablissement_id() IS DISTINCT FROM
           CASE v_acteur WHEN 'A' THEN e_a WHEN 'B' THEN e_b END
         OR public.est_admin() IS DISTINCT FROM (v_acteur = 'ADM') THEN
        RAISE EXCEPTION 'GARDES_NULL fixture : contexte % inattendu (etab %, admin %)',
          v_acteur, public.mon_etablissement_id(), public.est_admin();
      END IF;
    END LOOP;

    v_avant := jsonb_build_object(
      'm_term', (SELECT to_jsonb(m) FROM public.missions m WHERE m.id = m_term),
      'm_ouv', (SELECT to_jsonb(m) FROM public.missions m WHERE m.id = m_ouv),
      'presence', (SELECT to_jsonb(p) FROM public.presences p WHERE p.id = p_pres),
      'contrat', (SELECT to_jsonb(cm) FROM public.contrats_mission cm WHERE cm.id = c_contrat),
      'evenement', (SELECT to_jsonb(e) FROM public.evenements_score_etab e WHERE e.id = evt),
      'codes_secours', (SELECT count(*) FROM public.codes_secours_mission WHERE mission_id IN (m_term, m_ouv)),
      'qr', (SELECT count(*) FROM public.qr_codes_mission WHERE mission_id IN (m_term, m_ouv)),
      'escrow', (SELECT count(*) FROM public.escrow_release_queue WHERE mission_id IN (m_term, m_ouv)),
      'missions_a', (SELECT count(*) FROM public.missions WHERE etablissement_id = e_a),
      'factures_a', (SELECT count(*) FROM public.factures WHERE etablissement_id = e_a),
      'reclamations', (SELECT count(*) FROM public.reclamations_score WHERE evenement_etab_id = evt),
      'notifications', (SELECT count(*) FROM public.notifications n
                        WHERE n.id_ressource IN (m_term, m_ouv, p_pres, c_contrat, evt)
                           OR n.lien LIKE '%' || m_term::text || '%'
                           OR n.lien LIKE '%' || m_ouv::text || '%'));
    IF (v_avant->>'presence') IS NULL OR (v_avant->>'contrat') IS NULL OR (v_avant->>'evenement') IS NULL
       OR (v_avant->'presence'->>'valide_par_etablissement')::boolean IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'GARDES_NULL fixture incomplète : %', v_avant;
    END IF;

    -- Refus : la garde ne vaut plus NULL.
    FOR c IN SELECT * FROM gardes_null_cas ORDER BY ordre LOOP
      FOREACH v_acteur IN ARRAY c.refuses LOOP
        v_uid := CASE v_acteur WHEN 'S' THEN u_s WHEN 'T' THEN u_t WHEN 'R' THEN u_r
                               WHEN 'B' THEN u_b WHEN 'A' THEN u_a ELSE u_adm END;
        PERFORM set_config('request.jwt.claim.sub', v_uid::text, true);
        PERFORM set_config('request.jwt.claims',
          jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);
        EXECUTE c.appel INTO r;
        IF r IS DISTINCT FROM c.refus THEN
          RAISE EXCEPTION 'GARDES_NULL refus manquant — cas %, acteur % : % (attendu %)',
            c.ordre, v_acteur, r, c.refus;
        END IF;
        n_refus := n_refus + 1;
      END LOOP;
    END LOOP;

    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', '{}', true);
    v_apres := jsonb_build_object(
      'm_term', (SELECT to_jsonb(m) FROM public.missions m WHERE m.id = m_term),
      'm_ouv', (SELECT to_jsonb(m) FROM public.missions m WHERE m.id = m_ouv),
      'presence', (SELECT to_jsonb(p) FROM public.presences p WHERE p.id = p_pres),
      'contrat', (SELECT to_jsonb(cm) FROM public.contrats_mission cm WHERE cm.id = c_contrat),
      'evenement', (SELECT to_jsonb(e) FROM public.evenements_score_etab e WHERE e.id = evt),
      'codes_secours', (SELECT count(*) FROM public.codes_secours_mission WHERE mission_id IN (m_term, m_ouv)),
      'qr', (SELECT count(*) FROM public.qr_codes_mission WHERE mission_id IN (m_term, m_ouv)),
      'escrow', (SELECT count(*) FROM public.escrow_release_queue WHERE mission_id IN (m_term, m_ouv)),
      'missions_a', (SELECT count(*) FROM public.missions WHERE etablissement_id = e_a),
      'factures_a', (SELECT count(*) FROM public.factures WHERE etablissement_id = e_a),
      'reclamations', (SELECT count(*) FROM public.reclamations_score WHERE evenement_etab_id = evt),
      'notifications', (SELECT count(*) FROM public.notifications n
                        WHERE n.id_ressource IN (m_term, m_ouv, p_pres, c_contrat, evt)
                           OR n.lien LIKE '%' || m_term::text || '%'
                           OR n.lien LIKE '%' || m_ouv::text || '%'));
    IF v_apres IS DISTINCT FROM v_avant THEN
      RAISE EXCEPTION 'GARDES_NULL : un refus a produit un effet. Avant % / après %', v_avant, v_apres;
    END IF;

    -- Appelants légitimes : la garde laisse passer (cas annulés un à un).
    FOR c IN SELECT * FROM gardes_null_cas ORDER BY ordre LOOP
      FOREACH v_acteur IN ARRAY c.passants LOOP
        v_uid := CASE v_acteur WHEN 'S' THEN u_s WHEN 'T' THEN u_t WHEN 'R' THEN u_r
                               WHEN 'B' THEN u_b WHEN 'A' THEN u_a ELSE u_adm END;
        r := NULL;
        v_etat := NULL;
        v_msg := NULL;
        BEGIN
          PERFORM set_config('request.jwt.claim.sub', v_uid::text, true);
          PERFORM set_config('request.jwt.claims',
            jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);
          EXECUTE c.appel INTO r;
          RAISE EXCEPTION USING ERRCODE = 'JGN02', MESSAGE = 'fin du cas légitime';
        EXCEPTION
          WHEN SQLSTATE 'JGN02' THEN NULL;
          WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_etat = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        END;
        IF v_etat IS NULL AND r IS NOT DISTINCT FROM c.refus THEN
          RAISE EXCEPTION 'GARDES_NULL appelant légitime refusé — cas %, acteur % : %', c.ordre, v_acteur, r;
        END IF;
        IF c.attendu IS NOT NULL AND (v_etat IS NOT NULL OR r IS DISTINCT FROM c.attendu) THEN
          RAISE EXCEPTION 'GARDES_NULL suite métier inattendue — cas %, acteur % : % [% %] (attendu %)',
            c.ordre, v_acteur, r, v_etat, v_msg, c.attendu;
        END IF;
        RAISE NOTICE 'GARDES_NULL légitime cas % acteur % : % %', c.ordre, v_acteur,
          COALESCE(left(r::text, 120), ''), COALESCE(v_etat || ' ' || left(v_msg, 120), '');
        n_passe := n_passe + 1;
      END LOOP;
    END LOOP;

    IF n_refus <> 85 OR n_passe <> 48
       OR n_refus <> (SELECT sum(cardinality(refuses)) FROM gardes_null_cas)
       OR n_passe <> (SELECT sum(cardinality(passants)) FROM gardes_null_cas) THEN
      RAISE EXCEPTION 'GARDES_NULL matrice incomplète : % refus, % passages', n_refus, n_passe;
    END IF;

    RAISE EXCEPTION USING ERRCODE = 'JGN01', MESSAGE = 'GARDES_NULL_FIXTURES_ROLLBACK';
  EXCEPTION
    WHEN SQLSTATE 'JGN01' THEN NULL;
  END;

  IF EXISTS (SELECT 1 FROM public.etablissements WHERE id IN (e_a, e_b))
     OR EXISTS (SELECT 1 FROM public.missions WHERE id IN (m_term, m_ouv))
     OR EXISTS (SELECT 1 FROM auth.users WHERE id IN (u_s, u_t, u_r, u_b, u_a, u_adm)) THEN
    RAISE EXCEPTION 'GARDES_NULL : sous-transaction non nettoyée';
  END IF;
  PERFORM set_config('jolene.admin_seed_override_reason', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '{}', true);
END;
$gardes_null$;

ROLLBACK;
