-- ============================================================
-- FIX T18 — fenêtre F2/F3 : facture_id résolu pour types FINANCIER
-- ============================================================
-- Prérequis : migration 20260417130721_fix_t18_fenetre_financier_facture_lookup.
-- Usage : psql "$DB_URL" -f tests/litiges/fix-t18-fenetre-financier.test.sql
--
-- 5 scénarios BEGIN/ROLLBACK :
--   S1 — libéral, facture émise 24h ago  → contestation autorisée (<48h)
--   S2 — libéral, facture émise 72h ago  → contestation rejetée  (>48h)
--   S3 — salarié, facture émise 30j ago  → contestation autorisée (<60j)
--   S4 — salarié, facture émise 70j ago  → contestation rejetée  (>60j)
--   S5 — pas de facture sur la mission   → erreur spécifique
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== FIX T18 — fenêtre financier facture_id lookup =='

-- ─── Helper : chaque scénario crée étab+soignant+mission TERMINEE ───
-- Note : soignant.est_salarie_etablissement=FALSE (défaut)=libéral,
-- TRUE=salarié. La fenêtre F2 (48h libéral) est sur date_emission,
-- F3 (60j salarié) sur date_paiement.

-- ─────────────────────────────────────────────────────────────
-- S1 — Libéral, facture émise 24h ago → autorisée
-- ─────────────────────────────────────────────────────────────
BEGIN;
DO $$
DECLARE
  v_e UUID := gen_random_uuid(); v_s UUID := gen_random_uuid();
  v_m UUID := gen_random_uuid(); v_f UUID := gen_random_uuid();
  v_result JSONB;
BEGIN
  INSERT INTO public.etablissements (id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact)
    VALUES (v_e,'T18_S1','33333333300001','HOPITAL_PUBLIC','1 r','Paris','75001','t18s1@t.l');
  INSERT INTO public.soignants (id,nom,prenom,email,profession,est_salarie_etablissement)
    VALUES (v_s,'T18S1','A','t18s1-'||v_s||'@t.l','IDE',FALSE);
  INSERT INTO public.missions (id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,taux_horaire_base,statut,soignant_assigne_id)
    VALUES (v_m,v_e,'T18_S1_M','IDE',NOW()-INTERVAL '3 days',NOW()-INTERVAL '2 days 16h',8,25,'TERMINEE',v_s);
  INSERT INTO public.presences (id,mission_id,soignant_id,valide_par_etablissement,valide_le,heures_reelles)
    VALUES (gen_random_uuid(),v_m,v_s,TRUE,NOW()-INTERVAL '2 days',8);
  INSERT INTO public.factures_honoraires (id,soignant_id,etablissement_id,mission_id,numero_facture,montant_ht,montant_tva,montant_ttc,taux_tva,exoneration_tva,date_emission,statut)
    VALUES (v_f,v_s,v_e,v_m,'T18S1-'||substr(v_f::text,1,8),200,0,200,0,TRUE,(NOW()-INTERVAL '24 hours')::DATE,'EMISE');

  PERFORM set_config('request.jwt.claim.sub', v_s::text, true);
  v_result := public.fn_ouvrir_litige_rate_limited(v_m,'DESACCORD_MONTANT_FACTURE'::public.type_litige,
    'Libéral conteste le montant facturé (émise <48h).');

  IF v_result ? 'error' THEN
    RAISE NOTICE '[S1] FAIL — devrait passer (<48h): %', v_result->>'error';
  ELSE
    RAISE NOTICE '[S1] PASS — litige autorisé (<48h), facture_id=%', v_result->>'facture_id';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[S1] FAIL — exception: %', SQLERRM;
END $$;
ROLLBACK;

-- ─────────────────────────────────────────────────────────────
-- S2 — Libéral, facture émise 72h ago → rejetée
-- ─────────────────────────────────────────────────────────────
BEGIN;
DO $$
DECLARE
  v_e UUID := gen_random_uuid(); v_s UUID := gen_random_uuid();
  v_m UUID := gen_random_uuid(); v_f UUID := gen_random_uuid();
  v_result JSONB;
