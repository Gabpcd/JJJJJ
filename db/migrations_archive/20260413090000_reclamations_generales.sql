-- Table de réclamations générales (soignants ET établissements)
-- Distincte de reclamations_scoring qui est spécifique aux contestations
-- de pénalités de score fiabilité.

CREATE TABLE IF NOT EXISTS public.reclamations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  utilisateur_id UUID NOT NULL REFERENCES auth.users(id),
  type_utilisateur TEXT NOT NULL CHECK (type_utilisateur IN ('SOIGNANT', 'ETABLISSEMENT')),
  categorie TEXT NOT NULL CHECK (categorie IN ('MISSION', 'PAIEMENT', 'TECHNIQUE', 'COMPORTEMENT', 'AUTRE')),
  sujet TEXT NOT NULL,
  details TEXT NOT NULL,
  mission_id UUID REFERENCES public.missions(id),
  statut TEXT NOT NULL DEFAULT 'EN_ATTENTE' CHECK (statut IN ('EN_ATTENTE', 'EN_COURS', 'RESOLUE', 'FERMEE')),
  priorite TEXT NOT NULL DEFAULT 'NORMALE' CHECK (priorite IN ('BASSE', 'NORMALE', 'HAUTE')),
  reponse_admin TEXT,
  traite_par UUID REFERENCES auth.users(id),
  traite_le TIMESTAMPTZ,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index pour les requêtes admin et utilisateur
CREATE INDEX IF NOT EXISTS idx_reclamations_utilisateur ON public.reclamations(utilisateur_id);
CREATE INDEX IF NOT EXISTS idx_reclamations_statut ON public.reclamations(statut);
CREATE INDEX IF NOT EXISTS idx_reclamations_cree_le ON public.reclamations(cree_le DESC);

-- RLS
ALTER TABLE public.reclamations ENABLE ROW LEVEL SECURITY;

-- Policies idempotentes (DROP IF EXISTS avant CREATE)
DROP POLICY IF EXISTS "reclamations_select_own" ON public.reclamations;
CREATE POLICY "reclamations_select_own" ON public.reclamations
  FOR SELECT TO authenticated
  USING (utilisateur_id = auth.uid() OR est_admin());

DROP POLICY IF EXISTS "reclamations_insert_own" ON public.reclamations;
CREATE POLICY "reclamations_insert_own" ON public.reclamations
  FOR INSERT TO authenticated
  WITH CHECK (utilisateur_id = auth.uid());

DROP POLICY IF EXISTS "reclamations_update_admin" ON public.reclamations;
CREATE POLICY "reclamations_update_admin" ON public.reclamations
  FOR UPDATE TO authenticated
  USING (est_admin());

-- RPC pour soumettre une réclamation (audit trail inclus)
CREATE OR REPLACE FUNCTION public.fn_soumettre_reclamation(
  p_categorie TEXT,
  p_sujet TEXT,
  p_details TEXT,
  p_mission_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_role TEXT;
  v_type TEXT;
  v_reclamation_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  -- Déterminer le type d'utilisateur
  SELECT raw_app_meta_data ->> 'role' INTO v_role
  FROM auth.users WHERE id = v_user_id;

  IF v_role IN ('SOIGNANT') THEN
    v_type := 'SOIGNANT';
  ELSIF v_role IN ('ADMIN_ETABLISSEMENT', 'ETABLISSEMENT') THEN
    v_type := 'ETABLISSEMENT';
  ELSE
    RETURN jsonb_build_object('error', 'Rôle non autorisé');
  END IF;

  INSERT INTO reclamations (utilisateur_id, type_utilisateur, categorie, sujet, details, mission_id)
  VALUES (v_user_id, v_type, p_categorie, p_sujet, p_details, p_mission_id)
  RETURNING id INTO v_reclamation_id;

  -- Audit RGPD
  PERFORM fn_ecrire_audit_safe(
    v_user_id, v_type, 'RECLAMATION_CREEE',
    'reclamation', v_reclamation_id, NULL,
    jsonb_build_object('categorie', p_categorie, 'sujet', p_sujet),
    NULL, NULL
  );

  RETURN jsonb_build_object('id', v_reclamation_id, 'statut', 'EN_ATTENTE');
END;
$$;

-- RPC admin pour traiter une réclamation générale
CREATE OR REPLACE FUNCTION public.fn_traiter_reclamation_generale(
  p_reclamation_id UUID,
  p_statut TEXT,
  p_reponse TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_admin_id UUID := auth.uid();
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès réservé aux administrateurs');
  END IF;

  UPDATE reclamations
  SET statut = p_statut,
      reponse_admin = COALESCE(p_reponse, reponse_admin),
      traite_par = v_admin_id,
      traite_le = now()
  WHERE id = p_reclamation_id;

  RETURN jsonb_build_object('ok', true);
END;
$$;
