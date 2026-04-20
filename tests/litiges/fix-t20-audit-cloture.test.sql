-- ============================================================
-- FIX T20 — audit RGPD clôture amiable fn_cloturer_litige_mutuel
-- ============================================================
-- Prérequis : migration 20260417130723_fix_t20_audit_cloture_amiable.
-- Usage : psql "$DB_URL" -f tests/litiges/fix-t20-audit-cloture.test.sql
--
-- 2 cas (même transaction BEGIN/ROLLBACK) :
--   S1 — Soignant accorde → 1 entrée LITIGE_ACCORD_CLOTURE
--   S2 — Étab accorde aussi → 1 entrée ACCORD + 1 LITIGE_CLOTURE_AMIABLE
-- Note : auth.users minimal requis pour l'étab (mon_etablissement_id()).
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== FIX T20 — audit RGPD clôture amiable =='

BEGIN;
DO $$
DECLARE
  v_e UUID := gen_random_uuid(); v_s UUID := gen_random_uuid();
  v_eu UUID := gen_random_uuid(); v_m UUID := gen_random_uuid();
  v_l UUID := gen_random_uuid();
  v_r JSONB;
  v_nb_accord INT;
  v_nb_cloture INT;
BEGIN
  INSERT INTO public.etablissements (id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact)
    VALUES (v_e,'T20_Etab','55555555500001','HOPITAL_PUBLIC','1 r','Paris','75001','t20@t.l');
  INSERT INTO public.soignants (id,nom,prenom,email,profession)
    VALUES (v_s,'T20','A','t20-'||v_s||'@t.l','IDE');
  INSERT INTO public.missions (id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,taux_horaire_base,statut,soignant_assigne_id)
    VALUES (v_m,v_e,'T20_M','IDE',NOW()-INTERVAL '3 days',NOW()-INTERVAL '2 days 16h',8,25,'TERMINEE',v_s);
  INSERT INTO public.presences (id,mission_id,soignant_id,valide_par_etablissement,valide_le,heures_reelles)
    VALUES (gen_random_uuid(),v_m,v_s,TRUE,NOW()-INTERVAL '2 days',8);
  INSERT INTO public.litiges (id,mission_id,soignant_id,etablissement_id,initie_par,motif,statut,type_litige)
    VALUES (v_l,v_m,v_s,v_e,'SOIGNANT','Contestation heures — test audit clôture.','OUVERT','DESACCORD_HEURES_POINTAGE');

  INSERT INTO auth.users (id,email,raw_app_meta_data,role,aud,instance_id)
    VALUES (v_eu,'t20-etab@test.local',
            jsonb_build_object('role','ADMIN_ETABLISSEMENT','etablissement_id',v_e),
            'authenticated','authenticated','00000000-0000-0000-0000-000000000000'::uuid)
    ON CONFLICT (id) DO NOTHING;

  -- S1 : soignant accorde
  PERFORM set_config('request.jwt.claim.sub', v_s::text, true);
  v_r := public.fn_cloturer_litige_mutuel(v_l);
  IF v_r ? 'error' THEN
    RAISE NOTICE '[S1] FAIL — soignant error: %', v_r->>'error'; RETURN;
  END IF;

  SELECT COUNT(*) INTO v_nb_accord FROM public.journaux_audit
   WHERE action = 'LITIGE_ACCORD_CLOTURE' AND id_ressource = v_l;

  IF v_nb_accord <> 1 THEN
    RAISE NOTICE '[S1] FAIL — LITIGE_ACCORD_CLOTURE count=% (attendu 1)', v_nb_accord;
    RETURN;
  END IF;
  RAISE NOTICE '[S1] PASS — 1 entrée LITIGE_ACCORD_CLOTURE (soignant)';

  -- S2 : étab accorde → clôture bilatérale
  PERFORM set_config('request.jwt.claim.sub', v_eu::text, true);
  v_r := public.fn_cloturer_litige_mutuel(v_l);
  IF v_r ? 'error' THEN
    RAISE NOTICE '[S2] FAIL — étab error: %', v_r->>'error'; RETURN;
  END IF;

  SELECT COUNT(*) INTO v_nb_accord FROM public.journaux_audit
   WHERE action = 'LITIGE_ACCORD_CLOTURE' AND id_ressource = v_l;
  SELECT COUNT(*) INTO v_nb_cloture FROM public.journaux_audit
   WHERE action = 'LITIGE_CLOTURE_AMIABLE' AND id_ressource = v_l;

  IF v_nb_accord <> 2 THEN
    RAISE NOTICE '[S2] FAIL — ACCORD total=% (attendu 2)', v_nb_accord;
  ELSIF v_nb_cloture <> 1 THEN
    RAISE NOTICE '[S2] FAIL — CLOTURE_AMIABLE=% (attendu 1)', v_nb_cloture;
  ELSE
    RAISE NOTICE '[S2] PASS — 2× ACCORD + 1× CLOTURE_AMIABLE dans journaux_audit';
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[T20] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;
ROLLBACK;

\echo ''
\echo '== Fin FIX T20 =='
