-- Corrige trois ruptures de parcours observées en production le 2026-08-03 :
-- 1. la policy UPDATE de soignants se relisait elle-même et bouclait ;
-- 2. une ancienne protection documentaire ignorait le contexte serveur borné ;
-- 3. les réclamations avaient des policies RLS mais aucun droit Data API.

DROP POLICY IF EXISTS pol_soig_update ON public.soignants;
CREATE POLICY pol_soig_update
ON public.soignants
FOR UPDATE
TO authenticated
USING (
  (SELECT public.est_admin())
  OR id = (SELECT auth.uid())
)
WITH CHECK (
  (SELECT public.est_admin())
  OR id = (SELECT auth.uid())
);

-- Les colonnes de vérification restent protégées par
-- trg_protect_soignant_verification / fn_protect_soignant_verification().
-- La policy ne doit jamais relire public.soignants elle-même.

CREATE OR REPLACE FUNCTION public.dec_proteger_validation_documents()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF auth.role() = 'service_role'
     OR auth.uid() IS NULL
     OR public.est_admin()
     OR COALESCE(current_setting('jolene.system_update', true), '') = 'true'
     OR COALESCE(current_setting('jolene.document_server_update', true), '') = 'true'
     OR COALESCE(current_setting('jolene.document_moderation_rpc', true), '') = 'true' THEN
    RETURN NEW;
  END IF;

  IF NEW.statut_verification IS DISTINCT FROM OLD.statut_verification THEN
    RAISE EXCEPTION 'Seul un administrateur peut modifier le statut de vérification';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_proteger_validation_documents() FROM PUBLIC, anon, authenticated;

-- Les policies existantes restent l'unique filtre de lignes : un utilisateur
-- authentifié ne voit et ne crée que ses propres réclamations.
GRANT SELECT, INSERT ON TABLE public.reclamations TO authenticated;

DO $assertions$
DECLARE
  v_policy text;
BEGIN
  SELECT COALESCE(qual, '') || ' ' || COALESCE(with_check, '')
  INTO v_policy
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'soignants'
    AND policyname = 'pol_soig_update';

  IF v_policy ILIKE '%from soignants%' OR v_policy ILIKE '%from public.soignants%' THEN
    RAISE EXCEPTION 'pol_soig_update ne doit pas se référencer elle-même';
  END IF;

  IF NOT has_table_privilege('authenticated', 'public.reclamations', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.reclamations', 'INSERT') THEN
    RAISE EXCEPTION 'Droits Data API reclamations incomplets';
  END IF;
END;
$assertions$;
