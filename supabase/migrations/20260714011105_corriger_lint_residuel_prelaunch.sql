-- Solde des diagnostics PL/pgSQL pre-lancement apres les migrations 03439,
-- 04020 et 05000.
--
-- Aucun enregistrement metier n'est modifie par cette migration : seules des
-- definitions de fonctions existantes sont remplacees. Le helper temporaire
-- exige un nombre exact d'occurrences pour chaque fragment ; tout drift du
-- schema source fait echouer la migration au lieu d'appliquer un patch ambigu.

CREATE OR REPLACE FUNCTION pg_temp.jolene_replace_function_fragment(
  p_signature regprocedure,
  p_old text,
  p_new text,
  p_expected_occurrences integer DEFAULT 1
)
RETURNS void
LANGUAGE plpgsql
AS $helper$
DECLARE
  v_definition text;
  v_occurrences integer;
BEGIN
  IF p_old IS NULL OR p_old = '' OR p_expected_occurrences < 1 THEN
    RAISE EXCEPTION 'Parametres de remplacement invalides pour %', p_signature;
  END IF;

  SELECT pg_get_functiondef(p_signature) INTO v_definition;
  IF v_definition IS NULL THEN
    RAISE EXCEPTION 'Fonction introuvable : %', p_signature;
  END IF;

  v_occurrences :=
    (length(v_definition) - length(replace(v_definition, p_old, '')))
    / length(p_old);

  IF v_occurrences <> p_expected_occurrences THEN
    RAISE EXCEPTION
      'Remplacement refuse pour % : fragment attendu % fois, trouve %',
      p_signature,
      p_expected_occurrences,
      v_occurrences;
  END IF;

  EXECUTE replace(v_definition, p_old, p_new);
END;
$helper$;

-- 1. Drill-down BFA : la ville canonique est etablissements.adresse_ville.
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_admin_bfa_detail_groupe(uuid,integer)'::regprocedure,
  $old$e.ville$old$,
  $new$e.adresse_ville$new$
);

-- 2. Levee de suspension : le lecteur de secret existant retourne la cle
-- service_role sans argument. L'URL projet est la meme que celle des crons DB.
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_admin_lever_suspension(uuid,text)'::regprocedure,
  $old$v_url := public.fn_lire_secret_cron('supabase_url');$old$,
  $new$v_url := 'https://flripxtsyegjshnhzjkz.supabase.co';$new$
);
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_admin_lever_suspension(uuid,text)'::regprocedure,
  $old$v_token := public.fn_lire_secret_cron('service_role_key');$old$,
  $new$v_token := public.fn_lire_secret_cron();$new$
);

-- 3. Reset Playwright : tables, colonnes et enum reellement deployes.
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_admin_reset_test_account(text)'::regprocedure,
  $old$DELETE FROM public.notations WHERE evaluateur_id = v_user_id OR evalue_id = v_user_id;$old$,
  $new$DELETE FROM public.notations_missions
    WHERE notateur_id = v_user_id OR note_id = v_user_id;
    DELETE FROM public.evaluations
    WHERE evaluateur_id = v_user_id OR evalue_id = v_user_id;$new$
);
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_admin_reset_test_account(text)'::regprocedure,
  $old$DELETE FROM public.exclusions WHERE excluant_id = v_user_id;$old$,
  $new$DELETE FROM public.exclusions
    WHERE exclu_par = v_user_id OR exclu_id = v_user_id;$new$
);
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_admin_reset_test_account(text)'::regprocedure,
  $old$DELETE FROM public.missions WHERE etablissement_id = v_user_id AND statut IN ('OUVERTE', 'BROUILLON');$old$,
  $new$DELETE FROM public.missions
    WHERE etablissement_id = v_user_id AND statut = 'OUVERTE';$new$
);

