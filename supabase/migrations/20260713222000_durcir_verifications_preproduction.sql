-- Préproduction stores : vérifications documentaires déterministes, gates
-- cohérents et isolation stricte des pièces privées.
-- Cette migration ne supprime ni ne masque aucune donnée de démonstration.

-- Les justificatifs d'heures externes étaient envoyés avec des valeurs absentes
-- de l'enum : le parcours échouait avant même l'analyse documentaire.
ALTER TYPE public.type_document ADD VALUE IF NOT EXISTS 'BULLETIN_PAIE';
ALTER TYPE public.type_document ADD VALUE IF NOT EXISTS 'ATTESTATION_EMPLOYEUR';
ALTER TYPE public.type_document ADD VALUE IF NOT EXISTS 'CERTIFICAT_TRAVAIL';

-- ---------------------------------------------------------------------------
-- 1. Preuves structurées et contraintes de rattachement
-- ---------------------------------------------------------------------------

ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS siret_liberal_verifie boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS siret_liberal_verifie_le timestamptz,
  ADD COLUMN IF NOT EXISTS siret_liberal_raison_sociale text,
  ADD COLUMN IF NOT EXISTS siret_liberal_coherence_identite boolean;

-- Une spécialité déclarative ne doit jamais alimenter le matching médical.
-- On conserve la saisie pour l'interface dans un champ distinct, tandis que
-- specialite_medicale reste exclusivement alimentée par la preuve RPPS.
ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS specialite_medicale_declaree text;

UPDATE public.soignants
SET specialite_medicale_declaree = COALESCE(specialite_medicale_declaree, specialite_medicale),
    specialite_medicale = NULL,
    specialite_code = NULL,
    specialite_source = NULL
WHERE COALESCE(specialite_verifiee, false) = false
  AND specialite_medicale IS NOT NULL;

REVOKE UPDATE (specialite_medicale, specialite_code, specialite_source) ON public.soignants FROM authenticated;
GRANT UPDATE (specialite_medicale_declaree) ON public.soignants TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_protect_specialite_medicale_verifiee()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.role() = 'service_role' OR auth.uid() IS NULL OR public.est_admin()
     OR COALESCE(current_setting('jolene.system_update', true), '') = 'true' THEN
    RETURN NEW;
  END IF;
  IF OLD.id = auth.uid() THEN
    NEW.specialite_medicale := OLD.specialite_medicale;
    NEW.specialite_code := OLD.specialite_code;
    NEW.specialite_source := OLD.specialite_source;
    NEW.specialite_verifiee := OLD.specialite_verifiee;
    NEW.specialite_verifiee_le := OLD.specialite_verifiee_le;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_specialite_medicale_verifiee ON public.soignants;
CREATE TRIGGER trg_protect_specialite_medicale_verifiee
BEFORE UPDATE ON public.soignants
FOR EACH ROW EXECUTE FUNCTION public.fn_protect_specialite_medicale_verifiee();
REVOKE ALL ON FUNCTION public.fn_protect_specialite_medicale_verifiee() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_protect_specialite_medicale_verifiee() TO service_role;

COMMENT ON COLUMN public.soignants.siret_liberal_verifie IS
  'Vrai uniquement après contrôle du registre officiel et concordance avec l identité du soignant.';

ALTER TABLE public.etablissements
  DROP CONSTRAINT IF EXISTS etablissements_rattachement_methode_check;
ALTER TABLE public.etablissements
  ADD CONSTRAINT etablissements_rattachement_methode_check
  CHECK (rattachement_methode IS NULL OR rattachement_methode IN (
    'AUTO_DIRIGEANT', 'JUSTIFICATIF', 'ADMIN'
  ));

