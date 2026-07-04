-- ============================================================================
-- Sprint 5.5 PR 10 — DPAE soignant : NIR + liste DPAE générées
-- ============================================================================
-- Fix P0-12 + P0-13 audit Sprint 5 :
--  - NIR (numéro sécurité sociale) absent du formulaire DPAE soignant
--    (champ DB existant mais pas exposé en UI)
--  - Aucune page /soignant/dpae : soignant ne voit pas ses DPAE générées
--
-- Ce script crée :
--  1. RPC fn_maj_nir_soignant(p_nir) : valide format + persist + audit
--  2. RPC fn_mes_dpae() : liste DPAE par contrat (statut, n° URSSAF, mission)
-- ============================================================================

-- 1. RPC : modifier le NIR (numéro de sécurité sociale)
CREATE OR REPLACE FUNCTION public.fn_maj_nir_soignant(
  p_nir text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_normalise text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF p_nir IS NULL OR length(trim(p_nir)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NIR_REQUIS');
  END IF;

  -- Normalisation : supprime espaces, garde chiffres + 2A/2B Corse
  v_normalise := regexp_replace(upper(trim(p_nir)), '\s+', '', 'g');

  -- Validation format : 13 chiffres OBLIGATOIRES + 2 chiffres clé optionnels
  -- Position 6-7 (département) : 01-95, 2A, 2B, 96-99
  IF v_normalise !~ '^[12][0-9]{2}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01]|2A|2B|9[0-9])[0-9]{6}([0-9]{2})?$' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'NIR_FORMAT_INVALIDE',
      'error', 'Le NIR doit faire 13 ou 15 chiffres au format français.'
    );
  END IF;

  UPDATE public.soignants
  SET numero_securite_sociale = v_normalise,
      modifie_le = now()
  WHERE id = v_uid;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'SOIGNANT', 'DONNEES_PERSO_MODIFICATION', 'soignant', v_uid,
    jsonb_build_object(
      'champ', 'numero_securite_sociale',
      'horodatage', now()
    )
  );

  RETURN jsonb_build_object('success', true);
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_maj_nir_soignant(text) TO authenticated;

-- 2. RPC : lister les DPAE générées pour les missions du soignant
CREATE OR REPLACE FUNCTION public.fn_mes_dpae()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_dpae jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'contrat_id', cm.id,
    'mission_id', cm.mission_id,
    'mission_intitule', m.intitule,
    'etablissement_id', m.etablissement_id,
    'etablissement_nom', e.nom,
    'debut_le', m.debut_le,
    'fin_le', m.fin_le,
    'type_contrat', cm.type_contrat,
    'dpae_effectuee', cm.dpae_effectuee,
    'dpae_numero', cm.dpae_numero,
    'dpae_effectuee_le', cm.dpae_effectuee_le,
    'rappel_dpae_affiche', cm.rappel_dpae_affiche,
    'rappel_dpae_affiche_le', cm.rappel_dpae_affiche_le,
    'statut_contrat', cm.statut
  ) ORDER BY m.debut_le DESC), '[]'::jsonb)
  INTO v_dpae
  FROM public.contrats_mission cm
  JOIN public.missions m ON m.id = cm.mission_id
  JOIN public.etablissements e ON e.id = m.etablissement_id
  WHERE cm.soignant_id = v_uid
    AND cm.type_contrat IN ('CDD', 'CDDU', 'SALARIE')
    AND cm.statut IN ('SIGNE_COMPLET', 'SIGNE_PARTIEL');

  RETURN jsonb_build_object('success', true, 'dpae', v_dpae);
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_mes_dpae() TO authenticated;

-- Audit migration
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT55_PR10_DPAE_SOIGNANT_NIR_INSTALLED',
    'pr', 'PR 10 Sprint 5.5',
    'rpcs', jsonb_build_array('fn_maj_nir_soignant', 'fn_mes_dpae')
  )
);
