-- Cockpit Fondateur — tables et RPC pour suivi stratégique, gestion équipe
-- admin, pipeline investisseurs et métriques d'acquisition/growth.

-- ═══════════════════════════════════════════════════════════
-- 1. Equipe admin — comptes employés avec permissions granulaires
-- ═══════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.equipe_admin (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid UNIQUE,
  nom text NOT NULL,
  prenom text NOT NULL,
  email text NOT NULL,
  poste text NOT NULL DEFAULT 'Opérations',
  salaire_brut_mensuel numeric(10,2) DEFAULT 0,
  date_embauche date,
  acces_groupes text[] NOT NULL DEFAULT ARRAY['Dashboard'],
  actif boolean NOT NULL DEFAULT true,
  cree_le timestamptz NOT NULL DEFAULT now(),
  maj_le timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.equipe_admin ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.equipe_admin IS
  'Registre des membres de l''équipe admin (fondatrice + futurs employés). user_id = lien auth.users si le compte existe.';

-- Seed : la fondatrice
INSERT INTO public.equipe_admin (user_id, nom, prenom, email, poste, date_embauche, acces_groupes)
VALUES (
  '09e82688-e524-42bb-9268-1384c757f33d',
  'Pcd', 'Gabrielle', 'gabrielle.pcd@outlook.com',
  'Fondatrice & CEO', '2025-01-01',
  ARRAY['Dashboard','Utilisateurs','Missions','Litiges & contrats','Finances','Messagerie','Conformité & Technique','Fondateur']
) ON CONFLICT (user_id) DO NOTHING;

-- ═══════════════════════════════════════════════════════════
-- 2. Pipeline investisseurs (CRM léger levée)
-- ═══════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.investisseurs_pipeline (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nom text NOT NULL,
  type text NOT NULL DEFAULT 'VC',
  contact_nom text,
  contact_email text,
  statut text NOT NULL DEFAULT 'A_CONTACTER'
    CHECK (statut IN ('A_CONTACTER','CONTACTE','INTRO_FAITE','PITCH','DUE_DILIGENCE','TERM_SHEET','SIGNE','DECLINE')),
  montant_vise numeric(12,2),
  notes text,
  derniere_interaction timestamptz,
  cree_le timestamptz NOT NULL DEFAULT now(),
  maj_le timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.investisseurs_pipeline ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.investisseurs_pipeline IS
  'CRM léger des investisseurs potentiels pour suivi pipeline levée de fonds.';

-- ═══════════════════════════════════════════════════════════
-- 3. Notes fondateur (docs/decks/business plans)
-- ═══════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.fondateur_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  titre text NOT NULL,
  categorie text NOT NULL DEFAULT 'NOTE'
    CHECK (categorie IN ('NOTE','BUSINESS_PLAN','DECK','FINANCIER','LEGAL','AUTRE')),
  contenu text,
  url_externe text,
  cree_le timestamptz NOT NULL DEFAULT now(),
  maj_le timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.fondateur_documents ENABLE ROW LEVEL SECURITY;

-- ═══════════════════════════════════════════════════════════
-- 4. RPC : métriques cockpit fondateur
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_admin_cockpit_fondateur()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
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
  -- Vérifier admin
  IF NOT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = auth.uid()
    AND raw_app_meta_data->>'role' = 'ADMIN_PLATEFORME'
  ) THEN
    RAISE EXCEPTION 'Accès admin requis';
  END IF;

  -- Utilisateurs
  SELECT count(*) INTO v_total_soignants FROM soignants;
  SELECT count(*) INTO v_total_etabs FROM etablissements WHERE supprime_le IS NULL;
  SELECT count(*) INTO v_soignants_7j FROM soignants WHERE cree_le >= now() - interval '7 days';
  SELECT count(*) INTO v_etabs_7j FROM etablissements WHERE cree_le >= now() - interval '7 days' AND supprime_le IS NULL;
  SELECT count(*) INTO v_soignants_30j FROM soignants WHERE cree_le >= now() - interval '30 days';
  SELECT count(*) INTO v_etabs_30j FROM etablissements WHERE cree_le >= now() - interval '30 days' AND supprime_le IS NULL;

  -- Missions
  SELECT count(*) INTO v_missions_terminees FROM missions WHERE statut = 'TERMINEE';
  SELECT count(*) INTO v_missions_mois FROM missions
    WHERE statut = 'TERMINEE' AND date_debut >= date_trunc('month', now());

  -- Revenue
  SELECT coalesce(sum(total_brut), 0) INTO v_gmv_total FROM missions WHERE statut = 'TERMINEE';
  SELECT coalesce(sum(montant_commission_ht), 0) INTO v_revenue_total
    FROM missions WHERE statut = 'TERMINEE' AND montant_commission_ht IS NOT NULL;
  SELECT coalesce(sum(montant_commission_ht), 0) INTO v_revenue_mois
    FROM missions
    WHERE statut = 'TERMINEE' AND montant_commission_ht IS NOT NULL
    AND date_debut >= date_trunc('month', now());

  -- Taux d'activation (soignant ayant au moins 1 candidature / total)
  SELECT CASE WHEN v_total_soignants = 0 THEN 0 ELSE
    round(100.0 * (SELECT count(DISTINCT soignant_id) FROM candidatures) / v_total_soignants, 1)
  END INTO v_taux_activation_soignant;

  -- Taux d'activation étab (étab ayant au moins 1 mission publiée / total)
  SELECT CASE WHEN v_total_etabs = 0 THEN 0 ELSE
    round(100.0 * (SELECT count(DISTINCT etablissement_id) FROM missions) / v_total_etabs, 1)
  END INTO v_taux_activation_etab;

  -- Acquisition mensuelle (12 derniers mois)
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

  -- Revenue mensuel (12 derniers mois)
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
        AND date_trunc('month', mi.date_debut) = m.mois
      ), 0) AS revenue_ht,
      coalesce((
        SELECT sum(mi.total_brut)
        FROM missions mi
        WHERE mi.statut = 'TERMINEE'
        AND date_trunc('month', mi.date_debut) = m.mois
      ), 0) AS gmv
    FROM generate_series(
      date_trunc('month', now()) - interval '11 months',
      date_trunc('month', now()),
      interval '1 month'
    ) AS m(mois)
  ) t;

  -- Charges équipe (salaires bruts mensuels * coeff charges patronales ~1.45)
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
$body$;