CREATE OR REPLACE FUNCTION public.fn_evaluer_rattachement_etablissement(
  p_etablissement_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_etab record;
  v_methode text := 'ADMIN';
  v_verifie boolean := false;
  v_match boolean := false;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role'
     AND NOT (public.est_admin() OR p_etablissement_id = public.mon_etablissement_id()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  SELECT dirigeants, representant_nom, representant_prenom,
         representant_identite_verifiee, justificatif_fonction_verifie
    INTO v_etab
  FROM public.etablissements
  WHERE id = p_etablissement_id AND supprime_le IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Établissement introuvable');
  END IF;

  IF v_etab.representant_identite_verifiee IS TRUE
     AND NULLIF(btrim(v_etab.representant_nom), '') IS NOT NULL
     AND jsonb_typeof(v_etab.dirigeants) = 'array' THEN
    SELECT true INTO v_match
    FROM jsonb_array_elements(v_etab.dirigeants) AS d
    WHERE public.fn_normaliser_nom(d->>'type_dirigeant') LIKE '%physique%'
      AND public.fn_normaliser_nom(d->>'nom') = public.fn_normaliser_nom(v_etab.representant_nom)
      AND NULLIF(public.fn_normaliser_nom(v_etab.representant_prenom), '') IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM unnest(regexp_split_to_array(public.fn_normaliser_nom(v_etab.representant_prenom), ' +')) AS attendu(prenom)
        WHERE attendu.prenom <> ''
          AND NOT (
            attendu.prenom = ANY (
              regexp_split_to_array(public.fn_normaliser_nom(d->>'prenoms'), ' +')
            )
          )
      )
    LIMIT 1;
    IF v_match IS TRUE THEN
      v_methode := 'AUTO_DIRIGEANT';
      v_verifie := true;
    END IF;
  END IF;

  IF NOT v_verifie
     AND v_etab.representant_identite_verifiee IS TRUE
     AND v_etab.justificatif_fonction_verifie IS TRUE THEN
    v_methode := 'JUSTIFICATIF';
    v_verifie := true;
  END IF;

  UPDATE public.etablissements
  SET rattachement_methode = v_methode,
      rattachement_verifie = v_verifie,
      rattachement_verifie_le = CASE WHEN v_verifie THEN now() ELSE NULL END,
      modifie_le = now()
  WHERE id = p_etablissement_id;

  RETURN jsonb_build_object(
    'success', true,
    'methode', v_methode,
    'verifie', v_verifie,
    'match_dirigeant', COALESCE(v_match, false)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_evaluer_rattachement_etablissement(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_evaluer_rattachement_etablissement(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Gate unique de publication établissement
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_blocage_publication_etab(p_etab_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v record;
BEGIN
  IF public.est_admin() THEN RETURN NULL; END IF;
  IF p_etab_id IS NULL THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;

  SELECT peut_publier_missions, statut_verification, contrat_service_signe,
         bloque_auto_le, bloque_auto_raisons, finess_verifie,
         siret_verifie, representant_identite_verifiee, rattachement_verifie
    INTO v
  FROM public.etablissements
  WHERE id = p_etab_id AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Établissement introuvable'); END IF;

  IF v.peut_publier_missions IS NOT TRUE OR v.statut_verification <> 'VERIFIE' THEN
    RETURN jsonb_build_object(
      'error', 'ETABLISSEMENT_NON_VERIFIE',
      'message', 'Votre établissement doit être vérifié avant de publier des missions.'
    );
  END IF;
  IF v.siret_verifie IS NOT TRUE OR v.finess_verifie IS NOT TRUE
     OR v.representant_identite_verifiee IS NOT TRUE
     OR v.rattachement_verifie IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'error', 'VERIFICATION_INCOMPLETE',
      'message', 'Les contrôles SIRET, FINESS, identité et habilitation du représentant doivent être validés.',
      'siret_verifie', COALESCE(v.siret_verifie, false),
      'finess_verifie', COALESCE(v.finess_verifie, false),
      'identite_verifiee', COALESCE(v.representant_identite_verifiee, false),
      'rattachement_verifie', COALESCE(v.rattachement_verifie, false)
    );
  END IF;
  IF v.contrat_service_signe IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'error', 'CONTRAT_SERVICE_REQUIS',
      'message', 'Le contrat de service Jolene doit être signé avant de publier des missions.'
    );
  END IF;
  IF v.bloque_auto_le IS NOT NULL THEN
    RETURN jsonb_build_object(
      'error', 'PUBLICATION_SUSPENDUE',
      'message', 'Publication suspendue en raison d obligations de paiement à régulariser.',
      'bloque_auto_le', v.bloque_auto_le,
      'raisons', v.bloque_auto_raisons
    );
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.factures
    WHERE etablissement_id = p_etab_id
      AND statut IN ('EMISE', 'EN_RETARD')
      AND date_echeance < current_date
  ) THEN
    RETURN jsonb_build_object('error', 'FACTURES_IMPAYEES', 'message', 'Vous avez des factures impayées à régulariser.');
  END IF;
  RETURN NULL;
END;
$$;

-- Le même verrou doit s'appliquer aux INSERT PostgREST directs. Le trigger
-- historique ne contrôlait pas le statut, le droit de publier, SIRET ni FINESS
-- et son bypass via un custom GUC était positionnable par un client SQL.
CREATE OR REPLACE FUNCTION public.fn_trg_verifier_onboarding_etab()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_blocage jsonb;
BEGIN
  IF public.est_admin() OR auth.role() = 'service_role' THEN
    RETURN NEW;
  END IF;

  v_blocage := public.fn_blocage_publication_etab(NEW.etablissement_id);
  IF v_blocage IS NOT NULL THEN
    RAISE EXCEPTION '%', COALESCE(v_blocage->>'message', v_blocage->>'error', 'Publication de mission interdite')
      USING ERRCODE = 'check_violation', DETAIL = v_blocage::text;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_trg_verifier_onboarding_etab() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_trg_verifier_onboarding_etab() TO service_role;

-- ---------------------------------------------------------------------------
-- 3. Gate documents soignant : preuve officielle ≠ simple image téléversée
-- ---------------------------------------------------------------------------

-- Source de vérité unique pour l'exercice libéral. Le choix déclaratif du
-- profil ne vaut jamais activation : il faut un SIRET courant, contrôlé dans
-- le registre officiel, rattaché à l'identité du soignant et un statut actif.
CREATE OR REPLACE FUNCTION public.fn_soignant_liberal_actif_verifie(
  p_soignant_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.soignants s
    WHERE s.id = p_soignant_id
      AND s.supprime_le IS NULL
      AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
      AND COALESCE(s.type_exercice, 'SALARIE') IN ('LIBERAL', 'MIXTE')
      AND s.statut_liberal = 'ACTIF'
      AND s.siret_liberal ~ '^[0-9]{14}$'
      AND s.siret_liberal_verifie IS TRUE
      AND s.siret_liberal_verifie_le IS NOT NULL
      AND s.siret_liberal_coherence_identite IS TRUE
  );
$$;

REVOKE ALL ON FUNCTION public.fn_soignant_liberal_actif_verifie(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_soignant_liberal_actif_verifie(uuid)
  TO service_role;

-- La résolution canonique ne se fie plus à type_exercice seul. Une ancienne
-- valeur LIBERAL/MIXTE sans preuve complète retombe en salarié pour une mission
-- TOUS, et un choix libéral explicite échoue fermé.
CREATE OR REPLACE FUNCTION public.fn_resoudre_contrat_mission(
  p_mission_id uuid,
  p_soignant_id uuid,
  p_choix_contrat text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_mission record;
  v_soignant record;
  v_etablissement record;
  v_recherche text;
  v_choix text;
  v_mode jsonb;
  v_liberal_verifie boolean := false;
BEGIN
  SELECT id, profession_requise, type_contrat_recherche, etablissement_id
    INTO v_mission
  FROM public.missions
  WHERE id = p_mission_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Mission introuvable');
  END IF;

  SELECT id, COALESCE(type_exercice, 'SALARIE') AS type_exercice,
         preference_contrat_mixte, COALESCE(est_compte_test, false) AS est_compte_test
    INTO v_soignant
  FROM public.soignants
  WHERE id = p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Profil soignant introuvable');
  END IF;

  v_liberal_verifie := public.fn_soignant_liberal_actif_verifie(p_soignant_id);

  SELECT type::text AS type_etablissement,
         COALESCE(est_secteur_public, false) AS est_public,
         COALESCE(est_compte_test, false) AS est_compte_test
    INTO v_etablissement
  FROM public.etablissements
  WHERE id = v_mission.etablissement_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Établissement introuvable');
  END IF;

  IF v_etablissement.est_compte_test AND NOT v_soignant.est_compte_test THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Mission de démonstration non disponible');
  END IF;

  IF p_choix_contrat IS NOT NULL
     AND upper(p_choix_contrat) NOT IN ('SALARIE', 'LIBERAL') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Choix de contrat invalide');
  END IF;

  v_recherche := CASE
    WHEN upper(COALESCE(v_mission.type_contrat_recherche::text, 'SALARIE'))
           IN ('SALARIE', 'LIBERAL', 'TOUS')
      THEN upper(COALESCE(v_mission.type_contrat_recherche::text, 'SALARIE'))
    ELSE 'SALARIE'
  END;

  IF v_recherche = 'SALARIE' THEN
    -- Le diplôme ou le statut du profil ne bloque jamais une mission salariée.
    v_choix := 'SALARIE';
  ELSIF v_recherche = 'LIBERAL' THEN
    IF v_soignant.type_exercice NOT IN ('LIBERAL', 'MIXTE')
       OR NOT v_liberal_verifie THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'Cette mission est proposée en libéral ; activez un profil libéral avec SIRET et identité vérifiés.'
      );
    END IF;
    v_choix := 'LIBERAL';
  ELSE
    v_choix := upper(p_choix_contrat);

    IF v_choix = 'LIBERAL' AND NOT v_liberal_verifie THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'Votre profil libéral doit être actif, avec SIRET et identité vérifiés.'
      );
    END IF;

    IF v_choix IS NULL THEN
      IF v_soignant.type_exercice = 'MIXTE' AND v_liberal_verifie THEN
        v_choix := CASE
          WHEN upper(COALESCE(v_soignant.preference_contrat_mixte, ''))
                 IN ('SALARIE', 'LIBERAL')
            THEN upper(v_soignant.preference_contrat_mixte)
          ELSE NULL
        END;
        IF v_choix IS NULL THEN
          RETURN jsonb_build_object(
            'ok', false,
            'choix_requis', true,
            'error', 'Choisissez votre mode de contrat.',
            'options', jsonb_build_array(
              jsonb_build_object('value', 'SALARIE', 'label', 'Salarié (CDD / bulletin de paie)'),
              jsonb_build_object('value', 'LIBERAL', 'label', 'Libéral (note d''honoraires)')
            )
          );
        END IF;
      ELSIF v_soignant.type_exercice = 'LIBERAL' AND v_liberal_verifie THEN
        v_choix := 'LIBERAL';
      ELSE
        -- Valeur de profil héritée/incohérente : aucun contrat libéral implicite.
        v_choix := 'SALARIE';
      END IF;
    END IF;

    IF v_choix = 'LIBERAL'
       AND (v_soignant.type_exercice NOT IN ('LIBERAL', 'MIXTE')
            OR NOT v_liberal_verifie) THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'Votre profil n''est pas activé pour un contrat libéral vérifié.'
      );
    END IF;
  END IF;

  IF v_choix = 'LIBERAL' THEN
    v_mode := public.fn_mode_exercice(
      v_mission.profession_requise::text,
      v_etablissement.type_etablissement,
      CASE WHEN v_etablissement.est_public THEN 'PUBLIC' ELSE NULL END
    );
    IF COALESCE(v_mode->>'niveau', 'NON_PROPOSE') <> 'AUTORISE' THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', COALESCE(v_mode->>'source_libelle', 'Cette mission est proposée en salarié.'),
        'niveau', COALESCE(v_mode->>'niveau', 'NON_PROPOSE')
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'contrat', v_choix,
    'profession_requise', v_mission.profession_requise::text,
    'type_contrat_recherche', v_recherche
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_documents_ok_pour_mission(
  p_soignant_id uuid,
  p_type_contrat text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_profession public.type_profession;
  v_identifiant_officiel boolean;
  v_diplome_officiel boolean;
  v_regime_liberal boolean;
BEGIN
  IF p_soignant_id IS NULL THEN RETURN false; END IF;
  SELECT profession,
         COALESCE(rpps_verifie, false) OR COALESCE(adeli_verifie, false),
         COALESCE(diplome_verifie, false)
    INTO v_profession, v_identifiant_officiel, v_diplome_officiel
  FROM public.soignants
  WHERE id = p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND OR v_profession IS NULL THEN RETURN false; END IF;

  v_regime_liberal := upper(COALESCE(p_type_contrat, 'SALARIE')) = 'LIBERAL';
  IF v_regime_liberal
     AND NOT public.fn_soignant_liberal_actif_verifie(p_soignant_id) THEN
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
        OR (drp.type_document = 'DIPLOME' AND v_diplome_officiel)
        OR (
          drp.type_document NOT IN ('RPPS_ADELI', 'DIPLOME')
          AND EXISTS (
            SELECT 1
            FROM public.documents_soignants ds
            WHERE ds.soignant_id = p_soignant_id
              AND ds.type_document = drp.type_document
              AND ds.statut_verification = 'VERIFIE'
              AND ds.supprime_le IS NULL
              AND (
                drp.a_expiration IS FALSE
                OR (ds.valide_jusqua IS NOT NULL AND ds.valide_jusqua > current_date)
              )
          )
        )
        OR (
          drp.type_document = 'DIPLOME'
          AND EXISTS (
            SELECT 1
            FROM public.documents_soignants ds
            WHERE ds.soignant_id = p_soignant_id
              AND ds.type_document = 'DIPLOME'
              AND ds.statut_verification = 'VERIFIE'
              AND ds.supprime_le IS NULL
          )
        )
      )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_calculer_tous_documents_valides(p_soignant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_type_exercice text;
  v_regime text;
BEGIN
  IF p_soignant_id IS NULL THEN RETURN; END IF;
  SELECT type_exercice INTO v_type_exercice
  FROM public.soignants
  WHERE id = p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN; END IF;

  -- Un profil MIXTE doit être prêt pour son régime le plus exigeant. La règle
  -- mission continuera de relire le régime réel au moment de l'affectation.
  v_regime := CASE WHEN upper(COALESCE(v_type_exercice, 'SALARIE')) IN ('LIBERAL', 'MIXTE')
    THEN 'LIBERAL' ELSE 'SALARIE' END;
  UPDATE public.soignants
  SET tous_documents_valides = public.fn_documents_ok_pour_mission(p_soignant_id, v_regime),
      modifie_le = now()
  WHERE id = p_soignant_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_calculer_tous_documents_valides(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_calculer_tous_documents_valides(uuid) TO authenticated, service_role;

-- À l'affectation, on cherche une preuve courante couvrant réellement toute
-- la mission pour chaque type requis. Un ancien document expiré ne bloque plus
-- si un renouvellement valide existe, et une date absente n'est jamais traitée
-- comme illimitée pour un type soumis à expiration.
CREATE OR REPLACE FUNCTION public.dec_verifier_docs_jusqua_fin()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_type_manquant public.type_document;
  v_regime_liberal boolean;
  v_verifier boolean := false;
BEGIN
  IF NEW.statut = 'ASSIGNEE' AND NEW.soignant_assigne_id IS NOT NULL THEN
    IF TG_OP = 'INSERT' THEN
      v_verifier := true;
    ELSE
      v_verifier := OLD.statut IS DISTINCT FROM NEW.statut
        OR OLD.soignant_assigne_id IS DISTINCT FROM NEW.soignant_assigne_id
        OR OLD.type_contrat_applique IS DISTINCT FROM NEW.type_contrat_applique;
    END IF;
  END IF;

  IF v_verifier THEN
    IF NEW.type_contrat_applique IS NULL THEN
      RAISE EXCEPTION 'Le contrat appliqué doit être déterminé avant l''affectation.'
        USING ERRCODE = 'check_violation';
    END IF;

    v_regime_liberal := upper(COALESCE(NEW.type_contrat_applique::text, 'SALARIE')) = 'LIBERAL';

    IF NOT public.fn_documents_ok_pour_mission(
      NEW.soignant_assigne_id,
      NEW.type_contrat_applique::text
    ) THEN
      RAISE EXCEPTION 'Les documents obligatoires ne sont pas tous vérifiés pour le contrat attribué.'
        USING ERRCODE = 'check_violation';
    END IF;

    SELECT drp.type_document
      INTO v_type_manquant
    FROM public.documents_requis_par_profession drp
    JOIN public.soignants s
      ON s.id = NEW.soignant_assigne_id
     AND s.profession = drp.profession
     AND s.supprime_le IS NULL
    WHERE drp.est_critique IS TRUE
      AND drp.type_document NOT IN ('RPPS_ADELI', 'DIPLOME')
      AND (
        drp.type_exercice_requis = 'TOUS'
        OR (drp.type_exercice_requis = 'LIBERAL_ONLY' AND v_regime_liberal)
        OR (drp.type_exercice_requis = 'SALARIE_ONLY' AND NOT v_regime_liberal)
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.documents_soignants ds
        WHERE ds.soignant_id = NEW.soignant_assigne_id
          AND ds.type_document = drp.type_document
          AND ds.statut_verification = 'VERIFIE'
          AND ds.supprime_le IS NULL
          AND (
            drp.a_expiration IS FALSE
            OR (
              ds.valide_jusqua IS NOT NULL
              AND ds.valide_jusqua >= NEW.fin_le::date
            )
          )
      )
    LIMIT 1;

    IF v_type_manquant IS NOT NULL THEN
      RAISE EXCEPTION 'Aucun document vérifié de type « % » ne couvre la mission jusqu’au %. Veuillez le renouveler.',
        v_type_manquant,
        to_char(NEW.fin_le, 'DD/MM/YYYY')
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.dec_verifier_docs_jusqua_fin() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_verifier_docs_jusqua_fin() TO service_role;

DROP TRIGGER IF EXISTS dec_docs_fin_mission ON public.missions;
CREATE TRIGGER dec_docs_fin_mission
BEFORE INSERT OR UPDATE ON public.missions
FOR EACH ROW EXECUTE FUNCTION public.dec_verifier_docs_jusqua_fin();

-- Écriture fail-closed du verdict par les seules Edge Functions. L'ancienne
-- version ignorait une ligne absente et conservait silencieusement d'anciennes
-- dates via COALESCE, ce qui rendait une réanalyse non déterministe.
CREATE OR REPLACE FUNCTION public.fn_update_document_verification(
  p_document_id uuid,
  p_statut_verification text,
  p_motif_rejet text DEFAULT NULL,
  p_valide_depuis date DEFAULT NULL,
  p_valide_jusqua date DEFAULT NULL,
  p_verifie_le timestamptz DEFAULT now()
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_statut_verification NOT IN ('VERIFIE', 'EN_ATTENTE', 'REJETE') THEN
    RAISE EXCEPTION 'Verdict documentaire invalide' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  UPDATE public.documents_soignants
  SET statut_verification = p_statut_verification::public.statut_verification,
      motif_rejet = NULLIF(left(COALESCE(p_motif_rejet, ''), 1000), ''),
      valide_depuis = CASE WHEN p_statut_verification = 'REJETE' THEN NULL ELSE p_valide_depuis END,
      valide_jusqua = CASE WHEN p_statut_verification = 'REJETE' THEN NULL ELSE p_valide_jusqua END,
      verifie_le = CASE WHEN p_statut_verification = 'VERIFIE' THEN COALESCE(p_verifie_le, now()) ELSE NULL END,
      modifie_le = now()
  WHERE id = p_document_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Document introuvable' USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_update_document_verification(uuid, text, text, date, date, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_update_document_verification(uuid, text, text, date, date, timestamptz)
  TO service_role;

-- Une RPC générique de profil ne peut ni activer le libéral, ni changer le
-- SIRET/statut sous-jacent. Le GUC dédié n'est positionné que par les deux RPC
-- bornées ci-dessous et reste local à leur transaction.
CREATE OR REPLACE FUNCTION public.fn_verrouiller_transition_liberale()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_preuve_ancienne_valide boolean;
  v_preuve_nouvelle_valide boolean;
BEGIN
  -- session_user conserve le rôle appelant ; current_user vaudrait toujours
  -- le propriétaire de cette fonction SECURITY DEFINER.
  IF session_user IN ('postgres', 'supabase_admin')
     OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role'
     OR auth.role() = 'service_role'
     OR public.est_admin() THEN
    RETURN NEW;
  END IF;

  IF COALESCE(current_setting('jolene.liberal_transition', true), '') = 'true' THEN
    RETURN NEW;
  END IF;

  IF NEW.siret_liberal IS NOT DISTINCT FROM OLD.siret_liberal
     AND NEW.statut_liberal IS NOT DISTINCT FROM OLD.statut_liberal
     AND NOT (
       NEW.type_contrat IS DISTINCT FROM OLD.type_contrat
       AND (NEW.type_contrat::text = 'LIBERAL' OR OLD.type_contrat::text = 'LIBERAL')
     )
     AND NOT (
       NEW.type_exercice IS DISTINCT FROM OLD.type_exercice
       AND NEW.type_exercice IN ('LIBERAL', 'MIXTE')
     ) THEN
    RETURN NEW;
  END IF;

  IF auth.uid() IS NULL OR OLD.id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Transition libérale non autorisée' USING ERRCODE = '42501';
  END IF;

  IF NEW.siret_liberal IS DISTINCT FROM OLD.siret_liberal
     OR NEW.statut_liberal IS DISTINCT FROM OLD.statut_liberal
     OR (
       NEW.type_contrat IS DISTINCT FROM OLD.type_contrat
       AND (NEW.type_contrat::text = 'LIBERAL' OR OLD.type_contrat::text = 'LIBERAL')
     ) THEN
    RAISE EXCEPTION 'Utilisez le parcours vérifié pour modifier le statut ou le SIRET libéral'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.type_exercice IS DISTINCT FROM OLD.type_exercice
     AND NEW.type_exercice IN ('LIBERAL', 'MIXTE') THEN
    v_preuve_ancienne_valide :=
      OLD.statut_liberal = 'ACTIF'
      AND OLD.siret_liberal ~ '^[0-9]{14}$'
      AND OLD.siret_liberal_verifie IS TRUE
      AND OLD.siret_liberal_verifie_le IS NOT NULL
      AND OLD.siret_liberal_coherence_identite IS TRUE;
    v_preuve_nouvelle_valide :=
      NEW.statut_liberal = 'ACTIF'
      AND NEW.siret_liberal ~ '^[0-9]{14}$'
      AND NEW.siret_liberal_verifie IS TRUE
      AND NEW.siret_liberal_verifie_le IS NOT NULL
      AND NEW.siret_liberal_coherence_identite IS TRUE;

    IF NOT v_preuve_ancienne_valide OR NOT v_preuve_nouvelle_valide THEN
      RAISE EXCEPTION 'Activation libérale réservée au parcours SIRET et identité vérifiés'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_00_verrouiller_transition_liberale ON public.soignants;
CREATE TRIGGER trg_00_verrouiller_transition_liberale
BEFORE UPDATE ON public.soignants
FOR EACH ROW EXECUTE FUNCTION public.fn_verrouiller_transition_liberale();

REVOKE ALL ON FUNCTION public.fn_verrouiller_transition_liberale()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_verrouiller_transition_liberale()
  TO service_role;

-- Le SIRET libéral doit être confirmé côté serveur avant toute activation.
CREATE OR REPLACE FUNCTION public.fn_enregistrer_siret_liberal(p_siret text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_siret text := regexp_replace(COALESCE(p_siret, ''), '[^0-9]', '', 'g');
  v_soignant record;
  v_verification_complete boolean := false;
  v_previous_system_update text := COALESCE(current_setting('jolene.system_update', true), '');
  v_previous_liberal_transition text := COALESCE(current_setting('jolene.liberal_transition', true), '');
  v_previous_siret_reset text := COALESCE(current_setting('jolene.siret_liberal_reset', true), '');
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE', 'error', 'Non authentifié');
  END IF;
  IF v_siret !~ '^[0-9]{14}$' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'SIRET_INVALIDE', 'error', 'Le SIRET doit contenir 14 chiffres');
  END IF;

  SELECT siret_liberal, statut_liberal, siret_liberal_verifie,
         siret_liberal_verifie_le, siret_liberal_coherence_identite
    INTO v_soignant
  FROM public.soignants
  WHERE id = v_uid AND supprime_le IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'SOIGNANT_INTROUVABLE', 'error', 'Soignant introuvable');
  END IF;

  v_verification_complete :=
    v_soignant.siret_liberal_verifie IS TRUE
    AND v_soignant.siret_liberal_verifie_le IS NOT NULL
    AND v_soignant.siret_liberal_coherence_identite IS TRUE;

  -- Rejouer la même demande est sans effet et ne détruit jamais une preuve
  -- déjà obtenue (important après un retry réseau mobile).
  IF v_soignant.siret_liberal IS NOT DISTINCT FROM v_siret THEN
    RETURN jsonb_build_object(
      'success', true,
      'verification_requise', NOT v_verification_complete,
      'statut_liberal', v_soignant.statut_liberal
    );
  END IF;

  IF v_soignant.statut_liberal = 'ACTIF' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'SIRET_LIBERAL_ACTIF_VERROUILLE',
      'error', 'Un SIRET libéral actif ne peut pas être remplacé depuis le profil. Contactez le support.'
    );
  END IF;

  PERFORM set_config('jolene.liberal_transition', 'true', true);
  PERFORM set_config('jolene.system_update', 'true', true);
  PERFORM set_config('jolene.siret_liberal_reset', 'true', true);
  UPDATE public.soignants
  SET siret_liberal = v_siret,
      siret_liberal_verifie = false,
      siret_liberal_verifie_le = NULL,
      siret_liberal_raison_sociale = NULL,
      siret_liberal_coherence_identite = NULL,
      statut_liberal = 'EN_COURS',
      type_exercice = 'SALARIE',
      type_contrat = 'CDD',
      date_passage_liberal = NULL,
      code_ape = NULL,
      modifie_le = now()
  WHERE id = v_uid;

  PERFORM public.fn_calculer_tous_documents_valides(v_uid);
  PERFORM set_config('jolene.system_update', v_previous_system_update, true);
  PERFORM set_config('jolene.liberal_transition', v_previous_liberal_transition, true);
  PERFORM set_config('jolene.siret_liberal_reset', v_previous_siret_reset, true);
  RETURN jsonb_build_object('success', true, 'verification_requise', true);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_enregistrer_siret_liberal(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_enregistrer_siret_liberal(text) TO authenticated, service_role;

-- Protection symétrique ADELI/RPPS : l'ancien trigger protégeait uniquement
-- les champs RPPS, ce qui permettait de remplacer un numéro ADELI déjà vérifié.
CREATE OR REPLACE FUNCTION public.fn_protect_adeli_verification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.role() = 'service_role' OR auth.uid() IS NULL OR public.est_admin() THEN RETURN NEW; END IF;
  IF OLD.id = auth.uid() THEN
    NEW.adeli_verifie := OLD.adeli_verifie;
    NEW.adeli_verifie_le := OLD.adeli_verifie_le;
    NEW.adeli_nom_api := OLD.adeli_nom_api;
    NEW.adeli_prenom_api := OLD.adeli_prenom_api;
    NEW.adeli_profession_api := OLD.adeli_profession_api;
    IF OLD.adeli_verifie IS TRUE THEN
      NEW.numero_adeli := OLD.numero_adeli;
      NEW.profession := OLD.profession;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_adeli_verification ON public.soignants;
CREATE TRIGGER trg_protect_adeli_verification
BEFORE UPDATE ON public.soignants
FOR EACH ROW EXECUTE FUNCTION public.fn_protect_adeli_verification();
REVOKE ALL ON FUNCTION public.fn_protect_adeli_verification() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_protect_adeli_verification() TO service_role;

CREATE OR REPLACE FUNCTION public.fn_reinitialiser_ma_profession()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.soignants s
    WHERE s.id = v_uid AND s.supprime_le IS NULL
      AND COALESCE(s.rpps_verifie, false) = false
      AND COALESCE(s.adeli_verifie, false) = false
      AND COALESCE(s.diplome_verifie, false) = false
      AND COALESCE(s.tous_documents_valides, false) = false
  ) OR EXISTS (
    SELECT 1 FROM public.documents_soignants d
    WHERE d.soignant_id = v_uid AND d.supprime_le IS NULL
      AND d.statut_verification = 'VERIFIE'
  ) OR EXISTS (
    SELECT 1 FROM public.missions m
    WHERE m.soignant_assigne_id = v_uid
      AND m.statut IN ('ASSIGNEE', 'EN_COURS')
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'PROFESSION_VERROUILLEE',
      'error', 'La profession est verrouillée après vérification ou attribution.'
    );
  END IF;

  PERFORM set_config('jolene.system_update', 'true', true);
  UPDATE public.soignants
  SET profession = NULL,
      specialite_medicale = NULL,
      specialite_code = NULL,
      specialite_source = NULL,
      modifie_le = now()
  WHERE id = v_uid;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'MODIFICATION_PROFIL',
    p_type_ressource := 'soignant',
    p_id_ressource := v_uid,
    p_details := jsonb_build_object('champs_modifies', jsonb_build_array('profession_reinitialisee'))
  );
  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_reinitialiser_ma_profession() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.fn_reinitialiser_ma_profession() TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_activer_liberal()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_soignant record;
  v_taux jsonb;
  v_previous_system_update text := COALESCE(current_setting('jolene.system_update', true), '');
  v_previous_liberal_transition text := COALESCE(current_setting('jolene.liberal_transition', true), '');
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE', 'error', 'Non authentifié');
  END IF;

  SELECT * INTO v_soignant
  FROM public.soignants
  WHERE id = v_uid AND supprime_le IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'SOIGNANT_INTROUVABLE', 'error', 'Soignant introuvable');
  END IF;
  IF v_soignant.siret_liberal !~ '^[0-9]{14}$'
     OR v_soignant.siret_liberal_verifie IS NOT TRUE
     OR v_soignant.siret_liberal_verifie_le IS NULL
     OR v_soignant.siret_liberal_coherence_identite IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'SIRET_LIBERAL_NON_VERIFIE',
      'error', 'Le SIRET doit être vérifié et correspondre à votre identité avant activation.'
    );
  END IF;
  IF v_soignant.profession NOT IN (SELECT profession FROM public.professions_liberal_eligible) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'PROFESSION_NON_ELIGIBLE',
      'error', 'Votre profession n est pas éligible au libéral'
    );
  END IF;

  v_taux := public.fn_calculer_taux_free_transition(v_uid);
  PERFORM set_config('jolene.liberal_transition', 'true', true);
  PERFORM set_config('jolene.system_update', 'true', true);
  UPDATE public.soignants
  SET type_exercice = 'LIBERAL',
      type_contrat = 'LIBERAL',
      statut_liberal = 'ACTIF',
      date_passage_liberal = current_date,
      code_ape = (SELECT code_ape FROM public.professions_liberal_eligible WHERE profession = v_soignant.profession),
      modifie_le = now()
  WHERE id = v_uid;

  PERFORM public.fn_calculer_tous_documents_valides(v_uid);
  PERFORM set_config('jolene.system_update', v_previous_system_update, true);
  PERFORM set_config('jolene.liberal_transition', v_previous_liberal_transition, true);

  INSERT INTO public.conversions_liberal (
    soignant_id, heures_plateforme_au_demarrage, heures_externes_validees,
    heures_totales, statut, free_transition_eligible,
    taux_prise_en_charge, montant_pris_en_charge, complete_le
  ) VALUES (
    v_uid, v_soignant.heures_plateforme,
    COALESCE((SELECT sum(heures_declarees) FROM public.heures_externes WHERE soignant_id = v_uid AND statut = 'VALIDEE'), 0),
    v_soignant.heures_cumulees, 'COMPLET',
    (v_taux->>'eligible')::boolean,
    (v_taux->>'taux_prise_en_charge')::integer,
    (v_taux->>'montant_pris_en_charge')::numeric,
    now()
  ) ON CONFLICT DO NOTHING;
  RETURN jsonb_build_object('success', true, 'taux', v_taux);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_activer_liberal() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_activer_liberal() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_proteger_verification_siret_liberal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.role() = 'service_role' OR auth.uid() IS NULL OR public.est_admin() THEN RETURN NEW; END IF;
  IF COALESCE(current_setting('jolene.siret_liberal_reset', true), '') = 'true'
     AND NEW.siret_liberal_verifie IS FALSE
     AND NEW.siret_liberal_verifie_le IS NULL
     AND NEW.siret_liberal_raison_sociale IS NULL
     AND NEW.siret_liberal_coherence_identite IS NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.siret_liberal_verifie IS DISTINCT FROM OLD.siret_liberal_verifie
     OR NEW.siret_liberal_verifie_le IS DISTINCT FROM OLD.siret_liberal_verifie_le
     OR NEW.siret_liberal_raison_sociale IS DISTINCT FROM OLD.siret_liberal_raison_sociale
     OR NEW.siret_liberal_coherence_identite IS DISTINCT FROM OLD.siret_liberal_coherence_identite THEN
    RAISE EXCEPTION 'Les preuves SIRET sont réservées au service de vérification' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_proteger_verification_siret_liberal()
FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_proteger_verification_siret_liberal ON public.soignants;
CREATE TRIGGER trg_proteger_verification_siret_liberal
BEFORE UPDATE ON public.soignants
FOR EACH ROW EXECUTE FUNCTION public.fn_proteger_verification_siret_liberal();

-- Dernier verrou avant affectation : il couvre aussi un INSERT PostgREST déjà
-- ASSIGNEE, que l'ancien trigger BEFORE UPDATE ne voyait pas. La profession est
-- celle requise par la mission ; le diplôme/spécialité du profil ne la remplace pas.
CREATE OR REPLACE FUNCTION public.dec_verifier_eligibilite_liberal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_heures_cumulees numeric;
  v_etablissement record;
  v_mode jsonb;
  v_verifier boolean := false;
BEGIN
  IF NEW.soignant_assigne_id IS NOT NULL
     AND NEW.statut = 'ASSIGNEE'
     AND NEW.type_contrat_applique::text = 'LIBERAL' THEN
    IF TG_OP = 'INSERT' THEN
      v_verifier := true;
    ELSE
      v_verifier := OLD.statut IS DISTINCT FROM NEW.statut
        OR OLD.soignant_assigne_id IS DISTINCT FROM NEW.soignant_assigne_id
        OR OLD.type_contrat_applique IS DISTINCT FROM NEW.type_contrat_applique;
    END IF;
  END IF;

  IF NOT v_verifier THEN
    RETURN NEW;
  END IF;

  IF upper(COALESCE(NEW.type_contrat_recherche::text, 'SALARIE'))
       NOT IN ('LIBERAL', 'TOUS') THEN
    RAISE EXCEPTION 'La mission n''est pas ouverte à un contrat libéral.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT e.type::text AS type_etablissement,
         COALESCE(e.est_secteur_public, false) AS est_public
    INTO v_etablissement
  FROM public.etablissements e
  WHERE e.id = NEW.etablissement_id AND e.supprime_le IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Établissement introuvable pour la mission.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_mode := public.fn_mode_exercice(
    NEW.profession_requise::text,
    v_etablissement.type_etablissement,
    CASE WHEN v_etablissement.est_public THEN 'PUBLIC' ELSE NULL END
  );
  IF COALESCE(v_mode->>'niveau', 'NON_PROPOSE') <> 'AUTORISE' THEN
    RAISE EXCEPTION '%', COALESCE(
      v_mode->>'source_libelle',
      'Cette profession est proposée en salarié pour cet établissement.'
    ) USING ERRCODE = 'check_violation';
  END IF;

  IF NOT public.fn_soignant_liberal_actif_verifie(NEW.soignant_assigne_id) THEN
    RAISE EXCEPTION 'Le profil libéral doit être actif, avec SIRET et identité vérifiés.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NOT public.fn_documents_ok_pour_mission(NEW.soignant_assigne_id, 'LIBERAL') THEN
    RAISE EXCEPTION 'Les documents requis pour la mission libérale ne sont pas tous vérifiés.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT COALESCE(s.heures_cumulees, 0)
    INTO v_heures_cumulees
  FROM public.soignants s
  WHERE s.id = NEW.soignant_assigne_id AND s.supprime_le IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profil soignant introuvable.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_heures_cumulees < 3200 THEN
    RAISE EXCEPTION 'Vous devez cumuler 3 200 heures d''exercice pour accepter une mission libérale. Vous avez actuellement % heures.',
      round(v_heures_cumulees)
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS dec_eligibilite_liberal ON public.missions;
CREATE TRIGGER dec_eligibilite_liberal
BEFORE INSERT OR UPDATE ON public.missions
FOR EACH ROW EXECUTE FUNCTION public.dec_verifier_eligibilite_liberal();

