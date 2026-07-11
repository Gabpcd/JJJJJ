-- Lot 19 — Rebrancher les tripwires premier-euro sur le canal d'alerte (#849).
-- `fn_tripwire_alerte` envoyait déjà l'email (edge notify-support) mais NE créait
-- PAS d'alerte in-app visible dans le cockpit admin. On ajoute l'émission d'une
-- alerte CRITICAL dédupliquée dans alertes_systeme (email_envoye_le horodaté),
-- EN PLUS de l'email. Émission par INSERT direct dédupliqué (la fonction est
-- SECURITY DEFINER, émetteur système ; les tripwires firent en contexte user,
-- donc fn_emettre_alerte_monitoring — gardée cron/admin — n'est pas utilisable).
-- Redéfinition depuis la déf LIVE (règle 9.0), seul l'ajout in-app.
CREATE OR REPLACE FUNCTION public.fn_tripwire_alerte(p_sujet text, p_corps text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF public.fn_param_num('alertes_tripwire_actives', 1) <> 1 THEN
    RETURN;
  END IF;

  -- 1. Alerte in-app CRITICAL dans le canal (visible cockpit, dédupliquée).
  BEGIN
    INSERT INTO public.alertes_systeme (type_alerte, severite, source, message, details, occurrences, derniere_occurrence, email_envoye_le)
    VALUES ('TRIPWIRE_PREMIER_EURO', 'CRITICAL', p_sujet, p_sujet, jsonb_build_object('corps', p_corps), 1, now(), now())
    ON CONFLICT (source, type_alerte) WHERE resolu_le IS NULL
    DO UPDATE SET occurrences = alertes_systeme.occurrences + 1, derniere_occurrence = now(), email_envoye_le = now(), details = EXCLUDED.details;
  EXCEPTION WHEN OTHERS THEN
    NULL; -- non bloquant.
  END;

  -- 2. Email (inchangé — edge notify-support).
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/notify-support',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
      ),
      body := jsonb_build_object('sujet', p_sujet, 'corps', p_corps, 'source', 'tripwire-paiement')
    );
  EXCEPTION WHEN OTHERS THEN
    NULL; -- non bloquant : une alerte ratée ne casse jamais le flux métier.
  END;
END;
$function$;
