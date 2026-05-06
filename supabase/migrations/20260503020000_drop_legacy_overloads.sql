-- Drop surcharges legacy pour éliminer l'ambiguïté de routing PostgREST
-- + risque "audit absent" sur l'ancienne fn_creer_api_key 4-args.
-- Date : 2026-05-03

BEGIN;

-- 1. fn_creer_api_key (legacy 4-args sans audit log) — anti-pattern.
--    La version 3-args (text, text[], uuid) avec audit reste seule.
DROP FUNCTION IF EXISTS public.fn_creer_api_key(text, uuid, uuid, text[]);

-- 2. fn_uploader_contrat_travail_mission (legacy integer)
--    file.size côté JS peut excéder 2³¹ → bigint requis.
--    La version bigint reste seule.
DROP FUNCTION IF EXISTS public.fn_uploader_contrat_travail_mission(uuid, text, text, integer);

NOTIFY pgrst, 'reload schema';

COMMIT;
