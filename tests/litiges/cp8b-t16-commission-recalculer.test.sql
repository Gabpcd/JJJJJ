-- ============================================================
-- CP8b — T16 : Commission à recalculer (ajustement post-paiement)
-- ============================================================
-- Prérequis : migrations CP-LITIGES 1 → 7b + FIX bonus null values.
-- Usage : psql "$DB_URL" -f tests/litiges/cp8b-t16-commission-recalculer.test.sql
--
-- Scénario : mission 8h×25€ → honoraires PAYEE 200€, commission déjà
-- facturée 30€. Litige DESACCORD_MONTANT_FACTURE → résolution admin
-- AVOIR (heures 6h). Diff 200−150=50€ → flag commission_a_recalculer.
-- fn_recalculer: new_brut=SUM(montant_signe)=200−50=150, new_commission
-- =22.50, delta=7.50 → AVOIR commission 7.50€ lié à facture d'origine.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== CP8b T16 — Commission à recalculer (AVOIR commission 7.50€) =='

BEGIN;
DO $$
DECLARE
  v_e UUID := gen_random_uuid(); v_s UUID := gen_random_uuid();
  v_m UUID := gen_random_uuid(); v_p UUID := gen_random_uuid();
  v_fh UUID := gen_random_uuid(); v_fc UUID := gen_random_uuid();
  v_l UUID := gen_random_uuid();
  v_admin UUID; v_r JSONB; v_recalc JSONB;
  v_flag BOOLEAN; v_avoir RECORD;
BEGIN
  SELECT user_id INTO v_admin FROM public.user_roles WHERE role = 'ADMIN_PLATEFORME' LIMIT 1;
  IF v_admin IS NULL THEN
    RAISE NOTICE '[T16] SKIP — aucun admin ADMIN_PLATEFORME disponible'; RETURN;
  END IF;

  INSERT INTO public.etablissements (id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact)
    VALUES (v_e,'CP8B_T16_Etab','12345678900091','HOPITAL_PUBLIC','16 r','Paris','75016','cp8b-t16@test.local');
  INSERT INTO public.soignants (id,nom,prenom,email,profession)
    VALUES (v_s,'CP8B_T16','Iris','cp8b-t16-'||v_s||'@test.local','IDE');

  -- Facture commission mensuelle d'origine (factures table)
  INSERT INTO public.factures (
    id, etablissement_id, numero_facture, type_document,
    montant_ht, montant_tva, montant_ttc, nombre_missions,
    periode_debut, periode_fin, date_emission, date_echeance, statut
  ) VALUES (
    v_fc, v_e, 'CP8B-T16-COM-'||substr(v_fc::text,1,6), 'FACTURE',
    30, 6, 36, 1,
    date_trunc('month', NOW()-INTERVAL '30 days')::date,
    (date_trunc('month', NOW()-INTERVAL '30 days') + INTERVAL '1 month - 1 day')::date,
    (NOW()-INTERVAL '25 days')::date, (NOW()+INTERVAL '5 days')::date, 'EMISE'
  );

  INSERT INTO public.missions (id,etablissement_id,intitule,profession_requise,debut_le,fin_le,
    duree_heures,taux_horaire_base,taux_commission,statut,soignant_assigne_id,
    commission_facturee,facture_id,montant_commission_ht)
  VALUES (v_m,v_e,'CP8B_T16_M','IDE',NOW()-INTERVAL '20 days',NOW()-INTERVAL '19 days 16h',
    8,25,15,'TERMINEE',v_s,TRUE,v_fc,30);
  INSERT INTO public.presences (id,mission_id,soignant_id,valide_par_etablissement,valide_le,heures_reelles)
    VALUES (v_p,v_m,v_s,TRUE,NOW()-INTERVAL '18 days',8);

  INSERT INTO public.factures_honoraires (id,soignant_id,etablissement_id,mission_id,
    numero_facture,montant_ht,montant_tva,montant_ttc,taux_tva,exoneration_tva,
    date_emission,date_paiement,statut,statut_litige)
  VALUES (v_fh,v_s,v_e,v_m,'CP8B-T16-FH-'||substr(v_fh::text,1,6),
    200,0,200,0,TRUE,(NOW()-INTERVAL '15 days')::DATE,(NOW()-INTERVAL '10 days')::DATE,
    'PAYEE','NORMAL');

  INSERT INTO public.litiges (
    id, mission_id, soignant_id, etablissement_id, initie_par,
    motif, statut, type_litige, facture_id
  ) VALUES (
    v_l, v_m, v_s, v_e, 'ETABLISSEMENT',
    'Étab conteste heures facturées sur honoraires payés : 6h au lieu de 8h.',
    'OUVERT', 'DESACCORD_MONTANT_FACTURE', v_fh
  );

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  v_r := public.fn_admin_resoudre_litige(
    v_l, 'Résolution admin : heures révisées à 6h, avoir honoraires émis.',
    'ETABLISSEMENT', 6, 25, 'AUTO'
  );
  IF v_r ? 'error' THEN RAISE NOTICE '[T16] FAIL — resoudre: %', v_r->>'error'; RETURN; END IF;
  IF (v_r->>'action_financiere') <> 'AVOIR' THEN
    RAISE NOTICE '[T16] FAIL — action=% (attendu AVOIR)', v_r->>'action_financiere'; RETURN;
  END IF;

  SELECT commission_a_recalculer INTO v_flag FROM public.missions WHERE id = v_m;
  IF v_flag IS NOT TRUE THEN
    RAISE NOTICE '[T16] FAIL — commission_a_recalculer=% après AVOIR (attendu TRUE)', v_flag; RETURN;
  END IF;

  v_recalc := public.fn_recalculer_commissions_post_litige();

  SELECT commission_a_recalculer INTO v_flag FROM public.missions WHERE id = v_m;
  IF v_flag IS NOT FALSE THEN
    RAISE NOTICE '[T16] FAIL — flag=% après recalcul (attendu FALSE)', v_flag; RETURN;
  END IF;

  SELECT numero_facture, type_document, montant_ht, facture_precedente_id
    INTO v_avoir
    FROM public.factures
   WHERE type_document = 'AVOIR' AND facture_precedente_id = v_fc;

  IF NOT FOUND THEN
    RAISE NOTICE '[T16] FAIL — aucun AVOIR commission trouvé pour v_fc=% (retour=%)', v_fc, v_recalc; RETURN;
  END IF;
  IF v_avoir.montant_ht <> 7.50 THEN
    RAISE NOTICE '[T16] FAIL — AVOIR montant_ht=% (attendu 7.50)', v_avoir.montant_ht; RETURN;
  END IF;

  RAISE NOTICE '[T16] PASS — AVOIR commission % (%) = %€, facture_precedente_id=% (retour=%)',
    v_avoir.numero_facture, v_avoir.type_document, v_avoir.montant_ht, v_avoir.facture_precedente_id, v_recalc;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[T16] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;
ROLLBACK;

\echo ''
\echo '== Fin CP8b T16 =='
