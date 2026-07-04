-- J2.1.B.2.3.B — Rappels J-1 contrat de travail SALARIE
-- Table tracking idempotence (1 row par mission par jour)
--
-- Note (2026-04-29) : ce fichier + 20260429140000_j2_onboarding_etab_contrat_rib
-- ont été appliqués via MCP `apply_migration` puis enregistrés manuellement
-- dans supabase_migrations.schema_migrations pour que `supabase db push`
-- les skippe sans tenter de les ré-exécuter (CREATE TABLE IF NOT EXISTS
-- est idempotent mais CREATE POLICY échoue en doublon).

CREATE TABLE IF NOT EXISTS public.rappels_contrat_travail (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  mission_id uuid NOT NULL REFERENCES public.missions(id),
  envoye_le date NOT NULL DEFAULT CURRENT_DATE,
  cible_etab boolean NOT NULL DEFAULT false,
  cible_soignant boolean NOT NULL DEFAULT false,
  cree_le timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uniq_rappel_mission_jour
  ON public.rappels_contrat_travail (mission_id, envoye_le);

ALTER TABLE public.rappels_contrat_travail ENABLE ROW LEVEL SECURITY;
CREATE POLICY rct_admin_select ON public.rappels_contrat_travail
  FOR SELECT TO authenticated USING (est_admin());
GRANT SELECT, INSERT ON public.rappels_contrat_travail TO authenticated, service_role;

-- RPC liste missions SALARIE J-1 sans contrat uploadé, non rappelées aujourd'hui
CREATE OR REPLACE FUNCTION public.fn_lister_missions_contrat_travail_manquant()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_result jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mission_id', m.id, 'etablissement_id', m.etablissement_id,
    'soignant_id', m.soignant_assigne_id, 'intitule', m.intitule,
    'debut_le', m.debut_le, 'nom_etablissement', e.nom,
    'prenom_soignant', s.prenom, 'nom_soignant', s.nom
  )), '[]'::jsonb)
  INTO v_result
  FROM missions m
  JOIN etablissements e ON e.id = m.etablissement_id
  JOIN soignants s ON s.id = m.soignant_assigne_id
  WHERE m.statut IN ('ASSIGNEE','EN_COURS')
    AND m.type_contrat_applique = 'SALARIE'
    AND m.debut_le >= now()
    AND m.debut_le < now() + INTERVAL '36 hours'
    AND m.soignant_assigne_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM contrats_travail_missions ct WHERE ct.mission_id = m.id)
    AND NOT EXISTS (SELECT 1 FROM rappels_contrat_travail rct
                    WHERE rct.mission_id = m.id AND rct.envoye_le = CURRENT_DATE);
  RETURN v_result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_lister_missions_contrat_travail_manquant() TO service_role;

-- RPC marquer rappel envoyé (idempotence par jour)
CREATE OR REPLACE FUNCTION public.fn_marquer_rappel_contrat_travail_envoye(
  p_mission_id uuid, p_cible_etab boolean, p_cible_soignant boolean
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  INSERT INTO rappels_contrat_travail (mission_id, cible_etab, cible_soignant)
  VALUES (p_mission_id, p_cible_etab, p_cible_soignant)
  ON CONFLICT (mission_id, envoye_le) DO UPDATE
    SET cible_etab = rappels_contrat_travail.cible_etab OR EXCLUDED.cible_etab,
        cible_soignant = rappels_contrat_travail.cible_soignant OR EXCLUDED.cible_soignant;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_marquer_rappel_contrat_travail_envoye(uuid, boolean, boolean) TO service_role;

NOTIFY pgrst, 'reload schema';
