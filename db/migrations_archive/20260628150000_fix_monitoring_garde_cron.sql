-- Fix monitoring mort : fn_emettre_alerte_monitoring refusait l'exécution en
-- contexte pg_cron. L'ancien garde « est_admin() OR service_role » lève 42501
-- quand auth.uid() IS NULL (cron), ce qui faisait avorter fn_check_crons_health
-- au premier cron en échec → 0 alerte émise (alerting silencieusement cassé).
-- Remplacé par fn_est_contexte_cron_ou_admin() (true en contexte cron).
-- Déjà appliqué en prod via MCP ; ce fichier sert l'enregistrement repo.
-- (Appartient à la branche reliability-layer, PAS à la PR fix-merge-conflicts.)

CREATE OR REPLACE FUNCTION public.fn_emettre_alerte_monitoring(p_type text, p_severite text, p_source text, p_message text, p_details jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_id UUID; v_existing UUID;
BEGIN
  IF NOT fn_est_contexte_cron_ou_admin() THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;
  SELECT id INTO v_existing FROM alertes_systeme
  WHERE type_alerte = p_type AND source = p_source AND resolu_le IS NULL
    AND cree_le > NOW() - INTERVAL '1 hour'
  LIMIT 1;
  IF v_existing IS NOT NULL THEN RETURN v_existing; END IF;

  INSERT INTO alertes_systeme (type_alerte, severite, source, message, details)
  VALUES (p_type, p_severite, p_source, p_message, p_details)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;
