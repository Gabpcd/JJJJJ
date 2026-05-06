-- Phase C Session 3A : infrastructure parcours libéral
-- Tables + fonctions SQL + bucket Storage pour alimenter la page
-- /soignant/passer-en-liberal refondue en Session 3B.

-- =============================================================
-- 1. Helper trigger fn_set_mis_a_jour_le (si pas déjà créé)
-- =============================================================
CREATE OR REPLACE FUNCTION public.fn_set_mis_a_jour_le()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.mis_a_jour_le = now();
  RETURN NEW;
END;
$$;

-- =============================================================
-- 2. Table parcours_liberal_soignants
-- =============================================================
CREATE TABLE IF NOT EXISTS public.parcours_liberal_soignants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  soignant_id UUID NOT NULL UNIQUE
    REFERENCES public.soignants(id) ON DELETE CASCADE,
  demarre_le TIMESTAMPTZ DEFAULT now(),
  termine_le TIMESTAMPTZ NULL,
  parcours_kine TEXT NULL
    CHECK (parcours_kine IS NULL OR parcours_kine IN ('HEURES_2240', 'ZONE_SOUS_DOTEE')),
  etapes JSONB DEFAULT '{}'::jsonb,
  cree_le TIMESTAMPTZ DEFAULT now(),
  mis_a_jour_le TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_parcours_liberal_soignant
  ON public.parcours_liberal_soignants (soignant_id);

ALTER TABLE public.parcours_liberal_soignants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "soignant_voit_son_parcours" ON public.parcours_liberal_soignants;
CREATE POLICY "soignant_voit_son_parcours"
  ON public.parcours_liberal_soignants FOR SELECT TO authenticated
  USING (soignant_id = auth.uid() OR est_admin());

DROP POLICY IF EXISTS "soignant_modifie_son_parcours" ON public.parcours_liberal_soignants;
CREATE POLICY "soignant_modifie_son_parcours"
  ON public.parcours_liberal_soignants FOR UPDATE TO authenticated
  USING (soignant_id = auth.uid())
  WITH CHECK (soignant_id = auth.uid());

DROP POLICY IF EXISTS "soignant_cree_son_parcours" ON public.parcours_liberal_soignants;
CREATE POLICY "soignant_cree_son_parcours"
  ON public.parcours_liberal_soignants FOR INSERT TO authenticated
  WITH CHECK (soignant_id = auth.uid());

GRANT SELECT, INSERT, UPDATE ON public.parcours_liberal_soignants TO authenticated;

DROP TRIGGER IF EXISTS trg_parcours_liberal_maj ON public.parcours_liberal_soignants;
CREATE TRIGGER trg_parcours_liberal_maj
  BEFORE UPDATE ON public.parcours_liberal_soignants
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_mis_a_jour_le();

-- =============================================================
-- 3. Table heures_externes_soignants
-- =============================================================
CREATE TABLE IF NOT EXISTS public.heures_externes_soignants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  soignant_id UUID NOT NULL
    REFERENCES public.soignants(id) ON DELETE CASCADE,
  etablissement_nom TEXT NOT NULL,
  etablissement_type TEXT NULL,
  date_debut DATE NOT NULL,
  date_fin DATE NOT NULL CHECK (date_fin >= date_debut),
  heures_declarees INTEGER NOT NULL
    CHECK (heures_declarees > 0 AND heures_declarees <= 10000),
  attestation_url TEXT NULL,
  attestation_nom_fichier TEXT NULL,
  statut_validation TEXT DEFAULT 'EN_ATTENTE'
    CHECK (statut_validation IN ('EN_ATTENTE', 'VALIDE', 'REJETE')),
  commentaire_validation TEXT NULL,
  valide_par UUID NULL REFERENCES auth.users(id),
  valide_le TIMESTAMPTZ NULL,
  cree_le TIMESTAMPTZ DEFAULT now(),
  mis_a_jour_le TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_heures_externes_soignant
  ON public.heures_externes_soignants (soignant_id);

