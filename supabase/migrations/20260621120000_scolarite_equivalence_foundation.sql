-- Fondation parcours étudiant : attestation de scolarité vérifiée IA → équivalence profession.
-- Appliquée en prod via MCP (enum hors transaction + reste) puis enregistrée.

-- 0. Nouveau type de document (idempotent ; déjà appliqué hors transaction en prod)
ALTER TYPE public.type_document ADD VALUE IF NOT EXISTS 'ATTESTATION_SCOLARITE';

-- 1. Niveau scolaire VÉRIFIÉ (écrit par verify-document sur attestation de scolarité)
ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS scolarite_formation text,
  ADD COLUMN IF NOT EXISTS scolarite_annee_validee integer,
  ADD COLUMN IF NOT EXISTS scolarite_profession_autorisee public.type_profession,
  ADD COLUMN IF NOT EXISTS scolarite_verifiee boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS scolarite_verifiee_le timestamptz;

-- 2. Table d'équivalence (formation + année validée → profession faisant fonction), éditable admin
CREATE TABLE IF NOT EXISTS public.equivalences_scolarite (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  formation text NOT NULL,
  libelle_formation text NOT NULL,
  annee_validee_min integer NOT NULL CHECK (annee_validee_min >= 1),
  profession_autorisee public.type_profession NOT NULL,
  base_reglementaire text,
  actif boolean NOT NULL DEFAULT true,
  cree_le timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_equiv_scolarite UNIQUE (formation, annee_validee_min, profession_autorisee)
);
COMMENT ON TABLE public.equivalences_scolarite IS 'Equivalences etudiant : une formation + une annee validee autorise l''exercice faisant fonction d''une profession. Editable par admin.';

-- 3. Seed : la seule regle deja citee dans l'app (arrete du 3 fevrier 2022)
INSERT INTO public.equivalences_scolarite (formation, libelle_formation, annee_validee_min, profession_autorisee, base_reglementaire)
VALUES ('IFSI', 'Soins infirmiers (IFSI / ESI)', 1, 'AS', 'Arrete du 3 fevrier 2022 - etudiant en soins infirmiers ayant valide la 1re annee : exercice comme aide-soignant (faisant fonction).')
ON CONFLICT ON CONSTRAINT uq_equiv_scolarite DO NOTHING;

-- 4. RLS : admin uniquement (le calcul d'eligibilite passe par la RPC SECURITY DEFINER)
ALTER TABLE public.equivalences_scolarite ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS equiv_scolarite_admin_all ON public.equivalences_scolarite;
CREATE POLICY equiv_scolarite_admin_all ON public.equivalences_scolarite
  FOR ALL USING (public.est_admin()) WITH CHECK (public.est_admin());

-- 5. RPC : professions autorisees pour (formation, annee validee)
CREATE OR REPLACE FUNCTION public.fn_professions_autorisees_scolarite(p_formation text, p_annee_validee integer)
RETURNS SETOF public.type_profession
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT DISTINCT e.profession_autorisee
  FROM public.equivalences_scolarite e
  WHERE e.actif = true
    AND lower(e.formation) = lower(p_formation)
    AND p_annee_validee >= e.annee_validee_min;
$$;
GRANT EXECUTE ON FUNCTION public.fn_professions_autorisees_scolarite(text, integer) TO anon, authenticated, service_role;
