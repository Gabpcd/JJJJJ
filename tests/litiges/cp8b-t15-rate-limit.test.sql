-- ============================================================
-- CP8b — T15 : Rate limit atteint (3/heure → 4e refusé)
-- ============================================================
-- Prérequis : migrations CP-LITIGES 1 → 7b + FIX T18.
-- Usage : psql "$DB_URL" -f tests/litiges/cp8b-t15-rate-limit.test.sql
--
-- Scénario : même soignant ouvre 3 litiges (types différents sur 3
-- missions différentes pour contourner l'unique partiel) dans < 1h,
-- puis tente un 4e → rejet "Trop de litiges ouverts récemment…".
--
-- Seed : parametres_litiges.rate_limit_litiges_par_heure = 3 (CP-LITIGES-2
-- FIX-A, migration 20260417130200). Filtre : soignant_id = v_user_id
-- OR etablissement_id = mon_etablissement_id(), fenêtre 1h glissante.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== CP8b T15 — Rate limit 3/h (4e litige refusé) =='

BEGIN;
DO $$
DECLARE
  v_e UUID := gen_random_uuid(); v_s UUID := gen_random_uuid();
  v_m1 UUID := gen_random_uuid(); v_m2 UUID := gen_random_uuid();
  v_m3 UUID := gen_random_uuid(); v_m4 UUID := gen_random_uuid();
  v_seed INT;
  v_r1 JSONB; v_r2 JSONB; v_r3 JSONB; v_r4 JSONB;
  v_nb INT;
BEGIN
  SELECT valeur::INT INTO v_seed
    FROM public.parametres_litiges WHERE cle = 'rate_limit_litiges_par_heure';
  IF v_seed IS DISTINCT FROM 3 THEN
    RAISE NOTICE '[T15] FAIL — seed rate_limit=% (attendu 3)', v_seed; RETURN;
  END IF;

  INSERT INTO public.etablissements (id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact)
    VALUES (v_e,'CP8B_T15_Etab','12345678900090','HOPITAL_PUBLIC','15 r','Paris','75015','cp8b-t15@test.local');
  INSERT INTO public.soignants (id,nom,prenom,email,profession)
    VALUES (v_s,'CP8B_T15','Rémi','cp8b-t15-'||v_s||'@test.local','IDE');

  -- 4 missions TERMINEE + presences validées <48h (F1 ouverte pour DESACCORD_HEURES_POINTAGE)
  INSERT INTO public.missions (id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,taux_horaire_base,statut,soignant_assigne_id)
  VALUES (v_m1,v_e,'M1','IDE',NOW()-INTERVAL '1 day',NOW()-INTERVAL '16h',8,25,'TERMINEE',v_s),
         (v_m2,v_e,'M2','IDE',NOW()-INTERVAL '1 day',NOW()-INTERVAL '16h',8,25,'TERMINEE',v_s),
         (v_m3,v_e,'M3','IDE',NOW()-INTERVAL '1 day',NOW()-INTERVAL '16h',8,25,'TERMINEE',v_s),
         (v_m4,v_e,'M4','IDE',NOW()-INTERVAL '1 day',NOW()-INTERVAL '16h',8,25,'TERMINEE',v_s);
  INSERT INTO public.presences (id,mission_id,soignant_id,valide_par_etablissement,valide_le,heures_reelles)
  VALUES (gen_random_uuid(),v_m1,v_s,TRUE,NOW()-INTERVAL '2h',8),
         (gen_random_uuid(),v_m2,v_s,TRUE,NOW()-INTERVAL '2h',8),
         (gen_random_uuid(),v_m3,v_s,TRUE,NOW()-INTERVAL '2h',8),
         (gen_random_uuid(),v_m4,v_s,TRUE,NOW()-INTERVAL '2h',8);

  PERFORM set_config('request.jwt.claim.sub', v_s::text, true);

  -- 3 litiges types distincts (évite l'unique partiel mission_id+type_litige)
  v_r1 := public.fn_ouvrir_litige_rate_limited(v_m1,'DESACCORD_HEURES_POINTAGE'::public.type_litige,
    'Conteste heures pointage mission 1 (test rate limit, litige #1).');
  v_r2 := public.fn_ouvrir_litige_rate_limited(v_m2,'AUTRE'::public.type_litige,
    'Motif autre mission 2 (test rate limit, litige #2).');
  v_r3 := public.fn_ouvrir_litige_rate_limited(v_m3,'CONDITIONS_MISSION_NON_RESPECTEES'::public.type_litige,
    'Conditions non respectées mission 3 (test rate limit, litige #3).');

  IF v_r1 ? 'error' OR v_r2 ? 'error' OR v_r3 ? 'error' THEN
    RAISE NOTICE '[T15] FAIL — litige <=3 rejeté : r1=% r2=% r3=%',
      v_r1->>'error', v_r2->>'error', v_r3->>'error';
    RETURN;
  END IF;

  SELECT COUNT(*) INTO v_nb FROM public.litiges WHERE soignant_id = v_s;
  IF v_nb <> 3 THEN
    RAISE NOTICE '[T15] FAIL — COUNT(litiges)=% après 3 créations (attendu 3)', v_nb; RETURN;
  END IF;

  -- 4e litige : doit être rejeté par rate limit
  v_r4 := public.fn_ouvrir_litige_rate_limited(v_m4,'DESACCORD_HEURES_POINTAGE'::public.type_litige,
    'Quatrième litige supposé dépasser la limite horaire (test rate limit).');

  IF NOT (v_r4 ? 'error') THEN
    RAISE NOTICE '[T15] FAIL — 4e litige accepté (attendu rejet rate limit), retour=%', v_r4; RETURN;
  END IF;
  IF v_r4->>'error' NOT ILIKE '%trop de litiges%' THEN
    RAISE NOTICE '[T15] FAIL — message inattendu : %', v_r4->>'error'; RETURN;
  END IF;

  SELECT COUNT(*) INTO v_nb FROM public.litiges WHERE soignant_id = v_s;
  IF v_nb <> 3 THEN
    RAISE NOTICE '[T15] FAIL — COUNT(litiges)=% après 4e tentative (attendu 3)', v_nb; RETURN;
  END IF;

  RAISE NOTICE '[T15] PASS — 3 litiges créés, 4e rejeté (%), total=3', v_r4->>'error';

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[T15] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;
ROLLBACK;

\echo ''
\echo '== Fin CP8b T15 =='
