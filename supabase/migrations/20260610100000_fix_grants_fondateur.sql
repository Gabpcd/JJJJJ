-- Fix critique module Fondateur : GRANTs manquants + 2 RPCs cassées.
--
-- 1) Les tables/fonctions créées via MCP apply_migration n'héritent PAS des
--    privilèges par défaut Supabase → relacl NULL → "permission denied" pour
--    authenticated → l'UI affichait 0 partout (groupes, templates, équipe) et
--    "Erreur de chargement" (RPCs). La RLS (est_admin()) reste la barrière de
--    sécurité ; les GRANTs sont le prérequis d'accès.
-- 2) fn_admin_cockpit_fondateur référençait missions.date_debut (inexistant) →
--    debut_le. fn_admin_lister_etablissements ne castait pas les enums/varchar.
-- 3) fn_admin_mes_acces : la fondatrice (poste ILIKE '%fondat%') a toujours
--    accès total, même présente dans equipe_admin (sinon fragile à chaque
--    nouvel onglet de nav).

-- ── GRANTs tables ──
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sales_groupes TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sales_contacts TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sales_templates TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.equipe_admin TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.investisseurs_pipeline TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fondateur_documents TO authenticated, service_role;

-- ── fn_admin_cockpit_fondateur : date_debut → debut_le ──
CREATE OR REPLACE FUNCTION public.fn_admin_cockpit_fondateur()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
  v_total_soignants int;
  v_total_etabs int;
  v_soignants_7j int;
  v_etabs_7j int;
  v_soignants_30j int;
  v_etabs_30j int;
  v_missions_terminees int;
  v_missions_mois int;
  v_gmv_total numeric;
  v_revenue_total numeric;
  v_revenue_mois numeric;
  v_taux_activation_soignant numeric;
  v_taux_activation_etab numeric;
  v_acquisition_mensuelle jsonb;
  v_revenue_mensuel jsonb;
  v_charges_equipe numeric;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = auth.uid()
    AND raw_app_meta_data->>'role' = 'ADMIN_PLATEFORME'
  ) THEN
    RAISE EXCEPTION 'Accès admin requis';
  END IF;

  SELECT count(*) INTO v_total_soignants FROM soignants;
  SELECT count(*) INTO v_total_etabs FROM etablissements WHERE supprime_le IS NULL;
  SELECT count(*) INTO v_soignants_7j FROM soignants WHERE cree_le >= now() - interval '7 days';
  SELECT count(*) INTO v_etabs_7j FROM etablissements WHERE cree_le >= now() - interval '7 days' AND supprime_le IS NULL;
  SELECT count(*) INTO v_soignants_30j FROM soignants WHERE cree_le >= now() - interval '30 days';
  SELECT count(*) INTO v_etabs_30j FROM etablissements WHERE cree_le >= now() - interval '30 days' AND supprime_le IS NULL;

  SELECT count(*) INTO v_missions_terminees FROM missions WHERE statut = 'TERMINEE';
  SELECT count(*) INTO v_missions_mois FROM missions
    WHERE statut = 'TERMINEE' AND debut_le >= date_trunc('month', now());

  SELECT coalesce(sum(total_brut), 0) INTO v_gmv_total FROM missions WHERE statut = 'TERMINEE';
  SELECT coalesce(sum(montant_commission_ht), 0) INTO v_revenue_total
    FROM missions WHERE statut = 'TERMINEE' AND montant_commission_ht IS NOT NULL;
  SELECT coalesce(sum(montant_commission_ht), 0) INTO v_revenue_mois
    FROM missions
    WHERE statut = 'TERMINEE' AND montant_commission_ht IS NOT NULL
    AND debut_le >= date_trunc('month', now());

  SELECT CASE WHEN v_total_soignants = 0 THEN 0 ELSE
    round(100.0 * (SELECT count(DISTINCT soignant_id) FROM candidatures) / v_total_soignants, 1)
  END INTO v_taux_activation_soignant;

  SELECT CASE WHEN v_total_etabs = 0 THEN 0 ELSE
    round(100.0 * (SELECT count(DISTINCT etablissement_id) FROM missions) / v_total_etabs, 1)
  END INTO v_taux_activation_etab;

  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.mois), '[]'::jsonb)
  INTO v_acquisition_mensuelle
  FROM (
    SELECT
      to_char(m.mois, 'YYYY-MM') AS mois,
      (SELECT count(*) FROM soignants s WHERE date_trunc('month', s.cree_le) = m.mois) AS soignants,
      (SELECT count(*) FROM etablissements e WHERE date_trunc('month', e.cree_le) = m.mois AND e.supprime_le IS NULL) AS etablissements
    FROM generate_series(
      date_trunc('month', now()) - interval '11 months',
      date_trunc('month', now()),
      interval '1 month'
    ) AS m(mois)
  ) t;

  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.mois), '[]'::jsonb)
  INTO v_revenue_mensuel
  FROM (
    SELECT
      to_char(m.mois, 'YYYY-MM') AS mois,
      coalesce((
        SELECT sum(mi.montant_commission_ht)
        FROM missions mi
        WHERE mi.statut = 'TERMINEE'
        AND mi.montant_commission_ht IS NOT NULL
        AND date_trunc('month', mi.debut_le) = m.mois
      ), 0) AS revenue_ht,
      coalesce((
        SELECT sum(mi.total_brut)
        FROM missions mi
        WHERE mi.statut = 'TERMINEE'
        AND date_trunc('month', mi.debut_le) = m.mois
      ), 0) AS gmv
    FROM generate_series(
      date_trunc('month', now()) - interval '11 months',
      date_trunc('month', now()),
      interval '1 month'
    ) AS m(mois)
  ) t;

  SELECT coalesce(sum(salaire_brut_mensuel * 1.45), 0)
  INTO v_charges_equipe
  FROM equipe_admin WHERE actif = true AND salaire_brut_mensuel > 0;

  v_result := jsonb_build_object(
    'total_soignants', v_total_soignants,
    'total_etabs', v_total_etabs,
    'soignants_7j', v_soignants_7j,
    'etabs_7j', v_etabs_7j,
    'soignants_30j', v_soignants_30j,
    'etabs_30j', v_etabs_30j,
    'missions_terminees', v_missions_terminees,
    'missions_mois', v_missions_mois,
    'gmv_total', v_gmv_total,
    'revenue_total', v_revenue_total,
    'revenue_mois', v_revenue_mois,
    'taux_activation_soignant', v_taux_activation_soignant,
    'taux_activation_etab', v_taux_activation_etab,
    'acquisition_mensuelle', v_acquisition_mensuelle,
    'revenue_mensuel', v_revenue_mensuel,
    'charges_equipe_mensuel', v_charges_equipe
  );

  RETURN v_result;
