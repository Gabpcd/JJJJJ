-- Signalement d'un utilisateur à l'administration Jolene (avec motif obligatoire).
--
-- Permet à un soignant OU un établissement de signaler un autre utilisateur
-- (comportement, fraude suspectée, faux document, etc.) à l'admin, en précisant un
-- motif. Crée un enregistrement traçable + notifie les admins.

CREATE TABLE IF NOT EXISTS public.signalements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  signaleur_id uuid NOT NULL,
  signaleur_type text NOT NULL CHECK (signaleur_type IN ('SOIGNANT','ETABLISSEMENT')),
  cible_id uuid NOT NULL,
  cible_type text NOT NULL CHECK (cible_type IN ('SOIGNANT','ETABLISSEMENT')),
  categorie text NOT NULL CHECK (categorie IN (
    'COMPORTEMENT_INAPPROPRIE','FRAUDE_SUSPECTEE','FAUX_DOCUMENT',
    'NON_PROFESSIONNALISME','SECURITE_DANGER','USURPATION_IDENTITE','AUTRE'
  )),
  motif text NOT NULL,
  mission_id uuid,
  statut text NOT NULL DEFAULT 'OUVERT' CHECK (statut IN ('OUVERT','EN_COURS','TRAITE','REJETE')),
  resolution text,
  traite_par uuid,
  traite_le timestamptz,
  cree_le timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_signalements_statut ON public.signalements(statut, cree_le DESC);
CREATE INDEX IF NOT EXISTS idx_signalements_cible ON public.signalements(cible_id);

ALTER TABLE public.signalements ENABLE ROW LEVEL SECURITY;

-- Le signaleur voit ses propres signalements ; les admins voient tout.
DROP POLICY IF EXISTS pol_signalements_select ON public.signalements;
CREATE POLICY pol_signalements_select ON public.signalements FOR SELECT
  USING (signaleur_id = auth.uid() OR public.est_admin());

-- Seuls les admins modifient (traitement). Création via la RPC SECURITY DEFINER.
DROP POLICY IF EXISTS pol_signalements_update ON public.signalements;
CREATE POLICY pol_signalements_update ON public.signalements FOR UPDATE
  USING (public.est_admin()) WITH CHECK (public.est_admin());

-- RPC de création : valide, insère, notifie les admins.
CREATE OR REPLACE FUNCTION public.fn_signaler_utilisateur(
  p_cible_id uuid,
  p_cible_type text,
  p_categorie text,
  p_motif text,
  p_mission_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_signaleur_type text;
  v_id uuid;
  v_admin RECORD;
BEGIN
  IF v_me IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;
  IF p_cible_type NOT IN ('SOIGNANT','ETABLISSEMENT') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cible invalide');
  END IF;
  IF p_categorie IS NULL OR p_categorie NOT IN (
    'COMPORTEMENT_INAPPROPRIE','FRAUDE_SUSPECTEE','FAUX_DOCUMENT',
    'NON_PROFESSIONNALISME','SECURITE_DANGER','USURPATION_IDENTITE','AUTRE'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Catégorie invalide');
  END IF;
  IF p_motif IS NULL OR length(trim(p_motif)) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Motif obligatoire (10 caractères minimum).');
  END IF;
  IF p_cible_id = v_me THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous ne pouvez pas vous signaler vous-même.');
  END IF;

  -- Déterminer le type du signaleur
  IF EXISTS (SELECT 1 FROM soignants WHERE id = v_me) THEN
    v_signaleur_type := 'SOIGNANT';
  ELSIF EXISTS (SELECT 1 FROM etablissements WHERE id = v_me) THEN
    v_signaleur_type := 'ETABLISSEMENT';
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Profil signaleur inconnu');
  END IF;

  INSERT INTO public.signalements (signaleur_id, signaleur_type, cible_id, cible_type, categorie, motif, mission_id)
  VALUES (v_me, v_signaleur_type, p_cible_id, p_cible_type, p_categorie, trim(p_motif), p_mission_id)
  RETURNING id INTO v_id;

  -- Notifier tous les admins plateforme (in-app).
  FOR v_admin IN
    SELECT id FROM auth.users WHERE raw_app_meta_data->>'role' = 'ADMIN_PLATEFORME'
  LOOP
    INSERT INTO public.notifications (destinataire_id, type_destinataire, type, titre, corps, type_ressource, id_ressource)
    VALUES (
      v_admin.id, 'ADMIN', 'SYSTEM',
      '🚩 Nouveau signalement utilisateur',
      'Un ' || lower(v_signaleur_type) || ' a signalé un ' || lower(p_cible_type)
        || ' (' || p_categorie || ').',
      'signalement', v_id
    );
  END LOOP;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_me, p_type_acteur := v_signaleur_type,
    p_action := 'SIGNALEMENT_UTILISATEUR', p_type_ressource := 'signalement', p_id_ressource := v_id,
    p_details := jsonb_build_object('cible_id', p_cible_id, 'cible_type', p_cible_type, 'categorie', p_categorie)
  );

  RETURN jsonb_build_object('success', true, 'signalement_id', v_id);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_signaler_utilisateur(uuid, text, text, text, uuid) TO authenticated;

-- RPC admin : lister les signalements (file de modération).
CREATE OR REPLACE FUNCTION public.fn_admin_lister_signalements(p_statut text DEFAULT NULL)
RETURNS SETOF public.signalements
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT * FROM public.signalements
  WHERE public.est_admin()
    AND (p_statut IS NULL OR statut = p_statut)
  ORDER BY cree_le DESC;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_admin_lister_signalements(text) TO authenticated;

-- RPC admin : traiter un signalement.
CREATE OR REPLACE FUNCTION public.fn_admin_traiter_signalement(p_id uuid, p_statut text, p_resolution text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;
  IF p_statut NOT IN ('OUVERT','EN_COURS','TRAITE','REJETE') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Statut invalide');
  END IF;
  UPDATE public.signalements
  SET statut = p_statut, resolution = p_resolution,
      traite_par = auth.uid(),
      traite_le = CASE WHEN p_statut IN ('TRAITE','REJETE') THEN now() ELSE traite_le END
  WHERE id = p_id;
  RETURN jsonb_build_object('success', true);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_admin_traiter_signalement(uuid, text, text) TO authenticated;
