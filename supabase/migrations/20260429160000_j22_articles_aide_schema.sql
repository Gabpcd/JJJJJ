-- J2.2 — Centre d'aide / FAQ Jolene

CREATE TABLE IF NOT EXISTS public.articles_aide (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  slug text NOT NULL UNIQUE,
  titre text NOT NULL,
  contenu text NOT NULL,
  audience text NOT NULL CHECK (audience IN ('SOIGNANT','ETABLISSEMENT','COMMUN')),
  categorie text NOT NULL,
  ordre_affichage integer NOT NULL DEFAULT 100,
  publie boolean NOT NULL DEFAULT true,
  cree_le timestamptz NOT NULL DEFAULT now(),
  mis_a_jour_le timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.articles_aide IS
  'Centre d''aide / FAQ Jolene. Articles Markdown publiés (publie=true) accessibles à tous, filtrés par audience selon le rôle utilisateur.';

CREATE INDEX IF NOT EXISTS idx_articles_aide_audience_publie
  ON public.articles_aide (audience, publie, ordre_affichage);
CREATE INDEX IF NOT EXISTS idx_articles_aide_categorie
  ON public.articles_aide (categorie);
CREATE INDEX IF NOT EXISTS idx_articles_aide_search
  ON public.articles_aide
  USING GIN (to_tsvector('french', titre || ' ' || contenu))
  WHERE publie = true;

ALTER TABLE public.articles_aide ENABLE ROW LEVEL SECURITY;

CREATE POLICY aa_select_publie ON public.articles_aide
  FOR SELECT TO anon, authenticated
  USING (publie = true);

CREATE POLICY aa_admin_all ON public.articles_aide
  FOR ALL TO authenticated
  USING (est_admin())
  WITH CHECK (est_admin());

GRANT SELECT ON public.articles_aide TO anon, authenticated;

-- RPC fn_rechercher_aide(query, audience?) → search full-text + filtrage
CREATE OR REPLACE FUNCTION public.fn_rechercher_aide(
  p_query text DEFAULT NULL,
  p_audience text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_result jsonb;
  v_tsquery tsquery;
BEGIN
  IF p_query IS NOT NULL AND length(trim(p_query)) > 0 THEN
    v_tsquery := websearch_to_tsquery('french', p_query);
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', a.id,
    'slug', a.slug,
    'titre', a.titre,
    'audience', a.audience,
    'categorie', a.categorie,
    'extrait', LEFT(a.contenu, 200),
    'mis_a_jour_le', a.mis_a_jour_le,
    'rank', CASE WHEN v_tsquery IS NOT NULL
                 THEN ts_rank(to_tsvector('french', a.titre || ' ' || a.contenu), v_tsquery)
                 ELSE 0 END
  ) ORDER BY
    CASE WHEN v_tsquery IS NOT NULL
         THEN ts_rank(to_tsvector('french', a.titre || ' ' || a.contenu), v_tsquery)
         ELSE 0 END DESC,
    a.ordre_affichage ASC,
    a.titre ASC
  ), '[]'::jsonb)
  INTO v_result
  FROM articles_aide a
  WHERE a.publie = true
    AND (p_audience IS NULL OR a.audience = p_audience OR a.audience = 'COMMUN')
    AND (v_tsquery IS NULL OR
         to_tsvector('french', a.titre || ' ' || a.contenu) @@ v_tsquery);

  RETURN jsonb_build_object('articles', v_result, 'count', jsonb_array_length(v_result));
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_rechercher_aide(text, text) TO anon, authenticated;

-- Trigger updated_at
CREATE OR REPLACE FUNCTION public.fn_trg_articles_aide_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.mis_a_jour_le := now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS trg_articles_aide_updated_at ON public.articles_aide;
CREATE TRIGGER trg_articles_aide_updated_at
  BEFORE UPDATE ON public.articles_aide
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_articles_aide_updated_at();

NOTIFY pgrst, 'reload schema';
