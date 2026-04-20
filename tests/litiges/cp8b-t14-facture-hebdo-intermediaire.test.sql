-- ============================================================
-- CP8b — T14 : Litige sur facture hebdo intermédiaire
-- ============================================================
-- Prérequis : migrations CP-LITIGES 1 → 7b.
-- Usage : psql "$DB_URL" -f tests/litiges/cp8b-t14-facture-hebdo-intermediaire.test.sql
--
-- Scénario : mission TERMINEE avec 2 factures hebdo (S1 + S2), les 2
-- EMISE statut_litige=NORMAL. Soignant ouvre DESACCORD_MONTANT_FACTURE
-- ciblé sur S1 (litiges.facture_id = v_f1).
--
-- Comportement attendu (trigger trg_litige_gel_degel_facture) :
-- FINANCIER + facture_id NOT NULL → gel UNIQUEMENT de la facture visée
-- (cf. migration CP-LITIGES-2 ligne 165). S2 reste NORMAL.
--
-- NB : le gel granulaire par période n'est PAS encore implémenté pour
-- les types PRESENCE/CONDITIONS/COMPORTEMENT (ticket T9, Partie 2) ;
-- ici on vérifie le cas FINANCIER qui est déjà granulaire par facture.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== CP8b T14 — Litige facture hebdo intermédiaire (gel granulaire) =='

BEGIN;
DO $$
DECLARE
  v_e UUID := gen_random_uuid(); v_s UUID := gen_random_uuid();
  v_m UUID := gen_random_uuid(); v_p UUID := gen_random_uuid();
  v_f1 UUID := gen_random_uuid(); v_f2 UUID := gen_random_uuid();
  v_l UUID := gen_random_uuid();
  v_s1 RECORD; v_s2 RECORD;
BEGIN
  INSERT INTO public.etablissements (id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact)
    VALUES (v_e,'CP8B_T14_Etab','12345678900089','HOPITAL_PUBLIC','14 rue','Paris','75014','cp8b-t14@test.local');
  INSERT INTO public.soignants (id,nom,prenom,email,profession)
    VALUES (v_s,'CP8B_T14','Noa','cp8b-t14-'||v_s||'@test.local','IDE');
  INSERT INTO public.missions (id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,taux_horaire_base,statut,soignant_assigne_id)
    VALUES (v_m,v_e,'CP8B_T14_M2sem','IDE',NOW()-INTERVAL '14 days',NOW()-INTERVAL '1 day',70,25,'TERMINEE',v_s);
  INSERT INTO public.presences (id,mission_id,soignant_id,valide_par_etablissement,valide_le,heures_reelles)
    VALUES (v_p,v_m,v_s,TRUE,NOW()-INTERVAL '12 hours',70);

  -- 2 factures hebdo (simulation mission 2 semaines, non-PAYEE)
  INSERT INTO public.factures_honoraires (
    id, soignant_id, etablissement_id, mission_id,
    numero_facture, montant_ht, montant_tva, montant_ttc,
    taux_tva, exoneration_tva, date_emission, statut, statut_litige
  ) VALUES
    (v_f1, v_s, v_e, v_m, 'CP8B-T14-S1-'||substr(v_f1::text,1,6),
     150, 0, 150, 0, TRUE, (NOW()-INTERVAL '7 days')::DATE, 'EMISE', 'NORMAL'),
    (v_f2, v_s, v_e, v_m, 'CP8B-T14-S2-'||substr(v_f2::text,1,6),
     200, 0, 200, 0, TRUE, (NOW()-INTERVAL '1 day')::DATE, 'EMISE', 'NORMAL');

  -- Litige DESACCORD_MONTANT_FACTURE ciblé sur S1 uniquement
  INSERT INTO public.litiges (
    id, mission_id, soignant_id, etablissement_id, initie_par,
    motif, statut, type_litige, facture_id
  ) VALUES (
    v_l, v_m, v_s, v_e, 'SOIGNANT',
    'Soignant conteste montant facture hebdo S1 uniquement, S2 OK.',
    'OUVERT', 'DESACCORD_MONTANT_FACTURE', v_f1
  );

  -- Vérif comportement trigger
  SELECT statut_litige, litige_id INTO v_s1 FROM public.factures_honoraires WHERE id = v_f1;
  SELECT statut_litige, litige_id INTO v_s2 FROM public.factures_honoraires WHERE id = v_f2;

  IF v_s1.statut_litige <> 'EN_ATTENTE_LITIGE' THEN
    RAISE NOTICE '[T14] FAIL — S1 statut_litige=% (attendu EN_ATTENTE_LITIGE)', v_s1.statut_litige;
  ELSIF v_s1.litige_id IS DISTINCT FROM v_l THEN
    RAISE NOTICE '[T14] FAIL — S1 litige_id=% (attendu %)', v_s1.litige_id, v_l;
  ELSIF v_s2.statut_litige <> 'NORMAL' THEN
    RAISE NOTICE '[T14] FAIL — gel NON granulaire : S2 statut_litige=% (attendu NORMAL)', v_s2.statut_litige;
  ELSIF v_s2.litige_id IS NOT NULL THEN
    RAISE NOTICE '[T14] FAIL — S2 litige_id=% (attendu NULL)', v_s2.litige_id;
  ELSE
    RAISE NOTICE '[T14] PASS — gel granulaire OK : S1 EN_ATTENTE_LITIGE / S2 NORMAL (FINANCIER+facture_id ciblé)';
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[T14] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;
ROLLBACK;

\echo ''
\echo '== Fin CP8b T14 =='
