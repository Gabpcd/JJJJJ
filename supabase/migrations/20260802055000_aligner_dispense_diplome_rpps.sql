-- Un RPPS validé par l'API est la preuve officielle de l'inscription et des
-- qualifications enregistrées pour les professions concernées. Il dispense
-- donc du DIPLOME et de l'attestation RPPS_ADELI. Un ADELI validé seul ne
-- dispense que de l'attestation RPPS_ADELI.

-- Le bootstrap de staging restaure le schéma sans les lignes de référence.
-- Réaffirmer ici l'exigence garantit que l'absence de diplôme reste bloquante
-- tant qu'aucun RPPS n'a effectivement été validé par l'API.
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

CREATE OR REPLACE FUNCTION public.fn_document_requis_par_mission_active(
  p_document_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.documents_soignants ds
    JOIN public.soignants s
      ON s.id = ds.soignant_id
     AND s.supprime_le IS NULL
    JOIN public.missions m
      ON m.soignant_assigne_id = ds.soignant_id
     AND m.statut IN ('ASSIGNEE', 'EN_COURS')
    JOIN public.documents_requis_par_profession drp
      ON drp.profession = s.profession
     AND drp.est_critique IS TRUE
     AND (
       drp.type_exercice_requis = 'TOUS'
       OR (
         drp.type_exercice_requis = 'LIBERAL_ONLY'
         AND m.type_contrat_applique::text = 'LIBERAL'
       )
       OR (
         drp.type_exercice_requis = 'SALARIE_ONLY'
         AND m.type_contrat_applique::text <> 'LIBERAL'
       )
     )
     AND public.fn_type_document_preuve_compatible(
       drp.type_document,
       ds.type_document
     )
    WHERE ds.id = p_document_id
      AND ds.supprime_le IS NULL
      AND ds.revoque_le IS NULL
      AND ds.statut_verification = 'VERIFIE'
      AND NOT (
        (
          drp.type_document = 'RPPS_ADELI'
          AND (COALESCE(s.rpps_verifie, false) OR COALESCE(s.adeli_verifie, false))
        )
        OR (
          drp.type_document = 'DIPLOME'
          AND COALESCE(s.rpps_verifie, false)
          AND s.profession::text NOT IN ('AS', 'AES', 'AUXILIAIRE_PUERICULTURE')
        )
      )
      AND (
        drp.a_expiration IS FALSE
        OR (ds.valide_jusqua IS NOT NULL AND ds.valide_jusqua > current_date)
      )
  );
$function$;

REVOKE ALL ON FUNCTION public.fn_document_requis_par_mission_active(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_document_requis_par_mission_active(uuid)
  TO service_role;

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

-- Le changement de statut RPPS doit immédiatement recalculer la complétude,
-- dans les deux sens (validation API comme révocation ultérieure).
CREATE OR REPLACE FUNCTION public.dec_check_coherence_apres_rpps()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF NEW.rpps_verifie IS TRUE AND OLD.rpps_verifie IS NOT TRUE THEN
    PERFORM public.fn_verifier_coherence_identite(NEW.id);
  END IF;

  PERFORM public.fn_calculer_tous_documents_valides(NEW.id);
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_check_coherence_apres_rpps()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_check_coherence_apres_rpps()
  TO service_role;

DROP TRIGGER IF EXISTS trg_check_coherence_rpps ON public.soignants;
CREATE TRIGGER trg_check_coherence_rpps
AFTER UPDATE OF rpps_verifie ON public.soignants
FOR EACH ROW
WHEN (OLD.rpps_verifie IS DISTINCT FROM NEW.rpps_verifie)
EXECUTE FUNCTION public.dec_check_coherence_apres_rpps();

-- Recalcule le booléen présenté par les interfaces avec la même règle que le
-- gate serveur d'affectation et de démarrage de mission.
DO $migration$
DECLARE
  v_soignant_id uuid;
BEGIN
  FOR v_soignant_id IN
    SELECT id
    FROM public.soignants
    WHERE supprime_le IS NULL
    ORDER BY id
  LOOP
    PERFORM public.fn_calculer_tous_documents_valides(v_soignant_id);
  END LOOP;
END;
$migration$;
