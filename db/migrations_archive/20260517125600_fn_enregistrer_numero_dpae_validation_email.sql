-- Sprint 15 PR 3 — Validation format numéro DPAE + email confirmation soignant
--
-- Renforce fn_enregistrer_numero_dpae avec :
-- 1. Validation format URSSAF stricte : 8-30 caractères alphanumériques
--    avec au moins un chiffre (rejette "OK", "test", "fait", etc.)
-- 2. Email best-effort au soignant via send-email (template
--    DPAE_DECLAREE_SOIGNANT) une fois le numéro enregistré.
--
-- Préserve toute la logique existante : authz étab+admin, audit trail,
-- UPDATE dpae_numero + dpae_effectuee + dpae_effectuee_le.

CREATE OR REPLACE FUNCTION public.fn_enregistrer_numero_dpae(
  p_contrat_id uuid,
  p_dpae_numero text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_numero_trim text;
  v_soignant_id uuid;
  v_mission_id uuid;
  v_soignant_prenom text;
  v_etab_nom text;
  v_mission_intitule text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  IF p_dpae_numero IS NULL OR length(trim(p_dpae_numero)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Numéro DPAE requis');
  END IF;

  v_numero_trim := trim(p_dpae_numero);

  -- Validation format URSSAF : 8 à 30 caractères alphanumériques + au moins 1 chiffre
  -- Rejette les saisies type "OK", "test", "fait", "AAAAAAAA", etc.
  IF v_numero_trim !~ '^[A-Za-z0-9]{8,30}$' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Format invalide : 8 à 30 caractères alphanumériques (lettres et chiffres) requis. Aucun espace ni ponctuation.'
    );
  END IF;

  IF v_numero_trim !~ '[0-9]' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Format invalide : le numéro DPAE doit contenir au moins un chiffre.'
    );
  END IF;

  SELECT cm.etablissement_id, cm.soignant_id, cm.mission_id
    INTO v_etab_id, v_soignant_id, v_mission_id
  FROM public.contrats_mission cm
  WHERE cm.id = p_contrat_id;

  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Contrat introuvable');
  END IF;

  IF NOT (est_admin() OR v_etab_id = mon_etablissement_id()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  UPDATE public.contrats_mission
  SET dpae_numero = v_numero_trim,
      dpae_effectuee = true,
      dpae_effectuee_le = COALESCE(dpae_effectuee_le, NOW()),
      modifie_le = NOW()
  WHERE id = p_contrat_id;

  -- Audit (action SYSTEM autorisée)
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'SYSTEM', 'contrat_mission', p_contrat_id,
    jsonb_build_object(
      'evenement', 'DPAE_NUMERO_ENREGISTRE',
      'dpae_numero', v_numero_trim,
      'enregistre_le', NOW()::text
    )
  );

  -- Email best-effort au soignant via send-email
  IF v_soignant_id IS NOT NULL AND v_mission_id IS NOT NULL THEN
    SELECT prenom INTO v_soignant_prenom FROM public.soignants WHERE id = v_soignant_id;
    SELECT nom INTO v_etab_nom FROM public.etablissements WHERE id = v_etab_id;
    SELECT intitule INTO v_mission_intitule FROM public.missions WHERE id = v_mission_id;

    BEGIN
      PERFORM net.http_post(
        url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        body := jsonb_build_object(
          'type', 'DPAE_DECLAREE_SOIGNANT',
          'destinataire_id', v_soignant_id,
          'data', jsonb_build_object(
            'prenom', COALESCE(v_soignant_prenom, ''),
            'etablissement_nom', COALESCE(v_etab_nom, 'L''établissement'),
            'mission_intitule', COALESCE(v_mission_intitule, 'votre mission'),
            'dpae_numero', v_numero_trim,
            'contrat_id', p_contrat_id::text
          )
        )
      );
    EXCEPTION WHEN OTHERS THEN
      -- pg_net indisponible ou erreur réseau : silencieux
      -- Le numéro DPAE est déjà enregistré, l'email est best-effort.
      NULL;
    END;
  END IF;

  RETURN jsonb_build_object('success', true, 'dpae_numero', v_numero_trim);
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_enregistrer_numero_dpae(uuid, text)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_enregistrer_numero_dpae(uuid, text) IS
'Sprint 15 PR 3 : enregistre le n° DPAE URSSAF avec validation format strict + email best-effort au soignant via send-email (template DPAE_DECLAREE_SOIGNANT).';
