-- Cron mort surfacé par le monitoring restauré (20260628150000) :
-- relance-candidatures-en-attente échouait chaque jour 09:00 avec
--   ERROR: Non authentifié  (fn_creer_notification ligne 5)
-- Cause : le garde strict « auth.uid() IS NULL → refus » bloquait tout appel
-- sans session, donc TOUS les crons appelant fn_creer_notification.
-- anon n'a pas le GRANT EXECUTE → ce garde ne protégeait contre aucun appelant
-- non fiable (seuls authenticated/service_role/postgres l'ont). On l'aligne sur
-- le pattern fn_est_contexte_cron_ou_admin() : autorise session authentifiée OU
-- contexte cron/service/admin (auth.uid() IS NULL).
-- Déjà appliqué en prod via MCP ; vérifié : fn_relancer_candidatures_en_attente()
-- renvoie 6 (au lieu de planter). Ce fichier sert l'enregistrement repo.

CREATE OR REPLACE FUNCTION public.fn_creer_notification(p_destinataire_id uuid, p_type_destinataire text, p_type text, p_titre text, p_corps text, p_lien text DEFAULT NULL::text, p_type_ressource text DEFAULT NULL::text, p_id_ressource uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_id uuid;
BEGIN
    -- Sécurité : appelant authentifié OU contexte cron/service/admin (auth.uid() IS NULL).
    -- anon n'a PAS le GRANT EXECUTE → ce garde ne bloque que des appelants de confiance.
    IF auth.uid() IS NULL AND NOT fn_est_contexte_cron_ou_admin() THEN
      RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
    END IF;

    INSERT INTO public.notifications (
        destinataire_id, type_destinataire, type,
        titre, corps, lien, type_ressource, id_ressource
    ) VALUES (
        p_destinataire_id, p_type_destinataire, p_type,
        p_titre, p_corps, p_lien, p_type_ressource, p_id_ressource
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$function$;
