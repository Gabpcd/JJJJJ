-- Paramètres système éditables par l'admin plateforme (page Config).
CREATE TABLE IF NOT EXISTS public.parametres_systeme (
  cle text PRIMARY KEY,
  valeur numeric NOT NULL,
  label text NOT NULL,
  description text,
  unite text,
  val_min numeric,
  val_max numeric,
  categorie text NOT NULL DEFAULT 'GENERAL',
  avertissement text,
  cablee boolean NOT NULL DEFAULT true,   -- true = la valeur est réellement consommée par le code
  maj_le timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.parametres_systeme ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_parametres_systeme_admin ON public.parametres_systeme;
CREATE POLICY pol_parametres_systeme_admin ON public.parametres_systeme
  FOR ALL TO authenticated USING (public.est_admin()) WITH CHECK (public.est_admin());
GRANT ALL ON public.parametres_systeme TO authenticated, service_role;

-- Helper : lecture d'un paramètre numérique avec valeur par défaut (= valeur
-- actuelle codée en dur). Tant que l'admin ne change rien, comportement identique.
CREATE OR REPLACE FUNCTION public.fn_param_num(p_cle text, p_defaut numeric)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE((SELECT valeur FROM public.parametres_systeme WHERE cle = p_cle), p_defaut);
$$;

-- Lecture admin (page Config).
CREATE OR REPLACE FUNCTION public.fn_admin_lister_parametres()
RETURNS SETOF public.parametres_systeme LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.est_admin() THEN RAISE EXCEPTION 'Accès admin requis'; END IF;
  RETURN QUERY SELECT * FROM public.parametres_systeme ORDER BY categorie, label;
END; $$;

-- Écriture admin (avec bornes).
CREATE OR REPLACE FUNCTION public.fn_admin_maj_parametre(p_cle text, p_valeur numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v public.parametres_systeme;
BEGIN
  IF NOT public.est_admin() THEN RAISE EXCEPTION 'Accès admin requis'; END IF;
  SELECT * INTO v FROM public.parametres_systeme WHERE cle = p_cle;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Paramètre inconnu'); END IF;
  IF v.val_min IS NOT NULL AND p_valeur < v.val_min THEN
    RETURN jsonb_build_object('success', false, 'error', 'Valeur sous le minimum (' || v.val_min || ')'); END IF;
  IF v.val_max IS NOT NULL AND p_valeur > v.val_max THEN
    RETURN jsonb_build_object('success', false, 'error', 'Valeur au-dessus du maximum (' || v.val_max || ')'); END IF;
  UPDATE public.parametres_systeme SET valeur = p_valeur, maj_le = now() WHERE cle = p_cle;
  RETURN jsonb_build_object('success', true);
END; $$;

-- Seed avec les valeurs ACTUELLES.
INSERT INTO public.parametres_systeme (cle, valeur, label, description, unite, val_min, val_max, categorie, avertissement, cablee) VALUES
 ('commission_defaut_pct', 15, 'Commission par défaut', 'Taux de commission appliqué aux établissements sans taux négocié.', '%', 0, 100, 'FINANCE', 'Change le taux facturé. Vérifiez vos CGV (actuellement 15 %).', false),
 ('delai_paiement_prive_j', 30, 'Délai de paiement — privé', 'Échéance des factures pour les établissements privés.', 'jours', 1, 90, 'FINANCE', 'Encadré : le délai légal maximal du privé est 30 jours.', false),
 ('delai_paiement_public_j', 50, 'Délai de paiement — public', 'Échéance pour les établissements publics de santé.', 'jours', 1, 90, 'FINANCE', 'Encadré : 50 jours = maximum légal hôpitaux publics (Code commande publique L.2192-10). Ne pas dépasser.', false),
 ('seuil_blocage_retard_j', 15, 'Seuil de blocage (retard)', 'Jours de retard de paiement avant blocage automatique de l''établissement.', 'jours', 1, 120, 'RISQUE', NULL, false),
 ('delai_autovalidation_presence_h', 72, 'Auto-validation présences', 'Délai après lequel une présence non contestée est validée automatiquement.', 'heures', 1, 240, 'OPERATIONS', NULL, false),
 ('delai_relance_candidatures_h', 24, 'Relance candidatures', 'Délai avant de relancer l''établissement sur des candidatures en attente.', 'heures', 1, 168, 'OPERATIONS', NULL, true),
 ('quota_superlikes_jour', 5, 'Quota super-likes / jour', 'Nombre de super-likes autorisés par soignant et par jour (swipe).', '/jour', 0, 100, 'ENGAGEMENT', NULL, false),
 ('prime_parrainage_eur', 0, 'Prime de parrainage', 'Montant de la prime versée au parrain (soignant).', '€', 0, 1000, 'CROISSANCE', NULL, false),
 ('garantie_remplacement_prix_pct', 0, 'Prix garantie remplacement', 'Surcoût en % pour l''option garantie de remplacement.', '%', 0, 100, 'CROISSANCE', NULL, false),
 ('mission_boost_prix_ht', 0, 'Prix boost mission', 'Prix HT de l''option « booster » une mission.', '€ HT', 0, 1000, 'CROISSANCE', NULL, false)
ON CONFLICT (cle) DO NOTHING;