REVOKE ALL ON FUNCTION public.dec_verifier_eligibilite_liberal()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_verifier_eligibilite_liberal()
  TO service_role;

-- Répare l'audit de demande de revue : l'action utilisée existe dans le CHECK.
CREATE OR REPLACE FUNCTION public.fn_demander_revue_document(p_document_id uuid, p_motif text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_doc public.documents_soignants%ROWTYPE;
  v_revue_id uuid;
  v_motif text := btrim(COALESCE(p_motif, ''));
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;
  IF p_document_id IS NULL OR length(v_motif) < 10 OR length(v_motif) > 1000 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MOTIF_INVALIDE');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_document_id::text, 0));
  SELECT * INTO v_doc FROM public.documents_soignants
  WHERE id = p_document_id AND soignant_id = v_uid AND supprime_le IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error_code', 'DOCUMENT_INTROUVABLE'); END IF;

  SELECT id INTO v_revue_id FROM public.file_revue_manuelle
  WHERE type_entite = 'TELEVERSEMENT_DOCUMENT' AND id_entite = p_document_id
    AND statut IN ('EN_ATTENTE', 'EN_COURS_REVUE', 'ESCALADE')
  ORDER BY cree_le DESC LIMIT 1;
  IF v_revue_id IS NULL THEN
    INSERT INTO public.file_revue_manuelle (
      type_entite, id_entite, service_en_echec, motif_echec,
      donnees_originales, statut, priorite
    ) VALUES (
      'TELEVERSEMENT_DOCUMENT', p_document_id, 'REVUE_DEMANDEE_PAR_SOIGNANT', v_motif,
      jsonb_build_object('soignant_id', v_uid, 'type_document', v_doc.type_document::text,
                         'ancien_statut', v_doc.statut_verification::text, 'demande_le', now()),
      'EN_ATTENTE', 3
    ) RETURNING id INTO v_revue_id;
  END IF;
  PERFORM set_config('jolene.document_server_update', 'true', true);
  UPDATE public.documents_soignants
  SET statut_verification = 'REVUE_MANUELLE_REQUISE', verifie_par = NULL,
      verifie_le = NULL, motif_rejet = NULL, modifie_le = now()
  WHERE id = p_document_id;
  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'SOIGNANT', p_action := 'VERIFICATION_DOCUMENT',
    p_type_ressource := 'document_soignant', p_id_ressource := p_document_id,
    p_details := jsonb_build_object('sous_action', 'REVUE_MANUELLE_DEMANDEE', 'revue_id', v_revue_id)
  );
  RETURN jsonb_build_object('success', true, 'revue_id', v_revue_id);
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Documents : empêcher une ligne forgée de pointer vers le fichier d'un tiers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_proteger_ecriture_document_soignant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF auth.role() = 'service_role' OR v_uid IS NULL OR public.est_admin() THEN
    RETURN NEW;
  END IF;
  IF COALESCE(current_setting('jolene.document_server_update', true), '') = 'true' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.soignant_id IS DISTINCT FROM v_uid THEN
      RAISE EXCEPTION 'Propriétaire de document invalide' USING ERRCODE = '42501';
    END IF;
    IF NEW.s3_bucket IS DISTINCT FROM 'jolene-documents'
       OR NEW.s3_cle NOT LIKE v_uid::text || '/documents/%'
       OR NEW.s3_cle LIKE '%..%' THEN
      RAISE EXCEPTION 'Chemin de document invalide' USING ERRCODE = '42501';
    END IF;
    NEW.statut_verification := 'EN_ATTENTE';
    NEW.verifie_par := NULL;
    NEW.verifie_le := NULL;
    NEW.motif_rejet := NULL;
    NEW.valide_depuis := NULL;
    NEW.valide_jusqua := NULL;
    NEW.resultat_ia := NULL;
    NEW.nom_extrait_ia := NULL;
    NEW.prenom_extrait_ia := NULL;
    NEW.coherence_nom := NULL;
    NEW.score_confiance_ia := NULL;
    SELECT COALESCE(bool_or(est_critique), false) INTO NEW.est_critique
    FROM public.documents_requis_par_profession drp
    JOIN public.soignants s ON s.id = v_uid AND s.profession = drp.profession
    WHERE drp.type_document = NEW.type_document;
    RETURN NEW;
  END IF;

  IF NEW.soignant_id IS DISTINCT FROM OLD.soignant_id
     OR NEW.type_document IS DISTINCT FROM OLD.type_document
     OR NEW.s3_bucket IS DISTINCT FROM OLD.s3_bucket
     OR NEW.s3_cle IS DISTINCT FROM OLD.s3_cle
     OR NEW.s3_version_id IS DISTINCT FROM OLD.s3_version_id
     OR NEW.nom_fichier IS DISTINCT FROM OLD.nom_fichier
     OR NEW.type_mime IS DISTINCT FROM OLD.type_mime
     OR NEW.taille_octets IS DISTINCT FROM OLD.taille_octets
     OR NEW.valide_depuis IS DISTINCT FROM OLD.valide_depuis
     OR NEW.valide_jusqua IS DISTINCT FROM OLD.valide_jusqua
     OR NEW.statut_verification IS DISTINCT FROM OLD.statut_verification
     OR NEW.verifie_par IS DISTINCT FROM OLD.verifie_par
     OR NEW.verifie_le IS DISTINCT FROM OLD.verifie_le
     OR NEW.motif_rejet IS DISTINCT FROM OLD.motif_rejet
     OR NEW.est_critique IS DISTINCT FROM OLD.est_critique
     OR NEW.resultat_ia IS DISTINCT FROM OLD.resultat_ia
     OR NEW.nom_extrait_ia IS DISTINCT FROM OLD.nom_extrait_ia
     OR NEW.prenom_extrait_ia IS DISTINCT FROM OLD.prenom_extrait_ia
     OR NEW.coherence_nom IS DISTINCT FROM OLD.coherence_nom
     OR NEW.score_confiance_ia IS DISTINCT FROM OLD.score_confiance_ia THEN
    RAISE EXCEPTION 'Modification de preuve ou de validation interdite' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_proteger_ecriture_document_soignant()
FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.dec_proteger_validation_documents()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.role() = 'service_role' OR auth.uid() IS NULL OR public.est_admin()
     OR COALESCE(current_setting('jolene.document_server_update', true), '') = 'true' THEN
    RETURN NEW;
  END IF;
  IF NEW.statut_verification IS DISTINCT FROM OLD.statut_verification THEN
    RAISE EXCEPTION 'Seul le service de vérification peut modifier le statut';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_proteger_document_verification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.role() = 'service_role' OR auth.uid() IS NULL OR public.est_admin()
     OR COALESCE(current_setting('jolene.document_server_update', true), '') = 'true' THEN
    RETURN NEW;
  END IF;
  IF NEW.statut_verification IS DISTINCT FROM OLD.statut_verification
     OR NEW.verifie_par IS DISTINCT FROM OLD.verifie_par
     OR NEW.verifie_le IS DISTINCT FROM OLD.verifie_le
     OR NEW.valide_depuis IS DISTINCT FROM OLD.valide_depuis
     OR NEW.valide_jusqua IS DISTINCT FROM OLD.valide_jusqua
     OR NEW.motif_rejet IS DISTINCT FROM OLD.motif_rejet
     OR NEW.est_critique IS DISTINCT FROM OLD.est_critique
     OR NEW.resultat_ia IS DISTINCT FROM OLD.resultat_ia
     OR NEW.score_confiance_ia IS DISTINCT FROM OLD.score_confiance_ia
     OR NEW.nom_extrait_ia IS DISTINCT FROM OLD.nom_extrait_ia
     OR NEW.prenom_extrait_ia IS DISTINCT FROM OLD.prenom_extrait_ia
     OR NEW.coherence_nom IS DISTINCT FROM OLD.coherence_nom
     OR NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN
    RAISE EXCEPTION 'Modification des champs de vérification interdite' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_proteger_ecriture_document_soignant ON public.documents_soignants;
CREATE TRIGGER trg_proteger_ecriture_document_soignant
BEFORE INSERT OR UPDATE ON public.documents_soignants
FOR EACH ROW EXECUTE FUNCTION public.fn_proteger_ecriture_document_soignant();

REVOKE INSERT, UPDATE, DELETE ON public.documents_soignants FROM authenticated;
GRANT SELECT ON public.documents_soignants TO authenticated;
GRANT INSERT (
  soignant_id, type_document, libelle, s3_cle, nom_fichier, type_mime, taille_octets
) ON public.documents_soignants TO authenticated;
GRANT UPDATE (libelle, supprime_le, modifie_le) ON public.documents_soignants TO authenticated;

