-- ─── RGPD Phase 2 : Compléter les audits manquants ───
--
-- 1. fn_signer_attestation_sante : signature médicale = non-répudiation. L'audit
--    passait NULL pour l'IP et le User-Agent. Fix : capture auto via headers.
-- 2. fn_repondre_litige : pas d'audit du tout alors que c'est une modification
--    d'un litige (données sensibles). Fix : ajouter fn_ecrire_audit.
-- 3. fn_contester_presence : aucun audit alors que c'est une contestation de
--    pointage (traçabilité CDDU obligatoire). Fix : ajouter fn_ecrire_audit.
--
-- Toutes les fonctions capturent désormais IP + User-Agent via
-- `current_setting('request.headers')` (PostgREST expose les en-têtes HTTP).

-- ─── 1. fn_signer_attestation_sante ───
CREATE OR REPLACE FUNCTION public.fn_signer_attestation_sante()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_ip inet;
  v_user_agent text;
  v_headers jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM soignants WHERE id = v_user_id) THEN
    RETURN jsonb_build_object('error', 'Soignant introuvable');
  END IF;

  UPDATE soignants
  SET attestation_sante_signee_le = now(),
      modifie_le = now()
  WHERE id = v_user_id;

  -- Capture IP + User-Agent pour non-répudiation (signature médicale)
  BEGIN
    v_headers := current_setting('request.headers', true)::jsonb;
    v_ip := NULLIF(trim(split_part(coalesce(v_headers->>'x-forwarded-for', ''), ',', 1)), '')::inet;
    v_user_agent := NULLIF(v_headers->>'user-agent', '');
  EXCEPTION WHEN OTHERS THEN
    v_ip := NULL; v_user_agent := NULL;
  END;

  PERFORM fn_ecrire_audit(
    v_user_id, 'SOIGNANT', 'ATTESTATION_SANTE_SIGNEE',
    'soignant', v_user_id, NULL,
    jsonb_build_object(
      'vaccinations', true,
      'medecine_travail', true,
      'horodatage', now()
    ),
    v_ip, v_user_agent
  );

  RETURN jsonb_build_object('success', true, 'signe_le', now());
END;
$function$;

-- ─── 2. fn_repondre_litige ───
CREATE OR REPLACE FUNCTION public.fn_repondre_litige(p_litige_id uuid, p_reponse text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_uid UUID := auth.uid();
    v_litige RECORD;
    v_auteur TEXT;
    v_type_acteur TEXT;
    v_reponse_safe TEXT;
    v_date_str TEXT;
    v_ip inet;
    v_user_agent text;
    v_headers jsonb;
BEGIN
    IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
    IF v_litige IS NULL THEN RETURN jsonb_build_object('error', 'Litige introuvable'); END IF;
    IF v_litige.statut IN ('RESOLU_SOIGNANT','RESOLU_ETABLISSEMENT','RESOLU_ADMIN','FERME') THEN
        RETURN jsonb_build_object('error', 'Ce litige est déjà clôturé');
    END IF;
    IF v_uid = v_litige.soignant_id THEN
      v_auteur := 'Soignant'; v_type_acteur := 'SOIGNANT';
    ELSIF mon_etablissement_id() = v_litige.etablissement_id THEN
      v_auteur := 'Établissement'; v_type_acteur := 'ADMIN_ETABLISSEMENT';
    ELSIF est_admin() THEN
      v_auteur := 'Admin'; v_type_acteur := 'ADMIN_PLATEFORME';
    ELSE
      RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    v_reponse_safe := LEFT(REGEXP_REPLACE(COALESCE(NULLIF(TRIM(p_reponse), ''), ''), '<[^>]*>', '', 'g'), 2000);
    IF LENGTH(v_reponse_safe) < 10 THEN
      RETURN jsonb_build_object('error', 'La réponse doit contenir au moins 10 caractères');
    END IF;
    v_date_str := TO_CHAR(NOW(), 'DD/MM/YYYY HH24:MI');

    UPDATE litiges SET
        reponse = CASE WHEN reponse IS NOT NULL AND reponse != ''
            THEN reponse || E'\n---\n[' || v_date_str || '] ' || v_auteur || ': ' || v_reponse_safe
            ELSE '[' || v_date_str || '] ' || v_auteur || ': ' || v_reponse_safe END,
        statut = 'EN_DISCUSSION'
    WHERE id = p_litige_id;

    -- Audit RGPD (Art. 32 — traçabilité des modifications de litige)
    BEGIN
      v_headers := current_setting('request.headers', true)::jsonb;
      v_ip := NULLIF(trim(split_part(coalesce(v_headers->>'x-forwarded-for', ''), ',', 1)), '')::inet;
      v_user_agent := NULLIF(v_headers->>'user-agent', '');
    EXCEPTION WHEN OTHERS THEN
      v_ip := NULL; v_user_agent := NULL;
    END;

    PERFORM fn_ecrire_audit(
      v_uid, v_type_acteur, 'LITIGE_REPONSE',
      'litige', p_litige_id, NULL,
      jsonb_build_object(
        'mission_id', v_litige.mission_id,
        'motif_original', v_litige.motif,
        'auteur_reponse', v_auteur,
        'reponse_length', LENGTH(v_reponse_safe),
        'nouveau_statut', 'EN_DISCUSSION'
      ),
      v_ip, v_user_agent
    );

    RETURN jsonb_build_object('success', TRUE);
END;
$function$;

-- ─── 3. fn_contester_presence ───
CREATE OR REPLACE FUNCTION public.fn_contester_presence(p_presence_id uuid, p_motif text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_etab_id uuid;
  v_presence RECORD;
  v_ip inet;
  v_user_agent text;
  v_headers jsonb;
BEGIN
  v_etab_id := mon_etablissement_id();
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  IF p_motif IS NULL OR length(trim(p_motif)) < 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Le motif est obligatoire (3 caractères min.)');
  END IF;

  SELECT p.* INTO v_presence
  FROM presences p
  JOIN missions m ON m.id = p.mission_id
  WHERE p.id = p_presence_id
    AND m.etablissement_id = v_etab_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Présence introuvable');
  END IF;

  UPDATE presences
  SET motif_litige = trim(p_motif),
      modifie_le = now()
  WHERE id = p_presence_id;

  -- Audit RGPD (contestation d'un pointage = donnée CDDU critique)
  BEGIN
    v_headers := current_setting('request.headers', true)::jsonb;
    v_ip := NULLIF(trim(split_part(coalesce(v_headers->>'x-forwarded-for', ''), ',', 1)), '')::inet;
    v_user_agent := NULLIF(v_headers->>'user-agent', '');
  EXCEPTION WHEN OTHERS THEN
    v_ip := NULL; v_user_agent := NULL;
  END;

  PERFORM fn_ecrire_audit(
    auth.uid(), 'ADMIN_ETABLISSEMENT', 'PRESENCE_CONTESTATION',
    'presence', p_presence_id, NULL,
    jsonb_build_object(
      'mission_id', v_presence.mission_id,
      'soignant_id', v_presence.soignant_id,
      'motif', LEFT(trim(p_motif), 500)
    ),
    v_ip, v_user_agent
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;
