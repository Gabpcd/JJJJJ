-- Refactor : remplace toutes les mutations directes frontend sur tables sensibles
-- par des RPCs SECURITY DEFINER avec audit log obligatoire.
-- Date : 2026-05-03
--
-- Tables concernées :
-- 1. api_keys : génération de clés (avec hash secret côté serveur)
-- 2. factures : marquage EN_RETARD
-- 3. chorus_pro_config : toggle activation
-- 4. contrats_travail_missions : upload contrat + journaux_audit unifié
-- 5. missions : modification type_contrat_recherche post-création
--
-- Anti-pattern résolu : génération clé secret côté frontend (browser) +
-- INSERT direct sans audit. Désormais clé secret générée côté serveur,
-- hashée (SHA-256) avant stockage, retournée UNE SEULE FOIS au caller.

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════
-- Helpers : génération sécurisée et hash
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._sha256_hex(p_input text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public, extensions
AS $$
  SELECT encode(extensions.digest(p_input, 'sha256'), 'hex');
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- 1. api_keys : CRUD complet via RPC
-- ═══════════════════════════════════════════════════════════════════════

-- Création (admin OU étab pour soi-même)
CREATE OR REPLACE FUNCTION public.fn_creer_api_key(
  p_nom text,
  p_permissions text[],
  p_etablissement_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_is_admin boolean;
  v_etab_id uuid;
  v_cle_api text;
  v_cle_secret text;
  v_id uuid;
  v_actor_type text;
BEGIN
  IF v_actor IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  v_is_admin := est_admin();

  -- Détermination du scope
  IF v_is_admin THEN
    v_etab_id := p_etablissement_id; -- NULL = clé admin globale
    v_actor_type := 'ADMIN_PLATEFORME';
  ELSE
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL THEN
      RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;
    -- Étab ne peut créer de clé que pour lui-même
    IF p_etablissement_id IS NOT NULL AND p_etablissement_id <> v_etab_id THEN
      RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;
    v_actor_type := 'ADMIN_ETABLISSEMENT';
  END IF;

  IF p_nom IS NULL OR length(trim(p_nom)) = 0 THEN
    RETURN jsonb_build_object('error', 'Nom requis');
  END IF;

  IF p_permissions IS NULL OR array_length(p_permissions, 1) IS NULL THEN
    RETURN jsonb_build_object('error', 'Au moins une permission requise');
  END IF;

  -- Génération côté serveur (cryptographique, qualifié extensions)
  v_cle_api := 'sd_live_' || replace(extensions.gen_random_uuid()::text, '-', '');
  v_cle_secret := encode(extensions.gen_random_bytes(32), 'hex');

  INSERT INTO public.api_keys (nom, cle_api, cle_secret, cle_secret_hash, permissions, etablissement_id, actif)
  VALUES (
    trim(p_nom),
    v_cle_api,
    v_cle_secret, -- legacy (sera nullé en cleanup futur)
    public._sha256_hex(v_cle_secret),
    p_permissions,
    v_etab_id,
    true
  )
  RETURNING id INTO v_id;

  -- Audit
  PERFORM fn_ecrire_audit_safe(
    v_actor, v_actor_type,
    'API_KEY_CREEE', 'api_key', v_id,
    NULL,
    jsonb_build_object('nom', trim(p_nom), 'permissions', p_permissions, 'etablissement_id', v_etab_id),
    NULL, NULL
  );

  RETURN jsonb_build_object(
    'id', v_id,
    'cle_api', v_cle_api,
    'cle_secret', v_cle_secret -- retourné UNE SEULE FOIS
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_creer_api_key(text, text[], uuid) TO authenticated;

-- Révocation (désactivation, conservée pour audit)
CREATE OR REPLACE FUNCTION public.fn_revoquer_api_key(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_is_admin boolean := est_admin();
  v_etab_id uuid := mon_etablissement_id();
  v_target_etab uuid;
BEGIN
  SELECT etablissement_id INTO v_target_etab FROM public.api_keys WHERE id = p_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Clé introuvable');
  END IF;

  IF NOT v_is_admin AND v_target_etab IS DISTINCT FROM v_etab_id THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  UPDATE public.api_keys SET actif = false WHERE id = p_id;

  PERFORM fn_ecrire_audit_safe(
    v_actor, CASE WHEN v_is_admin THEN 'ADMIN_PLATEFORME' ELSE 'ADMIN_ETABLISSEMENT' END,
    'API_KEY_REVOQUEE', 'api_key', p_id,
    NULL, jsonb_build_object('id', p_id), NULL, NULL
  );

  RETURN jsonb_build_object('ok', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_revoquer_api_key(uuid) TO authenticated;

-- Suppression définitive
CREATE OR REPLACE FUNCTION public.fn_supprimer_api_key(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_is_admin boolean := est_admin();
  v_etab_id uuid := mon_etablissement_id();
  v_target_etab uuid;
  v_nom text;
BEGIN
  SELECT etablissement_id, nom INTO v_target_etab, v_nom FROM public.api_keys WHERE id = p_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Clé introuvable');
  END IF;

  IF NOT v_is_admin AND v_target_etab IS DISTINCT FROM v_etab_id THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  DELETE FROM public.api_keys WHERE id = p_id;

  PERFORM fn_ecrire_audit_safe(
    v_actor, CASE WHEN v_is_admin THEN 'ADMIN_PLATEFORME' ELSE 'ADMIN_ETABLISSEMENT' END,
    'API_KEY_SUPPRIMEE', 'api_key', p_id,
    NULL, jsonb_build_object('id', p_id, 'nom', v_nom), NULL, NULL
  );

  RETURN jsonb_build_object('ok', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_supprimer_api_key(uuid) TO authenticated;

-- Lock down : interdire toute mutation directe sur api_keys depuis le rôle authenticated.
-- Les RPCs ci-dessus (SECURITY DEFINER) bypassent ces revokes.
REVOKE INSERT, UPDATE, DELETE ON TABLE public.api_keys FROM authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 2. factures : marquage EN_RETARD via RPC
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_admin_marquer_facture_en_retard(p_facture_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_ancien_statut text;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  SELECT statut INTO v_ancien_statut FROM public.factures WHERE id = p_facture_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Facture introuvable');
  END IF;

  UPDATE public.factures SET statut = 'EN_RETARD' WHERE id = p_facture_id;

  PERFORM fn_ecrire_audit_safe(
    v_actor, 'ADMIN_PLATEFORME',
    'FACTURE_MARQUEE_EN_RETARD', 'facture', p_facture_id,
    NULL,
    jsonb_build_object('ancien_statut', v_ancien_statut, 'nouveau_statut', 'EN_RETARD'),
    NULL, NULL
  );

  RETURN jsonb_build_object('ok', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_admin_marquer_facture_en_retard(uuid) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 3. chorus_pro_config : toggle via RPC
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_admin_chorus_config_toggle(
  p_etablissement_id uuid,
  p_actif boolean,
  p_numero_structure text DEFAULT NULL,
  p_code_service text DEFAULT NULL,
  p_identifiant_cpro text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  INSERT INTO public.chorus_pro_config (etablissement_id, numero_structure, code_service, identifiant_cpro, actif)
  VALUES (p_etablissement_id, p_numero_structure, p_code_service, p_identifiant_cpro, p_actif)
  ON CONFLICT (etablissement_id) DO UPDATE
    SET actif = EXCLUDED.actif,
        numero_structure = COALESCE(EXCLUDED.numero_structure, chorus_pro_config.numero_structure),
        code_service = COALESCE(EXCLUDED.code_service, chorus_pro_config.code_service),
        identifiant_cpro = COALESCE(EXCLUDED.identifiant_cpro, chorus_pro_config.identifiant_cpro);

  PERFORM fn_ecrire_audit_safe(
    v_actor, 'ADMIN_PLATEFORME',
    CASE WHEN p_actif THEN 'CHORUS_CONFIG_ACTIVEE' ELSE 'CHORUS_CONFIG_DESACTIVEE' END,
    'chorus_pro_config', p_etablissement_id,
    NULL, jsonb_build_object('actif', p_actif), NULL, NULL
  );

  RETURN jsonb_build_object('ok', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_admin_chorus_config_toggle(uuid, boolean, text, text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 4. contrats_travail_missions : upload via RPC unifiée + audit
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_uploader_contrat_travail_mission(
  p_mission_id uuid,
  p_pdf_s3_key text,
  p_nom_fichier text,
  p_taille_octets bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_etab_id uuid;
  v_soignant_id uuid;
  v_existing_id uuid;
  v_action text;
BEGIN
  -- Récupérer etab + soignant de la mission
  SELECT etablissement_id, soignant_assigne_id
  INTO v_etab_id, v_soignant_id
  FROM public.missions
  WHERE id = p_mission_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  -- Vérification : actor doit être l'établissement (ou admin)
  IF NOT est_admin() AND v_etab_id IS DISTINCT FROM mon_etablissement_id() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  IF v_soignant_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Mission sans soignant assigné');
  END IF;

  -- INSERT ou UPDATE (idempotent par mission_id)
  SELECT id INTO v_existing_id FROM public.contrats_travail_missions WHERE mission_id = p_mission_id;

  IF v_existing_id IS NULL THEN
    INSERT INTO public.contrats_travail_missions (mission_id, etablissement_id, soignant_id, pdf_s3_key, nom_fichier, taille_octets, uploaded_by, uploaded_at)
    VALUES (p_mission_id, v_etab_id, v_soignant_id, p_pdf_s3_key, p_nom_fichier, p_taille_octets, v_actor, now());
    v_action := 'CONTRAT_TRAVAIL_UPLOADE';
  ELSE
    UPDATE public.contrats_travail_missions
    SET pdf_s3_key = p_pdf_s3_key,
        nom_fichier = p_nom_fichier,
        taille_octets = p_taille_octets,
        uploaded_at = now(),
        uploaded_by = v_actor
    WHERE id = v_existing_id;
    v_action := 'CONTRAT_TRAVAIL_REMPLACE';
  END IF;

  PERFORM fn_ecrire_audit_safe(
    v_actor,
    CASE WHEN est_admin() THEN 'ADMIN_PLATEFORME' ELSE 'ADMIN_ETABLISSEMENT' END,
    v_action, 'mission', p_mission_id,
    NULL, jsonb_build_object('nom_fichier', p_nom_fichier, 'taille_octets', p_taille_octets),
    NULL, NULL
  );

  RETURN jsonb_build_object('ok', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_uploader_contrat_travail_mission(uuid, text, text, bigint) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 5. missions.type_contrat_recherche : modification post-création via RPC
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_modifier_type_contrat_mission(
  p_mission_id uuid,
  p_type_contrat text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_etab_id uuid;
  v_ancien text;
BEGIN
  SELECT etablissement_id, type_contrat_recherche INTO v_etab_id, v_ancien
  FROM public.missions WHERE id = p_mission_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  IF NOT est_admin() AND v_etab_id IS DISTINCT FROM mon_etablissement_id() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  UPDATE public.missions SET type_contrat_recherche = p_type_contrat WHERE id = p_mission_id;

  PERFORM fn_ecrire_audit_safe(
    v_actor,
    CASE WHEN est_admin() THEN 'ADMIN_PLATEFORME' ELSE 'ADMIN_ETABLISSEMENT' END,
    'MISSION_TYPE_CONTRAT_MODIFIE', 'mission', p_mission_id,
    NULL,
    jsonb_build_object('ancien', v_ancien, 'nouveau', p_type_contrat),
    NULL, NULL
  );

  RETURN jsonb_build_object('ok', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_modifier_type_contrat_mission(uuid, text) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
