-- Cascade : supprimer un compte depuis l'UI Supabase Auth libère désormais le RPPS
-- (et l'email côté soignants) automatiquement.
--
-- Il n'existait aucune cascade auth.users -> soignants : supprimer un user laissait la
-- ligne `soignants` (avec son RPPS) orpheline → le RPPS restait « associé à un compte ».
--
-- Stratégie (ne bloque JAMAIS la suppression auth) :
--   1. Tente DELETE soignant (compte test sans historique → suppression complète,
--      RPPS + email libérés).
--   2. Si FK RESTRICT (compte avec missions/historique) → fallback : libère le RPPS/ADELI
--      + soft-delete (préserve l'historique comptable/légal, RPPS réutilisable).

CREATE OR REPLACE FUNCTION public.fn_auth_user_deleted_cleanup_soignant()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  BEGIN
    DELETE FROM public.soignants WHERE id = OLD.id;
  EXCEPTION WHEN others THEN
    UPDATE public.soignants
      SET numero_rpps = NULL, rpps_verifie = false, rpps_verifie_le = NULL,
          rpps_nom_api = NULL, rpps_prenom_api = NULL, rpps_profession_api = NULL,
          numero_adeli = NULL,
          supprime_le = COALESCE(supprime_le, now())
      WHERE id = OLD.id;
  END;
  RETURN OLD;
END;
$function$;

DROP TRIGGER IF EXISTS trg_auth_user_deleted_cleanup ON auth.users;
CREATE TRIGGER trg_auth_user_deleted_cleanup
  AFTER DELETE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.fn_auth_user_deleted_cleanup_soignant();
