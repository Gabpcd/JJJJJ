-- Une tentative de vérification documentaire possède un jeton serveur unique.
-- Une réponse IA ancienne ne peut donc jamais écraser une tentative plus
-- récente. La finalisation verrouille document + profil et revalide toutes les
-- données métier utilisées par l'analyse avant d'écrire le verdict.

ALTER TABLE public.documents_soignants
  ADD COLUMN IF NOT EXISTS verification_attempt_id uuid;

COMMENT ON COLUMN public.documents_soignants.verification_attempt_id IS
  'Jeton interne éphémère de la tentative de vérification automatique active.';

CREATE OR REPLACE FUNCTION public.fn_proteger_tentative_verification_document()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.role() = 'service_role'
     OR auth.uid() IS NULL
     OR public.est_admin()
     OR COALESCE(current_setting('jolene.document_server_update', true), '') = 'true'
     OR COALESCE(current_setting('jolene.system_update', true), '') = 'true' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.verification_attempt_id := NULL;
  ELSIF NEW.verification_attempt_id IS DISTINCT FROM OLD.verification_attempt_id THEN
    RAISE EXCEPTION 'Modification de la tentative de vérification interdite'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_proteger_tentative_verification_document
  ON public.documents_soignants;
CREATE TRIGGER trg_proteger_tentative_verification_document
BEFORE INSERT OR UPDATE OF verification_attempt_id ON public.documents_soignants
FOR EACH ROW EXECUTE FUNCTION public.fn_proteger_tentative_verification_document();

