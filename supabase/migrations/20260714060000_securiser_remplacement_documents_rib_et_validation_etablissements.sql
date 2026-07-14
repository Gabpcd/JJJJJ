-- Une seule récompense peut être enfilée pour un même parrainage. Ce verrou
-- appartient au flux de versement, pas aux migrations Stripe.
CREATE UNIQUE INDEX IF NOT EXISTS
  uniq_externalisation_recompense_parrainage
ON public.externalisation_actions (type_action, source, source_id)
WHERE type_action = 'RECOMPENSE_PARRAINAGE_SOIGNANT'
  AND source = 'parrainage_soignant'
  AND source_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.fn_parrainage_verifier_seuils(
  p_parrainage_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_p public.parrainages%ROWTYPE;
  v_prime integer := public.fn_param_num('prime_parrainage_eur', 25)::integer;
  v_seuil_gmv numeric := public.fn_param_num('seuil_gmv_parrainage_eur', 500);
  v_nb_fraude_signals integer;
  v_rows integer;
  v_audit jsonb;
BEGIN
  SELECT p.*
    INTO v_p
    FROM public.parrainages p
   WHERE p.id = p_parrainage_id
   FOR UPDATE;
  IF NOT FOUND OR v_p.statut <> 'FILLEUL_ACTIF' THEN
    RETURN;
  END IF;

  IF COALESCE(v_p.gmv_cumule_filleul, 0) < v_seuil_gmv
     OR COALESCE(v_p.commission_cumulee_filleul, 0) < 4 * v_prime THEN
    RETURN;
  END IF;

  SELECT count(*)
    INTO v_nb_fraude_signals
    FROM public.parrainage_fraude_signals pfs
   WHERE pfs.parrainage_id = v_p.id
     AND pfs.type = 'MEME_IP';
  IF v_nb_fraude_signals > 0 THEN
    UPDATE public.parrainages
       SET statut = 'FRAUDE'
     WHERE id = v_p.id
       AND statut = 'FILLEUL_ACTIF';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN
      RAISE EXCEPTION 'Transition fraude parrainage concurrente';
    END IF;
    v_audit := public.fn_ecrire_audit_safe(
      v_p.parrain_id, 'SYSTEME', 'PARRAINAGE_SOIGNANT_FRAUDE',
      'parrainage', v_p.id, NULL,
      jsonb_build_object(
        'filleul_id', v_p.filleul_id,
        'commission_cumulee', v_p.commission_cumulee_filleul,
        'gmv_cumule', v_p.gmv_cumule_filleul,
        'raison', 'MEME_IP détectée à inscription'
      ), NULL, 'fn_parrainage_verifier_seuils'
    );
    IF COALESCE(v_audit @> '{"success": true}'::jsonb, false) IS NOT TRUE THEN
      RAISE EXCEPTION 'Audit fraude parrainage non écrit';
    END IF;
    INSERT INTO public.notifications (
      destinataire_id, type_destinataire, type, titre, corps, lien
    )
    SELECT admins.admin_user_id, 'ADMIN', 'SYSTEM',
           'Parrainage fraude détectée',
           'Parrainage ' || v_p.id::text
             || ' : même IP parrain/filleul. Versement bloqué.',
           '/admin/utilisateurs'
      FROM public.fn_list_admin_user_ids() AS admins(admin_user_id);
    RETURN;
  END IF;

  UPDATE public.parrainages
     SET statut = 'VALIDE_EN_ATTENTE_SEUIL'
   WHERE id = v_p.id
     AND statut = 'FILLEUL_ACTIF';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Validation parrainage concurrente';
  END IF;

  INSERT INTO public.externalisation_actions (
    type_action, payload, source, source_id
  ) VALUES (
    'RECOMPENSE_PARRAINAGE_SOIGNANT',
    jsonb_build_object(
      'parrainage_id', v_p.id,
      'parrain_id', v_p.parrain_id,
      'filleul_id', v_p.filleul_id,
      'montant_parrain', v_prime,
      'montant_filleul', v_prime,
      'commission_cumulee', v_p.commission_cumulee_filleul,
      'gmv_cumule', v_p.gmv_cumule_filleul
    ),
    'parrainage_soignant',
    v_p.id
  )
  ON CONFLICT (type_action, source, source_id)
    WHERE type_action = 'RECOMPENSE_PARRAINAGE_SOIGNANT'
      AND source = 'parrainage_soignant'
      AND source_id IS NOT NULL
  DO NOTHING;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Action de récompense parrainage déjà présente';
  END IF;

  v_audit := public.fn_ecrire_audit_safe(
    v_p.parrain_id, 'SYSTEME', 'PARRAINAGE_SOIGNANT_SEUIL_ATTEINT',
    'parrainage', v_p.id, NULL,
    jsonb_build_object(
      'filleul_id', v_p.filleul_id,
      'commission_cumulee', v_p.commission_cumulee_filleul,
      'gmv_cumule', v_p.gmv_cumule_filleul,
      'prime_due_eur', v_prime
    ), NULL, 'fn_parrainage_verifier_seuils'
  );
  IF COALESCE(v_audit @> '{"success": true}'::jsonb, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Audit seuil parrainage non écrit';
  END IF;

  INSERT INTO public.notifications (
    destinataire_id, type_destinataire, type, titre, corps, lien
  ) VALUES
    (
      v_p.parrain_id, 'SOIGNANT', 'PARRAINAGE',
      'Prime de parrainage validée',
      'Votre filleul a atteint le seuil. La prime de ' || v_prime
        || '€ est due et son paiement est en cours de traitement.',
      '/soignant/parrainage'
    ),
    (
      v_p.filleul_id, 'SOIGNANT', 'PARRAINAGE',
      'Prime de parrainage validée',
      'Le seuil est atteint. Votre prime de ' || v_prime
        || '€ est due et son paiement est en cours de traitement.',
      '/soignant/parrainage'
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_parrainage_verifier_seuils(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_parrainage_verifier_seuils(uuid)
  TO service_role;

-- ---------------------------------------------------------------------------
-- Preuves soignant : une seule version courante et historique conservé
-- ---------------------------------------------------------------------------

ALTER TABLE public.documents_soignants
  ADD COLUMN IF NOT EXISTS revoque_le timestamptz,
  ADD COLUMN IF NOT EXISTS revoque_raison text,
  ADD COLUMN IF NOT EXISTS remplace_par_document_id uuid;

DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'documents_soignants_remplace_par_document_id_fkey'
      AND conrelid = 'public.documents_soignants'::regclass
  ) THEN
    ALTER TABLE public.documents_soignants
      ADD CONSTRAINT documents_soignants_remplace_par_document_id_fkey
      FOREIGN KEY (remplace_par_document_id)
      REFERENCES public.documents_soignants(id)
      ON DELETE SET NULL
      DEFERRABLE INITIALLY DEFERRED;
  END IF;
END;
$migration$;

ALTER TABLE public.documents_soignants
  DROP CONSTRAINT IF EXISTS documents_soignants_revoque_raison_check;
ALTER TABLE public.documents_soignants
  ADD CONSTRAINT documents_soignants_revoque_raison_check
  CHECK (
    (revoque_le IS NULL AND revoque_raison IS NULL AND remplace_par_document_id IS NULL)
    OR (
      revoque_le IS NOT NULL
      AND revoque_raison IN ('REMPLACEMENT', 'RETRAIT')
    )
  );

CREATE INDEX IF NOT EXISTS idx_documents_soignants_preuve_courante
  ON public.documents_soignants (soignant_id, type_document, televerse_le DESC)
  WHERE supprime_le IS NULL AND revoque_le IS NULL;

COMMENT ON COLUMN public.documents_soignants.revoque_le IS
  'Date de désactivation de cette version de preuve. La ligne et son verdict restent conservés pour audit.';
COMMENT ON COLUMN public.documents_soignants.remplace_par_document_id IS
  'Nouvelle version qui a atomiquement remplacé cette preuve.';

-- Le diplôme est une preuve critique pour toutes les professions. Un RPPS ou
-- un ADELI vérifié reste un recoupement de registre et ne dispense jamais du
-- diplôme, notamment pour distinguer IDE, IADE et IBODE.
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
  'Diplôme correspondant à la profession déclarée ; la spécialité exacte est obligatoire pour IADE et IBODE.',
  'TOUS'
FROM unnest(enum_range(NULL::public.type_profession)) AS p(profession)
ON CONFLICT (profession, type_document) DO UPDATE
SET est_critique = true,
    a_expiration = false,
    duree_validite_mois = NULL,
    type_exercice_requis = 'TOUS',
    description = COALESCE(
      NULLIF(drp.description, ''),
      EXCLUDED.description
    );

-- Vrai uniquement si cette version précise satisfait actuellement une preuve
-- critique d'une mission déjà attribuée. La suppression ou le remplacement
-- est alors refusé : le dossier ne peut pas devenir non conforme après le gate
-- d'affectation.
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
        drp.type_document = 'RPPS_ADELI'
        AND (COALESCE(s.rpps_verifie, false) OR COALESCE(s.adeli_verifie, false))
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

CREATE OR REPLACE FUNCTION public.fn_bloquer_retrait_preuve_mission_active()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF COALESCE(current_setting('jolene.document_replacement', true), '') = 'true' THEN
    RETURN NEW;
  END IF;

  IF OLD.supprime_le IS NULL
     AND OLD.revoque_le IS NULL
     AND (
       NEW.supprime_le IS NOT NULL
       OR NEW.revoque_le IS NOT NULL
     )
     AND public.fn_document_requis_par_mission_active(OLD.id) THEN
    RAISE EXCEPTION
      'Ce justificatif est requis par une mission assignée ou en cours et ne peut pas être retiré.'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_05_bloquer_retrait_preuve_mission_active
  ON public.documents_soignants;
CREATE TRIGGER trg_05_bloquer_retrait_preuve_mission_active
BEFORE UPDATE OF supprime_le, revoque_le ON public.documents_soignants
FOR EACH ROW
EXECUTE FUNCTION public.fn_bloquer_retrait_preuve_mission_active();

REVOKE ALL ON FUNCTION public.fn_bloquer_retrait_preuve_mission_active()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_bloquer_retrait_preuve_mission_active()
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_remplacer_preuves_documentaires_actives()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_classe text;
  v_ids_revoques jsonb := '[]'::jsonb;
BEGIN
  IF NEW.supprime_le IS NOT NULL OR NEW.revoque_le IS NOT NULL THEN
    RETURN NEW;
  END IF;

  v_classe := CASE
    WHEN NEW.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')
      THEN 'IDENTITE_OFFICIELLE'
    ELSE NEW.type_document::text
  END;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(NEW.soignant_id::text || ':' || v_classe, 0)
  );

  IF EXISTS (
    SELECT 1
    FROM public.documents_soignants precedent
    WHERE precedent.soignant_id = NEW.soignant_id
      AND precedent.id IS DISTINCT FROM NEW.id
      AND precedent.supprime_le IS NULL
      AND precedent.revoque_le IS NULL
      AND CASE
        WHEN precedent.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')
          THEN 'IDENTITE_OFFICIELLE'
        ELSE precedent.type_document::text
      END = v_classe
      AND public.fn_document_requis_par_mission_active(precedent.id)
  ) THEN
    RAISE EXCEPTION
      'Cette preuve est utilisée par une mission assignée ou en cours. Son remplacement est temporairement bloqué.'
      USING ERRCODE = '23514';
  END IF;

  PERFORM set_config('jolene.document_replacement', 'true', true);
  WITH revoquees AS (
    UPDATE public.documents_soignants precedent
    SET supprime_le = now(),
        revoque_le = now(),
        revoque_raison = 'REMPLACEMENT',
        remplace_par_document_id = NEW.id,
        verification_attempt_id = NULL,
        modifie_le = now()
    WHERE precedent.soignant_id = NEW.soignant_id
      AND precedent.id IS DISTINCT FROM NEW.id
      AND precedent.supprime_le IS NULL
      AND precedent.revoque_le IS NULL
      AND CASE
        WHEN precedent.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')
          THEN 'IDENTITE_OFFICIELLE'
        ELSE precedent.type_document::text
      END = v_classe
    RETURNING precedent.id
  )
  SELECT COALESCE(jsonb_agg(id), '[]'::jsonb)
    INTO v_ids_revoques
  FROM revoquees;
  PERFORM set_config('jolene.document_replacement', '', true);

  IF jsonb_array_length(v_ids_revoques) > 0 THEN
    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := NEW.soignant_id,
      p_type_acteur := 'SOIGNANT',
      p_action := 'VERIFICATION_DOCUMENT',
      p_type_ressource := 'document_soignant',
      p_id_ressource := NEW.id,
      p_details := jsonb_build_object(
        'sous_action', 'REMPLACEMENT_PREUVE',
        'classe_preuve', v_classe,
        'documents_revoques', v_ids_revoques
      )
    );
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_10_remplacer_preuves_documentaires_actives
  ON public.documents_soignants;
CREATE TRIGGER trg_10_remplacer_preuves_documentaires_actives
BEFORE INSERT ON public.documents_soignants
FOR EACH ROW
EXECUTE FUNCTION public.fn_remplacer_preuves_documentaires_actives();

REVOKE ALL ON FUNCTION public.fn_remplacer_preuves_documentaires_actives()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_remplacer_preuves_documentaires_actives()
  TO service_role;

-- Canonical gate : une preuve révoquée ne satisfait jamais une mission. Le
-- RPPS/ADELI peut satisfaire uniquement la ligne de registre. Le diplôme reste
-- obligatoire, et IADE/IBODE exigent le diplôme exact de spécialité.
CREATE OR REPLACE FUNCTION public.fn_documents_ok_pour_mission(
  p_soignant_id uuid,
  p_type_contrat text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_profession public.type_profession;
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
         COALESCE(rpps_verifie, false) OR COALESCE(adeli_verifie, false),
         COALESCE(statut_compte::text, 'ACTIF') = 'ACTIF'
           AND COALESCE(type_exercice, 'SALARIE') IN ('LIBERAL', 'MIXTE')
           AND statut_liberal = 'ACTIF'
           AND siret_liberal ~ '^[0-9]{14}$'
           AND siret_liberal_verifie IS TRUE
           AND siret_liberal_verifie_le IS NOT NULL
           AND siret_liberal_coherence_identite IS TRUE
    INTO v_profession, v_identifiant_officiel, v_liberal_actif
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

-- ---------------------------------------------------------------------------
-- RIB soignant : l'IBAN de virement doit provenir du RIB courant vérifié
-- ---------------------------------------------------------------------------

ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS iban_source_document_id uuid,
  ADD COLUMN IF NOT EXISTS iban_verifie_le timestamptz,
  ADD COLUMN IF NOT EXISTS iban_titulaire_coherent boolean NOT NULL DEFAULT false;

DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'soignants_iban_source_document_id_fkey'
      AND conrelid = 'public.soignants'::regclass
  ) THEN
    ALTER TABLE public.soignants
      ADD CONSTRAINT soignants_iban_source_document_id_fkey
      FOREIGN KEY (iban_source_document_id)
      REFERENCES public.documents_soignants(id)
      ON DELETE SET NULL
      DEFERRABLE INITIALLY DEFERRED;
  END IF;
END;
$migration$;

ALTER TABLE public.soignants
  DROP CONSTRAINT IF EXISTS soignants_iban_provenance_coherente_check;
ALTER TABLE public.soignants
  ADD CONSTRAINT soignants_iban_provenance_coherente_check
  CHECK (
    iban_titulaire_coherent IS FALSE
    OR (iban_source_document_id IS NOT NULL AND iban_verifie_le IS NOT NULL)
  );

COMMENT ON COLUMN public.soignants.iban_source_document_id IS
  'RIB actif et vérifié ayant prouvé exactement l IBAN de virement courant.';
COMMENT ON COLUMN public.soignants.iban_titulaire_coherent IS
  'Concordance déterministe entre titulaire du compte, RIB et identité actuelle du soignant.';

CREATE OR REPLACE FUNCTION public.fn_iban_est_valide(p_iban text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_iban text := upper(regexp_replace(COALESCE(p_iban, ''), '[^A-Za-z0-9]', '', 'g'));
  v_rearranged text;
  v_char text;
  v_numeric text;
  v_remainder integer := 0;
  i integer;
  j integer;
BEGIN
  IF v_iban !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' THEN
    RETURN false;
  END IF;

  v_rearranged := substring(v_iban FROM 5) || substring(v_iban FROM 1 FOR 4);
  FOR i IN 1..length(v_rearranged) LOOP
    v_char := substring(v_rearranged FROM i FOR 1);
    v_numeric := CASE
      WHEN v_char ~ '^[A-Z]$' THEN (ascii(v_char) - 55)::text
      ELSE v_char
    END;
    FOR j IN 1..length(v_numeric) LOOP
      v_remainder := (
        v_remainder * 10 + substring(v_numeric FROM j FOR 1)::integer
      ) % 97;
    END LOOP;
  END LOOP;
  RETURN v_remainder = 1;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_iban_est_valide(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_iban_est_valide(text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_proteger_provenance_iban_soignant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF auth.role() = 'service_role'
     OR auth.uid() IS NULL
     OR session_user IN ('postgres', 'supabase_admin')
     OR COALESCE(current_setting('jolene.bank_server_update', true), '') = 'true' THEN
    RETURN NEW;
  END IF;

  IF NEW.iban_virement IS DISTINCT FROM OLD.iban_virement
     OR NEW.iban_titulaire IS DISTINCT FROM OLD.iban_titulaire
     OR NEW.iban_last4 IS DISTINCT FROM OLD.iban_last4
     OR NEW.iban_source_document_id IS DISTINCT FROM OLD.iban_source_document_id
     OR NEW.iban_verifie_le IS DISTINCT FROM OLD.iban_verifie_le
     OR NEW.iban_titulaire_coherent IS DISTINCT FROM OLD.iban_titulaire_coherent THEN
    RAISE EXCEPTION 'Les coordonnées bancaires sont enregistrées exclusivement par le parcours RIB vérifié.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_proteger_provenance_iban_soignant
  ON public.soignants;
CREATE TRIGGER trg_proteger_provenance_iban_soignant
BEFORE UPDATE OF iban_virement, iban_titulaire, iban_last4,
  iban_source_document_id, iban_verifie_le, iban_titulaire_coherent
ON public.soignants
FOR EACH ROW
EXECUTE FUNCTION public.fn_proteger_provenance_iban_soignant();

REVOKE ALL ON FUNCTION public.fn_proteger_provenance_iban_soignant()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_proteger_provenance_iban_soignant()
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_enregistrer_mon_iban(
  p_iban text,
  p_titulaire text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_iban text;
  v_last4 text;
  v_hash text;
  v_action text;
  v_soignant public.soignants%ROWTYPE;
  v_rib public.documents_soignants%ROWTYPE;
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  v_iban := upper(regexp_replace(COALESCE(p_iban, ''), '[^A-Za-z0-9]', '', 'g'));
  IF NOT public.fn_iban_est_valide(v_iban) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'IBAN_INVALIDE',
      'error', 'IBAN invalide. Vérifiez le format et la clé de contrôle.'
    );
  END IF;
  IF NULLIF(btrim(COALESCE(p_titulaire, '')), '') IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'TITULAIRE_REQUIS',
      'error', 'Le nom du titulaire est obligatoire.'
    );
  END IF;

  SELECT * INTO v_soignant
  FROM public.soignants
  WHERE id = v_uid AND supprime_le IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Profil soignant introuvable');
  END IF;
  IF v_soignant.identite_verifiee IS NOT TRUE
     OR v_soignant.coherence_identite IS DISTINCT FROM 'COHERENT' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'IDENTITE_VERIFIEE_REQUISE',
      'error', 'Votre identité doit être vérifiée avant d enregistrer un IBAN.'
    );
  END IF;

  SELECT * INTO v_rib
  FROM public.documents_soignants
  WHERE soignant_id = v_uid
    AND type_document = 'RIB'
    AND supprime_le IS NULL
    AND revoque_le IS NULL
    AND statut_verification = 'VERIFIE'
  ORDER BY televerse_le DESC, id DESC
  LIMIT 1
  FOR SHARE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'RIB_VERIFIE_REQUIS',
      'error', 'Téléversez puis faites vérifier le RIB correspondant avant d enregistrer cet IBAN.'
    );
  END IF;

  v_last4 := right(v_iban, 4);
  v_hash := encode(
    extensions.digest(convert_to(v_iban || ':' || v_rib.id::text, 'UTF8'), 'sha256'),
    'hex'
  );

  IF COALESCE(v_rib.resultat_ia->>'verdict_serveur', '') <> 'VERIFIE'
     OR COALESCE(v_rib.resultat_ia->>'iban_valide', '') <> 'true'
     OR upper(COALESCE(v_rib.resultat_ia->>'iban_last4', '')) <> v_last4
     OR COALESCE(v_rib.resultat_ia->>'iban_preuve_hash_v1', '') <> v_hash
     OR v_rib.coherence_nom IS NOT TRUE
     OR NOT public.fn_noms_personne_correspondent(
       v_soignant.nom,
       v_soignant.prenom,
       v_rib.nom_extrait_ia,
       v_rib.prenom_extrait_ia
     ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'RIB_NON_CONCORDANT',
      'error', 'L IBAN ou le titulaire ne correspond pas exactement au RIB vérifié et à votre identité.'
    );
  END IF;

  IF NOT public.fn_noms_personne_correspondent(
    v_soignant.nom,
    v_soignant.prenom,
    p_titulaire,
    p_titulaire
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'TITULAIRE_NON_CONCORDANT',
      'error', 'Le titulaire saisi doit correspondre à votre identité vérifiée.'
    );
  END IF;

  v_action := CASE
    WHEN NULLIF(v_soignant.iban_virement, '') IS NULL THEN 'IBAN_RENSEIGNE'
    ELSE 'IBAN_MODIFIE'
  END;

  PERFORM set_config('jolene.bank_server_update', 'true', true);
  UPDATE public.soignants
  SET iban_virement = v_iban,
      iban_titulaire = btrim(p_titulaire),
      iban_last4 = v_last4,
      iban_source_document_id = v_rib.id,
      iban_verifie_le = now(),
      iban_titulaire_coherent = true,
      modifie_le = now()
  WHERE id = v_uid;
  PERFORM set_config('jolene.bank_server_update', '', true);

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := v_action,
    p_type_ressource := 'soignant',
    p_id_ressource := v_uid,
    p_details := jsonb_build_object(
      'iban_last4', v_last4,
      'source_document_id', v_rib.id,
      'titulaire_coherent', true
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'iban_last4', v_last4,
    'titulaire', btrim(p_titulaire),
    'rib_verifie', true,
    'message', 'IBAN vérifié et enregistré.'
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_enregistrer_mon_iban(text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_enregistrer_mon_iban(text, text)
  TO authenticated, service_role;

-- Cette RPC est la seule source autorisée pour les virements SWAN. Elle
-- réévalue la preuve, l'identité et le hash exact à chaque lecture. Aucun
-- fallback vers un ancien iban_virement brut n'est permis.
CREATE OR REPLACE FUNCTION public.fn_coordonnees_bancaires_soignant_verifiees(
  p_soignant_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions
AS $function$
DECLARE
  v_soignant public.soignants%ROWTYPE;
  v_rib public.documents_soignants%ROWTYPE;
  v_hash text;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_soignant
  FROM public.soignants
  WHERE id = p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND
     OR NULLIF(v_soignant.iban_virement, '') IS NULL
     OR v_soignant.iban_source_document_id IS NULL
     OR v_soignant.iban_verifie_le IS NULL
     OR v_soignant.iban_titulaire_coherent IS NOT TRUE
     OR v_soignant.identite_verifiee IS NOT TRUE
     OR v_soignant.coherence_identite IS DISTINCT FROM 'COHERENT'
     OR NOT public.fn_iban_est_valide(v_soignant.iban_virement) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'RIB_VERIFIE_REQUIS',
      'error', 'Aucune coordonnée bancaire vérifiée et active.'
    );
  END IF;

  SELECT * INTO v_rib
  FROM public.documents_soignants
  WHERE id = v_soignant.iban_source_document_id
    AND soignant_id = p_soignant_id
    AND type_document = 'RIB'
    AND supprime_le IS NULL
    AND revoque_le IS NULL
    AND statut_verification = 'VERIFIE';
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'RIB_VERIFIE_REQUIS',
      'error', 'La preuve bancaire associée n est plus active.'
    );
  END IF;

  v_hash := encode(
    extensions.digest(
      convert_to(v_soignant.iban_virement || ':' || v_rib.id::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  IF COALESCE(v_rib.resultat_ia->>'verdict_serveur', '') <> 'VERIFIE'
     OR COALESCE(v_rib.resultat_ia->>'iban_valide', '') <> 'true'
     OR upper(COALESCE(v_rib.resultat_ia->>'iban_last4', ''))
          <> right(v_soignant.iban_virement, 4)
     OR COALESCE(v_rib.resultat_ia->>'iban_preuve_hash_v1', '') <> v_hash
     OR v_rib.coherence_nom IS NOT TRUE
     OR NOT public.fn_noms_personne_correspondent(
       v_soignant.nom,
       v_soignant.prenom,
       v_rib.nom_extrait_ia,
       v_rib.prenom_extrait_ia
     )
     OR NOT public.fn_noms_personne_correspondent(
       v_soignant.nom,
       v_soignant.prenom,
       v_soignant.iban_titulaire,
       v_soignant.iban_titulaire
     ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'RIB_NON_CONCORDANT',
      'error', 'La preuve bancaire ne concorde plus avec le profil courant.'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'iban', v_soignant.iban_virement,
    'titulaire', v_soignant.iban_titulaire,
    'iban_last4', right(v_soignant.iban_virement, 4),
    'source_document_id', v_rib.id,
    'verifie_le', v_soignant.iban_verifie_le
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_coordonnees_bancaires_soignant_verifiees(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_coordonnees_bancaires_soignant_verifiees(uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_consulter_mon_iban()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_result record;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT
    s.iban_last4,
    s.iban_titulaire,
    NULLIF(s.iban_virement, '') IS NOT NULL AS iban_renseigne,
    (
      s.iban_titulaire_coherent IS TRUE
      AND s.iban_verifie_le IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.documents_soignants ds
        WHERE ds.id = s.iban_source_document_id
          AND ds.soignant_id = s.id
          AND ds.type_document = 'RIB'
          AND ds.statut_verification = 'VERIFIE'
          AND ds.supprime_le IS NULL
          AND ds.revoque_le IS NULL
      )
    ) AS iban_verifie
    INTO v_result
  FROM public.soignants s
  WHERE s.id = v_uid AND s.supprime_le IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('iban_renseigne', false, 'iban_verifie', false);
  END IF;

  RETURN jsonb_build_object(
    'iban_renseigne', COALESCE(v_result.iban_renseigne, false),
    'iban_verifie', COALESCE(v_result.iban_verifie, false),
    'verification_requise',
      COALESCE(v_result.iban_renseigne, false) AND NOT COALESCE(v_result.iban_verifie, false),
    'iban_last4', v_result.iban_last4,
    'iban_titulaire', v_result.iban_titulaire
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_consulter_mon_iban()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_consulter_mon_iban()
  TO authenticated, service_role;

-- Une nouvelle version, un retrait ou un nouveau verdict du RIB invalide
-- uniquement sa provenance de paiement. L'ancien IBAN brut est conservé pour
-- l'historique et les paiements externes déjà initiés, mais n'est plus lisible
-- par la RPC de décaissement.
CREATE OR REPLACE FUNCTION public.fn_invalider_provenance_iban_depuis_document()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_document_id uuid;
  v_type_document public.type_document;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_document_id := OLD.id;
    v_type_document := OLD.type_document;
  ELSE
    v_document_id := NEW.id;
    v_type_document := NEW.type_document;
  END IF;

  IF v_type_document = 'RIB' THEN
    PERFORM set_config('jolene.bank_server_update', 'true', true);
    UPDATE public.soignants
    SET iban_source_document_id = NULL,
        iban_verifie_le = NULL,
        iban_titulaire_coherent = false,
        modifie_le = now()
    WHERE iban_source_document_id = v_document_id;
    PERFORM set_config('jolene.bank_server_update', '', true);
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_invalider_provenance_iban_document_update
  ON public.documents_soignants;
CREATE TRIGGER trg_invalider_provenance_iban_document_update
AFTER UPDATE OF statut_verification, resultat_ia, coherence_nom, supprime_le, revoque_le,
  soignant_id, type_document, s3_cle
ON public.documents_soignants
FOR EACH ROW
EXECUTE FUNCTION public.fn_invalider_provenance_iban_depuis_document();

DROP TRIGGER IF EXISTS trg_invalider_provenance_iban_document_delete
  ON public.documents_soignants;
CREATE TRIGGER trg_invalider_provenance_iban_document_delete
AFTER DELETE ON public.documents_soignants
FOR EACH ROW
EXECUTE FUNCTION public.fn_invalider_provenance_iban_depuis_document();

CREATE OR REPLACE FUNCTION public.fn_invalider_provenance_iban_sur_identite()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF NEW.nom IS DISTINCT FROM OLD.nom
     OR NEW.prenom IS DISTINCT FROM OLD.prenom
     OR NEW.identite_verifiee IS DISTINCT FROM OLD.identite_verifiee
     OR NEW.coherence_identite IS DISTINCT FROM OLD.coherence_identite THEN
    PERFORM set_config('jolene.bank_server_update', 'true', true);
    UPDATE public.soignants
    SET iban_source_document_id = NULL,
        iban_verifie_le = NULL,
        iban_titulaire_coherent = false,
        modifie_le = now()
    WHERE id = NEW.id;
    PERFORM set_config('jolene.bank_server_update', '', true);
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_invalider_provenance_iban_sur_identite
  ON public.soignants;
CREATE TRIGGER trg_invalider_provenance_iban_sur_identite
AFTER UPDATE OF nom, prenom, identite_verifiee, coherence_identite
ON public.soignants
FOR EACH ROW
EXECUTE FUNCTION public.fn_invalider_provenance_iban_sur_identite();

REVOKE ALL ON FUNCTION public.fn_invalider_provenance_iban_depuis_document()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_invalider_provenance_iban_sur_identite()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_invalider_provenance_iban_depuis_document()
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_invalider_provenance_iban_sur_identite()
  TO service_role;