-- 4. Annulation legacy : conserver la variable dans le type enum de la colonne.
-- Les flux livres utilisent fn_annuler_mission_etab/fn_annuler_mission_soignant ;
-- cette ancienne RPC divergente est donc corrigee pour le lint puis fermee.
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_annuler_mission(uuid,text)'::regprocedure,
  $old$v_nouveau_statut TEXT;$old$,
  $new$v_nouveau_statut public.statut_mission;$new$
);
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_annuler_mission(uuid,text)'::regprocedure,
  $old$    IF NOT v_is_admin AND v_mission.etablissement_id != v_etab_id AND v_mission.soignant_assigne_id != auth.uid() THEN
        RETURN '{"error":"Accès refusé"}'::JSONB;
    END IF;$old$,
  $new$    IF auth.uid() IS NULL THEN
        RETURN '{"error":"Accès refusé"}'::jsonb;
    END IF;

    IF v_is_admin IS NOT TRUE
       AND v_mission.etablissement_id IS DISTINCT FROM v_etab_id
       AND v_mission.soignant_assigne_id IS DISTINCT FROM auth.uid() THEN
        RETURN '{"error":"Accès refusé"}'::jsonb;
    END IF;$new$
);

-- Les deux variantes etablissement doivent refuser un soignant (etab courant
-- NULL) et un membre d'un autre etablissement. L'operateur IS DISTINCT FROM
-- ferme le contournement SQL a trois valeurs de l'ancienne comparaison `!=`.
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_annuler_mission_etab(uuid,text,text)'::regprocedure,
  $old$  IF v_mission.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN$old$,
  $new$  IF public.est_admin() IS NOT TRUE
     AND (
       v_mission.etablissement_id IS DISTINCT FROM public.mon_etablissement_id()
       OR public.fn_a_permission_etablissement(
         'missions', v_mission.etablissement_id
       ) IS NOT TRUE
     ) THEN$new$
);
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_annuler_mission_etablissement(uuid,text)'::regprocedure,
  $old$    IF v_mission.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN$old$,
  $new$    IF public.est_admin() IS NOT TRUE
       AND (
         v_mission.etablissement_id IS DISTINCT FROM public.mon_etablissement_id()
         OR public.fn_a_permission_etablissement(
           'missions', v_mission.etablissement_id
         ) IS NOT TRUE
       ) THEN$new$
);

REVOKE ALL ON FUNCTION public.fn_annuler_mission(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;

-- 5-6. Literaux explicitement types : memes valeurs, aucun cast implicite.
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_calculer_heures_majorees(timestamp with time zone,timestamp with time zone)'::regprocedure,
  $old$v_step INTERVAL := '30 minutes';$old$,
  $new$v_step interval := interval '30 minutes';
    v_duree numeric;$new$
);
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_calculer_heures_majorees(timestamp with time zone,timestamp with time zone)'::regprocedure,
  $old$        v_heure := EXTRACT(HOUR FROM v_cursor);
        v_dow := EXTRACT(DOW FROM v_cursor); -- 0 = dimanche
        v_date := v_cursor::DATE;$old$,
  $new$        v_heure := EXTRACT(HOUR FROM (v_cursor AT TIME ZONE 'Europe/Paris'));
        v_dow := EXTRACT(DOW FROM (v_cursor AT TIME ZONE 'Europe/Paris')); -- 0 = dimanche
        v_date := (v_cursor AT TIME ZONE 'Europe/Paris')::DATE;
        v_duree := LEAST(
          0.5::numeric,
          GREATEST(
            0::numeric,
            EXTRACT(EPOCH FROM (p_fin - v_cursor))::numeric / 3600
          )
        );$new$
);
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_calculer_heures_majorees(timestamp with time zone,timestamp with time zone)'::regprocedure,
  $old$v_nuit := v_nuit + 0.5;$old$,
  $new$v_nuit := v_nuit + v_duree;$new$
);
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_calculer_heures_majorees(timestamp with time zone,timestamp with time zone)'::regprocedure,
  $old$v_dim := v_dim + 0.5;$old$,
  $new$v_dim := v_dim + v_duree;$new$
);
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_calculer_heures_majorees(timestamp with time zone,timestamp with time zone)'::regprocedure,
  $old$v_fer := v_fer + 0.5;$old$,
  $new$v_fer := v_fer + v_duree;$new$
);

