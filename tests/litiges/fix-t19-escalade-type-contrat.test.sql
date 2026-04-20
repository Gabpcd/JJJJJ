-- ============================================================
-- FIX T19 — fn_litiges_escalader_auto + fn_fenetre via type_contrat_applique
-- ============================================================
-- Prérequis : migration 20260417130722_fix_t19_escalade_type_contrat_applique.
-- Usage : psql "$DB_URL" -f tests/litiges/fix-t19-escalade-type-contrat.test.sql
--
-- 3 scénarios BEGIN/ROLLBACK sur fn_litiges_escalader_auto :
--   S1 — mission LIBERAL + soignant flagué SALARIE global → 72h appliqués
--        (escalade après 80h, alors que 5 j.o. n'aurait pas escaladé)
--   S2 — mission SALARIE + soignant flagué LIBERAL global → 5 j.o. appliqués
--        (escalade après 8 jours, alors que 72h aurait escaladé bien plus tôt
--        et indûment si le flag global avait primé — mais ici on inverse
--        le sens : on vérifie que le délai 5 j.o. EST bien appliqué)
--   S3 — mission type_contrat_applique=NULL + soignant flagué LIBERAL
--        (FALSE) → fallback est_salarie_etablissement → 72h libéral OK
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== FIX T19 — escalade via type_contrat_applique =='

-- ─────────────────────────────────────────────────────────────
-- S1 — mission LIBERAL applique, soignant flagué SALARIE global
--      → 72h libéral appliqués, escalade à 80h OK
-- ─────────────────────────────────────────────────────────────
BEGIN;
DO $$
DECLARE
  v_e UUID := gen_random_uuid(); v_s UUID := gen_random_uuid();
  v_m UUID := gen_random_uuid(); v_l UUID := gen_random_uuid();
  v_litige RECORD;
BEGIN
  INSERT INTO public.etablissements (id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact)
    VALUES (v_e,'T19_S1','44444444400001','HOPITAL_PUBLIC','1 r','Paris','75001','t19s1@t.l');
  INSERT INTO public.soignants (id,nom,prenom,email,profession,est_salarie_etablissement)
    VALUES (v_s,'T19S1','A','t19s1-'||v_s||'@t.l','IDE',TRUE);  -- flag global SALARIE (incorrect)
  INSERT INTO public.missions (id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,taux_horaire_base,statut,soignant_assigne_id,type_contrat_applique)
    VALUES (v_m,v_e,'T19_S1_M','IDE',NOW()-INTERVAL '5 days',NOW()-INTERVAL '4 days 16h',8,25,'TERMINEE',v_s,'LIBERAL');
  INSERT INTO public.presences (id,mission_id,soignant_id,valide_par_etablissement,valide_le,heures_reelles)
    VALUES (gen_random_uuid(),v_m,v_s,TRUE,NOW()-INTERVAL '4 days',8);
  INSERT INTO public.litiges (id,mission_id,soignant_id,etablissement_id,initie_par,motif,statut,type_litige,cree_le,est_informatif)
    VALUES (v_l,v_m,v_s,v_e,'SOIGNANT','Litige libéral via mission applique=LIBERAL.',
            'OUVERT','DESACCORD_HEURES_POINTAGE',NOW()-INTERVAL '80 hours',FALSE);

  PERFORM public.fn_litiges_escalader_auto();
  SELECT statut, escalade_auto_motif INTO v_litige FROM public.litiges WHERE id = v_l;

  IF v_litige.statut <> 'EN_MEDIATION' THEN
    RAISE NOTICE '[S1] FAIL — statut=% (attendu EN_MEDIATION via 72h libéral)', v_litige.statut;
  ELSIF v_litige.escalade_auto_motif NOT LIKE '%libéral%' THEN
    RAISE NOTICE '[S1] FAIL — motif=% (attendu mention libéral)', v_litige.escalade_auto_motif;
  ELSE
    RAISE NOTICE '[S1] PASS — mission LIBERAL prime sur flag SALARIE global (motif=%)', v_litige.escalade_auto_motif;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[S1] FAIL — exception: %', SQLERRM;
END $$;
ROLLBACK;

-- ─────────────────────────────────────────────────────────────
-- S2 — mission SALARIE applique, soignant flagué LIBERAL global
--      → 5 j.o. appliqués, escalade à 8 jours OK + motif salarié
-- ─────────────────────────────────────────────────────────────
BEGIN;
DO $$
DECLARE
  v_e UUID := gen_random_uuid(); v_s UUID := gen_random_uuid();
  v_m UUID := gen_random_uuid(); v_l UUID := gen_random_uuid();
  v_litige RECORD;
BEGIN
  INSERT INTO public.etablissements (id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact)
    VALUES (v_e,'T19_S2','44444444400002','HOPITAL_PUBLIC','2 r','Paris','75002','t19s2@t.l');
  INSERT INTO public.soignants (id,nom,prenom,email,profession,est_salarie_etablissement)
    VALUES (v_s,'T19S2','B','t19s2-'||v_s||'@t.l','IDE',FALSE);  -- flag global LIBERAL (incorrect)
  INSERT INTO public.missions (id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,taux_horaire_base,statut,soignant_assigne_id,type_contrat_applique)
    VALUES (v_m,v_e,'T19_S2_M','IDE',NOW()-INTERVAL '12 days',NOW()-INTERVAL '11 days 16h',8,25,'TERMINEE',v_s,'SALARIE');
  INSERT INTO public.presences (id,mission_id,soignant_id,valide_par_etablissement,valide_le,heures_reelles)
    VALUES (gen_random_uuid(),v_m,v_s,TRUE,NOW()-INTERVAL '11 days',8);
  -- Litige créé il y a 8 jours (>5 jours ouvrés dans toutes les semaines)
  INSERT INTO public.litiges (id,mission_id,soignant_id,etablissement_id,initie_par,motif,statut,type_litige,cree_le,est_informatif)
    VALUES (v_l,v_m,v_s,v_e,'SOIGNANT','Litige salarié via mission applique=SALARIE.',
            'OUVERT','DESACCORD_HEURES_POINTAGE',NOW()-INTERVAL '8 days',FALSE);

  PERFORM public.fn_litiges_escalader_auto();
  SELECT statut, escalade_auto_motif INTO v_litige FROM public.litiges WHERE id = v_l;

  IF v_litige.statut <> 'EN_MEDIATION' THEN
    RAISE NOTICE '[S2] FAIL — statut=% (attendu EN_MEDIATION via 5 j.o. salarié)', v_litige.statut;
  ELSIF v_litige.escalade_auto_motif NOT LIKE '%salarié%' THEN
    RAISE NOTICE '[S2] FAIL — motif=% (attendu mention salarié)', v_litige.escalade_auto_motif;
  ELSE
    RAISE NOTICE '[S2] PASS — mission SALARIE prime sur flag LIBERAL global (motif=%)', v_litige.escalade_auto_motif;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[S2] FAIL — exception: %', SQLERRM;
END $$;
ROLLBACK;

-- ─────────────────────────────────────────────────────────────
-- S3 — mission type_contrat_applique=NULL → fallback flag global
--      soignant LIBERAL (FALSE) → 72h, escalade à 80h OK
-- ─────────────────────────────────────────────────────────────
BEGIN;
DO $$
DECLARE
  v_e UUID := gen_random_uuid(); v_s UUID := gen_random_uuid();
  v_m UUID := gen_random_uuid(); v_l UUID := gen_random_uuid();
  v_litige RECORD;
BEGIN
  INSERT INTO public.etablissements (id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact)
    VALUES (v_e,'T19_S3','44444444400003','HOPITAL_PUBLIC','3 r','Paris','75003','t19s3@t.l');
  INSERT INTO public.soignants (id,nom,prenom,email,profession,est_salarie_etablissement)
    VALUES (v_s,'T19S3','C','t19s3-'||v_s||'@t.l','IDE',FALSE);
  -- Pas de type_contrat_applique → fallback sur flag global
  INSERT INTO public.missions (id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,taux_horaire_base,statut,soignant_assigne_id)
    VALUES (v_m,v_e,'T19_S3_M','IDE',NOW()-INTERVAL '5 days',NOW()-INTERVAL '4 days 16h',8,25,'TERMINEE',v_s);
  INSERT INTO public.presences (id,mission_id,soignant_id,valide_par_etablissement,valide_le,heures_reelles)
    VALUES (gen_random_uuid(),v_m,v_s,TRUE,NOW()-INTERVAL '4 days',8);
  INSERT INTO public.litiges (id,mission_id,soignant_id,etablissement_id,initie_par,motif,statut,type_litige,cree_le,est_informatif)
    VALUES (v_l,v_m,v_s,v_e,'SOIGNANT','Litige fallback : applique NULL, flag soignant LIBERAL.',
            'OUVERT','DESACCORD_HEURES_POINTAGE',NOW()-INTERVAL '80 hours',FALSE);

  PERFORM public.fn_litiges_escalader_auto();
  SELECT statut, escalade_auto_motif INTO v_litige FROM public.litiges WHERE id = v_l;

  IF v_litige.statut <> 'EN_MEDIATION' THEN
    RAISE NOTICE '[S3] FAIL — statut=% (attendu EN_MEDIATION via fallback libéral)', v_litige.statut;
  ELSIF v_litige.escalade_auto_motif NOT LIKE '%libéral%' THEN
    RAISE NOTICE '[S3] FAIL — motif=% (attendu mention libéral via fallback)', v_litige.escalade_auto_motif;
  ELSE
    RAISE NOTICE '[S3] PASS — fallback est_salarie_etablissement OK (motif=%)', v_litige.escalade_auto_motif;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[S3] FAIL — exception: %', SQLERRM;
END $$;
ROLLBACK;

\echo ''
\echo '== Fin FIX T19 =='