ALTER TABLE public.heures_externes_soignants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "soignant_voit_ses_heures_externes" ON public.heures_externes_soignants;
CREATE POLICY "soignant_voit_ses_heures_externes"
  ON public.heures_externes_soignants FOR SELECT TO authenticated
  USING (soignant_id = auth.uid() OR est_admin());

DROP POLICY IF EXISTS "soignant_gere_ses_heures_externes" ON public.heures_externes_soignants;
CREATE POLICY "soignant_gere_ses_heures_externes"
  ON public.heures_externes_soignants FOR INSERT TO authenticated
  WITH CHECK (soignant_id = auth.uid());

DROP POLICY IF EXISTS "soignant_modifie_ses_heures_externes" ON public.heures_externes_soignants;
CREATE POLICY "soignant_modifie_ses_heures_externes"
  ON public.heures_externes_soignants FOR UPDATE TO authenticated
  USING (
    (soignant_id = auth.uid() AND statut_validation = 'EN_ATTENTE')
    OR est_admin()
  )
  WITH CHECK (soignant_id = auth.uid() OR est_admin());

DROP POLICY IF EXISTS "soignant_supprime_ses_heures_en_attente" ON public.heures_externes_soignants;
CREATE POLICY "soignant_supprime_ses_heures_en_attente"
  ON public.heures_externes_soignants FOR DELETE TO authenticated
  USING (soignant_id = auth.uid() AND statut_validation = 'EN_ATTENTE');

GRANT SELECT, INSERT, UPDATE, DELETE ON public.heures_externes_soignants TO authenticated;

DROP TRIGGER IF EXISTS trg_heures_externes_maj ON public.heures_externes_soignants;
CREATE TRIGGER trg_heures_externes_maj
  BEFORE UPDATE ON public.heures_externes_soignants
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_mis_a_jour_le();

