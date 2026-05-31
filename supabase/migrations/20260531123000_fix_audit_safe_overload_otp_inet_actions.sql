-- 1) Surcharge 6-args de fn_ecrire_audit_safe (acteur, type_acteur, action,
--    type_ressource, id_ressource, details). De nombreuses fonctions
--    (annulation mission, litige, API keys, etc.) l'appelaient sous cette forme
--    qui n'existait pas → 42883 dans l'appelant (avant même d'entrer dans la
--    version safe) → l'opération entière échouait.
CREATE OR REPLACE FUNCTION public.fn_ecrire_audit_safe(
  p_acteur_id uuid, p_type_acteur text, p_action text,
  p_type_ressource text, p_id_ressource uuid, p_details jsonb
) RETURNS jsonb
  LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT public.fn_ecrire_audit_safe(p_acteur_id, p_type_acteur, p_action,
    p_type_ressource, p_id_ressource, NULL::text, p_details, NULL::inet, NULL::text);
$function$;

-- 2) fn_signer_contrat_otp : COALESCE(v_ip::text, signature_ip_*) mélangeait
--    text et inet (colonnes signature_ip_* = inet) → 42804. Retirer le ::text.
DO $mig$
DECLARE v_def text; v_new text;
BEGIN
  SELECT pg_get_functiondef('public.fn_signer_contrat_otp(uuid,text,text,text)'::regprocedure) INTO v_def;
  v_new := replace(v_def, 'COALESCE(v_ip::text,', 'COALESCE(v_ip,');
  IF v_new <> v_def THEN EXECUTE v_new; END IF;
END $mig$;

-- 3) Actions audit manquantes (écrites via fn_ecrire_audit_safe, jusqu'ici
--    avalées silencieusement → trous d'audit).
DO $mig$
DECLARE v_def text; v_expr text; v_additions text; v_new_expr text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_def FROM pg_constraint WHERE conname='journaux_audit_action_check';
  v_expr := substring(v_def from 7);
  v_additions := (SELECT string_agg(format(', %L::text', a), '') FROM unnest(ARRAY[
    'API_KEY_CREEE','API_KEY_REVOQUEE','API_KEY_SUPPRIMEE','FACTURE_MARQUEE_EN_RETARD',
    'HEURES_EXTERNES_VALIDATION_MANUELLE','MISSION_ANNULEE_PAR_SOIGNANT',
    'MISSION_ANNULEE_PAR_ETABLISSEMENT','MISSION_LITIGE','MISSION_TYPE_CONTRAT_MODIFIE'
  ]) a WHERE v_def NOT LIKE '%'''||a||'''::text%');
  IF v_additions IS NOT NULL AND v_additions <> '' THEN
    v_new_expr := regexp_replace(v_expr, '\]\)\)\)\s*$', v_additions || '])))');
    EXECUTE 'ALTER TABLE public.journaux_audit DROP CONSTRAINT journaux_audit_action_check';
    EXECUTE 'ALTER TABLE public.journaux_audit ADD CONSTRAINT journaux_audit_action_check CHECK ' || v_new_expr;
  END IF;
END $mig$;
