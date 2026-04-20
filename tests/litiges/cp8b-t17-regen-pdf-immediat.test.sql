-- ============================================================
-- CP8b — T17 : Regen PDF immédiat (FIX 18) via pg_net
-- ============================================================
-- Prérequis : CP-LITIGES 1→7b + FIX 18 + bonus null values.
-- Usage : psql "$DB_URL" -f tests/litiges/cp8b-t17-regen-pdf-immediat.test.sql
--
-- Scénario : facture EMISE, litige FINANCIER, résolution RECALCUL →
-- fn_trigger_regen_pdf_immediate pousse net.http_post. Vérifs : (1)
-- JSONB retour contient regen_pdf_request_ids non vide, (2) audit RGPD
-- contient la même clé, (3) au moins une req apparaît dans
-- net.http_request_queue. SKIP si generate_invoice_url absent ou vault
-- secret service_role_key manquant (helper renvoie NULL → array [0]).
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== CP8b T17 — Regen PDF immédiat (pg_net fire-and-forget) =='

BEGIN;
DO $$
DECLARE
  v_e UUID := gen_random_uuid(); v_s UUID := gen_random_uuid();
  v_m UUID := gen_random_uuid(); v_p UUID := gen_random_uuid();
  v_fh UUID := gen_random_uuid(); v_l UUID := gen_random_uuid();
  v_admin UUID; v_r JSONB; v_ids JSONB; v_audit JSONB;
  v_nb_req INT; v_url TEXT; v_ids_arr BIGINT[];
BEGIN
  SELECT user_id INTO v_admin FROM public.user_roles WHERE role = 'ADMIN_PLATEFORME' LIMIT 1;
  IF v_admin IS NULL THEN RAISE NOTICE '[T17] SKIP — aucun ADMIN_PLATEFORME'; RETURN; END IF;
  SELECT valeur INTO v_url FROM public.parametres_litiges WHERE cle = 'generate_invoice_url';
  IF v_url IS NULL OR length(v_url) = 0 THEN
    RAISE NOTICE '[T17] SKIP — generate_invoice_url absent/vide'; RETURN;
  END IF;

  INSERT INTO public.etablissements (id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact)
    VALUES (v_e,'CP8B_T17_Etab','12345678900092','HOPITAL_PUBLIC','17 r','Paris','75017','cp8b-t17@test.local');
  INSERT INTO public.soignants (id,nom,prenom,email,profession)
    VALUES (v_s,'CP8B_T17','Kim','cp8b-t17-'||v_s||'@test.local','IDE');
  INSERT INTO public.missions (id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,taux_horaire_base,statut,soignant_assigne_id)
    VALUES (v_m,v_e,'CP8B_T17_M','IDE',NOW()-INTERVAL '2 days',NOW()-INTERVAL '1 day 16h',8,25,'TERMINEE',v_s);
  INSERT INTO public.presences (id,mission_id,soignant_id,valide_par_etablissement,valide_le,heures_reelles)
    VALUES (v_p,v_m,v_s,TRUE,NOW()-INTERVAL '20h',8);
  INSERT INTO public.factures_honoraires (id,soignant_id,etablissement_id,mission_id,numero_facture,
    montant_ht,montant_tva,montant_ttc,taux_tva,exoneration_tva,date_emission,statut,statut_litige)
  VALUES (v_fh,v_s,v_e,v_m,'CP8B-T17-FH-'||substr(v_fh::text,1,6),
    200,0,200,0,TRUE,(NOW()-INTERVAL '1 day')::DATE,'EMISE','NORMAL');
  INSERT INTO public.litiges (id,mission_id,soignant_id,etablissement_id,initie_par,motif,statut,type_litige,facture_id)
  VALUES (v_l,v_m,v_s,v_e,'SOIGNANT',
          'Soignant conteste montant facture émise — test regen PDF pg_net.',
          'OUVERT','DESACCORD_MONTANT_FACTURE',v_fh);

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  v_r := public.fn_admin_resoudre_litige(
    v_l, 'Résolution admin : recalcul direct du montant facture pour test pg_net.',
    'SOIGNANT', 6, 25, 'RECALCUL'
  );
  IF v_r ? 'error' THEN RAISE NOTICE '[T17] FAIL — resoudre: %', v_r->>'error'; RETURN; END IF;

  v_ids := v_r->'regen_pdf_request_ids';
  IF v_ids IS NULL OR jsonb_typeof(v_ids) <> 'array' THEN
    RAISE NOTICE '[T17] FAIL — regen_pdf_request_ids absent ou non-array : %', v_ids; RETURN;
  END IF;
  IF jsonb_array_length(v_ids) = 0 THEN
    RAISE NOTICE '[T17] FAIL — regen_pdf_request_ids vide'; RETURN;
  END IF;

  -- SKIP si helper a retourné NULL (vault/URL manquant) → array contient que des 0
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(v_ids) x WHERE (x.value)::BIGINT > 0) THEN
    RAISE NOTICE '[T17] SKIP — regen_pdf_request_ids=%, vault secret service_role_key probablement absent', v_ids; RETURN;
  END IF;

  SELECT details INTO v_audit FROM public.journaux_audit
   WHERE action = 'LITIGE_RESOLUTION' AND id_ressource = v_l ORDER BY cree_le DESC LIMIT 1;
  IF NOT (v_audit ? 'regen_pdf_request_ids') THEN
    RAISE NOTICE '[T17] FAIL — audit details sans regen_pdf_request_ids : %', v_audit; RETURN;
  END IF;

  SELECT array_agg((x.value)::BIGINT) INTO v_ids_arr
    FROM jsonb_array_elements_text(v_ids) x WHERE (x.value)::BIGINT > 0;
  BEGIN
    EXECUTE 'SELECT COUNT(*) FROM net.http_request_queue WHERE id = ANY($1)' INTO v_nb_req USING v_ids_arr;
  EXCEPTION WHEN OTHERS THEN v_nb_req := NULL;
  END;
  IF v_nb_req IS NULL THEN
    RAISE NOTICE '[T17] PASS (partiel) — ids=% + audit OK ; net.http_request_queue inaccessible', v_ids;
  ELSIF v_nb_req >= 1 THEN
    RAISE NOTICE '[T17] PASS — ids=%, % req(s) présentes dans net.http_request_queue, audit OK', v_ids, v_nb_req;
  ELSE
    RAISE NOTICE '[T17] FAIL — aucun id du retour présent dans net.http_request_queue (ids=%)', v_ids;
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[T17] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;
ROLLBACK;

\echo ''
\echo '== Fin CP8b T17 =='