-- =============================================================
-- 4. Fonction compteur heures soignant
-- =============================================================
-- Source Jolene : SUM(missions.duree_heures_effective) avec fallback sur
-- missions.duree_heures (planifié) si la mission est TERMINEE mais pas de
-- pointage effectif enregistré. Filtrage sur soignant_assigne_id.
CREATE OR REPLACE FUNCTION public.fn_compteur_heures_soignant(p_soignant_id UUID)
RETURNS TABLE(
  heures_jolene INTEGER,
  heures_externes_validees INTEGER,
  heures_externes_en_attente INTEGER,
  heures_totales INTEGER,
  eligible_free_transition BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_heures_jolene INTEGER := 0;
  v_heures_ext_val INTEGER := 0;
  v_heures_ext_att INTEGER := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  IF auth.uid() != p_soignant_id AND NOT est_admin() THEN
    RAISE EXCEPTION 'Accès non autorisé';
  END IF;

  SELECT COALESCE(SUM(COALESCE(m.duree_heures_effective, m.duree_heures))::INTEGER, 0)
  INTO v_heures_jolene
  FROM public.missions m
  WHERE m.soignant_assigne_id = p_soignant_id
    AND m.statut = 'TERMINEE';

  SELECT COALESCE(SUM(heures_declarees)::INTEGER, 0)
  INTO v_heures_ext_val
  FROM public.heures_externes_soignants
  WHERE soignant_id = p_soignant_id
    AND statut_validation = 'VALIDE';

  SELECT COALESCE(SUM(heures_declarees)::INTEGER, 0)
  INTO v_heures_ext_att
  FROM public.heures_externes_soignants
  WHERE soignant_id = p_soignant_id
    AND statut_validation = 'EN_ATTENTE';

  RETURN QUERY SELECT
    v_heures_jolene,
    v_heures_ext_val,
    v_heures_ext_att,
    v_heures_jolene + v_heures_ext_val,
    v_heures_jolene >= 3200;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_compteur_heures_soignant(UUID) TO authenticated;

-- =============================================================
-- 5. Fonction get_or_create parcours
-- =============================================================
CREATE OR REPLACE FUNCTION public.fn_get_or_create_parcours_liberal(
  p_soignant_id UUID DEFAULT NULL
)
RETURNS public.parcours_liberal_soignants
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_soignant_id UUID;
  v_parcours public.parcours_liberal_soignants;
BEGIN
  v_soignant_id := COALESCE(p_soignant_id, auth.uid());

  IF v_soignant_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  IF v_soignant_id != auth.uid() AND NOT est_admin() THEN
    RAISE EXCEPTION 'Accès non autorisé';
  END IF;

  SELECT * INTO v_parcours
  FROM public.parcours_liberal_soignants
  WHERE soignant_id = v_soignant_id;

  IF NOT FOUND THEN
    INSERT INTO public.parcours_liberal_soignants (soignant_id, etapes)
    VALUES (v_soignant_id, '{}'::jsonb)
    RETURNING * INTO v_parcours;
  END IF;

  RETURN v_parcours;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_get_or_create_parcours_liberal(UUID) TO authenticated;

-- =============================================================
-- 6. Fonction maj étape parcours (JSONB)
-- =============================================================
CREATE OR REPLACE FUNCTION public.fn_maj_etape_parcours(
  p_etape_cle TEXT,
  p_valeur BOOLEAN
)
RETURNS public.parcours_liberal_soignants
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parcours public.parcours_liberal_soignants;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  IF p_etape_cle !~ '^[a-z0-9_]{1,50}$' THEN
    RAISE EXCEPTION 'Clé étape invalide';
  END IF;

  PERFORM public.fn_get_or_create_parcours_liberal();

  UPDATE public.parcours_liberal_soignants
  SET etapes = etapes || jsonb_build_object(
    p_etape_cle, p_valeur,
    p_etape_cle || '_date', CASE WHEN p_valeur THEN to_jsonb(now()::TEXT) ELSE 'null'::jsonb END
  )
  WHERE soignant_id = auth.uid()
  RETURNING * INTO v_parcours;

  RETURN v_parcours;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_maj_etape_parcours(TEXT, BOOLEAN) TO authenticated;

-- =============================================================
-- 7. Fonction choix parcours kiné
-- =============================================================
CREATE OR REPLACE FUNCTION public.fn_choisir_parcours_kine(p_parcours TEXT)
RETURNS public.parcours_liberal_soignants
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parcours public.parcours_liberal_soignants;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  IF p_parcours IS NOT NULL AND p_parcours NOT IN ('HEURES_2240', 'ZONE_SOUS_DOTEE') THEN
    RAISE EXCEPTION 'Parcours kiné invalide';
  END IF;

  PERFORM public.fn_get_or_create_parcours_liberal();

  UPDATE public.parcours_liberal_soignants
  SET parcours_kine = p_parcours
  WHERE soignant_id = auth.uid()
  RETURNING * INTO v_parcours;

  RETURN v_parcours;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_choisir_parcours_kine(TEXT) TO authenticated;

-- =============================================================
-- 8. Bucket Storage attestations + policies
-- =============================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'attestations-heures-externes',
  'attestations-heures-externes',
  false,
  10485760,
  ARRAY['application/pdf', 'image/jpeg', 'image/png']
) ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "soignant_upload_ses_attestations" ON storage.objects;
CREATE POLICY "soignant_upload_ses_attestations"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'attestations-heures-externes'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "soignant_lit_ses_attestations" ON storage.objects;
CREATE POLICY "soignant_lit_ses_attestations"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'attestations-heures-externes'
    AND ((storage.foldername(name))[1] = auth.uid()::text OR est_admin())
  );

DROP POLICY IF EXISTS "soignant_supprime_ses_attestations" ON storage.objects;
CREATE POLICY "soignant_supprime_ses_attestations"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'attestations-heures-externes'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

NOTIFY pgrst, 'reload schema';