BEGIN
  INSERT INTO public.etablissements (id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact)
    VALUES (v_e,'T18_S2','33333333300002','HOPITAL_PUBLIC','2 r','Paris','75002','t18s2@t.l');
  INSERT INTO public.soignants (id,nom,prenom,email,profession,est_salarie_etablissement)
    VALUES (v_s,'T18S2','B','t18s2-'||v_s||'@t.l','IDE',FALSE);
  INSERT INTO public.missions (id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,taux_horaire_base,statut,soignant_assigne_id)
    VALUES (v_m,v_e,'T18_S2_M','IDE',NOW()-INTERVAL '5 days',NOW()-INTERVAL '4 days 16h',8,25,'TERMINEE',v_s);
  INSERT INTO public.presences (id,mission_id,soignant_id,valide_par_etablissement,valide_le,heures_reelles)
    VALUES (gen_random_uuid(),v_m,v_s,TRUE,NOW()-INTERVAL '4 days',8);
  INSERT INTO public.factures_honoraires (id,soignant_id,etablissement_id,mission_id,numero_facture,montant_ht,montant_tva,montant_ttc,taux_tva,exoneration_tva,date_emission,statut)
    VALUES (v_f,v_s,v_e,v_m,'T18S2-'||substr(v_f::text,1,8),200,0,200,0,TRUE,(NOW()-INTERVAL '72 hours')::DATE,'EMISE');

  PERFORM set_config('request.jwt.claim.sub', v_s::text, true);
  v_result := public.fn_ouvrir_litige_rate_limited(v_m,'DESACCORD_MONTANT_FACTURE'::public.type_litige,
    'Libéral conteste le montant facturé (émise >48h, hors fenêtre).');

  IF v_result ? 'error' AND (v_result->>'error') LIKE '%Fenêtre%' THEN
    RAISE NOTICE '[S2] PASS — rejeté (>48h): %', v_result->>'error';
  ELSIF v_result ? 'error' THEN
    RAISE NOTICE '[S2] FAIL — error inattendue: %', v_result->>'error';
  ELSE
    RAISE NOTICE '[S2] FAIL — devrait être rejeté (>48h), got litige_id=%', v_result->>'litige_id';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[S2] FAIL — exception: %', SQLERRM;
END $$;
ROLLBACK;

-- ─────────────────────────────────────────────────────────────
-- S3 — Salarié, facture payée 30j ago → autorisée (<60j)
-- ─────────────────────────────────────────────────────────────
BEGIN;
DO $$
DECLARE
  v_e UUID := gen_random_uuid(); v_s UUID := gen_random_uuid();
  v_m UUID := gen_random_uuid(); v_f UUID := gen_random_uuid();
  v_result JSONB;
BEGIN
  INSERT INTO public.etablissements (id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact)
    VALUES (v_e,'T18_S3','33333333300003','HOPITAL_PUBLIC','3 r','Paris','75003','t18s3@t.l');
  INSERT INTO public.soignants (id,nom,prenom,email,profession,est_salarie_etablissement)
    VALUES (v_s,'T18S3','C','t18s3-'||v_s||'@t.l','IDE',TRUE);
  INSERT INTO public.missions (id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,taux_horaire_base,statut,soignant_assigne_id)
    VALUES (v_m,v_e,'T18_S3_M','IDE',NOW()-INTERVAL '35 days',NOW()-INTERVAL '34 days 16h',8,25,'TERMINEE',v_s);
  INSERT INTO public.presences (id,mission_id,soignant_id,valide_par_etablissement,valide_le,heures_reelles)
    VALUES (gen_random_uuid(),v_m,v_s,TRUE,NOW()-INTERVAL '34 days',8);
  INSERT INTO public.factures_honoraires (id,soignant_id,etablissement_id,mission_id,numero_facture,montant_ht,montant_tva,montant_ttc,taux_tva,exoneration_tva,date_emission,date_paiement,statut)
    VALUES (v_f,v_s,v_e,v_m,'T18S3-'||substr(v_f::text,1,8),200,0,200,0,TRUE,(NOW()-INTERVAL '32 days')::DATE,(NOW()-INTERVAL '30 days')::DATE,'PAYEE');

  PERFORM set_config('request.jwt.claim.sub', v_s::text, true);
  v_result := public.fn_ouvrir_litige_rate_limited(v_m,'DESACCORD_MONTANT_FACTURE'::public.type_litige,
    'Salarié conteste le montant facturé (payée <60j).');

  IF v_result ? 'error' THEN
    RAISE NOTICE '[S3] FAIL — devrait passer (<60j): %', v_result->>'error';
  ELSE
    RAISE NOTICE '[S3] PASS — litige autorisé (<60j salarié), facture_id=%', v_result->>'facture_id';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[S3] FAIL — exception: %', SQLERRM;
END $$;
ROLLBACK;

