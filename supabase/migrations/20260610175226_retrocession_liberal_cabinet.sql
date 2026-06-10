-- Fondation remplacement libéral en cabinet (dentistes/médecins) : le titulaire
-- encaisse les honoraires (feuilles de soins du remplacé) puis rétrocède au
-- remplaçant — contrat type Ordre. La mission porte mode_remuneration RETROCESSION
-- (% des honoraires) au lieu du taux horaire. RPC post-création
-- fn_definir_retrocession_mission(p_mission_id, p_pct) — pattern
-- fn_modifier_type_contrat_mission. Wiring formulaire/affichage : PR suivante.
-- NOTE : appliquée prod via MCP (version 20260610175226).
ALTER TABLE public.missions ADD COLUMN IF NOT EXISTS mode_remuneration text NOT NULL DEFAULT 'TAUX_HORAIRE'
  CHECK (mode_remuneration IN ('TAUX_HORAIRE','RETROCESSION'));
ALTER TABLE public.missions ADD COLUMN IF NOT EXISTS retrocession_pct numeric
  CHECK (retrocession_pct IS NULL OR (retrocession_pct > 0 AND retrocession_pct <= 100));

CREATE OR REPLACE FUNCTION public.fn_definir_retrocession_mission(p_mission_id uuid, p_pct numeric)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE v_m RECORD;
BEGIN
  SELECT * INTO v_m FROM missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_m.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF v_m.statut != 'OUVERTE' THEN
    RETURN jsonb_build_object('error', 'Modifiable uniquement sur une mission ouverte.');
  END IF;
  IF p_pct IS NULL OR p_pct <= 0 OR p_pct > 100 THEN
    RETURN jsonb_build_object('error', 'Pourcentage de rétrocession invalide (1-100).');
  END IF;
  UPDATE missions SET mode_remuneration = 'RETROCESSION', retrocession_pct = p_pct,
    type_contrat_recherche = 'LIBERAL', modifie_le = NOW()
   WHERE id = p_mission_id;
  RETURN jsonb_build_object('success', TRUE, 'retrocession_pct', p_pct);
END;
$body$;
GRANT EXECUTE ON FUNCTION public.fn_definir_retrocession_mission(uuid, numeric) TO authenticated;