-- La fonction lit jours_feries_fr : STABLE, et non IMMUTABLE.
ALTER FUNCTION public.fn_calculer_heures_majorees(
  timestamp with time zone,
  timestamp with time zone
) STABLE;
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_calculer_remuneration_mission(timestamp with time zone,timestamp with time zone,numeric,uuid,uuid)'::regprocedure,
  $old$v_contrat type_contrat := 'CDD';$old$,
  $new$v_contrat public.type_contrat := 'CDD'::public.type_contrat;$new$
);

-- 7. Score soignant : les notations multi-criteres vivent dans
-- notations_missions ; note_id est la cible et masque le flag de moderation.
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_calculer_score_soignant(uuid)'::regprocedure,
  $old$SELECT AVG(note), COUNT(*) INTO v_note_moyenne, v_note_count
  FROM public.notations
  WHERE cible_id = p_soignant_id AND cible_type = 'SOIGNANT'
    AND masquee_par_admin IS NOT TRUE
    AND cree_le > NOW() - INTERVAL '12 months';$old$,
  $new$SELECT
    AVG((n.critere_1 + n.critere_2 + n.critere_3 + n.critere_4) / 4.0),
    COUNT(*)
  INTO v_note_moyenne, v_note_count
  FROM public.notations_missions n
  WHERE n.note_id = p_soignant_id
    AND n.sens = 'ETAB_VERS_SOIGNANT'::public.sens_notation
    AND n.masque IS NOT TRUE
    AND n.publie_le IS NOT NULL
    AND n.cree_le > NOW() - INTERVAL '12 months';$new$
);

-- 8. Jeu de demonstration : l'ancien seed n'est plus rejouable (SIRET fixes,
-- colonnes obligatoires et missions PHARMACIEN incompatibles avec la matrice
-- de conformite). La RPC devient volontairement non destructive : elle
-- conserve les comptes de test deja presents pour les captures Store et en
-- retourne simplement l'inventaire. Aucun enregistrement de test n'est masque.
CREATE OR REPLACE FUNCTION public.fn_charger_demo_investisseur()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $demo$
DECLARE
  v_etablissements integer;
  v_soignants integer;
  v_missions integer;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('error', 'Acces refuse');
  END IF;

  SELECT COUNT(*)::integer
    INTO v_etablissements
    FROM public.etablissements
   WHERE est_compte_test IS TRUE;

  SELECT COUNT(*)::integer
    INTO v_soignants
    FROM public.soignants
   WHERE est_compte_test IS TRUE;

  SELECT COUNT(*)::integer
    INTO v_missions
    FROM public.missions m
    LEFT JOIN public.etablissements e ON e.id = m.etablissement_id
    LEFT JOIN public.soignants s ON s.id = m.soignant_assigne_id
   WHERE COALESCE(e.est_compte_test, false)
      OR COALESCE(s.est_compte_test, false);

  RETURN jsonb_build_object(
    'success', true,
    'mode', 'PRESERVATION',
    'message', 'Donnees de demonstration existantes conservees',
    'etablissements', v_etablissements,
    'soignants', v_soignants,
    'missions', v_missions
  );
END;
$demo$;

-- 9. Variable jamais lue.
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_commission_info_etablissement()'::regprocedure,
  $old$    v_palier RECORD;