-- ─────────────────────────────────────────────────────────────
-- S4 — Salarié, facture payée 70j ago → rejetée (>60j)
-- ─────────────────────────────────────────────────────────────
BEGIN;
DO $$
DECLARE
  v_e UUID := gen_random_uuid(); v_s UUID := gen_random_uuid();
  v_m UUID := gen_random_uuid(); v_f UUID := gen_random_uuid();
  v_result JSONB;
BEGIN
  INSERT INTO public.etablissements (id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact)
    VALUES (v_e,'T18_S4','33333333300004','HOPITAL_PUBLIC','4 r','Paris','75004','t18s4@t.l');
  INSERT INTO public.soignants (id,nom,prenom,email,profession,est_salarie_etablissement)
    VALUES (v_s,'T18S4','D','t18s4-'||v_s||'@t.l','IDE',TRUE);
  INSERT INTO public.missions (id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,taux_horaire_base,statut,soignant_assigne_id)
    VALUES (v_m,v_e,'T18_S4_M','IDE',NOW()-INTERVAL '75 days',NOW()-INTERVAL '74 days 16h',8,25,'TERMINEE',v_s);
  INSERT INTO public.presences (id,mission_id,soignant_id,valide_par_etablissement,valide_le,heures_reelles)
    VALUES (gen_random_uuid(),v_m,v_s,TRUE,NOW()-INTERVAL '74 days',8);
  INSERT INTO public.factures_honoraires (id,soignant_id,etablissement_id,mission_id,numero_facture,montant_ht,montant_tva,montant_ttc,taux_tva,exoneration_tva,date_emission,date_paiement,statut)
    VALUES (v_f,v_s,v_e,v_m,'T18S4-'||substr(v_f::text,1,8),200,0,200,0,TRUE,(NOW()-INTERVAL '72 days')::DATE,(NOW()-INTERVAL '70 days')::DATE,'PAYEE');

  PERFORM set_config('request.jwt.claim.sub', v_s::text, true);
  v_result := public.fn_ouvrir_litige_rate_limited(v_m,'DESACCORD_MONTANT_FACTURE'::public.type_litige,
    'Salarié conteste le montant facturé (payée >60j, hors fenêtre).');

  IF v_result ? 'error' AND (v_result->>'error') LIKE '%Fenêtre%' THEN
    RAISE NOTICE '[S4] PASS — rejeté (>60j salarié): %', v_result->>'error';
  ELSIF v_result ? 'error' THEN
    RAISE NOTICE '[S4] FAIL — error inattendue: %', v_result->>'error';
  ELSE
    RAISE NOTICE '[S4] FAIL — devrait être rejeté (>60j), got litige_id=%', v_result->>'litige_id';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[S4] FAIL — exception: %', SQLERRM;
END $$;
ROLLBACK;

-- ─────────────────────────────────────────────────────────────
-- S5 — Pas de facture sur la mission → erreur spécifique
-- ─────────────────────────────────────────────────────────────
BEGIN;
DO $$
DECLARE
  v_e UUID := gen_random_uuid(); v_s UUID := gen_random_uuid();
  v_m UUID := gen_random_uuid();
  v_result JSONB;
BEGIN
  INSERT INTO public.etablissements (id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact)
    VALUES (v_e,'T18_S5','33333333300005','HOPITAL_PUBLIC','5 r','Paris','75005','t18s5@t.l');
  INSERT INTO public.soignants (id,nom,prenom,email,profession)
    VALUES (v_s,'T18S5','E','t18s5-'||v_s||'@t.l','IDE');
  INSERT INTO public.missions (id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,taux_horaire_base,statut,soignant_assigne_id)
    VALUES (v_m,v_e,'T18_S5_M','IDE',NOW()-INTERVAL '3 days',NOW()-INTERVAL '2 days 16h',8,25,'TERMINEE',v_s);

  PERFORM set_config('request.jwt.claim.sub', v_s::text, true);
  v_result := public.fn_ouvrir_litige_rate_limited(v_m,'DESACCORD_MONTANT_FACTURE'::public.type_litige,
    'Tentative de contestation sans facture sur la mission.');

  IF v_result ? 'error' AND (v_result->>'error') LIKE '%Aucune facture%' THEN
    RAISE NOTICE '[S5] PASS — rejeté (pas de facture): %', v_result->>'error';
  ELSIF v_result ? 'error' THEN
    RAISE NOTICE '[S5] FAIL — error inattendue: %', v_result->>'error';
  ELSE
    RAISE NOTICE '[S5] FAIL — devrait être rejeté, got litige_id=%', v_result->>'litige_id';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[S5] FAIL — exception: %', SQLERRM;
END $$;
ROLLBACK;

\echo ''
\echo '== Fin FIX T18 =='
