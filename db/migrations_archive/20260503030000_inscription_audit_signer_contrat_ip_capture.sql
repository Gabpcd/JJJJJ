-- Audit production-ready inscription/onboarding (2026-05-03)
-- 1. fn_signer_contrat_service : capture l'IP réelle du signataire depuis
--    les headers PostgREST (cf-connecting-ip / x-forwarded-for) pour audit HDS.
--    Le frontend ne peut pas connaître son IP publique → la RPC l'override.
-- 2. Drop surcharge legacy 4-args.
-- 3. Idempotence emails BIENVENUE : index unique partiel + cleanup doublons existants.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_signer_contrat_service(
  p_version text,
  p_ip text,
  p_user_agent text,
  p_contenu_hash text,
  p_signature_s3_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_etab_id uuid := mon_etablissement_id();
  v_existing uuid;
  v_headers jsonb;
  v_real_ip text;
BEGIN
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;

  SELECT id INTO v_existing FROM contrats_service_signatures
   WHERE etablissement_id = v_etab_id AND revoked_at IS NULL;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Contrat déjà signé et actif');
  END IF;

  -- Capture IP réelle depuis les headers
  BEGIN
    v_headers := current_setting('request.headers', true)::jsonb;
    v_real_ip := COALESCE(
      v_headers->>'cf-connecting-ip',
      split_part(v_headers->>'x-forwarded-for', ',', 1),
      v_headers->>'x-real-ip',
      NULLIF(p_ip, ''),
      'unknown'
    );
  EXCEPTION WHEN OTHERS THEN
    v_real_ip := COALESCE(NULLIF(p_ip, ''), 'unknown');
  END;

  INSERT INTO contrats_service_signatures (etablissement_id, version, ip_address, user_agent, contenu_hash, signature_s3_key)
  VALUES (v_etab_id, p_version, v_real_ip, p_user_agent, p_contenu_hash, p_signature_s3_key);

  PERFORM set_config('app.internal_operation', 'true', true);
  UPDATE etablissements
  SET contrat_service_signe = true, contrat_service_signe_le = now()
  WHERE id = v_etab_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := auth.uid(),
    p_type_acteur := 'ADMIN_ETABLISSEMENT',
    p_action := 'CONTRAT_SIGNE',
    p_type_ressource := 'etablissement',
    p_id_ressource := v_etab_id,
    p_details := jsonb_build_object(
      'type', 'contrat_service_jolene',
      'version', p_version,
      'ip', v_real_ip,
      'has_signature_image', p_signature_s3_key IS NOT NULL
    )
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_signer_contrat_service(text, text, text, text, text) TO authenticated;

DROP FUNCTION IF EXISTS public.fn_signer_contrat_service(text, text, text, text);

-- Idempotence BIENVENUE : cleanup doublons + index unique partiel
WITH ranked AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY destinataire_id, type
           ORDER BY cree_le ASC
         ) as rn
  FROM public.emails_envoyes
  WHERE type IN ('BIENVENUE_SOIGNANT', 'BIENVENUE_ETABLISSEMENT')
    AND statut <> 'ERREUR'
)
DELETE FROM public.emails_envoyes
WHERE id IN (SELECT id FROM ranked WHERE rn > 1);

CREATE UNIQUE INDEX IF NOT EXISTS uq_emails_bienvenue_destinataire
  ON public.emails_envoyes (destinataire_id, type)
  WHERE type IN ('BIENVENUE_SOIGNANT', 'BIENVENUE_ETABLISSEMENT')
    AND statut <> 'ERREUR';

NOTIFY pgrst, 'reload schema';

COMMIT;