$old$,
  $new$$new$
);
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_commission_info_etablissement()'::regprocedure,
  $old$    v_missions_mois INT;$old$,
  $new$    v_missions_mois INT;
    v_etab_id uuid;$new$
);
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_commission_info_etablissement()'::regprocedure,
  $old$BEGIN
    SELECT e.*, p.nom AS palier_nom FROM etablissements e$old$,
  $new$BEGIN
    IF auth.uid() IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
      RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    v_etab_id := public.mon_etablissement_id();
    IF v_etab_id IS NULL
       OR public.fn_a_permission_etablissement(
         'lecture_paiement', v_etab_id
       ) IS NOT TRUE THEN
      RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    SELECT e.*, p.nom AS palier_nom FROM etablissements e$new$
);
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_commission_info_etablissement()'::regprocedure,
  $old$INTO v_etab WHERE e.id = mon_etablissement_id();$old$,
  $new$INTO v_etab WHERE e.id = v_etab_id;$new$
);

-- 10. Tableau UUID vide explicitement type.
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_creer_serie(text,text,type_profession,text,numeric,boolean,integer,jsonb)'::regprocedure,
  $old$v_created_ids uuid[] := '{}';$old$,
  $new$v_created_ids uuid[] := ARRAY[]::uuid[];$new$
);

-- 11. La fonction retourne une adresse email, pas un telephone.
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_email_factures_impayees()'::regprocedure,
  $old$SELECT e.telephone, e.nom, f.numero_facture,$old$,
  $new$SELECT e.email_contact, e.nom, f.numero_facture,$new$
);
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_email_factures_impayees()'::regprocedure,
  $old$EXTRACT(DAY FROM NOW() - f.cree_le)::INTEGER, e.id$old$,
  $new$(CURRENT_DATE - f.date_echeance)::INTEGER, e.id$new$
);
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_email_factures_impayees()'::regprocedure,
  $old$WHERE f.statut = 'EMISE'
      AND f.cree_le + INTERVAL '15 days' < NOW()$old$,
  $new$WHERE f.statut IN ('EMISE', 'EN_RETARD')
      AND f.date_echeance < CURRENT_DATE
      AND e.email_contact IS NOT NULL$new$
);

-- 12. Rappels de notation : meme correction de secret que le flux admin.
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_envoyer_rappels_notation_j1()'::regprocedure,
  $old$v_url := public.fn_lire_secret_cron('supabase_url');$old$,
  $new$v_url := 'https://flripxtsyegjshnhzjkz.supabase.co';$new$
);
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_envoyer_rappels_notation_j1()'::regprocedure,
  $old$v_token := public.fn_lire_secret_cron('service_role_key');$old$,
  $new$v_token := public.fn_lire_secret_cron();$new$
);
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_envoyer_rappels_notation_j1()'::regprocedure,
  $old$      INSERT INTO notifications_notation_j1 (mission_id, sens, destinataire_id)
      VALUES (v_mission.id, 'ETAB_VERS_SOIGNANT', v_mission.etablissement_id)
      ON CONFLICT (mission_id, sens) DO NOTHING;

      PERFORM public.fn_ecrire_audit_safe(
        p_acteur_id := v_mission.etablissement_id, p_type_acteur := 'SYSTEME',
        p_action := 'RAPPEL_NOTATION_J1_ENVOYE', p_type_ressource := 'mission', p_id_ressource := v_mission.id,
        p_details := jsonb_build_object('sens', 'ETAB_VERS_SOIGNANT', 'send_email_called', v_send_email_called)
      );
      v_count_etab := v_count_etab + 1;$old$,
  $new$      IF v_send_email_called THEN
        INSERT INTO notifications_notation_j1 (mission_id, sens, destinataire_id)
        VALUES (v_mission.id, 'ETAB_VERS_SOIGNANT', v_mission.etablissement_id)
        ON CONFLICT (mission_id, sens) DO NOTHING;

        PERFORM public.fn_ecrire_audit_safe(
          p_acteur_id := v_mission.etablissement_id, p_type_acteur := 'SYSTEME',
          p_action := 'RAPPEL_NOTATION_J1_ENVOYE', p_type_ressource := 'mission', p_id_ressource := v_mission.id,
          p_details := jsonb_build_object('sens', 'ETAB_VERS_SOIGNANT', 'send_email_called', true)
        );
        v_count_etab := v_count_etab + 1;
      END IF;$new$
);
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_envoyer_rappels_notation_j1()'::regprocedure,
  $old$      INSERT INTO notifications_notation_j1 (mission_id, sens, destinataire_id)
      VALUES (v_mission.id, 'SOIGNANT_VERS_ETAB', v_mission.soignant_assigne_id)
      ON CONFLICT (mission_id, sens) DO NOTHING;

      PERFORM public.fn_ecrire_audit_safe(
        p_acteur_id := v_mission.soignant_assigne_id, p_type_acteur := 'SYSTEME',
        p_action := 'RAPPEL_NOTATION_J1_ENVOYE', p_type_ressource := 'mission', p_id_ressource := v_mission.id,
        p_details := jsonb_build_object('sens', 'SOIGNANT_VERS_ETAB', 'send_email_called', v_send_email_called)
      );
      v_count_soignant := v_count_soignant + 1;$old$,
  $new$      IF v_send_email_called THEN
        INSERT INTO notifications_notation_j1 (mission_id, sens, destinataire_id)
        VALUES (v_mission.id, 'SOIGNANT_VERS_ETAB', v_mission.soignant_assigne_id)
        ON CONFLICT (mission_id, sens) DO NOTHING;

        PERFORM public.fn_ecrire_audit_safe(
          p_acteur_id := v_mission.soignant_assigne_id, p_type_acteur := 'SYSTEME',
          p_action := 'RAPPEL_NOTATION_J1_ENVOYE', p_type_ressource := 'mission', p_id_ressource := v_mission.id,
          p_details := jsonb_build_object('sens', 'SOIGNANT_VERS_ETAB', 'send_email_called', true)
        );
        v_count_soignant := v_count_soignant + 1;
      END IF;$new$
);

