-- Lot 4 B1 (app iOS native) — score de matching inconnu = NULL dans le paquet de swipe.
--
-- fn_obtenir_missions_swipe renvoyait 'score', COALESCE(ms.score_global, 0) : une
-- mission sans ligne matching_scores (LEFT JOIN manquant) affichait « 0/100 », un
-- score fabriqué. matching_scores.score_global est NOT NULL (CHECK 0..100) : NULL
-- signifie donc exactement « aucun score calculé pour ce soignant et cette mission ».
-- Le web traite déjà null (src/components/swipe/MissionScore.test.tsx : ni « /100 »,
-- ni « Pourquoi », ni score vocal) ; le natif décode Int? et affiche la valeur serveur.
--
-- Seul changement : la ligne 'score' du payload. Le tri (tri aléatoire borné et
-- ORDER BY) garde COALESCE(ms.score_global, 0) : l'ordre du paquet est inchangé.
-- 'breakdown' reste COALESCE(ms.breakdown, '{}'). Aucun changement de signature,
-- d'attributs (SECURITY DEFINER, search_path), de propriétaire ni d'ACL :
-- CREATE OR REPLACE conserve les droits existants (authenticated, service_role).
--
-- Source : définition LIVE production relue en lecture seule le 02/11/2026
-- (pg_get_functiondef, garde-fou 9.0 n°2), identique à supabase/schema/public.sql :
-- md5(pg_get_functiondef) = 1d4708a06d88a43c10331d1a51e61edb, md5(prosrc) =
-- 8b9597449427a7fa639715b22c76a6a6 (= empreinte de l'inventaire SECURITY DEFINER).
-- La migration refuse de s'appliquer si cette définition a changé depuis.
--
-- B9 (redéfinition d'une fonction SECURITY DEFINER) : merge sur go explicite de
-- Gabrielle uniquement. Aucun texte exposé à l'utilisateur (HARD STOP n°4 : sans objet).

DO $avant_score_matching$
DECLARE
  v_oid oid := to_regprocedure('public.fn_obtenir_missions_swipe(integer)');
BEGIN
  IF v_oid IS NULL
     OR pg_catalog.md5(pg_catalog.pg_get_functiondef(v_oid)) IS DISTINCT FROM '1d4708a06d88a43c10331d1a51e61edb'
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc p
        WHERE p.oid = v_oid
          AND pg_catalog.md5(p.prosrc) = '8b9597449427a7fa639715b22c76a6a6'
          AND p.prosecdef
          AND pg_catalog.pg_get_userbyid(p.proowner) = 'postgres'
          AND COALESCE(p.proacl::text, '') = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
     )
     OR (SELECT count(*) FROM private.security_definer_inventory i
          WHERE i.signature IN ('fn_obtenir_missions_swipe(integer)', 'public.fn_obtenir_missions_swipe(integer)')) <> 1
     OR NOT EXISTS (
       SELECT 1 FROM private.security_definer_inventory i
        WHERE i.signature = 'fn_obtenir_missions_swipe(integer)'
          AND i.categorie = 'RPC_UTILISATEUR_AUTH_INTERNE'
          AND i.definition_md5 = '8b9597449427a7fa639715b22c76a6a6'
     )
  THEN
    RAISE EXCEPTION 'SCORE_MATCHING_SOURCE_DIVERGENTE : fn_obtenir_missions_swipe(integer) ne correspond plus à la définition LIVE relevée le 02/11/2026 ; repartir de la définition LIVE (scripts/dump-live-def.sh fonction fn_obtenir_missions_swipe).'
      USING ERRCODE = '55000';
  END IF;
END;
$avant_score_matching$;

CREATE OR REPLACE FUNCTION public.fn_obtenir_missions_swipe(p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_soignant public.soignants%ROWTYPE;
  v_missions jsonb;
  v_flag_pr boolean := (public.fn_param_num('feature_paiement_rapide_actif', 0) = 1);
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('missions', '[]'::jsonb, 'error', 'auth_required'); END IF;
  SELECT * INTO v_soignant FROM public.soignants WHERE id = v_uid;

  SELECT COALESCE(jsonb_agg(payload ORDER BY tri DESC), '[]'::jsonb)
    INTO v_missions
    FROM (
      SELECT (COALESCE(ms.score_global, 0) + floor(random() * 13))::int AS tri,
        jsonb_build_object(
          'mission_id', m.id,
          'intitule', m.intitule,
          'profession_requise', m.profession_requise,
          'etablissement_id', m.etablissement_id,
          'etablissement_nom', e.nom,
          'etablissement_ville', e.adresse_ville,
          'etablissement_code_postal', e.adresse_code_postal,
          'etablissement_logo_url', e.logo_url,
          'etablissement_score', e.score_qualite,
          'taux_horaire_base', m.taux_horaire_base,
          'duree_heures', m.duree_heures,
          'debut_le', m.debut_le,
          'fin_le', m.fin_le,
          'est_urgente', m.est_urgente,
          'service', m.service,
          'type_contrat_applique', m.type_contrat_applique,
          'type_contrat_recherche', m.type_contrat_recherche,
          'nb_creneaux', m.nb_creneaux,
          'total_brut', m.total_brut,
          'net_a_payer', m.net_a_payer,
          'net_estime', m.net_estime,
          'montant_ifm', COALESCE(m.montant_ifm, 0),
          'montant_icp', COALESCE(m.montant_icp, 0),
          'montant_majoration_nuit', COALESCE(m.montant_majoration_nuit, 0),
          'montant_majoration_dimanche', COALESCE(m.montant_majoration_dimanche, 0),
          'montant_majoration_ferie', COALESCE(m.montant_majoration_ferie, 0),
          'score', ms.score_global,
          'breakdown', COALESCE(ms.breakdown, '{}'::jsonb),
          'paiement_rapide', (
            v_flag_pr AND m.type_contrat_recherche = 'LIBERAL'
            AND e.mode_paiement_commission = 'SEPA_DEBIT'
            AND e.stripe_sepa_payment_method_id IS NOT NULL
            AND public.fn_escrow_etab_eligible(m.etablissement_id)
          ),
          'distance_km', CASE
            WHEN v_soignant.adresse_lat IS NOT NULL AND v_soignant.adresse_lng IS NOT NULL
             AND e.adresse_lat IS NOT NULL AND e.adresse_lng IS NOT NULL
            THEN round((public.fn_haversine_distance_m(
              v_soignant.adresse_lat, v_soignant.adresse_lng,
              e.adresse_lat, e.adresse_lng
            ) / 1000.0)::numeric, 1)
            ELSE NULL
          END
        ) AS payload
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      LEFT JOIN public.matching_scores ms ON ms.mission_id = m.id AND ms.soignant_id = v_uid
      WHERE m.statut = 'OUVERTE'
        AND m.debut_le > now()
        AND (COALESCE(e.est_compte_test, false) = false OR COALESCE(v_soignant.est_compte_test, false))
        AND (m.intitule NOT LIKE '[%' OR v_soignant.email LIKE 'playwright-%')
        AND public.fn_soignant_eligible_mission(v_uid, m.id, false)
        AND (v_soignant.taux_horaire_minimum IS NULL OR m.taux_horaire_base IS NULL
             OR m.taux_horaire_base >= v_soignant.taux_horaire_minimum)
        AND NOT EXISTS (
          SELECT 1 FROM public.swipes sw WHERE sw.soignant_id = v_uid AND sw.mission_id = m.id
        )
      ORDER BY COALESCE(ms.score_global, 0) DESC, m.est_urgente DESC, m.cree_le DESC
      LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 20), 100))
    ) q;

  RETURN jsonb_build_object('missions', v_missions);