-- Bucket privé reproductible et politiques utilisant le vrai rôle applicatif.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'jolene-documents', 'jolene-documents', false, 26214400,
  ARRAY['application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE OR REPLACE FUNCTION public.fn_peut_gerer_objet_jolene(p_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, storage
AS $$
  SELECT auth.uid() IS NOT NULL AND (
    split_part(p_name, '/', 1) = auth.uid()::text
    OR public.est_admin()
    OR EXISTS (
      SELECT 1 FROM public.membres_etablissement me
      WHERE me.user_id = auth.uid() AND me.actif
        AND me.role IN ('PROPRIETAIRE', 'ADMIN_GROUPE')
        AND split_part(p_name, '/', 1) = me.etablissement_id::text
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.fn_peut_lire_objet_jolene(p_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, storage
AS $$
  SELECT public.fn_peut_gerer_objet_jolene(p_name)
    OR EXISTS (
      SELECT 1
      FROM public.documents_soignants ds
      JOIN public.partages_rib pr ON pr.document_rib_id = ds.id
      WHERE ds.s3_bucket = 'jolene-documents'
        AND ds.s3_cle = p_name
        AND ds.type_document = 'RIB'
        AND ds.supprime_le IS NULL
        AND pr.etablissement_id = public.mon_etablissement_id()
        AND pr.actif IS TRUE
        AND (pr.expire_le IS NULL OR pr.expire_le > now())
    );
$$;

REVOKE ALL ON FUNCTION public.fn_peut_gerer_objet_jolene(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_peut_lire_objet_jolene(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_peut_gerer_objet_jolene(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_peut_lire_objet_jolene(text) TO authenticated, service_role;

DROP POLICY IF EXISTS pol_storage_jolene_insert ON storage.objects;
DROP POLICY IF EXISTS pol_storage_jolene_select ON storage.objects;
DROP POLICY IF EXISTS pol_storage_jolene_update ON storage.objects;
DROP POLICY IF EXISTS pol_storage_jolene_delete ON storage.objects;

CREATE POLICY pol_storage_jolene_insert ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'jolene-documents' AND public.fn_peut_gerer_objet_jolene(name));

CREATE POLICY pol_storage_jolene_select ON storage.objects
FOR SELECT TO authenticated
USING (bucket_id = 'jolene-documents' AND public.fn_peut_lire_objet_jolene(name));

-- Les preuves sont immuables côté client. Un remplacement utilise toujours
-- une nouvelle clé horodatée puis met à jour la ligne métier, ce qui révoque
-- automatiquement l'ancien verdict. Sans politique UPDATE/DELETE, il est
-- impossible d'écraser les octets d'un document déjà marqué vérifié tout en
-- conservant sa clé et son statut. Le nettoyage passe par une Edge Function
-- service_role après suppression logique de la référence métier.

-- Le bucket historique `justificatifs` contenait des preuves de réclamation,
-- d'annulation et de rétrocession lisibles par n'importe quel utilisateur
-- authentifié. Les nouveaux dépôts sont obligatoirement préfixés par l'acteur;
-- la lecture des anciens chemins reste possible uniquement pour les parties
-- réellement liées à la ligne métier correspondante.
UPDATE storage.buckets
SET public = false,
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['application/pdf', 'image/jpeg', 'image/png', 'image/webp']
WHERE id = 'justificatifs';

CREATE OR REPLACE FUNCTION public.fn_peut_deposer_justificatif(p_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT auth.uid() IS NOT NULL
    AND p_name IS NOT NULL
    AND p_name NOT LIKE '%..%'
    -- Les clients déposent sous leur propre UID. Les anciens chemins préfixés
    -- par un établissement restent consultables uniquement via une relation
    -- métier ci-dessous, jamais par simple appartenance à l'établissement.
    AND split_part(p_name, '/', 1) = auth.uid()::text;
$$;

CREATE OR REPLACE FUNCTION public.fn_peut_lire_justificatif(p_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT public.est_admin()
    OR public.fn_peut_deposer_justificatif(p_name)
    OR EXISTS (
      SELECT 1 FROM public.missions m
      WHERE m.justificatif_honoraires_cle = p_name
        AND (
          m.soignant_assigne_id = auth.uid()
          OR public.fn_a_permission_etablissement('lecture_paiement', m.etablissement_id)
        )
    )
    OR EXISTS (
      SELECT 1 FROM public.evenements_score_soignant e
      LEFT JOIN public.missions m ON m.id = e.mission_id
      WHERE e.justificatif_storage_path = p_name
        AND (
          e.soignant_id = auth.uid()
          OR public.fn_a_permission_etablissement('candidatures', m.etablissement_id)
        )
    )
    OR EXISTS (
      SELECT 1 FROM public.evenements_score_etab e
      LEFT JOIN public.missions m ON m.id = e.mission_id
      WHERE e.justificatif_storage_path = p_name
        AND (
          public.fn_a_permission_etablissement('profil_etab', e.etablissement_id)
          OR m.soignant_assigne_id = auth.uid()
        )
    )
    OR EXISTS (
      SELECT 1 FROM public.reclamations_score r
      WHERE r.justificatif_storage_path = p_name AND r.contesteur_id = auth.uid()
    );
$$;

REVOKE ALL ON FUNCTION public.fn_peut_deposer_justificatif(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_peut_lire_justificatif(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_peut_deposer_justificatif(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_peut_lire_justificatif(text) TO authenticated, service_role;

DROP POLICY IF EXISTS justificatifs_insert_auth ON storage.objects;
DROP POLICY IF EXISTS justificatifs_select_auth ON storage.objects;
DROP POLICY IF EXISTS justificatifs_update_auth ON storage.objects;
DROP POLICY IF EXISTS justificatifs_delete_auth ON storage.objects;

CREATE POLICY justificatifs_insert_auth ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'justificatifs' AND public.fn_peut_deposer_justificatif(name));

CREATE POLICY justificatifs_select_auth ON storage.objects
FOR SELECT TO authenticated
USING (bucket_id = 'justificatifs' AND public.fn_peut_lire_justificatif(name));

CREATE OR REPLACE FUNCTION public.fn_verrouiller_reference_justificatif()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_path text;
BEGIN
  IF auth.role() = 'service_role' OR public.est_admin() THEN RETURN NEW; END IF;
  -- NEW est un record polymorphe : chaque table déclencheuse ne possède
  -- qu'une des deux colonnes. Une lecture directe dans un CASE force
  -- PostgreSQL à résoudre aussi la branche non retenue et échoue à l'exécution.
  v_path := CASE TG_TABLE_NAME
    WHEN 'missions'
      THEN pg_catalog.to_jsonb(NEW)->>'justificatif_honoraires_cle'
    ELSE pg_catalog.to_jsonb(NEW)->>'justificatif_storage_path'
  END;
  IF v_path IS NOT NULL AND NOT public.fn_peut_deposer_justificatif(v_path) THEN
    RAISE EXCEPTION 'Référence de justificatif non autorisée' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_verrouiller_reference_justificatif()
FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_verrouiller_justificatif_mission ON public.missions;
CREATE TRIGGER trg_verrouiller_justificatif_mission
BEFORE INSERT OR UPDATE OF justificatif_honoraires_cle ON public.missions
FOR EACH ROW EXECUTE FUNCTION public.fn_verrouiller_reference_justificatif();

DROP TRIGGER IF EXISTS trg_verrouiller_justificatif_score_soignant ON public.evenements_score_soignant;
CREATE TRIGGER trg_verrouiller_justificatif_score_soignant
BEFORE INSERT OR UPDATE OF justificatif_storage_path ON public.evenements_score_soignant
FOR EACH ROW EXECUTE FUNCTION public.fn_verrouiller_reference_justificatif();

DROP TRIGGER IF EXISTS trg_verrouiller_justificatif_score_etab ON public.evenements_score_etab;
CREATE TRIGGER trg_verrouiller_justificatif_score_etab
BEFORE INSERT OR UPDATE OF justificatif_storage_path ON public.evenements_score_etab
FOR EACH ROW EXECUTE FUNCTION public.fn_verrouiller_reference_justificatif();

DROP TRIGGER IF EXISTS trg_verrouiller_justificatif_reclamation ON public.reclamations_score;
CREATE TRIGGER trg_verrouiller_justificatif_reclamation
BEFORE INSERT OR UPDATE OF justificatif_storage_path ON public.reclamations_score
FOR EACH ROW EXECUTE FUNCTION public.fn_verrouiller_reference_justificatif();

-- ---------------------------------------------------------------------------
-- 5. Toute nouvelle preuve ou donnée d'identité révoque l'ancien verdict
-- ---------------------------------------------------------------------------

-- Le trigger historique promouvait automatiquement un établissement dès que
-- le SIRET et l'ancien champ contrat_valide étaient vrais. Il ne doit plus
-- pouvoir contourner FINESS, identité, rattachement et contrat de service.
CREATE OR REPLACE FUNCTION public.fn_auto_valider_etablissement_siret()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  -- Une vérification SIRET fait seulement avancer le dossier vers la revue.
  IF NEW.siret_verifie IS TRUE
     AND OLD.siret_verifie IS NOT TRUE
     AND NEW.statut_verification = 'EN_ATTENTE' THEN
    NEW.statut_verification := 'EN_COURS';
  END IF;

  -- La publication ne peut jamais être accordée par ce trigger. Elle exige
  -- désormais une validation admin explicite de toutes les preuves.
  IF NEW.peut_publier_missions IS TRUE AND NOT (
    NEW.statut_verification = 'VERIFIE'
    AND NEW.siret_verifie IS TRUE
    AND NEW.finess_verifie IS TRUE
    AND NEW.representant_identite_verifiee IS TRUE
    AND NEW.rattachement_verifie IS TRUE
    AND NEW.contrat_service_signe IS TRUE
  ) THEN
    NEW.peut_publier_missions := false;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_auto_valider_etablissement_siret() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_auto_valider_etablissement_siret() TO service_role;

-- Signature du contrat de service : droits profil_etab requis, version figée,
-- signature réellement présente et empreinte canonique recalculée côté serveur.
DROP POLICY IF EXISTS css_insert ON public.contrats_service_signatures;
REVOKE INSERT ON TABLE public.contrats_service_signatures FROM authenticated;

CREATE OR REPLACE FUNCTION public.fn_signer_contrat_service(
  p_version text,
  p_ip text,
  p_user_agent text,
  p_contenu_hash text,
  p_signature_s3_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, storage, extensions
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid := public.mon_etablissement_id();
  v_etab record;
  v_headers jsonb;
  v_real_ip text;
  v_user_agent text;
  v_canonical_hash text;
  v_signature_le timestamptz;
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() OR v_etab_id IS NULL
     OR NOT public.fn_a_permission_etablissement('profil_etab', v_etab_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;
  IF p_version IS DISTINCT FROM 'v1.0' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Version du contrat non reconnue');
  END IF;
  IF p_signature_s3_key IS NULL
     OR p_signature_s3_key NOT LIKE v_uid::text || '/signatures/contrat-service-%'
     OR p_signature_s3_key LIKE '%..%'
     OR NOT EXISTS (
       SELECT 1 FROM storage.objects o
       WHERE o.bucket_id = 'jolene-documents'
         AND o.name = p_signature_s3_key
         AND COALESCE(o.metadata->>'mimetype', '') IN ('image/png', 'image/jpeg')
     ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Signature électronique manquante ou invalide');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_etab_id::text, 0));
  IF EXISTS (
    SELECT 1 FROM public.contrats_service_signatures
    WHERE etablissement_id = v_etab_id AND revoked_at IS NULL
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Contrat déjà signé et actif');
  END IF;

  SELECT id, nom, siret, type, adresse_rue, adresse_code_postal,
         adresse_ville, email_contact, representant_nom, representant_prenom
    INTO v_etab
  FROM public.etablissements
  WHERE id = v_etab_id AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Établissement introuvable'); END IF;

  -- Cette empreinte ne dépend d'aucune valeur envoyée par le navigateur. Elle
  -- lie la version du modèle et les données légales relues en base.
  v_canonical_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'template_fingerprint', '11202a832970b69fcccbcdb95f079cd3d2d4b7bfbf4dc39d64ff961100c547f8',
    'version', 'v1.0',
    'etablissement_id', v_etab.id,
    'nom', COALESCE(v_etab.nom, ''),
    'siret', COALESCE(v_etab.siret, ''),
    'type', COALESCE(v_etab.type::text, ''),
    'adresse_rue', COALESCE(v_etab.adresse_rue, ''),
    'adresse_code_postal', COALESCE(v_etab.adresse_code_postal, ''),
    'adresse_ville', COALESCE(v_etab.adresse_ville, ''),
    'email_contact', COALESCE(v_etab.email_contact, ''),
    'representant_nom', COALESCE(v_etab.representant_nom, ''),
    'representant_prenom', COALESCE(v_etab.representant_prenom, '')
  )::text, 'UTF8'), 'sha256'), 'hex');

  BEGIN
    v_headers := current_setting('request.headers', true)::jsonb;
  EXCEPTION WHEN OTHERS THEN
    v_headers := '{}'::jsonb;
  END;
  v_real_ip := COALESCE(
    NULLIF(v_headers->>'cf-connecting-ip', ''),
    NULLIF(split_part(COALESCE(v_headers->>'x-forwarded-for', ''), ',', 1), ''),
    NULLIF(v_headers->>'x-real-ip', ''),
    'unknown'
  );
  v_user_agent := left(COALESCE(NULLIF(v_headers->>'user-agent', ''), NULLIF(p_user_agent, ''), 'unknown'), 500);

  INSERT INTO public.contrats_service_signatures
    (etablissement_id, version, ip_address, user_agent, contenu_hash, signature_s3_key)
  VALUES
    (v_etab_id, 'v1.0', v_real_ip, v_user_agent, v_canonical_hash, p_signature_s3_key)
  RETURNING signed_at INTO v_signature_le;

  UPDATE public.etablissements
  SET contrat_service_signe = true,
      contrat_service_signe_le = v_signature_le,
      modifie_le = now()
  WHERE id = v_etab_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'ADMIN_ETABLISSEMENT',
    p_action := 'CONTRAT_SIGNE',
    p_type_ressource := 'etablissement',
    p_id_ressource := v_etab_id,
    p_details := jsonb_build_object(
      'type', 'contrat_service_jolene', 'version', 'v1.0',
      'empreinte_serveur', true, 'has_signature_image', true
    )
  );
  RETURN jsonb_build_object('success', true, 'version', 'v1.0', 'contenu_hash', v_canonical_hash);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_signer_contrat_service(text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_signer_contrat_service(text, text, text, text, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_revoquer_contrat_service(p_motif text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid := public.mon_etablissement_id();
  v_sig_id uuid;
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() OR v_etab_id IS NULL
     OR NOT public.fn_a_permission_etablissement('profil_etab', v_etab_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;
  IF NULLIF(btrim(p_motif), '') IS NULL OR length(btrim(p_motif)) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Motif de révocation requis (10 caractères minimum)');
  END IF;
  SELECT id INTO v_sig_id FROM public.contrats_service_signatures
  WHERE etablissement_id = v_etab_id AND revoked_at IS NULL FOR UPDATE;
  IF v_sig_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Aucun contrat actif à révoquer');
  END IF;

  UPDATE public.contrats_service_signatures
  SET revoked_at = now(), motif_revocation = left(btrim(p_motif), 1000)
  WHERE id = v_sig_id;
  UPDATE public.etablissements
  SET contrat_service_signe = false,
      contrat_service_signe_le = NULL,
      peut_publier_missions = false,
      statut_verification = CASE WHEN statut_verification = 'VERIFIE' THEN 'EN_COURS' ELSE statut_verification END,
      verifie_le = NULL,
      verifie_par = NULL,
      modifie_le = now()
  WHERE id = v_etab_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'ADMIN_ETABLISSEMENT',
    p_action := 'CONTRAT_SIGNE', p_type_ressource := 'etablissement',
    p_id_ressource := v_etab_id,
    p_details := jsonb_build_object('type', 'contrat_service_jolene_revoque', 'motif', left(btrim(p_motif), 1000))
  );
  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_revoquer_contrat_service(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_revoquer_contrat_service(text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_invalider_verifications_etablissement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_identite_changee boolean := false;
  v_justificatif_change boolean := false;
  v_rib_change boolean := false;
  v_contrat_change boolean := false;
  v_finess_change boolean := false;
  v_siret_change boolean := false;
  v_source_changee boolean := false;
BEGIN
  v_identite_changee :=
    NEW.representant_piece_s3_key IS DISTINCT FROM OLD.representant_piece_s3_key
    OR NEW.representant_piece_type_document IS DISTINCT FROM OLD.representant_piece_type_document
    OR NEW.representant_piece_type_mime IS DISTINCT FROM OLD.representant_piece_type_mime
    OR NEW.representant_nom IS DISTINCT FROM OLD.representant_nom
    OR NEW.representant_prenom IS DISTINCT FROM OLD.representant_prenom;
  v_justificatif_change :=
    NEW.justificatif_fonction_s3_key IS DISTINCT FROM OLD.justificatif_fonction_s3_key
    OR NEW.justificatif_fonction_type IS DISTINCT FROM OLD.justificatif_fonction_type
    OR NEW.justificatif_fonction_type_mime IS DISTINCT FROM OLD.justificatif_fonction_type_mime;
  v_rib_change := NEW.rib_s3_key IS DISTINCT FROM OLD.rib_s3_key;
  v_contrat_change := NEW.contrat_url IS DISTINCT FROM OLD.contrat_url;
  v_finess_change :=
    NEW.finess IS DISTINCT FROM OLD.finess
    OR NEW.nom IS DISTINCT FROM OLD.nom
    OR NEW.adresse_rue IS DISTINCT FROM OLD.adresse_rue
    OR NEW.adresse_ville IS DISTINCT FROM OLD.adresse_ville
    OR NEW.adresse_code_postal IS DISTINCT FROM OLD.adresse_code_postal;
  v_siret_change := NEW.siret IS DISTINCT FROM OLD.siret;
  v_source_changee := v_identite_changee OR v_justificatif_change
    OR v_rib_change OR v_contrat_change OR v_finess_change OR v_siret_change;

  IF v_identite_changee THEN
    NEW.representant_identite_verifiee := false;
    NEW.representant_identite_verifiee_le := NULL;
    NEW.representant_identite_resultat_ia := NULL;
  END IF;

  IF v_justificatif_change THEN
    NEW.justificatif_fonction_verifie := false;
    NEW.justificatif_fonction_verifie_le := NULL;
    NEW.justificatif_fonction_resultat_ia := NULL;
  END IF;

  IF v_rib_change THEN
    NEW.rib_ia_resultat := NULL;
    NEW.rib_ia_coherent := NULL;
    NEW.rib_ia_verifie_le := NULL;
    NEW.iban_last4 := NULL;
  END IF;

  IF v_contrat_change THEN
    NEW.contrat_valide := false;
    NEW.contrat_ia_resultat := NULL;
    NEW.contrat_ia_coherent := NULL;
    NEW.contrat_ia_verifie_le := NULL;
    NEW.contrat_uploade_le := CASE
      WHEN NEW.contrat_url IS NULL THEN NULL
      ELSE transaction_timestamp()
    END;
  END IF;

  IF v_finess_change THEN
    NEW.finess_verifie := false;
    NEW.finess_verifie_le := NULL;
    NEW.finess_raison_sociale := NULL;
    NEW.finess_categorie := NULL;
    NEW.finess_secteur := NULL;
    NEW.finess_est_public := NULL;
  END IF;

  IF v_siret_change THEN
    NEW.siret_verifie := false;
    NEW.siret_verifie_le := NULL;
    NEW.siret_raison_sociale := NULL;
    NEW.siret_categorie_juridique := NULL;
    NEW.siret_code_naf := NULL;
    NEW.siret_est_actif := NULL;
    NEW.dirigeants := NULL;
  END IF;

  IF v_siret_change OR NEW.nom IS DISTINCT FROM OLD.nom THEN
    NEW.coherence_identite := NULL;
  END IF;

  -- Le rattachement d'un représentant dépend à la fois de ses preuves et des
  -- dirigeants officiels. Toute altération d'une de ces entrées le remet en
  -- revue ; fn_evaluer_rattachement_etablissement pourra ensuite le recalculer.
  IF v_identite_changee OR v_justificatif_change OR v_siret_change
     OR NEW.representant_identite_verifiee IS DISTINCT FROM OLD.representant_identite_verifiee
     OR NEW.justificatif_fonction_verifie IS DISTINCT FROM OLD.justificatif_fonction_verifie
     OR NEW.dirigeants IS DISTINCT FROM OLD.dirigeants THEN
    NEW.rattachement_verifie := false;
    NEW.rattachement_verifie_le := NULL;
    NEW.rattachement_methode := 'ADMIN';
  END IF;

  -- Le remplacement de n'importe quelle source invalide aussi le verdict
  -- global. Les valeurs sont dérivées exclusivement de OLD et des deltas de
  -- sources ; aucune valeur de statut fournie par le client n'est conservée.
  IF v_source_changee THEN
    NEW.peut_publier_missions := false;
    NEW.statut_verification := CASE
      WHEN OLD.statut_verification IN ('VERIFIE', 'REJETE') THEN 'EN_COURS'
      ELSE OLD.statut_verification
    END;
    NEW.verifie_le := NULL;
    NEW.verifie_par := NULL;
    NEW.motif_rejet := CASE
      WHEN OLD.statut_verification = 'REJETE' THEN NULL
      ELSE OLD.motif_rejet
    END;
  END IF;

  -- Ce trigger s'exécute après trg_auto_valider_etablissement et avant
  -- trg_protect_etablissement_commercial (ordre alphabétique PostgreSQL).
  -- Le protector voit ainsi uniquement la transition canonique ci-dessus.
  IF NOT (
    NEW.siret_verifie IS TRUE
    AND NEW.finess_verifie IS TRUE
    AND NEW.representant_identite_verifiee IS TRUE
    AND NEW.rattachement_verifie IS TRUE
    AND NEW.contrat_service_signe IS TRUE
  ) THEN
    NEW.peut_publier_missions := false;
    IF NEW.statut_verification = 'VERIFIE' THEN
      NEW.statut_verification := 'EN_COURS';
      NEW.verifie_le := NULL;
      NEW.verifie_par := NULL;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_invalider_verifications_etablissement()
FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_invalider_verifications_etablissement ON public.etablissements;
CREATE TRIGGER trg_invalider_verifications_etablissement
BEFORE UPDATE ON public.etablissements
FOR EACH ROW EXECUTE FUNCTION public.fn_invalider_verifications_etablissement();

-- Le trigger historique bloquait aussi les remises à zéro produites par
-- fn_invalider_verifications_etablissement. Le protector est redéfini ici :
-- pour un utilisateur établissement, il accepte uniquement (a) une valeur
-- inchangée, (b) la révocation canonique provoquée par une source modifiée,
-- (c) le rattachement recalculé depuis les preuves, ou (d) l'état exact de la
-- signature active. La GUC historique ne contourne ces contrôles à aucun
-- moment ; elle reste limitée aux anciens champs commerciaux internes.
CREATE OR REPLACE FUNCTION public.fn_protect_etablissement_commercial()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_jwt_role text := COALESCE(
    auth.jwt()->>'role',
    current_setting('request.jwt.claim.role', true),
    ''
  );
  v_is_service_role boolean;
  v_is_internal boolean;
  v_identite_changee boolean;
  v_justificatif_change boolean;
  v_rib_change boolean;
  v_contrat_change boolean;
  v_finess_change boolean;
  v_siret_change boolean;
  v_source_changee boolean;
  v_signature_active_le timestamptz;
  v_signature_transition boolean := false;
  v_revocation_globale boolean := false;
  v_rattachement_invalide boolean := false;
  v_rattachement_attendu boolean := false;
  v_methode_attendue text := 'ADMIN';
  v_match_dirigeant boolean := false;
BEGIN
  v_is_service_role := v_jwt_role = 'service_role'
    OR (auth.uid() IS NULL AND v_jwt_role <> 'anon');
  IF v_is_service_role OR public.est_admin() THEN
    RETURN NEW;
  END IF;

  v_identite_changee :=
    NEW.representant_piece_s3_key IS DISTINCT FROM OLD.representant_piece_s3_key
    OR NEW.representant_piece_type_document IS DISTINCT FROM OLD.representant_piece_type_document
    OR NEW.representant_piece_type_mime IS DISTINCT FROM OLD.representant_piece_type_mime
    OR NEW.representant_nom IS DISTINCT FROM OLD.representant_nom
    OR NEW.representant_prenom IS DISTINCT FROM OLD.representant_prenom;
  v_justificatif_change :=
    NEW.justificatif_fonction_s3_key IS DISTINCT FROM OLD.justificatif_fonction_s3_key
    OR NEW.justificatif_fonction_type IS DISTINCT FROM OLD.justificatif_fonction_type
    OR NEW.justificatif_fonction_type_mime IS DISTINCT FROM OLD.justificatif_fonction_type_mime;
  v_rib_change := NEW.rib_s3_key IS DISTINCT FROM OLD.rib_s3_key;
  v_contrat_change := NEW.contrat_url IS DISTINCT FROM OLD.contrat_url;
  v_finess_change :=
    NEW.finess IS DISTINCT FROM OLD.finess
    OR NEW.nom IS DISTINCT FROM OLD.nom
    OR NEW.adresse_rue IS DISTINCT FROM OLD.adresse_rue
    OR NEW.adresse_ville IS DISTINCT FROM OLD.adresse_ville
    OR NEW.adresse_code_postal IS DISTINCT FROM OLD.adresse_code_postal;
  v_siret_change := NEW.siret IS DISTINCT FROM OLD.siret;
  v_source_changee := v_identite_changee OR v_justificatif_change
    OR v_rib_change OR v_contrat_change OR v_finess_change OR v_siret_change;

  IF v_identite_changee THEN
    IF NEW.representant_identite_verifiee IS DISTINCT FROM false
       OR NEW.representant_identite_verifiee_le IS NOT NULL
       OR NEW.representant_identite_resultat_ia IS NOT NULL THEN
      RAISE EXCEPTION 'Révocation identité non canonique'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF NEW.representant_identite_verifiee IS DISTINCT FROM OLD.representant_identite_verifiee
     OR NEW.representant_identite_verifiee_le IS DISTINCT FROM OLD.representant_identite_verifiee_le
     OR NEW.representant_identite_resultat_ia IS DISTINCT FROM OLD.representant_identite_resultat_ia THEN
    RAISE EXCEPTION 'Écriture directe du verdict identité interdite'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_justificatif_change THEN
    IF NEW.justificatif_fonction_verifie IS DISTINCT FROM false
       OR NEW.justificatif_fonction_verifie_le IS NOT NULL
       OR NEW.justificatif_fonction_resultat_ia IS NOT NULL THEN
      RAISE EXCEPTION 'Révocation justificatif non canonique'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF NEW.justificatif_fonction_verifie IS DISTINCT FROM OLD.justificatif_fonction_verifie
     OR NEW.justificatif_fonction_verifie_le IS DISTINCT FROM OLD.justificatif_fonction_verifie_le
     OR NEW.justificatif_fonction_resultat_ia IS DISTINCT FROM OLD.justificatif_fonction_resultat_ia THEN
    RAISE EXCEPTION 'Écriture directe du verdict justificatif interdite'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_rib_change THEN
    IF NEW.rib_ia_resultat IS NOT NULL OR NEW.rib_ia_coherent IS NOT NULL
       OR NEW.rib_ia_verifie_le IS NOT NULL OR NEW.iban_last4 IS NOT NULL THEN
      RAISE EXCEPTION 'Révocation RIB non canonique'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF NEW.rib_ia_resultat IS DISTINCT FROM OLD.rib_ia_resultat
     OR NEW.rib_ia_coherent IS DISTINCT FROM OLD.rib_ia_coherent
     OR NEW.rib_ia_verifie_le IS DISTINCT FROM OLD.rib_ia_verifie_le
     OR NEW.iban_last4 IS DISTINCT FROM OLD.iban_last4 THEN
    RAISE EXCEPTION 'Écriture directe du verdict RIB interdite'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_contrat_change THEN
    IF NEW.contrat_valide IS DISTINCT FROM false
       OR NEW.contrat_ia_resultat IS NOT NULL OR NEW.contrat_ia_coherent IS NOT NULL
       OR NEW.contrat_ia_verifie_le IS NOT NULL
       OR NEW.contrat_uploade_le IS DISTINCT FROM (CASE
         WHEN NEW.contrat_url IS NULL THEN NULL
         ELSE transaction_timestamp()
       END) THEN
      RAISE EXCEPTION 'Révocation contrat non canonique'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF NEW.contrat_valide IS DISTINCT FROM OLD.contrat_valide
     OR NEW.contrat_ia_resultat IS DISTINCT FROM OLD.contrat_ia_resultat
     OR NEW.contrat_ia_coherent IS DISTINCT FROM OLD.contrat_ia_coherent
     OR NEW.contrat_ia_verifie_le IS DISTINCT FROM OLD.contrat_ia_verifie_le
     OR NEW.contrat_uploade_le IS DISTINCT FROM OLD.contrat_uploade_le THEN
    RAISE EXCEPTION 'Écriture directe du verdict contrat interdite'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_finess_change THEN
    IF NEW.finess_verifie IS DISTINCT FROM false OR NEW.finess_verifie_le IS NOT NULL
       OR NEW.finess_raison_sociale IS NOT NULL OR NEW.finess_categorie IS NOT NULL
       OR NEW.finess_secteur IS NOT NULL OR NEW.finess_est_public IS NOT NULL THEN
      RAISE EXCEPTION 'Révocation FINESS non canonique'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF NEW.finess_verifie IS DISTINCT FROM OLD.finess_verifie
     OR NEW.finess_verifie_le IS DISTINCT FROM OLD.finess_verifie_le
     OR NEW.finess_raison_sociale IS DISTINCT FROM OLD.finess_raison_sociale
     OR NEW.finess_categorie IS DISTINCT FROM OLD.finess_categorie
     OR NEW.finess_secteur IS DISTINCT FROM OLD.finess_secteur
     OR NEW.finess_est_public IS DISTINCT FROM OLD.finess_est_public THEN
    RAISE EXCEPTION 'Écriture directe du verdict FINESS interdite'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_siret_change THEN
    IF NEW.siret_verifie IS DISTINCT FROM false OR NEW.siret_verifie_le IS NOT NULL
       OR NEW.siret_raison_sociale IS NOT NULL OR NEW.siret_categorie_juridique IS NOT NULL
       OR NEW.siret_code_naf IS NOT NULL OR NEW.siret_est_actif IS NOT NULL
       OR NEW.dirigeants IS NOT NULL THEN
      RAISE EXCEPTION 'Révocation SIRET non canonique'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF NEW.siret_verifie IS DISTINCT FROM OLD.siret_verifie
     OR NEW.siret_verifie_le IS DISTINCT FROM OLD.siret_verifie_le
     OR NEW.siret_raison_sociale IS DISTINCT FROM OLD.siret_raison_sociale
     OR NEW.siret_categorie_juridique IS DISTINCT FROM OLD.siret_categorie_juridique
     OR NEW.siret_code_naf IS DISTINCT FROM OLD.siret_code_naf
     OR NEW.siret_est_actif IS DISTINCT FROM OLD.siret_est_actif
     OR NEW.dirigeants IS DISTINCT FROM OLD.dirigeants THEN
    RAISE EXCEPTION 'Écriture directe du verdict SIRET interdite'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_siret_change OR NEW.nom IS DISTINCT FROM OLD.nom THEN
    IF NEW.coherence_identite IS NOT NULL THEN
      RAISE EXCEPTION 'Révocation de cohérence identité non canonique'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF NEW.coherence_identite IS DISTINCT FROM OLD.coherence_identite THEN
    RAISE EXCEPTION 'Écriture directe de la cohérence identité interdite'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Une mise à jour de rattachement par la RPC publique est admise seulement
  -- si elle reproduit exactement le calcul serveur et l'horodatage de la
  -- transaction. Une valeur arbitraire envoyée via PostgREST ne peut donc pas
  -- promouvoir le dossier.
  IF NEW.representant_identite_verifiee IS TRUE
     AND NULLIF(btrim(NEW.representant_nom), '') IS NOT NULL
     AND jsonb_typeof(NEW.dirigeants) = 'array' THEN
    SELECT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(NEW.dirigeants) AS d
      WHERE public.fn_normaliser_nom(d->>'type_dirigeant') LIKE '%physique%'
        AND public.fn_normaliser_nom(d->>'nom') = public.fn_normaliser_nom(NEW.representant_nom)
        AND NULLIF(public.fn_normaliser_nom(NEW.representant_prenom), '') IS NOT NULL
        AND NOT EXISTS (
          SELECT 1
          FROM unnest(regexp_split_to_array(public.fn_normaliser_nom(NEW.representant_prenom), ' +')) AS attendu(prenom)
          WHERE attendu.prenom <> ''
            AND NOT (
              attendu.prenom = ANY (
                regexp_split_to_array(public.fn_normaliser_nom(d->>'prenoms'), ' +')
              )
            )
        )
    ) INTO v_match_dirigeant;
  END IF;
  IF v_match_dirigeant THEN
    v_rattachement_attendu := true;
    v_methode_attendue := 'AUTO_DIRIGEANT';
  ELSIF NEW.representant_identite_verifiee IS TRUE
        AND NEW.justificatif_fonction_verifie IS TRUE THEN
    v_rattachement_attendu := true;
    v_methode_attendue := 'JUSTIFICATIF';
  END IF;

  v_rattachement_invalide := v_identite_changee OR v_justificatif_change
    OR v_siret_change
    OR NEW.representant_identite_verifiee IS DISTINCT FROM OLD.representant_identite_verifiee
    OR NEW.justificatif_fonction_verifie IS DISTINCT FROM OLD.justificatif_fonction_verifie
    OR NEW.dirigeants IS DISTINCT FROM OLD.dirigeants;

  IF NEW.rattachement_verifie IS DISTINCT FROM OLD.rattachement_verifie
     OR NEW.rattachement_verifie_le IS DISTINCT FROM OLD.rattachement_verifie_le
     OR NEW.rattachement_methode IS DISTINCT FROM OLD.rattachement_methode THEN
    IF v_rattachement_invalide THEN
      IF NEW.rattachement_verifie IS DISTINCT FROM false
         OR NEW.rattachement_verifie_le IS NOT NULL
         OR NEW.rattachement_methode IS DISTINCT FROM 'ADMIN' THEN
        RAISE EXCEPTION 'Révocation de rattachement non canonique'
          USING ERRCODE = 'insufficient_privilege';
      END IF;
    ELSE
      IF NEW.rattachement_verifie IS DISTINCT FROM v_rattachement_attendu
         OR NEW.rattachement_methode IS DISTINCT FROM v_methode_attendue
         OR NEW.rattachement_verifie_le IS DISTINCT FROM (CASE
           WHEN v_rattachement_attendu THEN transaction_timestamp()
           ELSE NULL
         END) THEN
        RAISE EXCEPTION 'Transition de rattachement non calculée depuis les sources'
          USING ERRCODE = 'insufficient_privilege';
      END IF;
    END IF;
  END IF;

  -- L'état du contrat de service vient exclusivement de la ligne de signature
  -- active. La signature/révocation fonctionne sans GUC de contournement.
  SELECT signed_at INTO v_signature_active_le
  FROM public.contrats_service_signatures
  WHERE etablissement_id = NEW.id AND revoked_at IS NULL
  LIMIT 1;
  v_signature_transition :=
    NEW.contrat_service_signe IS DISTINCT FROM OLD.contrat_service_signe
    OR NEW.contrat_service_signe_le IS DISTINCT FROM OLD.contrat_service_signe_le;
  IF v_signature_transition AND (
    NEW.contrat_service_signe IS DISTINCT FROM (v_signature_active_le IS NOT NULL)
    OR NEW.contrat_service_signe_le IS DISTINCT FROM v_signature_active_le
  ) THEN
    RAISE EXCEPTION 'État du contrat de service sans preuve active'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_revocation_globale := v_source_changee
    OR (v_signature_transition
      AND OLD.contrat_service_signe IS TRUE
      AND NEW.contrat_service_signe IS FALSE);
  IF v_revocation_globale THEN
    IF NEW.peut_publier_missions IS DISTINCT FROM false
       OR NEW.statut_verification IS DISTINCT FROM (CASE
         WHEN v_source_changee
              AND OLD.statut_verification IN ('VERIFIE', 'REJETE') THEN 'EN_COURS'
         WHEN NOT v_source_changee
              AND OLD.statut_verification = 'VERIFIE' THEN 'EN_COURS'
         ELSE OLD.statut_verification
       END)
       OR NEW.verifie_le IS NOT NULL OR NEW.verifie_par IS NOT NULL
       OR NEW.motif_rejet IS DISTINCT FROM (CASE
         WHEN v_source_changee AND OLD.statut_verification = 'REJETE' THEN NULL
         ELSE OLD.motif_rejet
       END) THEN
      RAISE EXCEPTION 'Révocation globale non canonique'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF NEW.statut_verification IS DISTINCT FROM OLD.statut_verification
     OR NEW.peut_publier_missions IS DISTINCT FROM OLD.peut_publier_missions
     OR NEW.verifie_le IS DISTINCT FROM OLD.verifie_le
     OR NEW.verifie_par IS DISTINCT FROM OLD.verifie_par
     OR NEW.motif_rejet IS DISTINCT FROM OLD.motif_rejet THEN
    RAISE EXCEPTION 'Écriture directe du statut de vérification interdite'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Compatibilité avec les anciennes fonctions internes commerciales. Ce
  -- marqueur est évalué seulement après tous les contrôles de conformité.
  v_is_internal := COALESCE(current_setting('app.internal_operation', true), '') = 'true';
  IF v_is_internal THEN
    RETURN NEW;
  END IF;

  IF NEW.taux_commission_negocie IS DISTINCT FROM OLD.taux_commission_negocie THEN RAISE EXCEPTION 'Modification du taux de commission non autorisée'; END IF;
  IF NEW.stripe_customer_id IS DISTINCT FROM OLD.stripe_customer_id THEN RAISE EXCEPTION 'Modification du Stripe ID non autorisée'; END IF;
  IF NEW.palier_commission_id IS DISTINCT FROM OLD.palier_commission_id THEN RAISE EXCEPTION 'Modification du palier non autorisée'; END IF;
  IF NEW.formule_abonnement IS DISTINCT FROM OLD.formule_abonnement THEN RAISE EXCEPTION 'Modification de la formule non autorisée'; END IF;
  IF NEW.mode_facturation IS DISTINCT FROM OLD.mode_facturation THEN RAISE EXCEPTION 'Modification du mode de facturation non autorisée'; END IF;
  IF NEW.chorus_pro_actif IS DISTINCT FROM OLD.chorus_pro_actif THEN RAISE EXCEPTION 'Modification Chorus Pro non autorisée'; END IF;
  IF NEW.chorus_pro_identifiant IS DISTINCT FROM OLD.chorus_pro_identifiant THEN RAISE EXCEPTION 'Modification Chorus Pro non autorisée'; END IF;
  IF NEW.delai_paiement_jours IS DISTINCT FROM OLD.delai_paiement_jours THEN RAISE EXCEPTION 'Modification du délai non autorisée'; END IF;
  IF NEW.missions_mois_precedent IS DISTINCT FROM OLD.missions_mois_precedent THEN RAISE EXCEPTION 'Modification compteur non autorisée'; END IF;
  IF NEW.palier_recalcule_le IS DISTINCT FROM OLD.palier_recalcule_le THEN RAISE EXCEPTION 'Modification date recalcul non autorisée'; END IF;
  IF NEW.groupe_sante_id IS DISTINCT FROM OLD.groupe_sante_id THEN RAISE EXCEPTION 'Modification du groupe non autorisée'; END IF;
  IF NEW.note_moyenne IS DISTINCT FROM OLD.note_moyenne THEN RAISE EXCEPTION 'Modification de la note non autorisée'; END IF;
  IF NEW.est_secteur_public IS DISTINCT FROM OLD.est_secteur_public THEN RAISE EXCEPTION 'Modification du secteur public non autorisée'; END IF;
  IF NEW.mode_paiement_commission IS DISTINCT FROM OLD.mode_paiement_commission THEN RAISE EXCEPTION 'Modification du mode de paiement non autorisée'; END IF;

  RETURN NEW;
END;
$$;

-- L'admin ne peut plus fabriquer un FINESS absent et peut revalider une fiche
-- précédemment marquée VERIFIE seulement après contrôle de toutes les preuves.
CREATE OR REPLACE FUNCTION public.fn_admin_valider_etablissement(p_etablissement_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_etab record;
BEGIN
  IF NOT public.est_admin() THEN RETURN jsonb_build_object('error', 'Accès refusé — admin uniquement'); END IF;
  SELECT id, nom, siret, finess, siret_verifie, finess_verifie,
         representant_identite_verifiee, rattachement_verifie, contrat_service_signe
    INTO v_etab
  FROM public.etablissements
  WHERE id = p_etablissement_id AND supprime_le IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Établissement introuvable'); END IF;
  IF v_etab.siret IS NULL OR v_etab.siret_verifie IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Le SIRET officiel doit être vérifié.');
  END IF;
  IF v_etab.finess IS NULL OR v_etab.finess_verifie IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Le FINESS officiel doit être vérifié.');
  END IF;
  IF v_etab.representant_identite_verifiee IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'L identité du représentant doit être vérifiée.');
  END IF;
  IF v_etab.rattachement_verifie IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'L habilitation du représentant doit être vérifiée.');
  END IF;
  IF v_etab.contrat_service_signe IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Le contrat de service Jolene doit être signé.');
  END IF;
  UPDATE public.etablissements
  SET statut_verification = 'VERIFIE', peut_publier_missions = true,
      verifie_le = now(), verifie_par = auth.uid(), modifie_le = now()
  WHERE id = p_etablissement_id;
  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := auth.uid(), p_type_acteur := 'ADMIN_PLATEFORME', p_action := 'ADMIN_ACTION',
    p_type_ressource := 'etablissement', p_id_ressource := p_etablissement_id,
    p_details := jsonb_build_object('sous_action', 'VALIDATION_ETABLISSEMENT', 'nom', v_etab.nom)
  );
  RETURN jsonb_build_object('success', true, 'nom', v_etab.nom);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_admin_valider_contrat_etablissement(
  p_etablissement_id uuid,
  p_valider boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT public.est_admin() THEN RETURN jsonb_build_object('error', 'Accès refusé — admin uniquement'); END IF;
  IF p_valider AND NOT EXISTS (
    SELECT 1 FROM public.etablissements
    WHERE id = p_etablissement_id AND contrat_url IS NOT NULL AND contrat_ia_coherent IS TRUE
  ) THEN
    RETURN jsonb_build_object('error', 'Le contrat et sa cohérence IA doivent être contrôlés avant validation.');
  END IF;
  UPDATE public.etablissements SET contrat_valide = p_valider, modifie_le = now()
  WHERE id = p_etablissement_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Établissement introuvable'); END IF;
  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := auth.uid(), p_type_acteur := 'ADMIN_PLATEFORME', p_action := 'ADMIN_ACTION',
    p_type_ressource := 'etablissement', p_id_ressource := p_etablissement_id,
    p_details := jsonb_build_object('sous_action', 'VALIDATION_CONTRAT_ETABLISSEMENT', 'valide', p_valider)
  );
  RETURN jsonb_build_object('success', true);
END;
$$;