REVOKE ALL ON FUNCTION public.fn_proteger_tentative_verification_document()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_proteger_tentative_verification_document()
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_finaliser_document_verification(
  p_document_id uuid,
  p_attempt_id uuid,
  p_expected_soignant_id uuid,
  p_expected_s3_bucket text,
  p_expected_s3_cle text,
  p_expected_type_document text,
  p_expected_nom text,
  p_expected_prenom text,
  p_expected_date_naissance date,
  p_expected_sexe text,
  p_expected_lieu_naissance text,
  p_expected_profession text,
  p_expected_numero_rpps text,
  p_expected_numero_adeli text,
  p_expected_rpps_verifie boolean,
  p_expected_adeli_verifie boolean,
  p_statut_verification text,
  p_motif_rejet text DEFAULT NULL,
  p_valide_depuis date DEFAULT NULL,
  p_valide_jusqua date DEFAULT NULL,
  p_resultat_ia jsonb DEFAULT NULL,
  p_nom_extrait_ia text DEFAULT NULL,
  p_prenom_extrait_ia text DEFAULT NULL,
  p_score_confiance_ia numeric DEFAULT NULL,
  p_coherence_nom boolean DEFAULT NULL,
  p_identite_date_naissance date DEFAULT NULL,
  p_identite_sexe text DEFAULT NULL,
  p_identite_lieu_naissance text DEFAULT NULL,
  p_scolarite_formation text DEFAULT NULL,
  p_scolarite_annee_validee integer DEFAULT NULL,
  p_scolarite_profession text DEFAULT NULL,
  p_licence_valide_jusqua date DEFAULT NULL,
  p_licence_specialite text DEFAULT NULL,
  p_expected_heures_employeur text DEFAULT NULL,
  p_expected_heures_date_debut date DEFAULT NULL,
  p_expected_heures_date_fin date DEFAULT NULL,
  p_expected_heures_declarees numeric DEFAULT NULL,
  p_expected_heures_type_preuve text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_doc public.documents_soignants%ROWTYPE;
  v_soignant public.soignants%ROWTYPE;
  v_heures public.heures_externes%ROWTYPE;
  v_statut public.statut_verification;
  v_coherence_nom boolean := p_coherence_nom;
  v_identite boolean;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501';
  END IF;
  IF p_document_id IS NULL OR p_attempt_id IS NULL OR p_expected_soignant_id IS NULL THEN
    RAISE EXCEPTION 'Tentative documentaire incomplète' USING ERRCODE = '22023';
  END IF;
  IF p_statut_verification NOT IN ('VERIFIE', 'EN_ATTENTE', 'REJETE') THEN
    RAISE EXCEPTION 'Verdict documentaire invalide' USING ERRCODE = '22023';
  END IF;
  v_statut := p_statut_verification::public.statut_verification;

  SELECT * INTO v_doc
  FROM public.documents_soignants
  WHERE id = p_document_id
    AND verification_attempt_id = p_attempt_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tentative documentaire périmée' USING ERRCODE = '40001';
  END IF;

  IF v_doc.soignant_id IS DISTINCT FROM p_expected_soignant_id
     OR v_doc.s3_bucket IS DISTINCT FROM p_expected_s3_bucket
     OR v_doc.s3_cle IS DISTINCT FROM p_expected_s3_cle
     OR v_doc.type_document::text IS DISTINCT FROM p_expected_type_document
     OR v_doc.supprime_le IS NOT NULL THEN
    RAISE EXCEPTION 'Source documentaire modifiée pendant la vérification'
      USING ERRCODE = '40001';
  END IF;

  SELECT * INTO v_soignant
  FROM public.soignants
  WHERE id = p_expected_soignant_id AND supprime_le IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profil soignant introuvable' USING ERRCODE = 'P0002';
  END IF;

  IF v_soignant.nom IS DISTINCT FROM p_expected_nom
     OR v_soignant.prenom IS DISTINCT FROM p_expected_prenom
     OR v_soignant.date_naissance IS DISTINCT FROM p_expected_date_naissance
     OR v_soignant.sexe IS DISTINCT FROM p_expected_sexe
     OR v_soignant.lieu_naissance_commune IS DISTINCT FROM p_expected_lieu_naissance
     OR v_soignant.profession::text IS DISTINCT FROM p_expected_profession
     OR v_soignant.numero_rpps IS DISTINCT FROM p_expected_numero_rpps
     OR v_soignant.numero_adeli IS DISTINCT FROM p_expected_numero_adeli
     OR COALESCE(v_soignant.rpps_verifie, false) IS DISTINCT FROM COALESCE(p_expected_rpps_verifie, false)
     OR COALESCE(v_soignant.adeli_verifie, false) IS DISTINCT FROM COALESCE(p_expected_adeli_verifie, false) THEN
    RAISE EXCEPTION 'Profil modifié pendant la vérification'
      USING ERRCODE = '40001';
  END IF;

  v_identite := v_doc.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR');
  IF v_identite THEN
    v_coherence_nom := public.fn_noms_personne_correspondent(
      v_soignant.nom, v_soignant.prenom, p_nom_extrait_ia, p_prenom_extrait_ia
    );
  END IF;

  IF v_identite AND v_statut = 'VERIFIE' THEN
    IF NOT v_coherence_nom OR p_identite_date_naissance IS NULL THEN
      RAISE EXCEPTION 'Identité extraite incomplète ou incohérente' USING ERRCODE = '23514';
    END IF;
    IF v_soignant.date_naissance IS NOT NULL
       AND v_soignant.date_naissance IS DISTINCT FROM p_identite_date_naissance THEN
      RAISE EXCEPTION 'Date de naissance incohérente' USING ERRCODE = '23514';
    END IF;

    UPDATE public.soignants
    SET date_naissance = COALESCE(date_naissance, p_identite_date_naissance),
        sexe = CASE
          WHEN sexe IS NULL AND p_identite_sexe IN ('M', 'F') THEN p_identite_sexe
          ELSE sexe
        END,
        lieu_naissance_commune = CASE
          WHEN lieu_naissance_commune IS NULL
               AND NULLIF(btrim(p_identite_lieu_naissance), '') IS NOT NULL
            THEN left(btrim(p_identite_lieu_naissance), 120)
          ELSE lieu_naissance_commune
        END,
        modifie_le = now()
    WHERE id = v_soignant.id;
  END IF;

  IF p_scolarite_formation IS NOT NULL
     OR p_scolarite_annee_validee IS NOT NULL
     OR p_scolarite_profession IS NOT NULL THEN
    IF v_statut IS DISTINCT FROM 'VERIFIE'
       OR v_doc.type_document IS DISTINCT FROM 'ATTESTATION_SCOLARITE'
       OR p_scolarite_formation IS NULL
       OR p_scolarite_annee_validee IS NULL
       OR p_scolarite_profession IS DISTINCT FROM v_soignant.profession::text
       OR NOT EXISTS (
         SELECT 1
         FROM public.fn_professions_autorisees_scolarite(
           p_scolarite_formation,
           p_scolarite_annee_validee
         ) AS profession_autorisee
         WHERE profession_autorisee = v_soignant.profession
       ) THEN
      RAISE EXCEPTION 'Effet de scolarité incohérent' USING ERRCODE = '23514';
    END IF;

    UPDATE public.soignants
    SET scolarite_formation = left(p_scolarite_formation, 50),
        scolarite_annee_validee = p_scolarite_annee_validee,
        scolarite_profession_autorisee = v_soignant.profession,
        scolarite_verifiee = true,
        scolarite_verifiee_le = now(),
        est_etudiant = true,
        modifie_le = now()
    WHERE id = v_soignant.id;
  END IF;

  IF p_licence_valide_jusqua IS NOT NULL OR p_licence_specialite IS NOT NULL THEN
    IF v_statut IS DISTINCT FROM 'VERIFIE'
       OR v_doc.type_document IS DISTINCT FROM 'LICENCE_REMPLACEMENT'
       OR v_soignant.profession::text IS DISTINCT FROM 'MEDECIN'
       OR p_licence_valide_jusqua IS NULL
       OR p_licence_valide_jusqua < current_date
       OR NULLIF(btrim(p_licence_specialite), '') IS NULL THEN
      RAISE EXCEPTION 'Effet de licence incohérent' USING ERRCODE = '23514';
    END IF;

    UPDATE public.soignants
    SET licence_remplacement_verifiee = true,
        licence_remplacement_le = now(),
        licence_remplacement_valide_jusqua = p_licence_valide_jusqua,
        licence_remplacement_specialite = left(btrim(p_licence_specialite), 200),
        est_etudiant = true,
        modifie_le = now()
    WHERE id = v_soignant.id;
  END IF;

  IF v_statut = 'VERIFIE'
     AND v_doc.type_document::text IN ('BULLETIN_PAIE', 'ATTESTATION_EMPLOYEUR', 'CERTIFICAT_TRAVAIL') THEN
    SELECT * INTO v_heures
    FROM public.heures_externes
    WHERE document_id = v_doc.id AND soignant_id = v_soignant.id
    FOR SHARE;
    IF NOT FOUND
       OR v_heures.employeur_nom IS DISTINCT FROM p_expected_heures_employeur
       OR v_heures.date_debut IS DISTINCT FROM p_expected_heures_date_debut
       OR v_heures.date_fin IS DISTINCT FROM p_expected_heures_date_fin
       OR v_heures.heures_declarees IS DISTINCT FROM p_expected_heures_declarees
       OR v_heures.type_preuve IS DISTINCT FROM p_expected_heures_type_preuve THEN
      RAISE EXCEPTION 'Déclaration d''heures modifiée pendant la vérification'
        USING ERRCODE = '40001';
    END IF;
  END IF;

  UPDATE public.documents_soignants
  SET resultat_ia = p_resultat_ia,
      nom_extrait_ia = NULLIF(left(btrim(COALESCE(p_nom_extrait_ia, '')), 200), ''),
      prenom_extrait_ia = NULLIF(left(btrim(COALESCE(p_prenom_extrait_ia, '')), 200), ''),
      score_confiance_ia = CASE
        WHEN p_score_confiance_ia IS NULL THEN NULL
        ELSE greatest(0, least(100, p_score_confiance_ia))
      END,
      coherence_nom = v_coherence_nom,
      statut_verification = v_statut,
      motif_rejet = NULLIF(left(COALESCE(p_motif_rejet, ''), 1000), ''),
      valide_depuis = CASE WHEN v_statut = 'REJETE' THEN NULL ELSE p_valide_depuis END,
      valide_jusqua = CASE WHEN v_statut = 'REJETE' THEN NULL ELSE p_valide_jusqua END,
      verifie_le = CASE WHEN v_statut = 'VERIFIE' THEN now() ELSE NULL END,
      verification_attempt_id = NULL,
      modifie_le = now()
  WHERE id = v_doc.id AND verification_attempt_id = p_attempt_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tentative documentaire remplacée' USING ERRCODE = '40001';
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_finaliser_document_verification(
  uuid, uuid, uuid, text, text, text, text, text, date, text, text, text,
  text, text, boolean, boolean, text, text, date, date, jsonb, text, text,
  numeric, boolean, date, text, text, text, integer, text, date, text,
  text, date, date, numeric, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_finaliser_document_verification(
  uuid, uuid, uuid, text, text, text, text, text, date, text, text, text,
  text, text, boolean, boolean, text, text, date, date, jsonb, text, text,
  numeric, boolean, date, text, text, text, integer, text, date, text,
  text, date, date, numeric, text
) TO service_role;
