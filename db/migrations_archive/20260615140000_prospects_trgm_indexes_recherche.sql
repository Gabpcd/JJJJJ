-- Recherche prospection (ILIKE '%q%' sur nom/ville/enseigne) : sans index trigram
-- c'est un seq scan sur 245k soignants / 64k étabs → lent. GIN pg_trgm = quasi-instant.
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;

CREATE INDEX IF NOT EXISTS idx_prospects_etab_nom_trgm
  ON public.prospects_etablissements USING gin (nom extensions.gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_prospects_etab_ville_trgm
  ON public.prospects_etablissements USING gin (ville extensions.gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_prospects_soign_nom_trgm
  ON public.prospects_soignants USING gin (nom extensions.gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_prospects_soign_ville_trgm
  ON public.prospects_soignants USING gin (ville extensions.gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_prospects_soign_enseigne_trgm
  ON public.prospects_soignants USING gin (enseigne extensions.gin_trgm_ops);