END;
$function$;

-- L'inventaire SECURITY DEFINER suit le seul corps revu ; catégorie et
-- justification inchangées (RPC authentifiée, identité par auth.uid()).
UPDATE private.security_definer_inventory i
   SET definition_md5 = pg_catalog.md5(p.prosrc),
       recense_le = pg_catalog.now()
  FROM pg_catalog.pg_proc p
 WHERE p.oid = 'public.fn_obtenir_missions_swipe(integer)'::regprocedure
   AND i.signature = 'fn_obtenir_missions_swipe(integer)';

DO $apres_score_matching$
DECLARE
  v_oid oid := to_regprocedure('public.fn_obtenir_missions_swipe(integer)');
BEGIN
  IF v_oid IS NULL
     OR pg_catalog.md5(pg_catalog.pg_get_functiondef(v_oid)) IS DISTINCT FROM 'e1031b572d1bb8f397afd124783e192a'
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc p
        WHERE p.oid = v_oid
          AND pg_catalog.md5(p.prosrc) = '014d6b764e55730da0a614e919d64c10'
          AND p.prosecdef
          AND pg_catalog.pg_get_userbyid(p.proowner) = 'postgres'
          AND COALESCE(p.proacl::text, '') = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
     )
     OR (SELECT count(*) FROM private.security_definer_inventory i
          WHERE i.signature IN ('fn_obtenir_missions_swipe(integer)', 'public.fn_obtenir_missions_swipe(integer)')) <> 1
     OR NOT EXISTS (
       SELECT 1 FROM private.security_definer_inventory i
        WHERE i.signature = 'fn_obtenir_missions_swipe(integer)'
          AND i.categorie = 'RPC_UTILISATEUR_AUTH_INTERNE'
          AND i.definition_md5 = '014d6b764e55730da0a614e919d64c10'
     )
  THEN
    RAISE EXCEPTION 'SCORE_MATCHING_REDEFINITION_INCOMPLETE : corps, attributs, droits ou inventaire SECURITY DEFINER de fn_obtenir_missions_swipe(integer) inattendus après redéfinition.'
      USING ERRCODE = '55000';
  END IF;
END;
$apres_score_matching$;