-- 13. Variable jamais lue.
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_modifier_preferences_notifications(boolean,boolean,boolean,boolean,jsonb)'::regprocedure,
  $old$  v_old jsonb;
$old$,
  $new$$new$
);

-- 14. Alerte fraude parrainage : destinataires depuis la source admin canonique
-- et valeur ADMIN conforme a la contrainte notifications_type_destinataire.
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_parrainage_verifier_seuils(uuid)'::regprocedure,
  $old$INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
    SELECT id, 'ADMIN_PLATEFORME', 'SYSTEM', 'Parrainage fraude détectée',
      'Parrainage ' || v_p.id::text || ' : même IP parrain/filleul. Versement bloqué.', '/admin/utilisateurs'
    FROM soignants WHERE role = 'ADMIN_PLATEFORME' LIMIT 3;$old$,
  $new$INSERT INTO public.notifications (
      destinataire_id, type_destinataire, type, titre, corps, lien
    )
    SELECT
      admin_user_id,
      'ADMIN',
      'SYSTEM',
      'Parrainage fraude détectée',
      'Parrainage ' || v_p.id::text
        || ' : même IP parrain/filleul. Versement bloqué.',
      '/admin/utilisateurs'
    FROM public.fn_list_admin_user_ids() AS admins(admin_user_id);$new$
);

-- 15. Le numero externe est porte par soignants.prevoyance_numero_contrat ;
-- souscriptions_prevoyance ne contient pas cette colonne et utilise ACTIF.
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_souscrire_prevoyance(uuid,text)'::regprocedure,
  $old$INSERT INTO souscriptions_prevoyance (soignant_id, plan_id, numero_contrat_externe, statut)
    VALUES (auth.uid(), p_plan_id, p_numero_contrat, 'ACTIVE')
    ON CONFLICT DO NOTHING;$old$,
  $new$INSERT INTO public.souscriptions_prevoyance (soignant_id, plan_id, statut)
    VALUES (auth.uid(), p_plan_id, 'ACTIF')
    ON CONFLICT (soignant_id, plan_id) DO NOTHING;$new$
);
SELECT pg_temp.jolene_replace_function_fragment(
  'public.fn_souscrire_prevoyance(uuid,text)'::regprocedure,
  $old$BEGIN
    SELECT * INTO v_plan FROM plans_prevoyance$old$,
  $new$BEGIN
    IF auth.uid() IS NULL OR NOT EXISTS (
      SELECT 1
      FROM public.soignants s
      WHERE s.id = auth.uid()
        AND s.supprime_le IS NULL
    ) THEN
      RETURN jsonb_build_object('error', 'Acces refuse');
    END IF;

    SELECT * INTO v_plan FROM plans_prevoyance$new$
);

