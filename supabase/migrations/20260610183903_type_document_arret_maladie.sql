-- Certificat d'arrêt maladie : nouveau type de document vérifié par l'IA
-- (verify-document : nature Cerfa + concordance nom + dates) — protège la garantie
-- remplacement contre les faux arrêts et horodate une preuve pour l'employeur.
-- NOTE : appliquée prod via MCP (version 20260610183903).
ALTER TYPE public.type_document ADD VALUE IF NOT EXISTS 'ARRET_MALADIE';