END;
$function$;

-- ── fn_admin_lister_etablissements : casts enums/varchar → text ──
CREATE OR REPLACE FUNCTION public.fn_admin_lister_etablissements(p_recherche text DEFAULT NULL)
RETURNS TABLE (
  id uuid,
  nom text,
  type text,
  ville text,
  code_postal text,
  telephone text,
  email text,
  statut_verification text,
  peut_publier boolean,
  cree_le timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Accès admin requis';
  END IF;

  RETURN QUERY
  SELECT e.id, e.nom::text, e.type::text, e.adresse_ville::text, e.adresse_code_postal::text,
         e.telephone_contact::text, e.email_contact::text, e.statut_verification::text,
         e.peut_publier_missions, e.cree_le
  FROM public.etablissements e
  WHERE e.supprime_le IS NULL
    AND (p_recherche IS NULL OR p_recherche = ''
         OR e.nom ILIKE '%' || p_recherche || '%'
         OR e.adresse_ville ILIKE '%' || p_recherche || '%')
  ORDER BY e.cree_le DESC
  LIMIT 500;
END;
$body$;

-- ── fn_admin_mes_acces : fondatrice → accès total même dans equipe_admin ──
CREATE OR REPLACE FUNCTION public.fn_admin_mes_acces()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid;
  v_role text;
  v_groupes text[];
  v_actif boolean;
  v_poste text;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  SELECT raw_app_meta_data->>'role' INTO v_role
  FROM auth.users WHERE id = v_uid;

  IF v_role <> 'ADMIN_PLATEFORME' THEN
    RAISE EXCEPTION 'Accès admin requis';
  END IF;

  SELECT acces_groupes, actif, poste INTO v_groupes, v_actif, v_poste
  FROM equipe_admin WHERE user_id = v_uid;

  IF v_groupes IS NULL OR v_poste ILIKE '%fondat%' THEN
    RETURN jsonb_build_object('acces_total', true, 'groupes', '[]'::jsonb, 'actif', true);
  END IF;

  IF NOT v_actif THEN
    RAISE EXCEPTION 'Compte désactivé';
  END IF;

  RETURN jsonb_build_object('acces_total', false, 'groupes', to_jsonb(v_groupes), 'actif', v_actif);
END;
$body$;

-- ── GRANTs EXECUTE sur les RPCs admin (le trigger auto-revoke retire anon/public,
--    authenticated doit être explicite) ──
GRANT EXECUTE ON FUNCTION public.fn_admin_cockpit_fondateur() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_acquisition_canaux(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_lister_etablissements(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_mes_acces() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_creer_compte_employe(text, text, text, text, text, numeric, text[]) TO authenticated;
