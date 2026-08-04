-- Le même utilisateur peut être référencé comme soignant et conserver un rattachement
-- établissement. La RPC canonique donne alors la priorité au rôle soignant : le verrou
-- doit appliquer la même règle, y compris dans une transaction de test où la fonction
-- STABLE mon_etablissement_id() peut conserver la valeur du précédent acteur.
CREATE OR REPLACE FUNCTION public.fn_verrouiller_proposition_litige_en_attente()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
BEGIN
  IF OLD.payload_modifications IS NOT NULL
     AND NEW.payload_modifications IS DISTINCT FROM OLD.payload_modifications
     AND OLD.statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS')
     AND (
       (
         COALESCE(OLD.accord_soignant, false)
         AND NOT COALESCE(OLD.accord_etablissement, false)
         AND OLD.soignant_id = auth.uid()
       )
       OR
       (
         COALESCE(OLD.accord_etablissement, false)
         AND NOT COALESCE(OLD.accord_soignant, false)
         AND OLD.soignant_id IS DISTINCT FROM auth.uid()
         AND OLD.etablissement_id = public.mon_etablissement_id()
       )
     )
     AND NOT public.est_admin()
     AND COALESCE(auth.role(), '') <> 'service_role'
  THEN
    RAISE EXCEPTION 'PROPOSITION_LITIGE_EN_ATTENTE'
      USING ERRCODE = 'P0001',
            HINT = 'L autre partie doit répondre à la proposition existante avant toute nouvelle proposition.';
  END IF;

  RETURN NEW;
END;
$function$;
