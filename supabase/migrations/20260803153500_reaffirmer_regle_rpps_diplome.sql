-- Répare un drift observé sur le staging : la migration de référence était
-- marquée appliquée, mais la règle effective ne rétablissait plus le diplôme
-- après révocation du RPPS. Cette migration est volontairement idempotente.

INSERT INTO public.documents_requis_par_profession AS drp (
  profession,
  type_document,
  est_critique,
  a_expiration,
  duree_validite_mois,
  description,
  type_exercice_requis
)
SELECT
  p.profession,
  'DIPLOME'::public.type_document,
  true,
  false,
  NULL,
  'Diplôme requis hors dispense accordée par un RPPS validé par l''API.',
  'TOUS'
FROM unnest(enum_range(NULL::public.type_profession)) AS p(profession)
ON CONFLICT (profession, type_document) DO UPDATE
SET est_critique = true,
    a_expiration = false,
    duree_validite_mois = NULL,
    type_exercice_requis = 'TOUS',
    description = COALESCE(NULLIF(drp.description, ''), EXCLUDED.description);

CREATE OR REPLACE FUNCTION public.fn_documents_ok_pour_mission(
  p_soignant_id uuid,
  p_type_contrat text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_profession public.type_profession;
  v_rpps_verifie boolean;
  v_identifiant_officiel boolean;
  v_regime_liberal boolean;
  v_liberal_actif boolean;
BEGIN
  IF p_soignant_id IS NULL THEN RETURN false; END IF;

  IF current_user NOT IN ('postgres', 'supabase_admin', 'service_role')
     AND COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Calcul documentaire réservé au service interne.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT profession,
         COALESCE(rpps_verifie, false)
           AND profession::text NOT IN ('AS', 'AES', 'AUXILIAIRE_PUERICULTURE'),
         COALESCE(rpps_verifie, false) OR COALESCE(adeli_verifie, false),
         COALESCE(statut_compte::text, 'ACTIF') = 'ACTIF'
           AND COALESCE(type_exercice, 'SALARIE') IN ('LIBERAL', 'MIXTE')
           AND statut_liberal = 'ACTIF'
           AND siret_liberal ~ '^[0-9]{14}$'
           AND siret_liberal_verifie IS TRUE
           AND siret_liberal_verifie_le IS NOT NULL
           AND siret_liberal_coherence_identite IS TRUE
    INTO v_profession, v_rpps_verifie, v_identifiant_officiel, v_liberal_actif
  FROM public.soignants
  WHERE id = p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND OR v_profession IS NULL THEN RETURN false; END IF;

  v_regime_liberal := upper(COALESCE(p_type_contrat, 'SALARIE')) = 'LIBERAL';
  IF v_regime_liberal AND NOT COALESCE(v_liberal_actif, false) THEN
    RETURN false;
  END IF;

  RETURN NOT EXISTS (
    SELECT 1
    FROM public.documents_requis_par_profession drp
    WHERE drp.profession = v_profession
      AND drp.est_critique IS TRUE
      AND (
        drp.type_exercice_requis = 'TOUS'
        OR (drp.type_exercice_requis = 'LIBERAL_ONLY' AND v_regime_liberal)
        OR (drp.type_exercice_requis = 'SALARIE_ONLY' AND NOT v_regime_liberal)
      )
      AND NOT (
        (drp.type_document = 'RPPS_ADELI' AND v_identifiant_officiel)
        OR (drp.type_document = 'DIPLOME' AND v_rpps_verifie)
        OR EXISTS (
          SELECT 1
          FROM public.documents_soignants ds
          WHERE ds.soignant_id = p_soignant_id
            AND public.fn_type_document_preuve_compatible(
              drp.type_document,
              ds.type_document
            )
            AND ds.statut_verification = 'VERIFIE'
            AND ds.supprime_le IS NULL
            AND ds.revoque_le IS NULL
            AND (
              drp.a_expiration IS FALSE
              OR (ds.valide_jusqua IS NOT NULL AND ds.valide_jusqua > current_date)
            )
            AND (
              drp.type_document <> 'DIPLOME'
              OR v_profession NOT IN ('IADE', 'IBODE')
              OR upper(COALESCE(ds.resultat_ia->>'profession_certifiee', ''))
                   = v_profession::text
            )
        )
      )
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_documents_ok_pour_mission(uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_documents_ok_pour_mission(uuid, text)
  TO service_role;

COMMENT ON FUNCTION public.fn_documents_ok_pour_mission(uuid, text) IS
  'Vérifie les preuves critiques. RPPS API vérifié : dispense DIPLOME et RPPS_ADELI ; ADELI seul : dispense RPPS_ADELI uniquement.';

DO $assertions$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.documents_requis_par_profession
    WHERE profession = 'IDE'
      AND type_document = 'DIPLOME'
      AND est_critique IS TRUE
      AND type_exercice_requis = 'TOUS'
  ) THEN
    RAISE EXCEPTION 'Le diplôme IDE doit rester une preuve critique hors dispense RPPS';
  END IF;
END;
$assertions$;