-- Le parcours livre utilise fn_inscrire_liste_attente_prevoyance. La
-- souscription directe n'est pas lancee : cette RPC legacy reste fermee pour
-- tous les roles API jusqu'a un parcours produit et paiement dedie.
REVOKE ALL ON FUNCTION public.fn_souscrire_prevoyance(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;

-- 16. La table admin_securite n'existe plus ; l'AAL2 est porte par Supabase Auth
-- et verifie par est_admin_valide(). Le registre equipe_admin vient d'etre ecrit
-- juste avant ce bloc, il reste l'unique registre applicatif necessaire.
SELECT pg_temp.jolene_replace_function_fragment(
  'private.fn_admin_creer_compte_employe_interne_lancement(text,text,text,text,text,numeric,text[])'::regprocedure,
  $old$INSERT INTO admin_securite (admin_id, email_2fa)
  VALUES (v_new_user_id, p_email)
  ON CONFLICT (admin_id) DO UPDATE SET email_2fa = EXCLUDED.email_2fa;

  $old$,
  $new$$new$
);

-- Assertions de migration : aucun fragment residuel connu ne doit survivre.
DO $assertions$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text, ', ')
    INTO v_bad
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE (n.nspname = 'public' OR n.nspname = 'private')
     AND (
       p.prosrc LIKE '%e.ville%'
       OR p.prosrc LIKE '%fn_lire_secret_cron(''supabase_url'')%'
       OR p.prosrc LIKE '%fn_lire_secret_cron(''service_role_key'')%'
       OR p.prosrc LIKE '%public.notations WHERE evaluateur_id%'
       OR p.prosrc LIKE '%excluant_id%'
       OR p.prosrc LIKE '%''BROUILLON''%'
       OR p.prosrc ~ 'FROM public[.]notations([[:space:]]|$)'
       OR p.prosrc LIKE '%''INFIRMIER_DE''::type_profession%'
       OR p.prosrc LIKE '%''AIDE_SOIGNANT''::type_profession%'
       OR p.prosrc LIKE '%''KINESITHERAPEUTE''::type_profession%'
       OR p.prosrc LIKE '%SELECT e.telephone, e.nom, f.numero_facture%'
       OR p.prosrc LIKE '%FROM soignants WHERE role = ''ADMIN_PLATEFORME''%'
       OR p.prosrc LIKE '%numero_contrat_externe%'
       OR p.prosrc LIKE '%INSERT INTO admin_securite%'
     )
     AND p.proname = ANY(ARRAY[
       'fn_admin_bfa_detail_groupe',
       'fn_admin_lever_suspension',
       'fn_admin_reset_test_account',
       'fn_annuler_mission',
       'fn_calculer_score_soignant',
       'fn_charger_demo_investisseur',
       'fn_email_factures_impayees',
       'fn_envoyer_rappels_notation_j1',
       'fn_parrainage_verifier_seuils',
       'fn_souscrire_prevoyance',
       'fn_admin_creer_compte_employe_interne_lancement'
     ]);

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Fragments lint residuels encore presents dans : %', v_bad;
  END IF;
END;
$assertions$;

DROP FUNCTION pg_temp.jolene_replace_function_fragment(
  regprocedure, text, text, integer
);
