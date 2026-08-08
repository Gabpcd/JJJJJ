-- Mandat de facturation v1.4, TVA explicite, périodes sans chevauchement et
-- désactivation ferme de la rétrocession au lancement.

-- Le PDF lisible et le XML CII sont conservés séparément. Le dépôt public doit
-- tracer le flux réellement envoyé au lieu de qualifier à tort le PDF de
-- Factur-X hybride.
ALTER TABLE public.chorus_submissions
  DROP CONSTRAINT IF EXISTS chorus_submissions_submission_type_check;
ALTER TABLE public.chorus_submissions
  ADD CONSTRAINT chorus_submissions_submission_type_check
  CHECK (submission_type IN ('DEPOT_PDF_API', 'DEPOT_XML_API', 'SAISIE_API'));

-- ---------------------------------------------------------------------------
-- 1. Statut TVA du prestataire, nature TVA par mission et snapshots immuables
-- ---------------------------------------------------------------------------

ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS regime_tva_honoraires text,
  ADD COLUMN IF NOT EXISTS statut_tva_honoraires text;

ALTER TABLE public.soignants
  DROP CONSTRAINT IF EXISTS soignants_regime_tva_honoraires_check;
ALTER TABLE public.soignants
  ADD CONSTRAINT soignants_regime_tva_honoraires_check
  CHECK (
    regime_tva_honoraires IS NULL
    OR regime_tva_honoraires IN (
      'EXONERE_ART_261_4_1',
      'FRANCHISE_EN_BASE_ART_293_B',
      'ASSUJETTI_TVA'
    )
  );

ALTER TABLE public.soignants
  DROP CONSTRAINT IF EXISTS soignants_statut_tva_honoraires_check;
ALTER TABLE public.soignants
  ADD CONSTRAINT soignants_statut_tva_honoraires_check
  CHECK (
    statut_tva_honoraires IS NULL
    OR statut_tva_honoraires IN ('FRANCHISE_EN_BASE', 'REDEVABLE_TVA')
  );

-- Les anciennes valeurs globales 293 B et assujetti se convertissent sans
-- ambiguïté. Une ancienne exonération « globale » ne permet pas de déduire le
-- statut de l'activité : le soignant devra donc choisir lors de la v1.4.
UPDATE public.soignants
SET statut_tva_honoraires = CASE regime_tva_honoraires
  WHEN 'FRANCHISE_EN_BASE_ART_293_B' THEN 'FRANCHISE_EN_BASE'
  WHEN 'ASSUJETTI_TVA' THEN 'REDEVABLE_TVA'
  ELSE statut_tva_honoraires
END
WHERE statut_tva_honoraires IS NULL;

ALTER TABLE public.missions
  ADD COLUMN IF NOT EXISTS nature_tva_prestation text,
  ADD COLUMN IF NOT EXISTS nature_tva_declaree_par uuid,
  ADD COLUMN IF NOT EXISTS nature_tva_declaree_le timestamptz,
  ADD COLUMN IF NOT EXISTS nature_tva_confirmee_soignant text,
  ADD COLUMN IF NOT EXISTS nature_tva_confirmee_par uuid,
  ADD COLUMN IF NOT EXISTS nature_tva_confirmee_le timestamptz,
  ADD COLUMN IF NOT EXISTS statut_validation_tva text NOT NULL DEFAULT 'NON_REQUISE',
  ADD COLUMN IF NOT EXISTS revue_tva_motif text,
  ADD COLUMN IF NOT EXISTS revue_tva_resolue_par uuid,
  ADD COLUMN IF NOT EXISTS revue_tva_resolue_le timestamptz;

ALTER TABLE public.missions
  DROP CONSTRAINT IF EXISTS missions_nature_tva_prestation_check,
  DROP CONSTRAINT IF EXISTS missions_nature_tva_confirmee_soignant_check,
  DROP CONSTRAINT IF EXISTS missions_statut_validation_tva_check;
ALTER TABLE public.missions
  ADD CONSTRAINT missions_nature_tva_prestation_check CHECK (
    nature_tva_prestation IS NULL
    OR nature_tva_prestation IN (
      'SOIN_THERAPEUTIQUE_EXONERE',
      'PRESTATION_TAXABLE'
    )
  ),
  ADD CONSTRAINT missions_nature_tva_confirmee_soignant_check CHECK (
    nature_tva_confirmee_soignant IS NULL
    OR nature_tva_confirmee_soignant IN (
      'SOIN_THERAPEUTIQUE_EXONERE',
      'PRESTATION_TAXABLE'
    )
  ),
  ADD CONSTRAINT missions_statut_validation_tva_check CHECK (
    statut_validation_tva IN (
      'NON_REQUISE',
      'A_CONFIRMER',
      'CONFIRMEE',
      'A_REVOIR'
    )
  );

COMMENT ON COLUMN public.soignants.statut_tva_honoraires IS
  'Statut propre à l activité libérale : franchise en base ou redevable. La nature exonérée/taxable est déterminée mission par mission.';
COMMENT ON COLUMN public.missions.nature_tva_prestation IS
  'Nature TVA déclarée par l établissement puis confirmée par le soignant avant facturation libérale.';
COMMENT ON COLUMN public.missions.statut_validation_tva IS
  'Le statut TVA ne bloque jamais l exécution ni les litiges ; il bloque uniquement la création d une nouvelle facture tant qu il n est pas CONFIRMEE.';

-- Les missions libérales déjà affectées avant ce déploiement n'ont pas de
-- déclaration exploitable. Elles entrent dans la file humaine plutôt que
-- d'être facturées avec une hypothèse silencieuse.
UPDATE public.missions
SET statut_validation_tva = 'A_REVOIR'
WHERE soignant_assigne_id IS NOT NULL
  AND type_contrat_applique::text = 'LIBERAL'
  AND nature_tva_prestation IS NULL;

ALTER TABLE public.factures_honoraires
  ADD COLUMN IF NOT EXISTS regime_tva_snapshot text,
  ADD COLUMN IF NOT EXISTS base_legale_tva_snapshot text,
  ADD COLUMN IF NOT EXISTS nature_prestation_snapshot text,
  ADD COLUMN IF NOT EXISTS description_prestation_snapshot text,
  ADD COLUMN IF NOT EXISTS quantite_heures_snapshot numeric(10,2),
  ADD COLUMN IF NOT EXISTS taux_horaire_snapshot numeric(12,2),
  ADD COLUMN IF NOT EXISTS nature_correction text NOT NULL DEFAULT 'ORIGINALE',
  ADD COLUMN IF NOT EXISTS emetteur_identite_snapshot text,
  ADD COLUMN IF NOT EXISTS emetteur_profession_snapshot text,
  ADD COLUMN IF NOT EXISTS emetteur_siret_snapshot text,
  ADD COLUMN IF NOT EXISTS emetteur_numero_professionnel_snapshot text,
  ADD COLUMN IF NOT EXISTS emetteur_adresse_snapshot text,
  ADD COLUMN IF NOT EXISTS emetteur_adresse_rue_snapshot text,
  ADD COLUMN IF NOT EXISTS emetteur_adresse_code_postal_snapshot text,
  ADD COLUMN IF NOT EXISTS emetteur_adresse_ville_snapshot text,
  ADD COLUMN IF NOT EXISTS emetteur_email_snapshot text,
  ADD COLUMN IF NOT EXISTS emetteur_numero_tva_snapshot text,
  ADD COLUMN IF NOT EXISTS destinataire_nom_snapshot text,
  ADD COLUMN IF NOT EXISTS destinataire_siret_snapshot text,
  ADD COLUMN IF NOT EXISTS destinataire_adresse_rue_snapshot text,
  ADD COLUMN IF NOT EXISTS destinataire_adresse_code_postal_snapshot text,
  ADD COLUMN IF NOT EXISTS destinataire_adresse_ville_snapshot text;

ALTER TABLE public.factures_honoraires
  DROP CONSTRAINT IF EXISTS factures_honoraires_regime_tva_snapshot_check;
ALTER TABLE public.factures_honoraires
  ADD CONSTRAINT factures_honoraires_regime_tva_snapshot_check
  CHECK (
    regime_tva_snapshot IS NULL
    OR regime_tva_snapshot IN (
      'EXONERE_ART_261_4_1',
      'FRANCHISE_EN_BASE_ART_293_B',
      'ASSUJETTI_TVA'
    )
  );

ALTER TABLE public.factures_honoraires
  DROP CONSTRAINT IF EXISTS factures_honoraires_nature_correction_check;
ALTER TABLE public.factures_honoraires
  ADD CONSTRAINT factures_honoraires_nature_correction_check
  CHECK (
    nature_correction IN ('ORIGINALE', 'REMPLACEMENT', 'COMPLEMENT', 'AVOIR')
    AND (
      (type_document = 'AVOIR' AND nature_correction = 'AVOIR' AND facture_precedente_id IS NOT NULL)
      OR
      (type_document = 'FACTURE' AND nature_correction IN ('ORIGINALE', 'REMPLACEMENT', 'COMPLEMENT'))
    )
    AND (
      nature_correction NOT IN ('REMPLACEMENT', 'COMPLEMENT')
      OR (facture_precedente_id IS NOT NULL AND litige_id IS NOT NULL)
    )
  ) NOT VALID;

UPDATE public.factures_honoraires
SET nature_correction = CASE
  WHEN type_document = 'AVOIR' THEN 'AVOIR'
  WHEN facture_precedente_id IS NOT NULL AND litige_id IS NOT NULL THEN 'REMPLACEMENT'
  ELSE 'ORIGINALE'
END;

ALTER TABLE public.factures_honoraires
  VALIDATE CONSTRAINT factures_honoraires_nature_correction_check;

-- Compatibilité des flux de litige déjà en production : les RPC historiques
-- créent un AVOIR ou une facture liée sans encore renseigner explicitement la
-- nature. Le serveur la normalise avant les contraintes et les index.
CREATE OR REPLACE FUNCTION public.fn_normaliser_nature_correction_facture()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $body$
DECLARE
  v_origine public.factures_honoraires%ROWTYPE;
BEGIN
  IF NEW.type_document = 'AVOIR' THEN
    NEW.nature_correction := 'AVOIR';
  ELSIF NEW.nature_correction = 'ORIGINALE'
        AND NEW.facture_precedente_id IS NOT NULL
        AND NEW.litige_id IS NOT NULL THEN
    NEW.nature_correction := 'REMPLACEMENT';
  END IF;

  IF NEW.facture_precedente_id IS NOT NULL
     AND TG_OP = 'INSERT' THEN
    SELECT * INTO v_origine
    FROM public.factures_honoraires
    WHERE id = NEW.facture_precedente_id;

    IF FOUND THEN
      NEW.regime_tva_snapshot := COALESCE(NEW.regime_tva_snapshot, v_origine.regime_tva_snapshot);
      NEW.base_legale_tva_snapshot := COALESCE(NEW.base_legale_tva_snapshot, v_origine.base_legale_tva_snapshot);
      NEW.nature_prestation_snapshot := COALESCE(NEW.nature_prestation_snapshot, v_origine.nature_prestation_snapshot);
      NEW.emetteur_identite_snapshot := COALESCE(NEW.emetteur_identite_snapshot, v_origine.emetteur_identite_snapshot);
      NEW.emetteur_profession_snapshot := COALESCE(NEW.emetteur_profession_snapshot, v_origine.emetteur_profession_snapshot);
      NEW.emetteur_siret_snapshot := COALESCE(NEW.emetteur_siret_snapshot, v_origine.emetteur_siret_snapshot);
      NEW.emetteur_numero_professionnel_snapshot := COALESCE(NEW.emetteur_numero_professionnel_snapshot, v_origine.emetteur_numero_professionnel_snapshot);
      NEW.emetteur_adresse_snapshot := COALESCE(NEW.emetteur_adresse_snapshot, v_origine.emetteur_adresse_snapshot);
      NEW.emetteur_adresse_rue_snapshot := COALESCE(NEW.emetteur_adresse_rue_snapshot, v_origine.emetteur_adresse_rue_snapshot);
      NEW.emetteur_adresse_code_postal_snapshot := COALESCE(NEW.emetteur_adresse_code_postal_snapshot, v_origine.emetteur_adresse_code_postal_snapshot);
      NEW.emetteur_adresse_ville_snapshot := COALESCE(NEW.emetteur_adresse_ville_snapshot, v_origine.emetteur_adresse_ville_snapshot);
      NEW.emetteur_email_snapshot := COALESCE(NEW.emetteur_email_snapshot, v_origine.emetteur_email_snapshot);
      NEW.emetteur_numero_tva_snapshot := COALESCE(NEW.emetteur_numero_tva_snapshot, v_origine.emetteur_numero_tva_snapshot);
      NEW.destinataire_nom_snapshot := COALESCE(NEW.destinataire_nom_snapshot, v_origine.destinataire_nom_snapshot);
      NEW.destinataire_siret_snapshot := COALESCE(NEW.destinataire_siret_snapshot, v_origine.destinataire_siret_snapshot);
      NEW.destinataire_adresse_rue_snapshot := COALESCE(NEW.destinataire_adresse_rue_snapshot, v_origine.destinataire_adresse_rue_snapshot);
      NEW.destinataire_adresse_code_postal_snapshot := COALESCE(NEW.destinataire_adresse_code_postal_snapshot, v_origine.destinataire_adresse_code_postal_snapshot);
      NEW.destinataire_adresse_ville_snapshot := COALESCE(NEW.destinataire_adresse_ville_snapshot, v_origine.destinataire_adresse_ville_snapshot);
      NEW.description_prestation_snapshot := COALESCE(
        NEW.description_prestation_snapshot,
        CASE NEW.nature_correction
          WHEN 'AVOIR' THEN 'Avoir de correction lié à la facture ' || v_origine.numero_facture
          WHEN 'COMPLEMENT' THEN 'Complément d’honoraires lié à la facture ' || v_origine.numero_facture
          ELSE 'Facture rectificative remplaçant la facture ' || v_origine.numero_facture
        END
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$body$;

DROP TRIGGER IF EXISTS trg_00_normaliser_nature_correction_facture
  ON public.factures_honoraires;
CREATE TRIGGER trg_00_normaliser_nature_correction_facture
BEFORE INSERT OR UPDATE OF type_document, facture_precedente_id, litige_id, nature_correction
ON public.factures_honoraires
FOR EACH ROW EXECUTE FUNCTION public.fn_normaliser_nature_correction_facture();

UPDATE public.factures_honoraires fh
SET
  regime_tva_snapshot = COALESCE(
    fh.regime_tva_snapshot,
    CASE
      WHEN fh.exoneration_tva THEN 'EXONERE_ART_261_4_1'
      ELSE 'ASSUJETTI_TVA'
    END
  ),
  base_legale_tva_snapshot = COALESCE(
    fh.base_legale_tva_snapshot,
    CASE
      WHEN fh.exoneration_tva THEN 'Article 261, 4, 1° du CGI'
      ELSE 'Article 278 du CGI'
    END
  ),
  nature_prestation_snapshot = COALESCE(
    fh.nature_prestation_snapshot,
    CASE
      WHEN fh.exoneration_tva THEN 'SOINS_A_LA_PERSONNE_FINALITE_THERAPEUTIQUE'
      ELSE 'PRESTATION_HORS_EXONERATION_DE_SOIN'
    END
  ),
  description_prestation_snapshot = COALESCE(
    fh.description_prestation_snapshot,
    CASE
      WHEN fh.type_document = 'AVOIR' THEN 'Avoir lié à une correction de mission'
      WHEN fh.est_facture_finale_mission THEN 'Honoraires de mission — facture finale'
      ELSE 'Honoraires de mission — facture hebdomadaire'
    END
  ),
  taux_horaire_snapshot = COALESCE(
    fh.taux_horaire_snapshot,
    m.taux_horaire_base_fige,
    m.taux_horaire_base
  ),
  quantite_heures_snapshot = COALESCE(
    fh.quantite_heures_snapshot,
    CASE
      WHEN COALESCE(m.taux_horaire_base_fige, m.taux_horaire_base, 0) > 0
        THEN round(fh.montant_ht / COALESCE(m.taux_horaire_base_fige, m.taux_horaire_base), 2)
      ELSE NULL
    END
  ),
  emetteur_identite_snapshot = COALESCE(
    fh.emetteur_identite_snapshot,
    NULLIF(btrim(concat_ws(' ', s.prenom, s.nom)), '')
  ),
  emetteur_profession_snapshot = COALESCE(
    fh.emetteur_profession_snapshot,
    s.profession::text
  ),
  emetteur_siret_snapshot = COALESCE(
    fh.emetteur_siret_snapshot,
    s.siret_liberal
  ),
  emetteur_numero_professionnel_snapshot = COALESCE(
    fh.emetteur_numero_professionnel_snapshot,
    s.numero_rpps,
    s.numero_adeli
  ),
  emetteur_adresse_snapshot = COALESCE(
    fh.emetteur_adresse_snapshot,
    NULLIF(btrim(concat_ws(', ', s.adresse_rue, concat_ws(' ', s.adresse_code_postal, s.adresse_ville))), '')
  ),
  emetteur_adresse_rue_snapshot = COALESCE(fh.emetteur_adresse_rue_snapshot, s.adresse_rue),
  emetteur_adresse_code_postal_snapshot = COALESCE(fh.emetteur_adresse_code_postal_snapshot, s.adresse_code_postal),
  emetteur_adresse_ville_snapshot = COALESCE(fh.emetteur_adresse_ville_snapshot, s.adresse_ville),
  emetteur_email_snapshot = COALESCE(fh.emetteur_email_snapshot, s.email),
  emetteur_numero_tva_snapshot = COALESCE(
    fh.emetteur_numero_tva_snapshot,
    s.numero_tva
  ),
  destinataire_nom_snapshot = COALESCE(fh.destinataire_nom_snapshot, e.nom),
  destinataire_siret_snapshot = COALESCE(fh.destinataire_siret_snapshot, e.siret),
  destinataire_adresse_rue_snapshot = COALESCE(fh.destinataire_adresse_rue_snapshot, e.adresse_rue),
  destinataire_adresse_code_postal_snapshot = COALESCE(fh.destinataire_adresse_code_postal_snapshot, e.adresse_code_postal),
  destinataire_adresse_ville_snapshot = COALESCE(fh.destinataire_adresse_ville_snapshot, e.adresse_ville)
FROM public.soignants s, public.missions m, public.etablissements e
WHERE s.id = fh.soignant_id
  AND m.id = fh.mission_id
  AND e.id = fh.etablissement_id;

-- ---------------------------------------------------------------------------
-- 2. Preuve du mandat : texte exact, IP serveur, rétention et version active
-- ---------------------------------------------------------------------------

ALTER TABLE public.mandats_facturation_signatures
  ADD COLUMN IF NOT EXISTS contenu_texte text,
  ADD COLUMN IF NOT EXISTS regime_tva_honoraires text,
  ADD COLUMN IF NOT EXISTS statut_tva_honoraires text,
  ADD COLUMN IF NOT EXISTS ip_source text,
  ADD COLUMN IF NOT EXISTS retention_jusqu_au timestamptz,
  ADD COLUMN IF NOT EXISTS revocation_motif text;

ALTER TABLE public.mandats_facturation_signatures
  DROP CONSTRAINT IF EXISTS mandats_facturation_regime_tva_check;
ALTER TABLE public.mandats_facturation_signatures
  ADD CONSTRAINT mandats_facturation_regime_tva_check
  CHECK (
    regime_tva_honoraires IS NULL
    OR regime_tva_honoraires IN (
      'EXONERE_ART_261_4_1',
      'FRANCHISE_EN_BASE_ART_293_B',
      'ASSUJETTI_TVA'
    )
  );

ALTER TABLE public.mandats_facturation_signatures
  DROP CONSTRAINT IF EXISTS mandats_facturation_statut_tva_check;
ALTER TABLE public.mandats_facturation_signatures
  ADD CONSTRAINT mandats_facturation_statut_tva_check
  CHECK (
    statut_tva_honoraires IS NULL
    OR statut_tva_honoraires IN ('FRANCHISE_EN_BASE', 'REDEVABLE_TVA')
  );

UPDATE public.mandats_facturation_signatures
SET retention_jusqu_au = COALESCE(retention_jusqu_au, signed_at + interval '10 years');

-- La v1.4 modifie substantiellement le mandat : toute version antérieure doit
-- être révoquée et re-signée explicitement.
UPDATE public.mandats_facturation_signatures
SET
  revoked_at = COALESCE(revoked_at, now()),
  revocation_motif = COALESCE(revocation_motif, 'REMPLACEMENT_PAR_MANDAT_V1_4')
WHERE revoked_at IS NULL
  AND version IS DISTINCT FROM '1.4';

UPDATE public.soignants
SET
  mandat_facturation_signe = false,
  mandat_facturation_signe_le = NULL,
  mandat_facturation_version = NULL
WHERE COALESCE(mandat_facturation_signe, false) IS TRUE
  AND mandat_facturation_version IS DISTINCT FROM '1.4';

CREATE UNIQUE INDEX IF NOT EXISTS uniq_mandat_facturation_actif_soignant
  ON public.mandats_facturation_signatures (soignant_id)
  WHERE revoked_at IS NULL;

CREATE OR REPLACE FUNCTION public.fn_preserver_preuve_mandat_facturation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $body$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.retention_jusqu_au IS NULL OR OLD.retention_jusqu_au > now() THEN
      UPDATE public.mandats_facturation_signatures
      SET
        revoked_at = COALESCE(revoked_at, now()),
        revocation_motif = COALESCE(
          revocation_motif,
          'PREUVE_CONSERVEE_PENDANT_RETENTION'
        )
      WHERE id = OLD.id;
      RETURN NULL;
    END IF;
    RETURN OLD;
  END IF;

  IF NEW.soignant_id IS DISTINCT FROM OLD.soignant_id
     OR NEW.version IS DISTINCT FROM OLD.version
     OR NEW.signed_at IS DISTINCT FROM OLD.signed_at
     OR NEW.ip_address IS DISTINCT FROM OLD.ip_address
     OR NEW.user_agent IS DISTINCT FROM OLD.user_agent
     OR NEW.contenu_hash IS DISTINCT FROM OLD.contenu_hash
     OR NEW.contenu_texte IS DISTINCT FROM OLD.contenu_texte
     OR NEW.regime_tva_honoraires IS DISTINCT FROM OLD.regime_tva_honoraires
     OR NEW.statut_tva_honoraires IS DISTINCT FROM OLD.statut_tva_honoraires
     OR NEW.ip_source IS DISTINCT FROM OLD.ip_source
     OR NEW.retention_jusqu_au IS DISTINCT FROM OLD.retention_jusqu_au THEN
    RAISE EXCEPTION 'La preuve signée du mandat est immuable.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$body$;

DROP TRIGGER IF EXISTS trg_preserver_preuve_mandat_facturation
  ON public.mandats_facturation_signatures;
CREATE TRIGGER trg_preserver_preuve_mandat_facturation
BEFORE UPDATE OR DELETE ON public.mandats_facturation_signatures
FOR EACH ROW EXECUTE FUNCTION public.fn_preserver_preuve_mandat_facturation();

-- L'ancien RPC recevait une IP fournie par le navigateur (et donc falsifiable).
-- Il est conservé pour donner une erreur explicite aux clients obsolètes.
CREATE OR REPLACE FUNCTION public.fn_signer_mandat_facturation(
  p_version text,
  p_ip text DEFAULT NULL,
  p_user_agent text DEFAULT NULL,
  p_contenu_hash text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $body$
BEGIN
  RETURN jsonb_build_object(
    'success', false,
    'error', 'SIGNATURE_MANDAT_EDGE_REQUISE',
    'message', 'Rechargez l’application pour signer la version actuelle du mandat.'
  );
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_signer_mandat_facturation(text, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_signer_mandat_facturation(text, text, text, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_signer_mandat_facturation_serveur(
  p_soignant_id uuid,
  p_version text,
  p_ip text,
  p_ip_source text,
  p_user_agent text,
  p_contenu_hash text,
  p_contenu_texte text,
  p_statut_tva_honoraires text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $body$
DECLARE
  v_soignant public.soignants%ROWTYPE;
  v_signature_id uuid;
  v_hash_calcule text;
  v_champs_manquants text[] := ARRAY[]::text[];
BEGIN
  IF p_version IS DISTINCT FROM '1.4' THEN
    RETURN jsonb_build_object('success', false, 'error', 'VERSION_MANDAT_INVALIDE');
  END IF;
  IF p_statut_tva_honoraires IS NULL OR p_statut_tva_honoraires NOT IN (
    'FRANCHISE_EN_BASE',
    'REDEVABLE_TVA'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'STATUT_TVA_INVALIDE');
  END IF;
  IF p_contenu_texte IS NULL OR length(p_contenu_texte) NOT BETWEEN 1000 AND 60000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'CONTENU_MANDAT_INVALIDE');
  END IF;
  IF p_contenu_hash IS NULL OR p_contenu_hash !~ '^[a-f0-9]{64}$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'HASH_MANDAT_INVALIDE');
  END IF;

  v_hash_calcule := encode(digest(convert_to(p_contenu_texte, 'UTF8'), 'sha256'), 'hex');
  IF v_hash_calcule IS DISTINCT FROM p_contenu_hash THEN
    RETURN jsonb_build_object('success', false, 'error', 'HASH_MANDAT_INCOHERENT');
  END IF;

  SELECT * INTO v_soignant
  FROM public.soignants
  WHERE id = p_soignant_id
    AND supprime_le IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'SOIGNANT_INTROUVABLE');
  END IF;

  IF v_soignant.type_exercice IS NULL
     OR v_soignant.type_exercice::text NOT IN ('LIBERAL', 'MIXTE') THEN
    RETURN jsonb_build_object('success', false, 'error', 'MANDAT_RESERVE_EXERCICE_LIBERAL');
  END IF;
  IF NULLIF(btrim(v_soignant.prenom), '') IS NULL THEN v_champs_manquants := array_append(v_champs_manquants, 'prenom'); END IF;
  IF NULLIF(btrim(v_soignant.nom), '') IS NULL THEN v_champs_manquants := array_append(v_champs_manquants, 'nom'); END IF;
  IF v_soignant.profession IS NULL THEN v_champs_manquants := array_append(v_champs_manquants, 'profession'); END IF;
  IF v_soignant.profession::text IN ('MEDECIN', 'DENTISTE', 'SAGE_FEMME', 'PHARMACIEN')
     AND NULLIF(btrim(v_soignant.numero_rpps), '') IS NULL THEN
    v_champs_manquants := array_append(v_champs_manquants, 'numero_rpps');
  END IF;
  IF regexp_replace(COALESCE(v_soignant.siret_liberal, ''), '\D', '', 'g') !~ '^\d{14}$' THEN v_champs_manquants := array_append(v_champs_manquants, 'siret_liberal'); END IF;
  IF NULLIF(btrim(v_soignant.email), '') IS NULL THEN v_champs_manquants := array_append(v_champs_manquants, 'email'); END IF;
  IF NULLIF(btrim(v_soignant.adresse_rue), '') IS NULL THEN v_champs_manquants := array_append(v_champs_manquants, 'adresse_rue'); END IF;
  IF NULLIF(btrim(v_soignant.adresse_code_postal), '') IS NULL THEN v_champs_manquants := array_append(v_champs_manquants, 'adresse_code_postal'); END IF;
  IF NULLIF(btrim(v_soignant.adresse_ville), '') IS NULL THEN v_champs_manquants := array_append(v_champs_manquants, 'adresse_ville'); END IF;
  IF p_statut_tva_honoraires = 'REDEVABLE_TVA'
     AND NULLIF(btrim(v_soignant.numero_tva), '') IS NULL THEN
    v_champs_manquants := array_append(v_champs_manquants, 'numero_tva');
  END IF;

  IF cardinality(v_champs_manquants) > 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'PROFIL_FACTURATION_INCOMPLET',
      'champs_manquants', to_jsonb(v_champs_manquants)
    );
  END IF;

  UPDATE public.mandats_facturation_signatures
  SET
    revoked_at = now(),
    revocation_motif = 'REMPLACE_PAR_NOUVELLE_SIGNATURE'
  WHERE soignant_id = p_soignant_id
    AND revoked_at IS NULL;

  INSERT INTO public.mandats_facturation_signatures (
    soignant_id,
    version,
    ip_address,
    ip_source,
    user_agent,
    contenu_hash,
    contenu_texte,
    statut_tva_honoraires,
    retention_jusqu_au
  ) VALUES (
    p_soignant_id,
    p_version,
    NULLIF(left(COALESCE(p_ip, ''), 128), ''),
    NULLIF(left(COALESCE(p_ip_source, ''), 64), ''),
    NULLIF(left(COALESCE(p_user_agent, ''), 1000), ''),
    p_contenu_hash,
    p_contenu_texte,
    p_statut_tva_honoraires,
    now() + interval '10 years'
  )
  RETURNING id INTO v_signature_id;

  UPDATE public.soignants
  SET
    statut_tva_honoraires = p_statut_tva_honoraires,
    -- Compatibilité temporaire avec les lecteurs qui consomment encore le
    -- snapshot historique à trois valeurs. L'exonération n'est plus globale.
    regime_tva_honoraires = CASE p_statut_tva_honoraires
      WHEN 'FRANCHISE_EN_BASE' THEN 'FRANCHISE_EN_BASE_ART_293_B'
      ELSE 'ASSUJETTI_TVA'
    END,
    assujetti_tva = (p_statut_tva_honoraires = 'REDEVABLE_TVA'),
    mandat_facturation_signe = true,
    mandat_facturation_signe_le = now(),
    mandat_facturation_version = p_version
  WHERE id = p_soignant_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := p_soignant_id,
    p_type_acteur := 'SOIGNANT',
    p_action := 'FACTURATION',
    p_type_ressource := 'mandat_facturation',
    p_id_ressource := v_signature_id,
    p_details := jsonb_build_object(
      'event', 'MANDAT_FACTURATION_SIGNE',
      'version', p_version,
      'statut_tva_honoraires', p_statut_tva_honoraires,
      'ip_source', p_ip_source
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'signature_id', v_signature_id,
    'version', p_version,
    'signed_at', now(),
    'factures_regenerees', 0
  );
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_signer_mandat_facturation_serveur(
  uuid, text, text, text, text, text, text, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_signer_mandat_facturation_serveur(
  uuid, text, text, text, text, text, text, text
) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_revoquer_mandat_facturation(p_motif text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_signature_id uuid;
  v_version text;
  v_signed_at timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.soignants
    WHERE id = v_uid AND mandat_facturation_signe = true
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Aucun mandat actif à révoquer');
  END IF;

  SELECT id, version, signed_at
  INTO v_signature_id, v_version, v_signed_at
  FROM public.mandats_facturation_signatures
  WHERE soignant_id = v_uid AND revoked_at IS NULL
  ORDER BY signed_at DESC
  LIMIT 1;

  UPDATE public.mandats_facturation_signatures
  SET
    revoked_at = now(),
    revocation_motif = COALESCE(NULLIF(btrim(p_motif), ''), 'REVOCATION_PAR_LE_SOIGNANT')
  WHERE soignant_id = v_uid AND revoked_at IS NULL;

  UPDATE public.soignants
  SET
    mandat_facturation_signe = false,
    mandat_facturation_signe_le = NULL,
    mandat_facturation_version = NULL
  WHERE id = v_uid;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'FACTURATION',
    p_type_ressource := 'mandat_facturation',
    p_id_ressource := v_signature_id,
    p_details := jsonb_build_object(
      'event', 'MANDAT_FACTURATION_REVOQUE',
      'version', v_version,
      'signed_at', v_signed_at,
      'revoked_at', now(),
      'motif', p_motif,
      'effet', 'IMMEDIAT_POUR_NOUVELLES_FACTURES'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'signature_id', v_signature_id,
    'version', v_version,
    'revoked_at', now()
  );
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_revoquer_mandat_facturation(text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_revoquer_mandat_facturation(text)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Rétrocession désactivée côté serveur au lancement
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_bloquer_retrocession_prelaunch()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $body$
BEGIN
  IF NEW.mode_remuneration IS DISTINCT FROM 'TAUX_HORAIRE'
     OR NEW.retrocession_pct IS NOT NULL THEN
    RAISE EXCEPTION '[RETROCESSION_DESACTIVEE] La rétrocession de cabinet n’est pas disponible au lancement. Publiez une mission libérale directe à taux horaire.'
      USING ERRCODE = 'feature_not_supported';
  END IF;
  RETURN NEW;
END;
$body$;

DROP TRIGGER IF EXISTS trg_00_bloquer_retrocession_prelaunch ON public.missions;
CREATE TRIGGER trg_00_bloquer_retrocession_prelaunch
BEFORE INSERT OR UPDATE OF mode_remuneration, retrocession_pct ON public.missions
FOR EACH ROW EXECUTE FUNCTION public.fn_bloquer_retrocession_prelaunch();

ALTER TABLE public.missions
  DROP CONSTRAINT IF EXISTS missions_mode_remuneration_lancement_check;
ALTER TABLE public.missions
  ADD CONSTRAINT missions_mode_remuneration_lancement_check
  CHECK (mode_remuneration = 'TAUX_HORAIRE' AND retrocession_pct IS NULL)
  NOT VALID;

-- ---------------------------------------------------------------------------
-- 3 bis. Déclaration et confirmation TVA sans bloquer la mission ni le litige
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_proteger_validation_tva_mission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $body$
DECLARE
  v_managed boolean := COALESCE(
    current_setting('jolene.tva_mission_managed', true),
    'false'
  ) = 'true';
  v_affectation_change boolean :=
    NEW.soignant_assigne_id IS DISTINCT FROM OLD.soignant_assigne_id
    OR NEW.type_contrat_applique IS DISTINCT FROM OLD.type_contrat_applique;
  v_champ_pilote_change boolean :=
    NEW.nature_tva_prestation IS DISTINCT FROM OLD.nature_tva_prestation
    OR NEW.nature_tva_declaree_par IS DISTINCT FROM OLD.nature_tva_declaree_par
    OR NEW.nature_tva_declaree_le IS DISTINCT FROM OLD.nature_tva_declaree_le
    OR NEW.nature_tva_confirmee_soignant IS DISTINCT FROM OLD.nature_tva_confirmee_soignant
    OR NEW.nature_tva_confirmee_par IS DISTINCT FROM OLD.nature_tva_confirmee_par
    OR NEW.nature_tva_confirmee_le IS DISTINCT FROM OLD.nature_tva_confirmee_le
    OR NEW.revue_tva_motif IS DISTINCT FROM OLD.revue_tva_motif
    OR NEW.revue_tva_resolue_par IS DISTINCT FROM OLD.revue_tva_resolue_par
    OR NEW.revue_tva_resolue_le IS DISTINCT FROM OLD.revue_tva_resolue_le;
BEGIN
  -- Les changements d'heures, de taux, de présence, de statut de mission et
  -- les corrections de litige ne sont volontairement pas concernés.
  IF NOT v_managed AND v_champ_pilote_change THEN
    RAISE EXCEPTION 'Utilisez le parcours de validation TVA de la mission.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Les moteurs d'acceptation existants n'ont pas à connaître le workflow
  -- fiscal. Ce trigger initialise le bon état à partir du contrat réellement
  -- appliqué, sans bloquer l'affectation ni l'exécution de la mission.
  IF v_affectation_change AND NOT v_managed THEN
    IF NEW.soignant_assigne_id IS NOT NULL
       AND NEW.type_contrat_applique::text = 'LIBERAL' THEN
      NEW.nature_tva_confirmee_soignant := NULL;
      NEW.nature_tva_confirmee_par := NULL;
      NEW.nature_tva_confirmee_le := NULL;
      NEW.statut_validation_tva := CASE
        WHEN NEW.nature_tva_prestation IS NULL THEN 'A_REVOIR'
        ELSE 'A_CONFIRMER'
      END;
    ELSIF NEW.soignant_assigne_id IS NOT NULL THEN
      NEW.nature_tva_confirmee_soignant := NULL;
      NEW.nature_tva_confirmee_par := NULL;
      NEW.nature_tva_confirmee_le := NULL;
      NEW.statut_validation_tva := 'NON_REQUISE';
    ELSE
      NEW.nature_tva_confirmee_soignant := NULL;
      NEW.nature_tva_confirmee_par := NULL;
      NEW.nature_tva_confirmee_le := NULL;
      NEW.statut_validation_tva := CASE
        WHEN NEW.nature_tva_prestation IS NULL THEN 'NON_REQUISE'
        ELSE 'A_CONFIRMER'
      END;
    END IF;
  ELSIF NOT v_managed
        AND NEW.statut_validation_tva IS DISTINCT FROM OLD.statut_validation_tva THEN
    RAISE EXCEPTION 'Utilisez le parcours de validation TVA de la mission.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN NEW;
END;
$body$;

DROP TRIGGER IF EXISTS trg_05_proteger_validation_tva_mission ON public.missions;
CREATE TRIGGER trg_05_proteger_validation_tva_mission
BEFORE UPDATE OF
  soignant_assigne_id,
  type_contrat_applique,
  nature_tva_prestation,
  nature_tva_declaree_par,
  nature_tva_declaree_le,
  nature_tva_confirmee_soignant,
  nature_tva_confirmee_par,
  nature_tva_confirmee_le,
  statut_validation_tva,
  revue_tva_motif,
  revue_tva_resolue_par,
  revue_tva_resolue_le
ON public.missions
FOR EACH ROW EXECUTE FUNCTION public.fn_proteger_validation_tva_mission();

CREATE OR REPLACE FUNCTION public.fn_bloquer_insertion_validation_tva_directe()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $body$
BEGIN
  IF COALESCE(current_setting('jolene.tva_mission_managed', true), 'false') <> 'true'
     AND (
       NEW.nature_tva_prestation IS NOT NULL
       OR NEW.nature_tva_declaree_par IS NOT NULL
       OR NEW.nature_tva_declaree_le IS NOT NULL
       OR NEW.nature_tva_confirmee_soignant IS NOT NULL
       OR NEW.nature_tva_confirmee_par IS NOT NULL
       OR NEW.nature_tva_confirmee_le IS NOT NULL
       OR NEW.statut_validation_tva IS DISTINCT FROM 'NON_REQUISE'
       OR NEW.revue_tva_motif IS NOT NULL
       OR NEW.revue_tva_resolue_par IS NOT NULL
       OR NEW.revue_tva_resolue_le IS NOT NULL
     ) THEN
    RAISE EXCEPTION 'Utilisez le parcours de déclaration TVA de la mission.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END;
$body$;

DROP TRIGGER IF EXISTS trg_04_bloquer_insertion_validation_tva_directe ON public.missions;
CREATE TRIGGER trg_04_bloquer_insertion_validation_tva_directe
BEFORE INSERT ON public.missions
FOR EACH ROW EXECUTE FUNCTION public.fn_bloquer_insertion_validation_tva_directe();

CREATE OR REPLACE FUNCTION public.fn_creer_mission_multi_jours_v3(
  p_intitule text,
  p_description text,
  p_profession_requise public.type_profession,
  p_service text,
  p_taux_horaire_base numeric,
  p_est_urgente boolean,
  p_niveau_urgence integer,
  p_mode_attribution text,
  p_specialite_medicale_requise text,
  p_accepte_non_specialises boolean,
  p_creneaux jsonb,
  p_type_contrat_recherche text,
  p_mode_remuneration text,
  p_retrocession_pct numeric,
  p_nature_tva_prestation text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $body$
DECLARE
  v_resultat jsonb;
  v_mission_id uuid;
  v_nature_effective text;
  v_statut_tva_effectif text;
BEGIN
  IF p_type_contrat_recherche IN ('LIBERAL', 'TOUS')
     AND (
       p_nature_tva_prestation IS NULL
       OR p_nature_tva_prestation NOT IN (
       'SOIN_THERAPEUTIQUE_EXONERE',
       'PRESTATION_TAXABLE'
       )
     ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Indiquez la nature TVA prévue de la prestation libérale.'
    );
  END IF;

  v_resultat := public.fn_creer_mission_multi_jours_v2(
    p_intitule,
    p_description,
    p_profession_requise,
    p_service,
    p_taux_horaire_base,
    p_est_urgente,
    p_niveau_urgence,
    p_mode_attribution,
    p_specialite_medicale_requise,
    p_accepte_non_specialises,
    p_creneaux,
    p_type_contrat_recherche,
    p_mode_remuneration,
    p_retrocession_pct
  );
  IF COALESCE((v_resultat->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN v_resultat;
  END IF;

  v_mission_id := (v_resultat->>'mission_id')::uuid;
  PERFORM pg_catalog.set_config('jolene.tva_mission_managed', 'true', true);
  UPDATE public.missions
  SET
    nature_tva_prestation = CASE
      WHEN type_contrat_recherche::text = 'SALARIE' THEN NULL
      ELSE p_nature_tva_prestation
    END,
    nature_tva_declaree_par = CASE
      WHEN type_contrat_recherche::text = 'SALARIE' THEN NULL
      ELSE (SELECT auth.uid())
    END,
    nature_tva_declaree_le = CASE
      WHEN type_contrat_recherche::text = 'SALARIE' THEN NULL
      ELSE pg_catalog.now()
    END,
    statut_validation_tva = CASE
      WHEN type_contrat_recherche::text = 'SALARIE' THEN 'NON_REQUISE'
      ELSE 'A_CONFIRMER'
    END
  WHERE id = v_mission_id
  RETURNING nature_tva_prestation, statut_validation_tva
  INTO v_nature_effective, v_statut_tva_effectif;

  RETURN v_resultat || pg_catalog.jsonb_build_object(
    'nature_tva_prestation', v_nature_effective,
    'statut_validation_tva', v_statut_tva_effectif
  );
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_creer_mission_multi_jours_v3(
  text, text, public.type_profession, text, numeric, boolean, integer,
  text, text, boolean, jsonb, text, text, numeric, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_creer_mission_multi_jours_v3(
  text, text, public.type_profession, text, numeric, boolean, integer,
  text, text, boolean, jsonb, text, text, numeric, text
) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_modifier_mission_etablissement_v4(
  p_mission_id uuid,
  p_intitule text,
  p_description text,
  p_service text,
  p_profession_requise public.type_profession,
  p_taux_horaire_base numeric,
  p_est_urgente boolean,
  p_niveau_urgence integer,
  p_mode_attribution text,
  p_type_contrat_recherche text,
  p_specialite_medicale_requise text,
  p_accepte_non_specialises boolean,
  p_creneaux jsonb,
  p_nature_tva_prestation text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_mission public.missions%ROWTYPE;
  v_resultat jsonb;
  v_nature_demandee text;
  v_nature_effective text;
  v_statut_tva_effectif text;
BEGIN
  SELECT m.* INTO v_mission
  FROM public.missions m
  WHERE m.id = p_mission_id
  FOR UPDATE;
  IF NOT FOUND OR public.fn_a_permission_etablissement(
    'missions', v_mission.etablissement_id
  ) IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Mission introuvable ou accès refusé.'
    );
  END IF;

  v_nature_demandee := CASE
    WHEN p_type_contrat_recherche = 'SALARIE' THEN NULL
    ELSE p_nature_tva_prestation
  END;
  IF p_type_contrat_recherche IN ('LIBERAL', 'TOUS')
     AND (
       v_nature_demandee IS NULL
       OR v_nature_demandee NOT IN (
       'SOIN_THERAPEUTIQUE_EXONERE',
       'PRESTATION_TAXABLE'
       )
     ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'Indiquez la nature TVA prévue de la prestation libérale.'
    );
  END IF;
  IF v_nature_demandee IS DISTINCT FROM v_mission.nature_tva_prestation
     AND EXISTS (
       SELECT 1 FROM public.candidatures c
       WHERE c.mission_id = p_mission_id
         AND c.statut::text IN (
           'EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB', 'PROPOSEE'
         )
     ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'La nature TVA ne peut pas être modifiée pendant que des candidatures sont en attente.'
    );
  END IF;

  v_resultat := public.fn_modifier_mission_etablissement_v3(
    p_mission_id,
    p_intitule,
    p_description,
    p_service,
    p_profession_requise,
    p_taux_horaire_base,
    p_est_urgente,
    p_niveau_urgence,
    p_mode_attribution,
    p_type_contrat_recherche,
    p_specialite_medicale_requise,
    p_accepte_non_specialises,
    p_creneaux
  );
  IF COALESCE((v_resultat->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN v_resultat;
  END IF;

  PERFORM pg_catalog.set_config('jolene.tva_mission_managed', 'true', true);
  UPDATE public.missions
  SET
    nature_tva_prestation = CASE
      WHEN type_contrat_recherche::text = 'SALARIE' THEN NULL
      ELSE p_nature_tva_prestation
    END,
    nature_tva_declaree_par = CASE
      WHEN type_contrat_recherche::text = 'SALARIE' THEN NULL
      ELSE (SELECT auth.uid())
    END,
    nature_tva_declaree_le = CASE
      WHEN type_contrat_recherche::text = 'SALARIE' THEN NULL
      ELSE pg_catalog.now()
    END,
    nature_tva_confirmee_soignant = NULL,
    nature_tva_confirmee_par = NULL,
    nature_tva_confirmee_le = NULL,
    statut_validation_tva = CASE
      WHEN type_contrat_recherche::text = 'SALARIE' THEN 'NON_REQUISE'
      ELSE 'A_CONFIRMER'
    END,
    revue_tva_motif = NULL,
    revue_tva_resolue_par = NULL,
    revue_tva_resolue_le = NULL
  WHERE id = p_mission_id
  RETURNING nature_tva_prestation, statut_validation_tva
  INTO v_nature_effective, v_statut_tva_effectif;

  RETURN v_resultat || pg_catalog.jsonb_build_object(
    'nature_tva_prestation', v_nature_effective,
    'statut_validation_tva', v_statut_tva_effectif
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_modifier_mission_etablissement_v4(
  uuid, text, text, text, public.type_profession, numeric, boolean, integer,
  text, text, text, boolean, jsonb, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_modifier_mission_etablissement_v4(
  uuid, text, text, text, public.type_profession, numeric, boolean, integer,
  text, text, text, boolean, jsonb, text
) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_creer_mission_api_v2(
  p_etablissement_id uuid,
  p_intitule text,
  p_profession_requise public.type_profession,
  p_service text,
  p_taux_horaire_base numeric,
  p_creneaux jsonb,
  p_type_contrat_recherche text,
  p_mode_remuneration text,
  p_retrocession_pct numeric,
  p_nature_tva_prestation text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $function$
DECLARE
  v_resultat jsonb;
  v_mission_id uuid;
  v_nature_effective text;
  v_statut_tva_effectif text;
BEGIN
  IF p_type_contrat_recherche IN ('LIBERAL', 'TOUS')
     AND (
       p_nature_tva_prestation IS NULL
       OR p_nature_tva_prestation NOT IN (
       'SOIN_THERAPEUTIQUE_EXONERE',
       'PRESTATION_TAXABLE'
       )
     ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'success', false,
      'error', 'nature_tva_prestation requise pour une mission potentiellement libérale',
      'code', 'NATURE_TVA_REQUISE'
    );
  END IF;

  v_resultat := public.fn_creer_mission_api_v1(
    p_etablissement_id,
    p_intitule,
    p_profession_requise,
    p_service,
    p_taux_horaire_base,
    p_creneaux,
    p_type_contrat_recherche,
    p_mode_remuneration,
    p_retrocession_pct
  );
  IF COALESCE((v_resultat->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN v_resultat;
  END IF;

  v_mission_id := (v_resultat->>'mission_id')::uuid;
  PERFORM pg_catalog.set_config('jolene.tva_mission_managed', 'true', true);
  UPDATE public.missions
  SET
    nature_tva_prestation = CASE
      WHEN type_contrat_recherche::text = 'SALARIE' THEN NULL
      ELSE p_nature_tva_prestation
    END,
    nature_tva_declaree_par = NULL,
    nature_tva_declaree_le = CASE
      WHEN type_contrat_recherche::text = 'SALARIE' THEN NULL
      ELSE pg_catalog.now()
    END,
    statut_validation_tva = CASE
      WHEN type_contrat_recherche::text = 'SALARIE' THEN 'NON_REQUISE'
      ELSE 'A_CONFIRMER'
    END
  WHERE id = v_mission_id
  RETURNING nature_tva_prestation, statut_validation_tva
  INTO v_nature_effective, v_statut_tva_effectif;

  RETURN v_resultat || pg_catalog.jsonb_build_object(
    'nature_tva_prestation', v_nature_effective,
    'statut_validation_tva', v_statut_tva_effectif
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_creer_mission_api_v2(
  uuid, text, public.type_profession, text, numeric, jsonb, text, text,
  numeric, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_creer_mission_api_v2(
  uuid, text, public.type_profession, text, numeric, jsonb, text, text,
  numeric, text
) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_confirmer_nature_tva_mission(
  p_mission_id uuid,
  p_nature_tva_prestation text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_mission public.missions%ROWTYPE;
  v_confirmee boolean;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié.');
  END IF;
  IF p_nature_tva_prestation IS NULL OR p_nature_tva_prestation NOT IN (
    'SOIN_THERAPEUTIQUE_EXONERE',
    'PRESTATION_TAXABLE'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Nature TVA invalide.');
  END IF;

  SELECT m.* INTO v_mission
  FROM public.missions m
  WHERE m.id = p_mission_id
  FOR UPDATE;
  IF NOT FOUND
     OR v_mission.soignant_assigne_id IS DISTINCT FROM v_uid
     OR v_mission.type_contrat_applique::text IS DISTINCT FROM 'LIBERAL' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Cette confirmation est réservée au soignant libéral assigné.'
    );
  END IF;
  IF v_mission.nature_tva_prestation IS NULL
     OR v_mission.nature_tva_prestation NOT IN (
    'SOIN_THERAPEUTIQUE_EXONERE',
    'PRESTATION_TAXABLE'
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'La déclaration de l établissement est absente. Jolene a été prévenue.'
    );
  END IF;

  v_confirmee := p_nature_tva_prestation = v_mission.nature_tva_prestation;
  IF v_mission.nature_tva_confirmee_soignant = p_nature_tva_prestation
     AND v_mission.nature_tva_confirmee_par = v_uid
     AND v_mission.statut_validation_tva = (CASE
       WHEN v_confirmee THEN 'CONFIRMEE'
       ELSE 'A_REVOIR'
     END) THEN
    RETURN jsonb_build_object(
      'success', true,
      'statut_validation_tva', v_mission.statut_validation_tva,
      'accord', v_confirmee
    );
  END IF;

  PERFORM set_config('jolene.tva_mission_managed', 'true', true);
  UPDATE public.missions
  SET
    nature_tva_confirmee_soignant = p_nature_tva_prestation,
    nature_tva_confirmee_par = v_uid,
    nature_tva_confirmee_le = now(),
    statut_validation_tva = CASE
      WHEN v_confirmee THEN 'CONFIRMEE'
      ELSE 'A_REVOIR'
    END
  WHERE id = p_mission_id;

  INSERT INTO public.notifications (
    destinataire_id, type_destinataire, type, titre, corps, lien,
    type_ressource, id_ressource
  ) VALUES (
    v_mission.etablissement_id,
    'ETABLISSEMENT',
    'SYSTEM',
    CASE WHEN v_confirmee
      THEN 'Nature TVA confirmée'
      ELSE 'Nature TVA à revoir'
    END,
    CASE WHEN v_confirmee
      THEN 'Le soignant a confirmé la nature TVA de la mission « ' || left(v_mission.intitule, 120) || ' ».'
      ELSE 'Le soignant n est pas d accord avec la nature TVA de la mission « ' || left(v_mission.intitule, 120) || ' ». La mission continue, mais sa facturation est suspendue pendant la revue Jolene.'
    END,
    '/etablissement/missions/' || p_mission_id,
    'mission',
    p_mission_id
  );

  IF NOT v_confirmee THEN
    INSERT INTO public.notifications (
      destinataire_id, type_destinataire, type, titre, corps, lien,
      type_ressource, id_ressource
    )
    SELECT
      admin_id,
      'ADMIN',
      'SYSTEM',
      'Revue TVA mission requise',
      'Les parties ne concordent pas sur la nature TVA de la mission « ' || left(v_mission.intitule, 120) || ' ».',
      '/admin/facturation',
      'mission',
      p_mission_id
    FROM public.fn_list_admin_user_ids() AS admins(admin_id);
  END IF;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'FACTURATION',
    p_type_ressource := 'mission',
    p_id_ressource := p_mission_id,
    p_details := jsonb_build_object(
      'event', 'NATURE_TVA_MISSION_CONFIRMEE_PAR_SOIGNANT',
      'nature_etablissement', v_mission.nature_tva_prestation,
      'nature_soignant', p_nature_tva_prestation,
      'accord', v_confirmee,
      'effet', CASE WHEN v_confirmee
        THEN 'FACTURATION_AUTORISEE'
        ELSE 'FACTURATION_SUSPENDUE_MISSION_ACTIVE'
      END
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'statut_validation_tva', CASE
      WHEN v_confirmee THEN 'CONFIRMEE'
      ELSE 'A_REVOIR'
    END,
    'accord', v_confirmee
  );
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_confirmer_nature_tva_mission(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_confirmer_nature_tva_mission(uuid, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_admin_lister_revues_tva_missions()
RETURNS TABLE (
  mission_id uuid,
  intitule text,
  etablissement_id uuid,
  etablissement_nom text,
  soignant_id uuid,
  soignant_nom text,
  nature_etablissement text,
  nature_soignant text,
  declaration_le timestamptz,
  confirmation_le timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $body$
BEGIN
  IF auth.uid() IS NULL OR public.est_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Accès administrateur requis.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN QUERY
  SELECT
    m.id,
    m.intitule::text,
    m.etablissement_id,
    e.nom::text,
    m.soignant_assigne_id,
    NULLIF(btrim(concat_ws(' ', s.prenom, s.nom)), ''),
    m.nature_tva_prestation,
    m.nature_tva_confirmee_soignant,
    m.nature_tva_declaree_le,
    m.nature_tva_confirmee_le
  FROM public.missions m
  JOIN public.etablissements e ON e.id = m.etablissement_id
  JOIN public.soignants s ON s.id = m.soignant_assigne_id
  WHERE m.statut_validation_tva = 'A_REVOIR'
    AND m.type_contrat_applique::text = 'LIBERAL'
  ORDER BY m.nature_tva_confirmee_le ASC NULLS FIRST, m.id;
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_admin_lister_revues_tva_missions()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_lister_revues_tva_missions()
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_admin_proposer_nature_tva_mission(
  p_mission_id uuid,
  p_nature_tva_prestation text,
  p_motif text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_mission public.missions%ROWTYPE;
BEGIN
  IF v_uid IS NULL OR public.est_admin() IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès administrateur requis.');
  END IF;
  IF p_nature_tva_prestation IS NULL OR p_nature_tva_prestation NOT IN (
    'SOIN_THERAPEUTIQUE_EXONERE',
    'PRESTATION_TAXABLE'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Nature TVA invalide.');
  END IF;
  IF length(btrim(COALESCE(p_motif, ''))) NOT BETWEEN 10 AND 1000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Le motif de revue doit contenir entre 10 et 1000 caractères.'
    );
  END IF;

  SELECT m.* INTO v_mission
  FROM public.missions m
  WHERE m.id = p_mission_id
  FOR UPDATE;
  IF NOT FOUND
     OR v_mission.type_contrat_applique::text IS DISTINCT FROM 'LIBERAL'
     OR v_mission.statut_validation_tva IS DISTINCT FROM 'A_REVOIR'
     OR v_mission.soignant_assigne_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Cette mission n est plus en attente de revue TVA.'
    );
  END IF;

  PERFORM set_config('jolene.tva_mission_managed', 'true', true);
  UPDATE public.missions
  SET
    nature_tva_prestation = p_nature_tva_prestation,
    nature_tva_declaree_par = v_uid,
    nature_tva_declaree_le = now(),
    nature_tva_confirmee_soignant = NULL,
    nature_tva_confirmee_par = NULL,
    nature_tva_confirmee_le = NULL,
    statut_validation_tva = 'A_CONFIRMER',
    revue_tva_motif = btrim(p_motif),
    revue_tva_resolue_par = v_uid,
    revue_tva_resolue_le = now()
  WHERE id = p_mission_id;

  INSERT INTO public.notifications (
    destinataire_id, type_destinataire, type, titre, corps, lien,
    type_ressource, id_ressource
  ) VALUES
  (
    v_mission.soignant_assigne_id,
    'SOIGNANT',
    'SYSTEM',
    'Confirmation TVA à renouveler',
    'Jolene a examiné la divergence TVA de votre mission. Confirmez la proposition avant la facturation.',
    '/soignant/missions/' || p_mission_id,
    'mission',
    p_mission_id
  ),
  (
    v_mission.etablissement_id,
    'ETABLISSEMENT',
    'SYSTEM',
    'Revue TVA traitée',
    'Jolene a proposé une nature TVA. Le soignant doit maintenant la confirmer ; la mission reste active.',
    '/etablissement/missions/' || p_mission_id,
    'mission',
    p_mission_id
  );

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'ADMIN',
    p_action := 'FACTURATION',
    p_type_ressource := 'mission',
    p_id_ressource := p_mission_id,
    p_details := jsonb_build_object(
      'event', 'REVUE_NATURE_TVA_MISSION_PROPOSEE',
      'ancienne_nature_etablissement', v_mission.nature_tva_prestation,
      'position_soignant', v_mission.nature_tva_confirmee_soignant,
      'nature_proposee', p_nature_tva_prestation,
      'motif', btrim(p_motif),
      'confirmation_soignant_requise', true
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'statut_validation_tva', 'A_CONFIRMER',
    'confirmation_soignant_requise', true
  );
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_admin_proposer_nature_tva_mission(uuid, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_proposer_nature_tva_mission(uuid, text, text)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Seuil exact de sept jours et stratégie figée à l'assignation
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_strategie_facturation_pour_periode(
  p_debut timestamptz,
  p_fin timestamptz
)
RETURNS public.strategie_facturation
LANGUAGE sql
IMMUTABLE
STRICT
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $body$
  SELECT CASE
    WHEN p_fin > p_debut + interval '7 days'
      THEN 'HEBDO_ET_FINALE'::public.strategie_facturation
    ELSE 'FINALE_UNIQUE'::public.strategie_facturation
  END;
$body$;

CREATE OR REPLACE FUNCTION public.fn_corriger_strategie_facturation_assignation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $body$
DECLARE
  v_attendue public.strategie_facturation;
BEGIN
  IF OLD.statut = 'OUVERTE' AND NEW.statut = 'ASSIGNEE' THEN
    v_attendue := public.fn_strategie_facturation_pour_periode(NEW.debut_le, NEW.fin_le);
    IF NEW.strategie_facturation IS DISTINCT FROM v_attendue THEN
      NEW.strategie_facturation := v_attendue;
      PERFORM public.fn_ecrire_audit_safe(
        p_acteur_id := auth.uid(),
        p_type_acteur := 'SYSTEME',
        p_action := 'FACTURATION',
        p_type_ressource := 'mission',
        p_id_ressource := NEW.id,
        p_details := jsonb_build_object(
          'event', 'STRATEGIE_FACTURATION_CORRIGEE_A_ASSIGNATION',
          'strategie', v_attendue,
          'debut_le', NEW.debut_le,
          'fin_le', NEW.fin_le
        )
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$body$;

DROP TRIGGER IF EXISTS trg_zzz_corriger_strategie_facturation ON public.missions;
CREATE TRIGGER trg_zzz_corriger_strategie_facturation
BEFORE UPDATE OF statut ON public.missions
FOR EACH ROW EXECUTE FUNCTION public.fn_corriger_strategie_facturation_assignation();

-- ---------------------------------------------------------------------------
-- 5. Une seule facture principale par période, sans bloquer les corrections
-- ---------------------------------------------------------------------------

-- Les documents de correction sont liés à l'original et restent uniques par
-- litige. Une facture complémentaire ne remplace pas l'original payé : elle
-- facture uniquement le delta positif. Un avoir porte le delta négatif.
CREATE UNIQUE INDEX IF NOT EXISTS uniq_fh_correction_active_par_litige
  ON public.factures_honoraires (facture_precedente_id, litige_id, nature_correction)
  WHERE nature_correction IN ('REMPLACEMENT', 'COMPLEMENT', 'AVOIR')
    AND statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION');

ALTER TABLE public.factures DROP CONSTRAINT IF EXISTS factures_statut_check;
ALTER TABLE public.factures ADD CONSTRAINT factures_statut_check CHECK (
  statut IN (
    'BROUILLON', 'EMISE', 'VIREMENT_DECLARE', 'PAYEE', 'EN_RETARD',
    'ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION'
  )
);

DROP INDEX IF EXISTS public.uniq_fh_mission_semaine_active;
CREATE UNIQUE INDEX uniq_fh_mission_semaine_active
  ON public.factures_honoraires (
    mission_id, annee_iso, numero_semaine_iso, type_document
  )
  WHERE est_facture_finale_mission IS FALSE
    AND type_document = 'FACTURE'
    AND nature_correction <> 'COMPLEMENT'
    AND statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION');

CREATE UNIQUE INDEX IF NOT EXISTS uniq_fh_mission_finale_active
  ON public.factures_honoraires (mission_id)
  WHERE est_facture_finale_mission IS TRUE
    AND type_document = 'FACTURE'
    AND nature_correction <> 'COMPLEMENT'
    AND mission_id IS NOT NULL
    AND statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION');

CREATE OR REPLACE FUNCTION public.fn_verrouiller_periode_facture_honoraires()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $body$
DECLARE
  v_origine public.factures_honoraires%ROWTYPE;
BEGIN
  IF NEW.mission_id IS NULL
     OR NEW.type_document <> 'FACTURE'
     OR NEW.statut IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION') THEN
    RETURN NEW;
  END IF;
  IF NEW.periode_debut IS NULL OR NEW.periode_fin IS NULL OR NEW.periode_fin < NEW.periode_debut THEN
    RAISE EXCEPTION 'La période de facturation est invalide.'
      USING ERRCODE = 'check_violation';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(NEW.mission_id::text, 8194)
  );

  -- Les corrections comptables sont volontairement admises sur la même
  -- période. Elles doivent cependant pointer vers une facture exacte de la
  -- même mission, des mêmes parties et de la même période.
  IF NEW.nature_correction = 'COMPLEMENT' THEN
    SELECT * INTO v_origine
    FROM public.factures_honoraires
    WHERE id = NEW.facture_precedente_id
    FOR SHARE;

    IF NOT FOUND
       OR v_origine.type_document <> 'FACTURE'
       OR v_origine.statut NOT IN ('PAYEE', 'FACTORISEE')
       OR v_origine.mission_id IS DISTINCT FROM NEW.mission_id
       OR v_origine.soignant_id IS DISTINCT FROM NEW.soignant_id
       OR v_origine.etablissement_id IS DISTINCT FROM NEW.etablissement_id
       OR v_origine.periode_debut IS DISTINCT FROM NEW.periode_debut
       OR v_origine.periode_fin IS DISTINCT FROM NEW.periode_fin THEN
      RAISE EXCEPTION 'La facture complémentaire doit corriger une facture payée exacte de la même mission et période.'
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.factures_honoraires fh
    WHERE fh.mission_id = NEW.mission_id
      AND fh.id <> NEW.id
      AND fh.type_document = 'FACTURE'
      AND fh.nature_correction <> 'COMPLEMENT'
      AND fh.statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
      AND daterange(fh.periode_debut, fh.periode_fin, '[]')
          && daterange(NEW.periode_debut, NEW.periode_fin, '[]')
  ) THEN
    RAISE EXCEPTION 'Une facture active couvre déjà tout ou partie de cette période pour cette mission.'
      USING ERRCODE = 'exclusion_violation';
  END IF;
  RETURN NEW;
END;
$body$;

DROP TRIGGER IF EXISTS trg_verrouiller_periode_facture_honoraires
  ON public.factures_honoraires;
CREATE TRIGGER trg_verrouiller_periode_facture_honoraires
BEFORE INSERT OR UPDATE OF mission_id, periode_debut, periode_fin, statut, type_document, nature_correction, facture_precedente_id
ON public.factures_honoraires
FOR EACH ROW EXECUTE FUNCTION public.fn_verrouiller_periode_facture_honoraires();

-- Solde économique courant d'une pièce et de toute sa chaîne de corrections.
-- Une nouvelle décision ne doit jamais recalculer son delta depuis le document
-- d'origine en ignorant un complément ou un avoir déjà émis.
CREATE OR REPLACE FUNCTION public.fn_solde_correction_facture_honoraires(
  p_facture_id uuid
)
RETURNS TABLE (
  montant_ht numeric,
  montant_tva numeric,
  montant_ttc numeric
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $body$
  WITH RECURSIVE chaine AS (
    SELECT
      fh.id,
      fh.type_document,
      fh.montant_ht,
      fh.montant_tva,
      fh.montant_ttc,
      ARRAY[fh.id]::uuid[] AS chemin
    FROM public.factures_honoraires fh
    WHERE fh.id = p_facture_id

    UNION ALL

    SELECT
      enfant.id,
      enfant.type_document,
      enfant.montant_ht,
      enfant.montant_tva,
      enfant.montant_ttc,
      parent.chemin || enfant.id
    FROM chaine parent
    JOIN public.factures_honoraires enfant
      ON enfant.facture_precedente_id = parent.id
    WHERE enfant.statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
      AND enfant.id <> ALL(parent.chemin)
  )
  SELECT
    round(COALESCE(sum(CASE WHEN type_document = 'AVOIR' THEN -montant_ht ELSE montant_ht END), 0), 2),
    round(COALESCE(sum(CASE WHEN type_document = 'AVOIR' THEN -montant_tva ELSE montant_tva END), 0), 2),
    round(COALESCE(sum(CASE WHEN type_document = 'AVOIR' THEN -montant_ttc ELSE montant_ttc END), 0), 2)
  FROM chaine;
$body$;

REVOKE ALL ON FUNCTION public.fn_solde_correction_facture_honoraires(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_solde_correction_facture_honoraires(uuid)
  TO service_role;

-- La résolution historique était mission-scopée : le paiement d'une autre
-- semaine pouvait empêcher de corriger la facture ciblée. Elle dérivait aussi
-- heures/taux de la dernière présence et du taux courant de la mission. On
-- corrige chirurgicalement la fonction existante afin de préserver toutes ses
-- autres garanties transactionnelles déjà auditées.
DO $patch_resolution_facture_exacte$
DECLARE
  v_definition text;
  v_old_cumulative_variables text := $fragment$
  v_diff_ttc numeric;
  v_payload jsonb;$fragment$;
  v_new_cumulative_variables text := $fragment$
  v_diff_ttc numeric;
  v_total_courant_ht numeric;
  v_total_courant_tva numeric;
  v_total_courant_ttc numeric;
  v_payload jsonb;$fragment$;
  v_old_cumulative_load text := $fragment$
  -- Le verrou SQL couvre aussi la tentative Connect locale. Une Checkout
  -- Session ne peut pas être expirée de façon atomique en PostgreSQL : tant
  -- que son état n'est pas explicitement ECHOUE/ANNULEE/REMBOURSE, on refuse
  -- de remplacer le document qui a servi à calculer son montant.$fragment$;
  v_new_cumulative_load text := $fragment$
  IF v_facture_trouvee THEN
    SELECT solde.montant_ht, solde.montant_tva, solde.montant_ttc
      INTO v_total_courant_ht, v_total_courant_tva, v_total_courant_ttc
      FROM public.fn_solde_correction_facture_honoraires(v_facture.id) solde;
    IF v_total_courant_ht <= 0 OR v_total_courant_ttc <= 0 THEN
      RETURN jsonb_build_object(
        'error', 'Le solde cumulé de la chaîne de corrections est incohérent.'
      );
    END IF;
  END IF;

  -- Le verrou SQL couvre aussi la tentative Connect locale. Une Checkout
  -- Session ne peut pas être expirée de façon atomique en PostgreSQL : tant
  -- que son état n'est pas explicitement ECHOUE/ANNULEE/REMBOURSE, on refuse
  -- de remplacer le document qui a servi à calculer son montant.$fragment$;
  v_old_transfer text := $fragment$
  SELECT st.*
    INTO v_transfer
    FROM public.stripe_transfers st
   WHERE st.mission_id = v_litige.mission_id
   ORDER BY st.cree_le DESC, st.id
   LIMIT 1
   FOR UPDATE;$fragment$;
  v_new_transfer text := $fragment$
  SELECT st.*
    INTO v_transfer
    FROM public.stripe_transfers st
   WHERE st.mission_id = v_litige.mission_id
     AND (
       (v_litige.facture_id IS NOT NULL
         AND st.facture_honoraire_id = v_litige.facture_id)
       OR (v_litige.facture_id IS NULL
         AND st.facture_honoraire_id IS NULL)
     )
   ORDER BY st.cree_le DESC, st.id
   LIMIT 1
   FOR UPDATE;$fragment$;
  v_old_reference text := $fragment$
  IF v_presence_trouvee THEN
    v_heures_ref := COALESCE(
      v_presence.heures_ajustees_litige,
      v_presence.heures_reelles
    );
  END IF;
  v_taux_ref := v_mission.taux_horaire_base;
  IF v_facture_trouvee AND (v_taux_ref IS NULL OR v_taux_ref = 0) THEN
    v_taux_ref := CASE
      WHEN v_heures_ref > 0 THEN v_facture.montant_ht / v_heures_ref
      ELSE NULL
    END;
  END IF;
  IF v_facture_trouvee AND v_heures_ref IS NULL AND v_taux_ref > 0 THEN
    v_heures_ref := v_facture.montant_ht / v_taux_ref;
  END IF;$fragment$;
  v_new_reference text := $fragment$
  IF v_presence_trouvee THEN
    v_heures_ref := COALESCE(
      v_presence.heures_ajustees_litige,
      v_presence.heures_reelles
    );
  END IF;
  IF v_facture_trouvee THEN
    v_heures_ref := COALESCE(
      v_facture.quantite_heures_snapshot,
      v_heures_ref
    );
    v_taux_ref := COALESCE(
      v_facture.taux_horaire_snapshot,
      v_mission.taux_horaire_base
    );
  ELSE
    v_taux_ref := v_mission.taux_horaire_base;
  END IF;
  IF v_facture_trouvee AND (v_taux_ref IS NULL OR v_taux_ref = 0) THEN
    v_taux_ref := CASE
      WHEN v_heures_ref > 0 THEN v_facture.montant_ht / v_heures_ref
      ELSE NULL
    END;
  END IF;
  IF v_facture_trouvee AND v_heures_ref IS NULL AND v_taux_ref > 0 THEN
    v_heures_ref := v_facture.montant_ht / v_taux_ref;
  END IF;$fragment$;
  v_old_paid_auto text := $fragment$
    ELSIF v_facture.statut = 'PAYEE' THEN
      v_action := 'AVOIR';$fragment$;
  v_new_paid_auto text := $fragment$
    ELSIF v_facture.statut IN ('PAYEE', 'FACTORISEE') THEN
      v_action := CASE
        WHEN v_nouveau_montant_ttc IS NOT DISTINCT FROM v_total_courant_ttc
          THEN 'AUCUNE'
        ELSE 'AVOIR'
      END;$fragment$;
  v_old_ajustement_aucune text := $fragment$
  IF v_action = 'AUCUNE' AND v_ajustement_demande THEN
    RETURN jsonb_build_object(
      'error', 'AUCUNE est interdite lorsqu’un ajustement ou un accord financier existe.'
    );
  END IF;$fragment$;
  v_new_ajustement_aucune text := $fragment$
  IF v_action = 'AUCUNE' AND v_ajustement_demande
     AND (
       v_facture_trouvee IS NOT TRUE
       OR v_facture.statut NOT IN ('PAYEE', 'FACTORISEE')
       OR v_nouveau_montant_ttc IS DISTINCT FROM v_total_courant_ttc
     ) THEN
    RETURN jsonb_build_object(
      'error', 'Une correction sans pièce financière est réservée à une facture payée dont le total reste strictement identique.'
    );
  END IF;$fragment$;
  v_old_unchanged_total text := $fragment$
  IF v_action <> 'AUCUNE'
     AND v_nouveau_montant_ttc IS NOT DISTINCT FROM v_facture.montant_ttc THEN
    RETURN jsonb_build_object(
      'error', 'L’ajustement ne change pas le montant de la facture.'
    );
  END IF;$fragment$;
  v_new_unchanged_total text := $fragment$
  IF v_action <> 'AUCUNE'
     AND v_nouveau_montant_ttc IS NOT DISTINCT FROM v_total_courant_ttc THEN
    RETURN jsonb_build_object(
      'error', 'L’ajustement ne change pas le solde cumulé de la facture et de ses corrections.'
    );
  END IF;$fragment$;
  v_old_single_credit text := $fragment$
  IF v_action = 'AVOIR' AND EXISTS (
    SELECT 1
      FROM public.factures_honoraires enfant
     WHERE enfant.facture_precedente_id = v_facture.id
       AND enfant.type_document = 'AVOIR'
       AND enfant.statut NOT IN (
         'ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION'
       )
  ) THEN
    RETURN jsonb_build_object('error', 'Un avoir actif existe déjà pour cette facture.');
  END IF;$fragment$;
  v_new_single_credit text := $fragment$
  -- Plusieurs avoirs sont admis lorsqu'ils correspondent à des litiges
  -- distincts. Le montant de chacun est calculé sur le solde cumulé restant.$fragment$;
  v_old_credit_delta text := $fragment$
    v_diff := round(v_facture.montant_ht - v_nouveau_montant_ht, 2);
    v_diff_tva := round(v_facture.montant_tva - v_nouveau_montant_tva, 2);
    v_diff_ttc := round(v_facture.montant_ttc - v_nouveau_montant_ttc, 2);
    IF v_diff <= 0 OR v_diff_tva < 0 OR v_diff_ttc <= 0
       OR v_diff_ttc > v_facture.montant_ttc THEN$fragment$;
  v_new_credit_delta text := $fragment$
    v_diff := round(v_total_courant_ht - v_nouveau_montant_ht, 2);
    v_diff_tva := round(v_total_courant_tva - v_nouveau_montant_tva, 2);
    v_diff_ttc := round(v_total_courant_ttc - v_nouveau_montant_ttc, 2);
    IF v_diff <= 0 OR v_diff_tva < 0 OR v_diff_ttc <= 0
       OR v_diff_ttc > v_total_courant_ttc THEN$fragment$;
  v_old_refund_source text := $fragment$
    IF v_transfer_trouve THEN
      -- Un remboursement Connect doit aussi reprendre le transfer et la
      -- commission. La queue legacy ne sait pas garantir cette atomicité.
      v_mode_remboursement := 'VIREMENT_MANUEL';
    ELSIF v_facture.stripe_payment_intent_id IS NOT NULL$fragment$;
  v_new_refund_source text := $fragment$
    IF v_transfer_trouve OR EXISTS (
      SELECT 1
      FROM public.paiements_escrow pe
      WHERE pe.mission_id = v_litige.mission_id
        AND pe.statut IN (
          'DEBITE', 'DISPONIBLE', 'RELEASE_PLANIFIE', 'PAYE',
          'REMBOURSE_EN_COURS', 'REMBOURSE', 'DISPUTE'
        )
    ) OR EXISTS (
      SELECT 1
      FROM public.factor_advances fa
      WHERE fa.facture_honoraire_id = v_facture.id
        AND fa.statut IN ('APPROUVEE', 'FINANCEE', 'RECOUVREE', 'IMPAYEE')
    ) THEN
      -- Un remboursement Connect ou paiement rapide doit aussi reprendre la
      -- destination et la commission. La queue d'avoir standard ne sait pas
      -- garantir cette atomicité : la correction reste émise, le remboursement
      -- est placé en vérification financière explicite.
      v_mode_remboursement := 'VIREMENT_MANUEL';
    ELSIF v_facture.stripe_payment_intent_id IS NOT NULL$fragment$;
  v_old_avoir_emission text := $fragment$
      CURRENT_DATE, CURRENT_DATE, 'EMISE', v_facture.mandat_version,$fragment$;
  v_new_avoir_emission text := $fragment$
      CURRENT_DATE, CURRENT_DATE, 'EN_GENERATION', v_facture.mandat_version,$fragment$;
  v_old_refund_queue text := $fragment$
    IF v_mode_remboursement = 'AUTO_STRIPE' THEN
      INSERT INTO public.stripe_refunds_queue (
        avoir_id, facture_origine_id, stripe_payment_intent_id, montant_cts
      ) VALUES (
        v_avoir_id, v_facture.id, v_facture.stripe_payment_intent_id,
        round(v_diff_ttc * 100)::integer
      );
      GET DIAGNOSTICS v_rows = ROW_COUNT;
      IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Remboursement Stripe non mis en file';
      END IF;
    END IF;$fragment$;
  v_new_refund_queue text := $fragment$
    -- La file Stripe est alimentée atomiquement par
    -- fn_emettre_document_facturation_honoraires, seulement après dépôt du PDF
    -- et du XML CII. Aucun remboursement ne peut précéder son avoir émis.$fragment$;
  v_old_avoir_origin_status text := $fragment$
     WHERE id = v_facture.id
       AND statut = 'PAYEE';$fragment$;
  v_new_avoir_origin_status text := $fragment$
     WHERE id = v_facture.id
       AND statut IN ('PAYEE', 'FACTORISEE');$fragment$;
  v_old_admin_override_gel text := $fragment$
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission du litige introuvable.');
  END IF;

  IF v_litige.presence_id IS NOT NULL THEN$fragment$;
  v_new_admin_override_gel text := $fragment$
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission du litige introuvable.');
  END IF;

  -- Le gel contractuel continue de bloquer toute édition ordinaire après
  -- assignation. Cette dérogation transactionnelle, bornée à la mission et à
  -- un litige identifié, permet au résolveur admin de corriger le taux tout en
  -- laissant fn_geler_mission_a_assignation produire son audit détaillé.
  PERFORM set_config(
    'jolene.admin_override_gel', v_mission.id::text, true
  );
  PERFORM set_config(
    'jolene.admin_override_reason',
    'Résolution du litige ' || p_litige_id::text || ' : '
      || left(btrim(p_resolution), 500),
    true
  );

  IF v_litige.presence_id IS NOT NULL THEN$fragment$;
BEGIN
  v_definition := pg_get_functiondef(
    'public.fn_admin_resoudre_litige(uuid,text,text,numeric,numeric,text)'::regprocedure
  );
  IF strpos(v_definition, v_old_transfer) = 0
     OR strpos(v_definition, v_old_cumulative_variables) = 0
     OR strpos(v_definition, v_old_cumulative_load) = 0
     OR strpos(v_definition, v_old_reference) = 0
     OR strpos(v_definition, v_old_paid_auto) = 0
     OR strpos(v_definition, v_old_ajustement_aucune) = 0
     OR strpos(v_definition, v_old_unchanged_total) = 0
     OR strpos(v_definition, v_old_single_credit) = 0
     OR strpos(v_definition, v_old_credit_delta) = 0
     OR strpos(v_definition, v_old_refund_source) = 0
     OR strpos(v_definition, v_old_avoir_emission) = 0
     OR strpos(v_definition, v_old_refund_queue) = 0
     OR strpos(v_definition, v_old_avoir_origin_status) = 0
     OR strpos(v_definition, v_old_admin_override_gel) = 0 THEN
    RAISE EXCEPTION 'Le résolveur de litige a dérivé : correctif facture-scopé non appliqué';
  END IF;
  v_definition := replace(v_definition, v_old_cumulative_variables, v_new_cumulative_variables);
  v_definition := replace(v_definition, v_old_cumulative_load, v_new_cumulative_load);
  v_definition := replace(v_definition, v_old_transfer, v_new_transfer);
  v_definition := replace(v_definition, v_old_reference, v_new_reference);
  v_definition := replace(v_definition, v_old_paid_auto, v_new_paid_auto);
  v_definition := replace(v_definition, v_old_ajustement_aucune, v_new_ajustement_aucune);
  v_definition := replace(v_definition, v_old_unchanged_total, v_new_unchanged_total);
  v_definition := replace(v_definition, v_old_single_credit, v_new_single_credit);
  v_definition := replace(v_definition, v_old_credit_delta, v_new_credit_delta);
  v_definition := replace(v_definition, v_old_refund_source, v_new_refund_source);
  v_definition := replace(v_definition, v_old_avoir_emission, v_new_avoir_emission);
  v_definition := replace(v_definition, v_old_refund_queue, v_new_refund_queue);
  v_definition := replace(v_definition, v_old_avoir_origin_status, v_new_avoir_origin_status);
  v_definition := replace(v_definition, v_old_admin_override_gel, v_new_admin_override_gel);
  EXECUTE v_definition;
END;
$patch_resolution_facture_exacte$;

-- Cas manquant du flux historique : une facture déjà payée corrigée à la
-- hausse ne doit ni être modifiée, ni donner lieu à un avoir. On émet une
-- facture complémentaire pour le delta positif uniquement. Le flux historique
-- continue de gérer le delta négatif par avoir.
CREATE OR REPLACE FUNCTION public.fn_admin_resoudre_litige_complement_honoraires(
  p_litige_id uuid,
  p_resolution text,
  p_en_faveur_de text DEFAULT NULL,
  p_ajuster_heures numeric DEFAULT NULL,
  p_ajuster_taux numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_litige public.litiges%ROWTYPE;
  v_mission public.missions%ROWTYPE;
  v_presence public.presences%ROWTYPE;
  v_facture public.factures_honoraires%ROWTYPE;
  v_payload jsonb;
  v_modifications jsonb;
  v_type_payload text;
  v_arrivee timestamptz;
  v_depart timestamptz;
  v_heures_payload numeric;
  v_heures_final numeric;
  v_taux_final numeric;
  v_montant_payload_ttc numeric;
  v_nouveau_ht numeric;
  v_nouvelle_tva numeric;
  v_nouveau_ttc numeric;
  v_total_courant_ht numeric;
  v_total_courant_tva numeric;
  v_total_courant_ttc numeric;
  v_delta_ht numeric;
  v_delta_tva numeric;
  v_delta_ttc numeric;
  v_numero text;
  v_complement_id uuid;
  v_regen_id bigint;
  v_statut_resolution text;
  v_rows integer;
BEGIN
  IF v_uid IS NULL OR public.est_admin() IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin AAL2 requis.');
  END IF;
  IF length(btrim(COALESCE(p_resolution, ''))) NOT BETWEEN 10 AND 5000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'La résolution doit contenir entre 10 et 5 000 caractères.');
  END IF;
  IF upper(btrim(COALESCE(p_en_faveur_de, 'NEUTRE'))) NOT IN ('SOIGNANT', 'ETABLISSEMENT', 'NEUTRE') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Bénéficiaire de la décision invalide.');
  END IF;
  IF p_ajuster_heures IS NOT NULL AND (p_ajuster_heures <= 0 OR p_ajuster_heures > 168) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Les heures corrigées doivent être comprises entre 0 et 168.');
  END IF;
  IF p_ajuster_taux IS NOT NULL AND (p_ajuster_taux < 0.01 OR p_ajuster_taux > 1000) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Le taux corrigé doit être compris entre 0,01 € et 1 000 €.');
  END IF;

  SELECT * INTO v_litige
  FROM public.litiges
  WHERE id = p_litige_id
  FOR UPDATE;
  IF NOT FOUND OR v_litige.statut NOT IN (
    'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS', 'REVUE_ADMIN'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable ou déjà résolu.');
  END IF;

  v_payload := v_litige.payload_modifications;
  IF v_payload IS NOT NULL THEN
    IF v_litige.statut <> 'REVUE_ADMIN'
       OR v_litige.accord_soignant IS NOT TRUE
       OR v_litige.accord_etablissement IS NOT TRUE
       OR v_litige.accord_soignant_le IS NULL
       OR v_litige.accord_etablissement_le IS NULL
       OR v_litige.modifications_executees IS TRUE THEN
      RETURN jsonb_build_object('success', false, 'error', 'L’accord financier doit être accepté par les deux parties et non encore exécuté.');
    END IF;
    v_type_payload := v_payload->>'type';
    v_modifications := v_payload->'modifications';
    IF v_type_payload NOT IN ('MODIFICATION_HORAIRES', 'MODIFICATION_MONTANT', 'MIXTE')
       OR jsonb_typeof(v_modifications) IS DISTINCT FROM 'object' THEN
      RETURN jsonb_build_object('success', false, 'error', 'Le contenu de l’accord financier est invalide.');
    END IF;
    IF v_type_payload IN ('MODIFICATION_MONTANT', 'MIXTE')
       AND jsonb_typeof(v_modifications->'montant_total_corrige') = 'number' THEN
      v_montant_payload_ttc := (v_modifications->>'montant_total_corrige')::numeric;
    END IF;
    IF v_type_payload IN ('MODIFICATION_HORAIRES', 'MIXTE') THEN
      BEGIN
        v_arrivee := (v_modifications->>'pointage_arrivee_le')::timestamptz;
        v_depart := (v_modifications->>'pointage_depart_le')::timestamptz;
      EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
        RETURN jsonb_build_object('success', false, 'error', 'Les horaires convenus sont invalides.');
      END;
      IF v_depart <= v_arrivee OR v_depart - v_arrivee > interval '7 days' THEN
        RETURN jsonb_build_object('success', false, 'error', 'La plage horaire convenue est invalide.');
      END IF;
    END IF;
  END IF;

  SELECT * INTO v_mission
  FROM public.missions
  WHERE id = v_litige.mission_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable.');
  END IF;

  -- Même garde que dans le résolveur historique : le changement de taux est
  -- une dérogation de litige explicite et auditée, jamais un dégel général de
  -- la mission ni un contournement des pièces comptables déjà émises.
  PERFORM set_config(
    'jolene.admin_override_gel', v_mission.id::text, true
  );
  PERFORM set_config(
    'jolene.admin_override_reason',
    'Résolution du litige ' || p_litige_id::text || ' : '
      || left(btrim(p_resolution), 500),
    true
  );

  IF v_litige.presence_id IS NOT NULL THEN
    SELECT * INTO v_presence
    FROM public.presences
    WHERE id = v_litige.presence_id AND mission_id = v_litige.mission_id
    FOR UPDATE;
  ELSE
    SELECT * INTO v_presence
    FROM public.presences
    WHERE mission_id = v_litige.mission_id
    ORDER BY valide_le DESC NULLS LAST, cree_le DESC
    LIMIT 1
    FOR UPDATE;
  END IF;

  IF v_arrivee IS NOT NULL AND v_depart IS NOT NULL THEN
    v_heures_payload := round(GREATEST(
      0,
      extract(epoch FROM (v_depart - v_arrivee)) / 3600
        - COALESCE(v_presence.duree_pause_min, 0) / 60
    )::numeric, 2);
  END IF;
  v_heures_final := COALESCE(
    p_ajuster_heures,
    v_heures_payload,
    v_presence.heures_ajustees_litige,
    v_presence.heures_reelles
  );

  SELECT * INTO v_facture
  FROM public.factures_honoraires
  WHERE id = v_litige.facture_id
    AND mission_id = v_litige.mission_id
    AND soignant_id = v_litige.soignant_id
    AND etablissement_id = v_litige.etablissement_id
    AND type_document = 'FACTURE'
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'COMPLEMENT_NON_APPLICABLE',
      'error', 'La facture exacte à corriger est introuvable.'
    );
  END IF;
  IF v_facture.statut NOT IN ('PAYEE', 'FACTORISEE') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'COMPLEMENT_NON_APPLICABLE',
      'error', 'La facture n’est ni payée ni avancée : le remplacement comptable standard doit être utilisé.'
    );
  END IF;

  SELECT solde.montant_ht, solde.montant_tva, solde.montant_ttc
    INTO v_total_courant_ht, v_total_courant_tva, v_total_courant_ttc
    FROM public.fn_solde_correction_facture_honoraires(v_facture.id) solde;
  IF v_total_courant_ht <= 0 OR v_total_courant_ttc <= 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Le solde cumulé de la chaîne de corrections est incohérent.'
    );
  END IF;

  v_heures_final := CASE
    WHEN p_ajuster_heures IS NOT NULL OR v_heures_payload IS NOT NULL
      THEN COALESCE(p_ajuster_heures, v_heures_payload)
    ELSE COALESCE(
      v_facture.quantite_heures_snapshot,
      v_presence.heures_ajustees_litige,
      v_presence.heures_reelles
    )
  END;

  v_taux_final := COALESCE(
    p_ajuster_taux,
    v_facture.taux_horaire_snapshot,
    v_mission.taux_horaire_base,
    CASE WHEN v_heures_final > 0 THEN v_facture.montant_ht / v_heures_final END
  );
  IF v_montant_payload_ttc IS NOT NULL
     AND p_ajuster_heures IS NULL
     AND p_ajuster_taux IS NULL THEN
    v_nouveau_ttc := round(v_montant_payload_ttc, 2);
    v_nouveau_ht := round(v_nouveau_ttc / (1 + COALESCE(v_facture.taux_tva, 0) / 100), 2);
    v_nouvelle_tva := v_nouveau_ttc - v_nouveau_ht;
  ELSE
    IF v_heures_final IS NULL OR v_heures_final <= 0
       OR v_taux_final IS NULL OR v_taux_final <= 0 THEN
      RETURN jsonb_build_object('success', false, 'error', 'Heures ou taux corrigés manquants.');
    END IF;
    v_nouveau_ht := round(v_heures_final * v_taux_final, 2);
    v_nouvelle_tva := round(v_nouveau_ht * COALESCE(v_facture.taux_tva, 0) / 100, 2);
    v_nouveau_ttc := v_nouveau_ht + v_nouvelle_tva;
  END IF;

  IF v_nouveau_ttc <= v_total_courant_ttc THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'COMPLEMENT_NON_APPLICABLE',
      'error', 'La correction n’est pas une hausse : un avoir ou une rectification standard doit être utilisé.'
    );
  END IF;
  v_delta_ht := v_nouveau_ht - v_total_courant_ht;
  v_delta_tva := v_nouvelle_tva - v_total_courant_tva;
  v_delta_ttc := v_nouveau_ttc - v_total_courant_ttc;
  IF v_delta_ht <= 0 OR v_delta_tva < 0 OR v_delta_ttc <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Le delta de correction est incohérent.');
  END IF;

  v_numero := public.next_invoice_number(v_facture.soignant_id);
  IF NULLIF(btrim(v_numero), '') IS NULL THEN
    RAISE EXCEPTION 'Numéro de facture complémentaire invalide';
  END IF;
  INSERT INTO public.factures_honoraires (
    soignant_id, etablissement_id, mission_id, numero_facture,
    montant_ht, montant_tva, montant_ttc, taux_tva, exoneration_tva,
    date_emission, date_echeance, statut, mandat_version, type_document,
    facture_precedente_id, statut_litige, litige_id, pdf_a_regenerer,
    periode_debut, periode_fin, numero_semaine_iso, annee_iso,
    est_facture_finale_mission, nature_correction,
    regime_tva_snapshot, base_legale_tva_snapshot, nature_prestation_snapshot,
    description_prestation_snapshot, quantite_heures_snapshot,
    taux_horaire_snapshot, emetteur_identite_snapshot,
    emetteur_profession_snapshot, emetteur_siret_snapshot,
    emetteur_numero_professionnel_snapshot, emetteur_adresse_snapshot,
    emetteur_adresse_rue_snapshot, emetteur_adresse_code_postal_snapshot,
    emetteur_adresse_ville_snapshot, emetteur_email_snapshot,
    emetteur_numero_tva_snapshot, destinataire_nom_snapshot,
    destinataire_siret_snapshot, destinataire_adresse_rue_snapshot,
    destinataire_adresse_code_postal_snapshot,
    destinataire_adresse_ville_snapshot
  ) VALUES (
    v_facture.soignant_id, v_facture.etablissement_id, v_facture.mission_id,
    v_numero, v_delta_ht, v_delta_tva, v_delta_ttc,
    v_facture.taux_tva, v_facture.exoneration_tva,
    CURRENT_DATE, CURRENT_DATE + 30, 'EN_GENERATION',
    v_facture.mandat_version, 'FACTURE', v_facture.id,
    'LITIGE_RESOLU_AJUSTE', p_litige_id, true,
    v_facture.periode_debut, v_facture.periode_fin,
    v_facture.numero_semaine_iso, v_facture.annee_iso,
    v_facture.est_facture_finale_mission, 'COMPLEMENT',
    v_facture.regime_tva_snapshot, v_facture.base_legale_tva_snapshot,
    v_facture.nature_prestation_snapshot,
    'Complément après litige sur facture ' || v_facture.numero_facture
      || ' — total corrigé ' || v_nouveau_ttc || ' EUR TTC',
    NULL, v_taux_final, v_facture.emetteur_identite_snapshot,
    v_facture.emetteur_profession_snapshot, v_facture.emetteur_siret_snapshot,
    v_facture.emetteur_numero_professionnel_snapshot,
    v_facture.emetteur_adresse_snapshot,
    v_facture.emetteur_adresse_rue_snapshot,
    v_facture.emetteur_adresse_code_postal_snapshot,
    v_facture.emetteur_adresse_ville_snapshot,
    v_facture.emetteur_email_snapshot,
    v_facture.emetteur_numero_tva_snapshot,
    v_facture.destinataire_nom_snapshot,
    v_facture.destinataire_siret_snapshot,
    v_facture.destinataire_adresse_rue_snapshot,
    v_facture.destinataire_adresse_code_postal_snapshot,
    v_facture.destinataire_adresse_ville_snapshot
  ) RETURNING id INTO v_complement_id;

  UPDATE public.factures_honoraires
  SET statut_litige = 'LITIGE_RESOLU_AJUSTE'
  WHERE id = v_facture.id AND statut IN ('PAYEE', 'FACTORISEE');
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN RAISE EXCEPTION 'Correction concurrente refusée'; END IF;

  IF p_ajuster_heures IS NOT NULL OR v_heures_payload IS NOT NULL THEN
    UPDATE public.presences
    SET heures_ajustees_litige = v_heures_final,
        ajustement_litige_id = p_litige_id,
        motif_litige = left('Résolution admin : ' || btrim(p_resolution), 2000),
        modifie_le = now()
    WHERE id = v_presence.id;
  END IF;
  IF p_ajuster_taux IS NOT NULL THEN
    UPDATE public.missions
    SET taux_horaire_base = v_taux_final, modifie_le = now()
    WHERE id = v_mission.id;
  END IF;
  UPDATE public.missions
  SET commission_a_recalculer = true
  WHERE id = v_mission.id;

  v_statut_resolution := CASE upper(btrim(COALESCE(p_en_faveur_de, 'NEUTRE')))
    WHEN 'SOIGNANT' THEN 'RESOLU_SOIGNANT'
    WHEN 'ETABLISSEMENT' THEN 'RESOLU_ETABLISSEMENT'
    ELSE 'RESOLU_ADMIN'
  END;
  UPDATE public.litiges
  SET statut = v_statut_resolution,
      resolution = btrim(p_resolution),
      resolu_par = v_uid,
      resolu_le = now(),
      modifications_executees = CASE WHEN v_payload IS NOT NULL THEN true ELSE modifications_executees END,
      modifications_executees_a = CASE WHEN v_payload IS NOT NULL THEN now() ELSE modifications_executees_a END,
      modifications_executees_par = CASE WHEN v_payload IS NOT NULL THEN v_uid ELSE modifications_executees_par END
  WHERE id = p_litige_id
    AND statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS', 'REVUE_ADMIN');
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN RAISE EXCEPTION 'Résolution concurrente refusée'; END IF;

  v_regen_id := public.fn_trigger_regen_pdf_immediate(v_complement_id);
  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'LITIGE_RESOLUTION',
    p_type_ressource := 'litige',
    p_id_ressource := p_litige_id,
    p_details := jsonb_build_object(
      'evenement', 'FACTURE_COMPLEMENTAIRE_HONORAIRES',
      'facture_origine_id', v_facture.id,
      'facture_complementaire_id', v_complement_id,
      'montant_origine_ttc', v_facture.montant_ttc,
      'solde_cumule_avant_ttc', v_total_courant_ttc,
      'montant_corrige_ttc', v_nouveau_ttc,
      'delta_ttc', v_delta_ttc,
      'regen_pdf_request_id', v_regen_id
    )
  );
  PERFORM public.fn_litige_push_notification(
    v_litige.soignant_id, 'SOIGNANT', 'LITIGE_RESOLU_AJUSTE',
    'Litige résolu — complément d’honoraires',
    'Une facture complémentaire a été émise pour le seul montant ajouté.',
    p_litige_id,
    jsonb_build_object('facture_id', v_complement_id, 'montant_ttc', v_delta_ttc)
  );
  PERFORM public.fn_litige_push_notification(
    v_litige.etablissement_id, 'ETABLISSEMENT', 'LITIGE_RESOLU_AJUSTE',
    'Litige résolu — complément à régler',
    'La correction à la hausse génère une facture complémentaire distincte.',
    p_litige_id,
    jsonb_build_object('facture_id', v_complement_id, 'montant_ttc', v_delta_ttc)
  );

  RETURN jsonb_build_object(
    'success', true,
    'action_financiere', 'COMPLEMENT',
    'facture_id', v_facture.id,
    'nouvelle_facture_id', v_complement_id,
    'montant_final_ht', v_nouveau_ht,
    'montant_final_ttc', v_nouveau_ttc,
    'delta_ttc', v_delta_ttc,
    'regen_pdf_request_ids', jsonb_build_array(v_regen_id)
  );
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_admin_resoudre_litige_complement_honoraires(
  uuid, text, text, numeric, numeric
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_resoudre_litige_complement_honoraires(
  uuid, text, text, numeric, numeric
) TO authenticated, service_role;

-- Une facture payée peut nécessiter une correction des heures et du taux sans
-- que son total change (par exemple 10 h × 50 € devient 8 h × 62,50 €). Cette
-- correction ne génère ni nouvelle créance ni remboursement, mais elle ne doit
-- pas disparaître dans un simple audit : on conserve une rectification
-- descriptive immuable, rattachée à la facture et au litige exacts.
CREATE TABLE IF NOT EXISTS public.factures_honoraires_rectifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  facture_honoraire_id uuid NOT NULL
    REFERENCES public.factures_honoraires(id) ON DELETE RESTRICT,
  litige_id uuid NOT NULL REFERENCES public.litiges(id) ON DELETE RESTRICT,
  heures_avant numeric(8,2),
  taux_avant numeric(10,2),
  heures_apres numeric(8,2),
  taux_apres numeric(10,2),
  montant_ttc_inchange numeric(12,2) NOT NULL CHECK (montant_ttc_inchange > 0),
  resolution text NOT NULL CHECK (length(btrim(resolution)) BETWEEN 10 AND 5000),
  cree_par uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  cree_le timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT factures_honoraires_rectifications_litige_unique UNIQUE (litige_id),
  CONSTRAINT factures_honoraires_rectifications_difference_check CHECK (
    heures_avant IS DISTINCT FROM heures_apres
    OR taux_avant IS DISTINCT FROM taux_apres
  )
);

ALTER TABLE public.factures_honoraires_rectifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.factures_honoraires_rectifications
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.factures_honoraires_rectifications
  TO authenticated;
GRANT SELECT, INSERT ON TABLE public.factures_honoraires_rectifications
  TO service_role;

CREATE POLICY rectifications_facture_select_parties
ON public.factures_honoraires_rectifications
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.factures_honoraires fh
    WHERE fh.id = facture_honoraire_id
      AND (
        fh.soignant_id = auth.uid()
        OR (
          fh.etablissement_id = public.mon_etablissement_id()
          AND (
            public.fn_a_permission_etablissement('contrats', fh.etablissement_id) IS TRUE
            OR public.fn_a_permission_etablissement('lecture_paiement', fh.etablissement_id) IS TRUE
            OR public.fn_a_permission_etablissement('paiement', fh.etablissement_id) IS TRUE
          )
        )
        OR public.est_admin() IS TRUE
      )
  )
);

CREATE OR REPLACE FUNCTION public.fn_preserver_rectification_facture_honoraires()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $body$
BEGIN
  RAISE EXCEPTION 'Une rectification de facture est immuable et conservée pendant dix ans.'
    USING ERRCODE = '55000';
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_preserver_rectification_facture_honoraires()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_preserver_rectification_facture_honoraires()
  TO service_role;

DROP TRIGGER IF EXISTS trg_preserver_rectification_facture_honoraires
  ON public.factures_honoraires_rectifications;
CREATE TRIGGER trg_preserver_rectification_facture_honoraires
BEFORE UPDATE OR DELETE ON public.factures_honoraires_rectifications
FOR EACH ROW EXECUTE FUNCTION public.fn_preserver_rectification_facture_honoraires();

-- Lecture minimale pour le cockpit admin. Le helper comptable reste invisible
-- aux clients : cette enveloppe ne révèle que le solde de la facture exacte et
-- exige la garde admin AAL2 canonique avant de contourner les RLS.
CREATE OR REPLACE FUNCTION public.fn_admin_solde_correction_facture_honoraires(
  p_facture_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
SET row_security = off
AS $body$
DECLARE
  v_solde record;
  v_a_des_corrections boolean;
BEGIN
  IF auth.uid() IS NULL OR public.est_admin() IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Admin AAL2 requis.'
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.factures_honoraires fh
    WHERE fh.id = p_facture_id
      AND fh.type_document = 'FACTURE'
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Facture d’honoraires introuvable.'
    );
  END IF;

  SELECT solde.montant_ht, solde.montant_tva, solde.montant_ttc
    INTO v_solde
    FROM public.fn_solde_correction_facture_honoraires(p_facture_id) solde;

  SELECT EXISTS (
    SELECT 1
    FROM public.factures_honoraires enfant
    WHERE enfant.facture_precedente_id = p_facture_id
    UNION ALL
    SELECT 1
    FROM public.factures_honoraires_rectifications rectification
    WHERE rectification.facture_honoraire_id = p_facture_id
  ) INTO v_a_des_corrections;

  RETURN jsonb_build_object(
    'success', true,
    'facture_id', p_facture_id,
    'montant_ht', v_solde.montant_ht,
    'montant_tva', v_solde.montant_tva,
    'montant_ttc', v_solde.montant_ttc,
    'a_des_corrections', v_a_des_corrections
  );
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_admin_solde_correction_facture_honoraires(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_solde_correction_facture_honoraires(uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_admin_resoudre_litige_intelligent(
  p_litige_id uuid,
  p_resolution text,
  p_en_faveur_de text DEFAULT NULL,
  p_ajuster_heures numeric DEFAULT NULL,
  p_ajuster_taux numeric DEFAULT NULL,
  p_action_financiere text DEFAULT 'AUTO'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $body$
DECLARE
  v_action text := upper(btrim(COALESCE(p_action_financiere, 'AUTO')));
  v_result jsonb;
  v_action_resultat text;
  v_facture_cible_id uuid;
  v_rectification_id uuid;
  v_litige public.litiges%ROWTYPE;
  v_facture public.factures_honoraires%ROWTYPE;
  v_total_courant_ttc numeric;
  v_heures_apres numeric;
  v_taux_apres numeric;
  v_ajustement_demande boolean;
BEGIN
  IF v_action NOT IN ('AUTO', 'AUCUNE', 'RECALCUL', 'ANNULER_REEMETTRE', 'AVOIR', 'COMPLEMENT') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action financière invalide.');
  END IF;

  IF v_action IN ('AUTO', 'COMPLEMENT') THEN
    v_result := public.fn_admin_resoudre_litige_complement_honoraires(
      p_litige_id, p_resolution, p_en_faveur_de,
      p_ajuster_heures, p_ajuster_taux
    );
    IF COALESCE((v_result->>'success')::boolean, false) IS TRUE
       OR v_action = 'COMPLEMENT'
       OR COALESCE(v_result->>'error_code', '') <> 'COMPLEMENT_NON_APPLICABLE' THEN
      RETURN v_result;
    END IF;
  END IF;

  SELECT * INTO v_litige
  FROM public.litiges
  WHERE id = p_litige_id;
  v_ajustement_demande := p_ajuster_heures IS NOT NULL
    OR p_ajuster_taux IS NOT NULL
    OR v_litige.payload_modifications IS NOT NULL;

  v_result := public.fn_admin_resoudre_litige(
    p_litige_id,
    p_resolution,
    p_en_faveur_de,
    p_ajuster_heures,
    p_ajuster_taux,
    v_action
  );
  IF COALESCE((v_result->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN v_result;
  END IF;

  v_action_resultat := v_result->>'action_financiere';
  v_heures_apres := NULLIF(v_result->>'heures_final', '')::numeric;
  v_taux_apres := NULLIF(v_result->>'taux_final', '')::numeric;

  -- La file PDF est déclenchée dans le résolveur historique mais ne devient
  -- visible qu'après le commit. On complète donc les snapshots avant que le
  -- worker ne lise la facture rectificative.
  IF v_action_resultat IN ('RECALCUL', 'ANNULER_REEMETTRE') THEN
    v_facture_cible_id := CASE
      WHEN v_action_resultat = 'RECALCUL'
        THEN NULLIF(v_result->>'facture_id', '')::uuid
      ELSE NULLIF(v_result->>'nouvelle_facture_id', '')::uuid
    END;
    UPDATE public.factures_honoraires
    SET quantite_heures_snapshot = COALESCE(v_heures_apres, quantite_heures_snapshot),
        taux_horaire_snapshot = COALESCE(v_taux_apres, taux_horaire_snapshot),
        description_prestation_snapshot =
          'Rectification après litige — '
          || COALESCE(v_heures_apres::text, quantite_heures_snapshot::text, '—') || ' h × '
          || COALESCE(v_taux_apres::text, taux_horaire_snapshot::text, '—') || ' EUR/h',
        modifie_le = now()
    WHERE id = v_facture_cible_id;
  END IF;

  IF v_action_resultat = 'AUCUNE' AND v_ajustement_demande THEN
    SELECT * INTO v_facture
    FROM public.factures_honoraires
    WHERE id = NULLIF(v_result->>'facture_id', '')::uuid
      AND statut IN ('PAYEE', 'FACTORISEE')
    FOR UPDATE;
    IF FOUND THEN
      SELECT solde.montant_ttc
        INTO v_total_courant_ttc
        FROM public.fn_solde_correction_facture_honoraires(v_facture.id) solde;
    END IF;
    IF NOT FOUND
       OR NULLIF(v_result->>'montant_final_ttc', '')::numeric
          IS DISTINCT FROM v_total_courant_ttc THEN
      RAISE EXCEPTION 'Rectification descriptive incohérente';
    END IF;
    IF v_facture.quantite_heures_snapshot IS DISTINCT FROM v_heures_apres
       OR v_facture.taux_horaire_snapshot IS DISTINCT FROM v_taux_apres THEN
      INSERT INTO public.factures_honoraires_rectifications (
        facture_honoraire_id, litige_id, heures_avant, taux_avant,
        heures_apres, taux_apres, montant_ttc_inchange, resolution, cree_par
      ) VALUES (
        v_facture.id, p_litige_id,
        v_facture.quantite_heures_snapshot, v_facture.taux_horaire_snapshot,
        v_heures_apres, v_taux_apres, v_total_courant_ttc,
        btrim(p_resolution), auth.uid()
      ) RETURNING id INTO v_rectification_id;

      PERFORM public.fn_ecrire_audit_safe(
        p_acteur_id := auth.uid(),
        p_type_acteur := 'ADMIN_PLATEFORME',
        p_action := 'LITIGE_RESOLUTION',
        p_type_ressource := 'facture_honoraires_rectification',
        p_id_ressource := v_rectification_id,
        p_details := jsonb_build_object(
          'evenement', 'RECTIFICATION_DESCRIPTIVE_SANS_IMPACT_FINANCIER',
          'facture_id', v_facture.id,
          'litige_id', p_litige_id,
          'heures_avant', v_facture.quantite_heures_snapshot,
          'heures_apres', v_heures_apres,
          'taux_avant', v_facture.taux_horaire_snapshot,
          'taux_apres', v_taux_apres,
          'montant_ttc_inchange', v_total_courant_ttc
        )
      );
      PERFORM public.fn_litige_push_notification(
        v_litige.soignant_id, 'SOIGNANT', 'LITIGE_RESOLU_AJUSTE',
        'Litige résolu — détail de facture rectifié',
        'Les heures ou le taux ont été rectifiés sans changer le total déjà payé.',
        p_litige_id, jsonb_build_object('rectification_id', v_rectification_id)
      );
      PERFORM public.fn_litige_push_notification(
        v_litige.etablissement_id, 'ETABLISSEMENT', 'LITIGE_RESOLU_AJUSTE',
        'Litige résolu — détail de facture rectifié',
        'Les heures ou le taux ont été rectifiés sans changer le total déjà payé.',
        p_litige_id, jsonb_build_object('rectification_id', v_rectification_id)
      );
      v_result := v_result || jsonb_build_object(
        'action_financiere', 'RECTIFICATION_DESCRIPTIVE',
        'rectification_id', v_rectification_id
      );
    ELSE
      -- Un changement de pointage peut être légitime sans modifier ni les
      -- heures facturées ni le taux. Il est audité par le résolveur de litige,
      -- sans fabriquer un faux document comptable ni faire échouer le parcours.
      v_result := v_result || jsonb_build_object(
        'action_financiere', 'CORRECTION_PRESENCE_SANS_IMPACT_FACTURE'
      );
    END IF;
  END IF;

  RETURN v_result;
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_admin_resoudre_litige_intelligent(
  uuid, text, text, numeric, numeric, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_resoudre_litige_intelligent(
  uuid, text, text, numeric, numeric, text
) TO authenticated, service_role;

-- Variante facture-scopée utilisée par le cockpit de facturation. Sur une
-- mission longue, elle empêche qu'une contestation S1 corrige par erreur la
-- dernière facture S2/S3. La fonction historique à trois arguments reste
-- disponible pour les litiges non financiers et les anciens clients.
DROP INDEX IF EXISTS public.uq_litige_mission_type_ouvert;
CREATE UNIQUE INDEX uq_litige_mission_type_ouvert_legacy
  ON public.litiges (mission_id, type_litige)
  WHERE facture_id IS NULL
    AND statut IN (
      'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION',
      'MEDIATION_EN_COURS', 'REVUE_ADMIN'
    );
CREATE UNIQUE INDEX uq_litige_facture_type_ouvert
  ON public.litiges (facture_id, type_litige)
  WHERE facture_id IS NOT NULL
    AND statut IN (
      'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION',
      'MEDIATION_EN_COURS', 'REVUE_ADMIN'
    );

CREATE OR REPLACE FUNCTION public.fn_ouvrir_litige_rate_limited(
  p_mission_id uuid,
  p_type_litige public.type_litige,
  p_motif text,
  p_facture_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_mission public.missions%ROWTYPE;
  v_facture public.factures_honoraires%ROWTYPE;
  v_initie_par text;
  v_existing integer;
  v_recent integer;
  v_rate_limit integer;
  v_presence_id uuid;
  v_litige_id uuid;
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;
  IF p_facture_id IS NULL THEN
    RETURN public.fn_ouvrir_litige_rate_limited(
      p_mission_id, p_type_litige, p_motif
    );
  END IF;
  IF length(btrim(COALESCE(p_motif, ''))) NOT BETWEEN 10 AND 2000 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Le motif doit contenir entre 10 et 2 000 caractères.'
    );
  END IF;

  SELECT * INTO v_mission
  FROM public.missions
  WHERE id = p_mission_id
  FOR UPDATE;
  IF NOT FOUND OR NOT (
    v_mission.soignant_assigne_id = v_uid
    OR (
      v_mission.etablissement_id = public.mon_etablissement_id()
      AND public.fn_a_permission_etablissement(
        'contrats', v_mission.etablissement_id
      ) IS TRUE
    )
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Vous n’êtes pas autorisé à contester cette facture.'
    );
  END IF;
  v_initie_par := CASE
    WHEN v_mission.soignant_assigne_id = v_uid THEN 'SOIGNANT'
    ELSE 'ETABLISSEMENT'
  END;

  SELECT * INTO v_facture
  FROM public.factures_honoraires
  WHERE id = p_facture_id
    AND mission_id = p_mission_id
    AND soignant_id = v_mission.soignant_assigne_id
    AND etablissement_id = v_mission.etablissement_id
    AND type_document = 'FACTURE'
    AND statut IN ('BROUILLON', 'EMISE', 'EN_RETARD', 'PAYEE', 'FACTORISEE')
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'La facture sélectionnée est introuvable ou non contestable.'
    );
  END IF;
  IF p_type_litige IN (
    'DESACCORD_MONTANT_FACTURE', 'NON_PAIEMENT', 'FRAIS_COMPLEMENTAIRES'
  ) AND v_facture.statut = 'BROUILLON' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Cette facture n’est pas encore émise. Signalez plutôt un désaccord sur les heures.'
    );
  END IF;
  IF public.fn_fenetre_contestation_ouverte(
    p_type_litige, p_mission_id, p_facture_id
  ) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'La fenêtre de contestation de cette facture est fermée. Contactez le support.'
    );
  END IF;

  SELECT count(*) INTO v_existing
  FROM public.litiges l
  WHERE l.mission_id = p_mission_id
    AND l.facture_id = p_facture_id
    AND l.type_litige = p_type_litige
    AND l.statut IN (
      'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION',
      'MEDIATION_EN_COURS', 'REVUE_ADMIN'
    );
  IF v_existing > 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Un litige de ce type est déjà ouvert pour cette facture.'
    );
  END IF;

  v_rate_limit := COALESCE(
    (
      SELECT pl.valeur::integer
      FROM public.parametres_litiges pl
      WHERE pl.cle = 'rate_limit_litiges_par_heure'
    ),
    3
  );
  SELECT count(*) INTO v_recent
  FROM public.litiges l
  WHERE (
    l.soignant_id = v_uid
    OR l.etablissement_id = public.mon_etablissement_id()
  )
    AND l.cree_le > now() - interval '1 hour';
  IF v_recent >= v_rate_limit THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Trop de litiges ouverts récemment. Réessayez plus tard.'
    );
  END IF;

  SELECT p.id INTO v_presence_id
  FROM public.presences p
  WHERE p.mission_id = p_mission_id
    AND COALESCE(p.pointage_arrivee_le, p.cree_le)::date <= v_facture.periode_fin
    AND COALESCE(p.pointage_depart_le, p.pointage_arrivee_le, p.cree_le)::date >= v_facture.periode_debut
  ORDER BY p.valide_le DESC NULLS LAST, p.cree_le DESC
  LIMIT 1;

  INSERT INTO public.litiges (
    mission_id, soignant_id, etablissement_id, presence_id, facture_id,
    initie_par, motif, statut, type_litige, est_informatif,
    gel_facture_scope, periode_debut, periode_fin
  ) VALUES (
    p_mission_id, v_mission.soignant_assigne_id,
    v_mission.etablissement_id, v_presence_id, p_facture_id,
    v_initie_par, btrim(p_motif), 'OUVERT', p_type_litige, false,
    'FACTURE_UNIQUE', v_facture.periode_debut, v_facture.periode_fin
  ) RETURNING id INTO v_litige_id;

  -- Une déclaration de virement déjà en attente devient contestée. Les
  -- paiements des autres factures de la mission ne sont pas touchés.
  UPDATE public.paiements_soignant
  SET statut = 'CONTESTE',
      conteste = true,
      motif_contestation = COALESCE(
        NULLIF(motif_contestation, ''),
        left('Litige facture ' || v_facture.numero_facture || ' : ' || p_motif, 2000)
      ),
      modifie_le = now()
  WHERE facture_honoraire_id = p_facture_id
    AND statut = 'DECLARE';

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := CASE
      WHEN v_initie_par = 'SOIGNANT' THEN 'SOIGNANT'
      ELSE 'ETABLISSEMENT'
    END,
    p_action := 'LITIGE_OUVERTURE',
    p_type_ressource := 'litige',
    p_id_ressource := v_litige_id,
    p_details := jsonb_build_object(
      'evenement', 'FACTURE_CONTESTEE_EXPLICITEMENT',
      'mission_id', p_mission_id,
      'facture_id', p_facture_id,
      'numero_facture', v_facture.numero_facture,
      'periode_debut', v_facture.periode_debut,
      'periode_fin', v_facture.periode_fin
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'litige_id', v_litige_id,
    'est_informatif', false,
    'facture_id', p_facture_id,
    'numero_facture', v_facture.numero_facture,
    'periode_debut', v_facture.periode_debut,
    'periode_fin', v_facture.periode_fin
  );
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_ouvrir_litige_rate_limited(
  uuid, public.type_litige, text, uuid
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_ouvrir_litige_rate_limited(
  uuid, public.type_litige, text, uuid
) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_bloquer_paiement_facture_en_litige()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $body$
BEGIN
  IF NEW.facture_honoraire_id IS NOT NULL
     AND NEW.statut = 'DECLARE'
     AND EXISTS (
       SELECT 1
       FROM public.litiges l
       WHERE l.mission_id = NEW.mission_id
         AND (l.facture_id = NEW.facture_honoraire_id OR l.facture_id IS NULL)
         AND l.statut IN (
           'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION',
           'MEDIATION_EN_COURS', 'REVUE_ADMIN'
         )
     ) THEN
    RAISE EXCEPTION 'FACTURE_EN_LITIGE: cette échéance est suspendue jusqu’à la résolution.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$body$;

DROP TRIGGER IF EXISTS trg_bloquer_paiement_facture_en_litige
  ON public.paiements_soignant;
CREATE TRIGGER trg_bloquer_paiement_facture_en_litige
BEFORE INSERT OR UPDATE OF statut, facture_honoraire_id
ON public.paiements_soignant
FOR EACH ROW EXECUTE FUNCTION public.fn_bloquer_paiement_facture_en_litige();

-- La facture complémentaire d'honoraires doit conserver l'expérience de
-- paiement unique : le même checkout règle le delta d'honoraires et la facture
-- Jolene de 15 % (ou du taux contractuel figé), toutes deux distinctes.
CREATE OR REPLACE FUNCTION public.fn_preparer_commission_complement_honoraires(
  p_facture_honoraire_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $body$
DECLARE
  v_fh public.factures_honoraires%ROWTYPE;
  v_origine_honoraires public.factures_honoraires%ROWTYPE;
  v_origine_commission public.factures%ROWTYPE;
  v_mission public.missions%ROWTYPE;
  v_etab public.etablissements%ROWTYPE;
  v_existing public.factures%ROWTYPE;
  v_taux_commission numeric;
  v_ht numeric(10,2);
  v_tva numeric(10,2);
  v_ttc numeric(10,2);
  v_numero text;
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_fh
  FROM public.factures_honoraires
  WHERE id = p_facture_honoraire_id
    AND type_document = 'FACTURE'
    AND nature_correction = 'COMPLEMENT'
    AND statut IN ('EMISE', 'EN_RETARD', 'PAYEE')
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Facture complémentaire d''honoraires introuvable ou non émise';
  END IF;

  SELECT * INTO v_existing
  FROM public.factures
  WHERE facture_honoraire_id = v_fh.id
    AND type_document = 'FACTURE'
    AND statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
  FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true, 'facture_id', v_existing.id,
      'numero_facture', v_existing.numero_facture,
      'montant_ttc', v_existing.montant_ttc, 'existing', true
    );
  END IF;

  SELECT * INTO v_mission FROM public.missions WHERE id = v_fh.mission_id FOR UPDATE;
  SELECT * INTO v_etab FROM public.etablissements WHERE id = v_fh.etablissement_id;
  IF v_mission.id IS NULL OR v_etab.id IS NULL
     OR v_mission.type_contrat_applique <> 'LIBERAL'
     OR v_mission.soignant_assigne_id IS DISTINCT FROM v_fh.soignant_id
     OR v_mission.etablissement_id IS DISTINCT FROM v_fh.etablissement_id THEN
    RAISE EXCEPTION 'Mission incohérente pour la commission complémentaire';
  END IF;

  SELECT * INTO v_origine_honoraires
  FROM public.factures_honoraires
  WHERE id = v_fh.facture_precedente_id;
  SELECT * INTO v_origine_commission
  FROM public.factures
  WHERE facture_honoraire_id = v_origine_honoraires.id
    AND type_document = 'FACTURE'
    AND statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
  ORDER BY cree_le DESC
  LIMIT 1;
  v_taux_commission := CASE
    WHEN v_origine_honoraires.montant_ht > 0 AND v_origine_commission.montant_ht > 0
      THEN v_origine_commission.montant_ht / v_origine_honoraires.montant_ht
    ELSE COALESCE(v_mission.taux_commission, 15) / 100
  END;
  IF v_taux_commission <= 0 OR v_taux_commission > 1 THEN
    RAISE EXCEPTION 'Taux de commission historique incohérent';
  END IF;

  v_ht := round(v_fh.montant_ht * v_taux_commission, 2);
  v_tva := round(v_ht * 0.20, 2);
  v_ttc := v_ht + v_tva;
  IF v_ht <= 0 OR v_ttc <= 0 THEN
    RAISE EXCEPTION 'Commission complémentaire nulle ou négative';
  END IF;

  v_numero := 'JOL-' || to_char(CURRENT_DATE, 'YYYY') || '-HC-'
    || upper(left(replace(v_fh.id::text, '-', ''), 10));
  INSERT INTO public.factures (
    etablissement_id, mission_id, facture_honoraire_id, numero_facture,
    facture_precedente_id, periode_debut, periode_fin,
    montant_ht, taux_tva, montant_tva, montant_ttc, nombre_missions,
    statut, date_emission, date_echeance, est_secteur_public,
    mode_paiement, chorus_pro_statut, type_document
  ) VALUES (
    v_fh.etablissement_id, v_fh.mission_id, v_fh.id, v_numero,
    v_origine_commission.id, v_fh.periode_debut, v_fh.periode_fin,
    v_ht, 20, v_tva, v_ttc, 1, 'EMISE', now(), CURRENT_DATE + 30,
    COALESCE(v_etab.est_secteur_public, false),
    CASE WHEN COALESCE(v_etab.est_secteur_public, false) THEN 'CHORUS_PRO' ELSE 'STRIPE' END,
    CASE WHEN COALESCE(v_etab.est_secteur_public, false) THEN 'A_DEPOSER' ELSE 'NON_APPLICABLE' END,
    'FACTURE'
  ) RETURNING * INTO v_existing;

  UPDATE public.missions
  SET total_brut = round(COALESCE(total_brut, 0) + v_fh.montant_ht, 2),
      net_a_payer = round(COALESCE(net_a_payer, 0) + v_fh.montant_ttc, 2),
      montant_commission_ht = round(COALESCE(montant_commission_ht, 0) + v_ht, 2),
      montant_commission_tva = round(COALESCE(montant_commission_tva, 0) + v_tva, 2),
      montant_commission_ttc = round(COALESCE(montant_commission_ttc, 0) + v_ttc, 2),
      commission_a_recalculer = false,
      commission_facturee = true,
      modifie_le = now()
  WHERE id = v_mission.id;

  RETURN jsonb_build_object(
    'success', true, 'facture_id', v_existing.id,
    'numero_facture', v_existing.numero_facture,
    'montant_ttc', v_existing.montant_ttc, 'existing', false
  );
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_preparer_commission_complement_honoraires(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_preparer_commission_complement_honoraires(uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_preparer_commission_remplacement_honoraires(
  p_facture_honoraire_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $body$
DECLARE
  v_fh public.factures_honoraires%ROWTYPE;
  v_origine_honoraires public.factures_honoraires%ROWTYPE;
  v_mission public.missions%ROWTYPE;
  v_etab public.etablissements%ROWTYPE;
  v_origine_commission public.factures%ROWTYPE;
  v_existing public.factures%ROWTYPE;
  v_ht numeric(10,2);
  v_tva numeric(10,2);
  v_ttc numeric(10,2);
  v_delta_ht numeric(10,2);
  v_delta_tva numeric(10,2);
  v_delta_ttc numeric(10,2);
  v_taux_commission numeric;
  v_numero text;
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_fh
  FROM public.factures_honoraires
  WHERE id = p_facture_honoraire_id
    AND type_document = 'FACTURE'
    AND nature_correction = 'REMPLACEMENT'
    AND statut IN ('EMISE', 'EN_RETARD', 'PAYEE')
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Facture rectificative introuvable ou non émise'; END IF;

  SELECT * INTO v_existing
  FROM public.factures
  WHERE facture_honoraire_id = v_fh.id
    AND type_document = 'FACTURE'
    AND statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
  FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object('success', true, 'facture_id', v_existing.id, 'existing', true);
  END IF;

  SELECT * INTO v_origine_honoraires
  FROM public.factures_honoraires
  WHERE id = v_fh.facture_precedente_id
  FOR UPDATE;
  SELECT * INTO v_mission FROM public.missions WHERE id = v_fh.mission_id FOR UPDATE;
  SELECT * INTO v_etab FROM public.etablissements WHERE id = v_fh.etablissement_id;
  IF v_origine_honoraires.id IS NULL OR v_mission.id IS NULL OR v_etab.id IS NULL THEN
    RAISE EXCEPTION 'Chaîne de rectification incomplète';
  END IF;

  SELECT * INTO v_origine_commission
  FROM public.factures
  WHERE facture_honoraire_id = v_origine_honoraires.id
    AND type_document = 'FACTURE'
    AND statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
  ORDER BY cree_le DESC
  LIMIT 1
  FOR UPDATE;
  IF FOUND AND v_origine_commission.statut NOT IN ('BROUILLON', 'EMISE', 'EN_RETARD') THEN
    RAISE EXCEPTION 'La facture de services d''origine est déjà payée : un avoir est requis';
  END IF;

  v_taux_commission := CASE
    WHEN v_origine_honoraires.montant_ht > 0 AND v_origine_commission.montant_ht > 0
      THEN v_origine_commission.montant_ht / v_origine_honoraires.montant_ht
    ELSE COALESCE(v_mission.taux_commission, 15) / 100
  END;
  IF v_taux_commission <= 0 OR v_taux_commission > 1 THEN
    RAISE EXCEPTION 'Taux de commission historique incohérent';
  END IF;
  v_ht := round(v_fh.montant_ht * v_taux_commission, 2);
  v_tva := round(v_ht * 0.20, 2);
  v_ttc := v_ht + v_tva;
  v_delta_ht := v_ht - COALESCE(v_origine_commission.montant_ht, 0);
  v_delta_tva := v_tva - COALESCE(v_origine_commission.montant_tva, 0);
  v_delta_ttc := v_ttc - COALESCE(v_origine_commission.montant_ttc, 0);

  IF v_origine_commission.id IS NOT NULL THEN
    UPDATE public.factures
    SET statut = 'REMPLACEE', modifie_le = now()
    WHERE id = v_origine_commission.id
      AND statut IN ('BROUILLON', 'EMISE', 'EN_RETARD');
  END IF;

  v_numero := 'JOL-' || to_char(CURRENT_DATE, 'YYYY') || '-HR-'
    || upper(left(replace(v_fh.id::text, '-', ''), 10));
  INSERT INTO public.factures (
    etablissement_id, mission_id, facture_honoraire_id, numero_facture,
    facture_precedente_id, periode_debut, periode_fin,
    montant_ht, taux_tva, montant_tva, montant_ttc, nombre_missions,
    statut, date_emission, date_echeance, est_secteur_public,
    mode_paiement, chorus_pro_statut, type_document
  ) VALUES (
    v_fh.etablissement_id, v_fh.mission_id, v_fh.id, v_numero,
    v_origine_commission.id, v_fh.periode_debut, v_fh.periode_fin,
    v_ht, 20, v_tva, v_ttc, 1, 'EMISE', now(), CURRENT_DATE + 30,
    COALESCE(v_etab.est_secteur_public, false),
    CASE WHEN COALESCE(v_etab.est_secteur_public, false) THEN 'CHORUS_PRO' ELSE 'STRIPE' END,
    CASE WHEN COALESCE(v_etab.est_secteur_public, false) THEN 'A_DEPOSER' ELSE 'NON_APPLICABLE' END,
    'FACTURE'
  ) RETURNING * INTO v_existing;

  UPDATE public.missions
  SET total_brut = round(
        COALESCE(total_brut, 0)
          + v_fh.montant_ht - v_origine_honoraires.montant_ht,
        2
      ),
      net_a_payer = round(
        COALESCE(net_a_payer, 0)
          + v_fh.montant_ttc - v_origine_honoraires.montant_ttc,
        2
      ),
      montant_commission_ht = round(COALESCE(montant_commission_ht, 0) + v_delta_ht, 2),
      montant_commission_tva = round(COALESCE(montant_commission_tva, 0) + v_delta_tva, 2),
      montant_commission_ttc = round(COALESCE(montant_commission_ttc, 0) + v_delta_ttc, 2),
      commission_a_recalculer = false,
      modifie_le = now()
  WHERE id = v_mission.id;

  RETURN jsonb_build_object(
    'success', true, 'facture_id', v_existing.id,
    'numero_facture', v_existing.numero_facture,
    'montant_ttc', v_existing.montant_ttc, 'existing', false
  );
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_preparer_commission_remplacement_honoraires(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_preparer_commission_remplacement_honoraires(uuid)
  TO service_role;

-- Une baisse après paiement produit deux documents distincts mais cohérents :
-- l'avoir d'honoraires au nom du soignant et l'avoir Jolene correspondant au
-- même pourcentage de services, TVA 20 % comprise. Le calcul part de la
-- facture de commission exacte de la période, jamais du total de la mission.
CREATE OR REPLACE FUNCTION public.fn_preparer_avoir_commission_honoraires(
  p_avoir_honoraires_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $body$
DECLARE
  v_avoir_h public.factures_honoraires%ROWTYPE;
  v_origine_h public.factures_honoraires%ROWTYPE;
  v_origine_c public.factures%ROWTYPE;
  v_existing public.factures%ROWTYPE;
  v_taux_commission numeric;
  v_ht numeric(10,2);
  v_tva numeric(10,2);
  v_ttc numeric(10,2);
  v_numero text;
  v_avoir_c_id uuid;
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_avoir_h
  FROM public.factures_honoraires
  WHERE id = p_avoir_honoraires_id
    AND type_document = 'AVOIR'
    AND nature_correction = 'AVOIR'
    AND statut IN ('EMISE', 'REMBOURSE')
  FOR UPDATE;
  IF NOT FOUND OR v_avoir_h.facture_precedente_id IS NULL THEN
    RAISE EXCEPTION 'Avoir d''honoraires introuvable ou non émis';
  END IF;

  SELECT * INTO v_existing
  FROM public.factures
  WHERE facture_honoraire_id = v_avoir_h.id
    AND type_document = 'AVOIR'
    AND statut NOT IN ('ANNULEE', 'ERREUR_GENERATION')
  FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true, 'facture_id', v_existing.id,
      'numero_facture', v_existing.numero_facture,
      'montant_ttc', v_existing.montant_ttc, 'existing', true
    );
  END IF;

  SELECT * INTO v_origine_h
  FROM public.factures_honoraires
  WHERE id = v_avoir_h.facture_precedente_id
  FOR UPDATE;
  IF NOT FOUND OR v_origine_h.montant_ht <= 0 THEN
    RAISE EXCEPTION 'Facture d''honoraires d''origine incohérente';
  END IF;

  SELECT * INTO v_origine_c
  FROM public.factures
  WHERE facture_honoraire_id = v_origine_h.id
    AND type_document = 'FACTURE'
    AND statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
  ORDER BY cree_le DESC
  LIMIT 1
  FOR UPDATE;
  IF NOT FOUND OR v_origine_c.montant_ht <= 0 THEN
    RAISE EXCEPTION 'Facture Jolene d''origine introuvable';
  END IF;

  v_taux_commission := v_origine_c.montant_ht / v_origine_h.montant_ht;
  IF v_taux_commission <= 0 OR v_taux_commission > 1 THEN
    RAISE EXCEPTION 'Taux de commission historique incohérent';
  END IF;
  v_ht := round(v_avoir_h.montant_ht * v_taux_commission, 2);
  v_tva := round(v_ht * 0.20, 2);
  v_ttc := v_ht + v_tva;
  IF v_ht <= 0 OR v_ttc <= 0 THEN
    RAISE EXCEPTION 'Montant de l''avoir Jolene incohérent';
  END IF;

  v_numero := public.next_avoir_commission_number(v_avoir_h.etablissement_id);
  INSERT INTO public.factures (
    etablissement_id, mission_id, facture_honoraire_id,
    numero_facture, type_document, facture_precedente_id,
    montant_ht, taux_tva, montant_tva, montant_ttc, nombre_missions,
    statut, date_emission, date_echeance, periode_debut, periode_fin,
    est_secteur_public, mode_paiement
  ) VALUES (
    v_avoir_h.etablissement_id, v_avoir_h.mission_id, v_avoir_h.id,
    v_numero, 'AVOIR', v_origine_c.id,
    v_ht, 20, v_tva, v_ttc, 1,
    'EMISE', now(), CURRENT_DATE,
    v_origine_c.periode_debut, v_origine_c.periode_fin,
    v_origine_c.est_secteur_public, v_origine_c.mode_paiement
  ) RETURNING id INTO v_avoir_c_id;

  UPDATE public.missions
  SET total_brut = GREATEST(0, COALESCE(total_brut, 0) - v_avoir_h.montant_ht),
      net_a_payer = GREATEST(0, COALESCE(net_a_payer, 0) - v_avoir_h.montant_ttc),
      montant_commission_ht = GREATEST(0, COALESCE(montant_commission_ht, 0) - v_ht),
      montant_commission_tva = GREATEST(0, COALESCE(montant_commission_tva, 0) - v_tva),
      montant_commission_ttc = GREATEST(0, COALESCE(montant_commission_ttc, 0) - v_ttc),
      commission_a_recalculer = false,
      modifie_le = now()
  WHERE id = v_avoir_h.mission_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_avoir_h.etablissement_id,
    p_type_acteur := 'SYSTEME',
    p_action := 'FACTURATION',
    p_type_ressource := 'facture',
    p_id_ressource := v_avoir_c_id,
    p_details := jsonb_build_object(
      'evenement', 'AVOIR_COMMISSION_APRES_LITIGE',
      'avoir_honoraires_id', v_avoir_h.id,
      'facture_commission_origine_id', v_origine_c.id,
      'taux_commission_historique', v_taux_commission,
      'montant_ht', v_ht,
      'montant_tva', v_tva,
      'montant_ttc', v_ttc
    )
  );

  RETURN jsonb_build_object(
    'success', true, 'facture_id', v_avoir_c_id,
    'numero_facture', v_numero,
    'montant_ht', v_ht, 'montant_tva', v_tva,
    'montant_ttc', v_ttc, 'existing', false
  );
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_preparer_avoir_commission_honoraires(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_preparer_avoir_commission_honoraires(uuid)
  TO service_role;

-- ---------------------------------------------------------------------------
-- 6. File de facturation : finale = reliquat non encore facturé
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_lister_missions_a_facturer(p_today date DEFAULT CURRENT_DATE)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $body$
DECLARE
  v_finales jsonb;
  v_hebdo jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mode', 'FINALE',
    'mission_id', m.id,
    'soignant_id', m.soignant_assigne_id,
    'etablissement_id', m.etablissement_id,
    'periode_debut', CASE
      WHEN m.strategie_facturation = 'HEBDO_ET_FINALE'
        THEN COALESCE(derniere_periode.prochain_debut, m.debut_le::date)
      ELSE m.debut_le::date
    END,
    'periode_fin', m.fin_le::date,
    'numero_semaine_iso', NULL,
    'annee_iso', NULL,
    'strategie_facturation', m.strategie_facturation::text,
    'est_facture_finale_mission', true
  )), '[]'::jsonb)
  INTO v_finales
  FROM public.missions m
  JOIN public.soignants s ON s.id = m.soignant_assigne_id
  LEFT JOIN LATERAL (
    SELECT (max(fh.periode_fin) + 1)::date AS prochain_debut
    FROM public.factures_honoraires fh
    WHERE fh.mission_id = m.id
      AND fh.type_document = 'FACTURE'
      AND fh.est_facture_finale_mission IS FALSE
      AND fh.statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
  ) derniere_periode ON true
  WHERE m.statut = 'TERMINEE'
    AND COALESCE(m.est_arret_maladie, false) IS FALSE
    AND m.fin_le::date < p_today
    AND m.type_contrat_applique = 'LIBERAL'
    AND m.mode_remuneration = 'TAUX_HORAIRE'
    AND COALESCE(s.mandat_facturation_signe, false) IS TRUE
    AND s.mandat_facturation_version = '1.4'
    AND s.statut_tva_honoraires IN ('FRANCHISE_EN_BASE', 'REDEVABLE_TVA')
    AND m.statut_validation_tva = 'CONFIRMEE'
    AND m.nature_tva_prestation IN (
      'SOIN_THERAPEUTIQUE_EXONERE', 'PRESTATION_TAXABLE'
    )
    AND m.nature_tva_confirmee_soignant = m.nature_tva_prestation
    AND m.nature_tva_confirmee_par = m.soignant_assigne_id
    AND NOT EXISTS (
      SELECT 1 FROM public.missions r
      WHERE r.remplacement_de_mission_id = m.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.factures_honoraires fh
      WHERE fh.mission_id = m.id
        AND fh.est_facture_finale_mission IS TRUE
        AND fh.statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
    )
    AND (
      m.strategie_facturation = 'FINALE_UNIQUE'
      OR COALESCE(derniere_periode.prochain_debut, m.debut_le::date) <= m.fin_le::date
    )
    AND EXISTS (
      SELECT 1 FROM public.mission_creneaux mc
      WHERE mc.mission_id = m.id
        AND (
          (mc.type_creneau = 'EFFECTIF' AND mc.fin IS NOT NULL)
          OR mc.type_creneau = 'PREVISIONNEL'
        )
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.presences p
      WHERE p.mission_id = m.id
        AND COALESCE(p.valide_par_etablissement, false) IS FALSE
        AND (p.pointage_depart_le IS NOT NULL OR p.motif_litige IS NOT NULL)
    );

  WITH semaines AS (
    SELECT
      m.id AS mission_id,
      m.soignant_assigne_id,
      m.etablissement_id,
      m.debut_le,
      m.fin_le,
      m.strategie_facturation,
      gs.lundi_semaine
    FROM public.missions m
    JOIN public.soignants s ON s.id = m.soignant_assigne_id
    CROSS JOIN LATERAL generate_series(
      date_trunc('week', m.debut_le)::date,
      least(m.fin_le::date, p_today - interval '1 day')::date,
      '7 days'::interval
    ) AS gs(lundi_semaine)
    WHERE m.statut IN ('EN_COURS', 'TERMINEE')
      AND COALESCE(m.est_arret_maladie, false) IS FALSE
      AND m.strategie_facturation = 'HEBDO_ET_FINALE'
      AND m.type_contrat_applique = 'LIBERAL'
      AND m.mode_remuneration = 'TAUX_HORAIRE'
      AND COALESCE(s.mandat_facturation_signe, false) IS TRUE
      AND s.mandat_facturation_version = '1.4'
      AND s.statut_tva_honoraires IN ('FRANCHISE_EN_BASE', 'REDEVABLE_TVA')
      AND m.statut_validation_tva = 'CONFIRMEE'
      AND m.nature_tva_prestation IN (
        'SOIN_THERAPEUTIQUE_EXONERE', 'PRESTATION_TAXABLE'
      )
      AND m.nature_tva_confirmee_soignant = m.nature_tva_prestation
      AND m.nature_tva_confirmee_par = m.soignant_assigne_id
      AND NOT EXISTS (
        SELECT 1 FROM public.missions r
        WHERE r.remplacement_de_mission_id = m.id
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.presences p
        WHERE p.mission_id = m.id
          AND COALESCE(p.valide_par_etablissement, false) IS FALSE
          AND p.motif_litige IS NOT NULL
      )
  ),
  semaines_closes AS (
    SELECT
      sm.*,
      (sm.lundi_semaine + interval '6 days')::date AS dimanche_semaine,
      extract(week FROM sm.lundi_semaine)::smallint AS num_sem,
      extract(isoyear FROM sm.lundi_semaine)::smallint AS ann_iso,
      greatest(sm.lundi_semaine::date, sm.debut_le::date) AS periode_d,
      least((sm.lundi_semaine + interval '6 days')::date, sm.fin_le::date) AS periode_f
    FROM semaines sm
    WHERE (sm.lundi_semaine + interval '6 days')::date < p_today
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mode', 'HEBDO',
    'mission_id', sa.mission_id,
    'soignant_id', sa.soignant_assigne_id,
    'etablissement_id', sa.etablissement_id,
    'periode_debut', sa.periode_d,
    'periode_fin', sa.periode_f,
    'numero_semaine_iso', sa.num_sem,
    'annee_iso', sa.ann_iso,
    'strategie_facturation', sa.strategie_facturation::text,
    'est_facture_finale_mission', false
  )), '[]'::jsonb)
  INTO v_hebdo
  FROM semaines_closes sa
  WHERE NOT EXISTS (
    SELECT 1 FROM public.factures_honoraires fh
    WHERE fh.mission_id = sa.mission_id
      AND fh.annee_iso = sa.ann_iso
      AND fh.numero_semaine_iso = sa.num_sem
      AND fh.est_facture_finale_mission IS FALSE
      AND fh.statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
  )
    AND EXISTS (
      SELECT 1 FROM public.mission_creneaux mc
      WHERE mc.mission_id = sa.mission_id
        AND (
          (mc.type_creneau = 'EFFECTIF' AND mc.fin IS NOT NULL)
          OR mc.type_creneau = 'PREVISIONNEL'
        )
        AND mc.debut::date <= sa.periode_f
        AND COALESCE(mc.fin::date, mc.debut::date) >= sa.periode_d
    );

  RETURN jsonb_build_object(
    'today', p_today,
    'finales', v_finales,
    'hebdo', v_hebdo,
    'total', jsonb_array_length(v_finales) + jsonb_array_length(v_hebdo)
  );
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_lister_missions_a_facturer(date)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_lister_missions_a_facturer(date)
  TO service_role;

-- ---------------------------------------------------------------------------
-- 7. Registre immuable des versions PDF/XML conservées dix ans
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.factures_honoraires_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  facture_honoraire_id uuid NOT NULL REFERENCES public.factures_honoraires(id),
  pdf_s3_key text NOT NULL,
  facturx_xml_url text NOT NULL,
  pdf_sha256 text,
  xml_sha256 text,
  motif_generation text NOT NULL,
  cree_le timestamptz NOT NULL DEFAULT now(),
  retention_jusqu_au timestamptz NOT NULL DEFAULT (now() + interval '10 years'),
  CONSTRAINT factures_honoraires_documents_pdf_hash_check
    CHECK (pdf_sha256 IS NULL OR pdf_sha256 ~ '^[a-f0-9]{64}$'),
  CONSTRAINT factures_honoraires_documents_xml_hash_check
    CHECK (xml_sha256 IS NULL OR xml_sha256 ~ '^[a-f0-9]{64}$'),
  CONSTRAINT factures_honoraires_documents_pdf_unique UNIQUE (pdf_s3_key),
  CONSTRAINT factures_honoraires_documents_xml_unique UNIQUE (facturx_xml_url)
);

ALTER TABLE public.factures_honoraires_documents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.factures_honoraires_documents FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.factures_honoraires_documents TO service_role;

INSERT INTO public.factures_honoraires_documents (
  facture_honoraire_id,
  pdf_s3_key,
  facturx_xml_url,
  motif_generation,
  cree_le,
  retention_jusqu_au
)
SELECT
  fh.id,
  fh.pdf_s3_key,
  fh.facturx_xml_url,
  'MIGRATION_REFERENCE_EXISTANTE',
  COALESCE(fh.cree_le, now()),
  COALESCE(fh.cree_le, now()) + interval '10 years'
FROM public.factures_honoraires fh
WHERE fh.pdf_s3_key IS NOT NULL
  AND fh.facturx_xml_url IS NOT NULL
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.fn_preserver_document_facture_honoraires()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $body$
BEGIN
  IF OLD.retention_jusqu_au > now() THEN
    RAISE EXCEPTION 'Une version de facture conservée pendant la durée de rétention ne peut être ni modifiée ni supprimée.'
      USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$body$;

DROP TRIGGER IF EXISTS trg_preserver_document_facture_honoraires
  ON public.factures_honoraires_documents;
CREATE TRIGGER trg_preserver_document_facture_honoraires
BEFORE UPDATE OR DELETE ON public.factures_honoraires_documents
FOR EACH ROW EXECUTE FUNCTION public.fn_preserver_document_facture_honoraires();

-- Les PDF/XML de facturation sont déposés par le service sous des préfixes
-- techniques (invoices/, avoirs/, etc.) et non sous l'UID du lecteur. La
-- politique Storage historique ne pouvait donc pas les remettre aux parties.
-- La lecture est accordée uniquement si la clé exacte est encore référencée
-- par la facture courante ou par son registre de versions immuables. Aucun
-- droit d'écriture n'est ajouté et connaître/deviner un chemin ne suffit pas.
CREATE OR REPLACE FUNCTION public.fn_peut_lire_objet_jolene(p_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, storage
AS $body$
  SELECT auth.uid() IS NOT NULL
    AND public.fn_compte_auth_actif()
    AND (
      public.fn_peut_gerer_objet_jolene(p_name)
      OR EXISTS (
        SELECT 1
        FROM public.documents_soignants ds
        JOIN public.partages_rib pr ON pr.document_rib_id = ds.id
        WHERE ds.s3_bucket = 'jolene-documents'
          AND ds.s3_cle = p_name
          AND ds.type_document = 'RIB'
          AND ds.statut_verification = 'VERIFIE'
          AND ds.supprime_le IS NULL
          AND ds.revoque_le IS NULL
          AND ds.resultat_ia->>'verdict_serveur' = 'VERIFIE'
          AND pr.soignant_id = ds.soignant_id
          AND pr.etablissement_id = public.mon_etablissement_id()
          AND pr.actif IS TRUE
          AND (pr.expire_le IS NULL OR pr.expire_le > now())
      )
      OR EXISTS (
        SELECT 1
        FROM public.factures_honoraires fh
        WHERE (fh.pdf_s3_key = p_name OR fh.facturx_xml_url = p_name)
          AND (
            fh.soignant_id = auth.uid()
            OR public.fn_a_permission_etablissement(
              'lecture_paiement', fh.etablissement_id
            ) IS TRUE
            OR public.est_admin() IS TRUE
          )
      )
      OR EXISTS (
        SELECT 1
        FROM public.factures_honoraires_documents fhd
        JOIN public.factures_honoraires fh
          ON fh.id = fhd.facture_honoraire_id
        WHERE (fhd.pdf_s3_key = p_name OR fhd.facturx_xml_url = p_name)
          AND (
            fh.soignant_id = auth.uid()
            OR public.fn_a_permission_etablissement(
              'lecture_paiement', fh.etablissement_id
            ) IS TRUE
            OR public.est_admin() IS TRUE
          )
      )
    );
$body$;

REVOKE ALL ON FUNCTION public.fn_peut_lire_objet_jolene(text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_peut_lire_objet_jolene(text)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 8. Emission atomique, copie au soignant et acceptation/contestation exacte
-- ---------------------------------------------------------------------------

-- date_emission est une date comptable. emise_le est l'instant produit qui
-- ouvre le délai de vérification : on ne calcule jamais 48 h depuis minuit.
ALTER TABLE public.factures_honoraires
  ADD COLUMN IF NOT EXISTS emise_le timestamptz,
  ADD COLUMN IF NOT EXISTS notifiee_soignant_le timestamptz,
  ADD COLUMN IF NOT EXISTS verification_echeance_le timestamptz,
  ADD COLUMN IF NOT EXISTS acceptee_explicitement_le timestamptz,
  ADD COLUMN IF NOT EXISTS contestee_le timestamptz;

UPDATE public.factures_honoraires
SET emise_le = COALESCE(cree_le, date_emission::timestamptz)
WHERE emise_le IS NULL
  AND statut NOT IN ('BROUILLON', 'EN_GENERATION', 'ERREUR_GENERATION');

UPDATE public.factures_honoraires
SET verification_echeance_le = emise_le + make_interval(hours => COALESCE(
  (
    SELECT valeur::integer FROM public.parametres_litiges
    WHERE cle = 'delai_contestation_facture_liberal_h'
  ),
  48
))
WHERE verification_echeance_le IS NULL
  AND emise_le IS NOT NULL;

COMMENT ON COLUMN public.factures_honoraires.emise_le IS
  'Instant exact de première mise à disposition du document. Point de départ du délai de contestation.';
COMMENT ON COLUMN public.factures_honoraires.notifiee_soignant_le IS
  'Instant de création atomique de la notification in-app remettant la copie au soignant.';
COMMENT ON COLUMN public.factures_honoraires.verification_echeance_le IS
  'Echéance exacte et figée de vérification du contenu par le soignant.';
COMMENT ON COLUMN public.factures_honoraires.acceptee_explicitement_le IS
  'Acceptation expresse du document par le soignant. Sans contestation, l’acceptation peut aussi être tacite au terme du délai contractuel.';
COMMENT ON COLUMN public.factures_honoraires.contestee_le IS
  'Première contestation tracée visant exactement ce document.';

CREATE OR REPLACE FUNCTION public.fn_emettre_document_facturation_honoraires(
  p_facture_id uuid,
  p_pdf_s3_key text,
  p_facturx_xml_url text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $body$
DECLARE
  v_facture public.factures_honoraires%ROWTYPE;
  v_emise_le timestamptz := now();
  v_delai integer;
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Accès réservé au service de facturation.' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(btrim(COALESCE(p_pdf_s3_key, '')), '') IS NULL
     OR NULLIF(btrim(COALESCE(p_facturx_xml_url, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Les deux versions PDF et XML CII sont requises avant émission.';
  END IF;

  SELECT * INTO v_facture
  FROM public.factures_honoraires
  WHERE id = p_facture_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Document de facturation introuvable.';
  END IF;
  IF v_facture.statut NOT IN ('BROUILLON', 'EN_GENERATION') THEN
    RAISE EXCEPTION 'Le document % est déjà émis ou n’est plus émissible.', v_facture.numero_facture;
  END IF;

  SELECT COALESCE(valeur::integer, 48) INTO v_delai
  FROM public.parametres_litiges
  WHERE cle = 'delai_contestation_facture_liberal_h';
  v_delai := COALESCE(v_delai, 48);

  UPDATE public.factures_honoraires
  SET statut = 'EMISE',
      pdf_s3_key = p_pdf_s3_key,
      facturx_xml_url = p_facturx_xml_url,
      pdf_a_regenerer = false,
      emise_le = v_emise_le,
      notifiee_soignant_le = v_emise_le,
      verification_echeance_le = v_emise_le + make_interval(hours => v_delai),
      modifie_le = v_emise_le
  WHERE id = p_facture_id;

  -- Le remboursement automatique devient visible aux workers uniquement au
  -- commit qui rend aussi l'avoir et ses notifications visibles. Un retry de
  -- génération ne duplique jamais la file.
  IF v_facture.type_document = 'AVOIR'
     AND v_facture.mode_remboursement = 'AUTO_STRIPE' THEN
    INSERT INTO public.stripe_refunds_queue (
      avoir_id, facture_origine_id, stripe_payment_intent_id, montant_cts
    )
    SELECT
      v_facture.id,
      v_facture.facture_precedente_id,
      origine.stripe_payment_intent_id,
      round(v_facture.montant_ttc * 100)::integer
    FROM public.factures_honoraires origine
    WHERE origine.id = v_facture.facture_precedente_id
      AND origine.type_document = 'FACTURE'
      AND origine.statut = 'PAYEE'
      AND origine.stripe_payment_intent_id IS NOT NULL
      AND v_facture.montant_ttc > 0
      AND NOT EXISTS (
        SELECT 1 FROM public.stripe_refunds_queue q
        WHERE q.avoir_id = v_facture.id
      );
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Avoir émis mais source Stripe sûre introuvable : remboursement automatique annulé.';
    END IF;
  END IF;

  INSERT INTO public.notifications (
    destinataire_id, type_destinataire, type, titre, corps, lien,
    type_ressource, id_ressource
  ) VALUES
  (
    v_facture.soignant_id, 'SOIGNANT', 'FACTURE_EMISE',
    'Document ' || v_facture.numero_facture || ' à vérifier',
    'Une copie est disponible. Vérifiez les heures, le taux et le montant sous '
      || v_delai || ' h ; en cas d’erreur, contestez uniquement cette échéance.',
    '/soignant/mes-gains?tab=factures', 'facture_honoraire', p_facture_id
  ),
  (
    v_facture.etablissement_id, 'ETABLISSEMENT', 'FACTURE_EMISE',
    'Nouvelle échéance ' || v_facture.numero_facture,
    'La note d’honoraires et la facture de services Jolene associée sont disponibles. Chaque période reste indépendante.',
    '/etablissement/facturation', 'facture_honoraire', p_facture_id
  );

  INSERT INTO public.invoice_audit_log (
    invoice_id, action, actor_id, payload_before, payload_after
  ) VALUES (
    p_facture_id, 'EMISSION_ET_REMISE_COPIE',
    '00000000-0000-0000-0000-000000000000'::uuid,
    jsonb_build_object('statut', v_facture.statut),
    jsonb_build_object(
      'statut', 'EMISE', 'emise_le', v_emise_le,
      'notifiee_soignant_le', v_emise_le,
      'verification_echeance_le', v_emise_le + make_interval(hours => v_delai),
      'delai_verification_heures', v_delai
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'facture_id', p_facture_id,
    'emise_le', v_emise_le,
    'verification_echeance_le', v_emise_le + make_interval(hours => v_delai),
    'delai_verification_heures', v_delai
  );
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_emettre_document_facturation_honoraires(
  uuid, text, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_emettre_document_facturation_honoraires(
  uuid, text, text
) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_accepter_document_facturation_honoraires(
  p_facture_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_facture public.factures_honoraires%ROWTYPE;
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;
  SELECT * INTO v_facture
  FROM public.factures_honoraires
  WHERE id = p_facture_id
    AND soignant_id = v_uid
    AND emise_le IS NOT NULL
    AND statut NOT IN (
      'BROUILLON', 'EN_GENERATION', 'ERREUR_GENERATION', 'ANNULEE', 'REMPLACEE'
    )
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Ce document n’est pas disponible pour acceptation.'
    );
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.litiges l
    WHERE l.facture_id = p_facture_id
      AND l.statut IN (
        'OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION',
        'MEDIATION_EN_COURS', 'REVUE_ADMIN'
      )
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Une contestation est en cours sur ce document.'
    );
  END IF;
  IF v_facture.acceptee_explicitement_le IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'facture_id', p_facture_id,
      'acceptee_explicitement_le', v_facture.acceptee_explicitement_le,
      'deja_acceptee', true
    );
  END IF;

  UPDATE public.factures_honoraires
  SET acceptee_explicitement_le = now(),
      modifie_le = now()
  WHERE id = p_facture_id;

  INSERT INTO public.invoice_audit_log (
    invoice_id, action, actor_id, payload_before, payload_after
  ) VALUES (
    p_facture_id, 'ACCEPTEE_PAR_SOIGNANT', v_uid,
    jsonb_build_object('acceptee_explicitement_le', v_facture.acceptee_explicitement_le),
    jsonb_build_object('acceptee_explicitement_le', now())
  );

  RETURN jsonb_build_object(
    'success', true,
    'facture_id', p_facture_id,
    'acceptee_explicitement_le', now()
  );
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_accepter_document_facturation_honoraires(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_accepter_document_facturation_honoraires(uuid)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_tracer_contestation_facture_honoraires()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $body$
BEGIN
  IF NEW.facture_id IS NOT NULL THEN
    UPDATE public.factures_honoraires
    SET contestee_le = COALESCE(contestee_le, NEW.cree_le, now()),
        statut_litige = 'EN_ATTENTE_LITIGE',
        litige_id = NEW.id,
        modifie_le = now()
    WHERE id = NEW.facture_id;
  END IF;
  RETURN NEW;
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_tracer_contestation_facture_honoraires()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_tracer_contestation_facture_honoraires()
  TO service_role;

DROP TRIGGER IF EXISTS trg_tracer_contestation_facture_honoraires
  ON public.litiges;
CREATE TRIGGER trg_tracer_contestation_facture_honoraires
AFTER INSERT ON public.litiges
FOR EACH ROW EXECUTE FUNCTION public.fn_tracer_contestation_facture_honoraires();

-- Repose la fenêtre sur l'instant exact d'émission. Les litiges de sécurité,
-- non-paiement et autres restent ouverts : l'acceptation d'une facture ne
-- neutralise jamais les recours produit indispensables.
CREATE OR REPLACE FUNCTION public.fn_fenetre_contestation_ouverte(
  p_type_litige public.type_litige,
  p_mission_id uuid,
  p_facture_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $body$
DECLARE
  v_presence_validee timestamptz;
  v_facture_emise timestamptz;
  v_facture_verification_echeance timestamptz;
  v_facture_payee timestamptz;
  v_mission_fin timestamptz;
  v_est_salarie boolean;
  v_type_applique public.type_contrat_applique_enum;
  v_soignant_id uuid;
  v_delai_pointage integer;
  v_delai_liberal integer;
  v_delai_salarie integer;
  v_delai_compo_mois integer;
BEGIN
  IF p_type_litige IN ('SECURITE_DANGER', 'NON_PAIEMENT', 'AUTRE') THEN
    RETURN TRUE;
  END IF;

  SELECT COALESCE(valeur::integer, 48) INTO v_delai_pointage
  FROM public.parametres_litiges WHERE cle = 'delai_contestation_pointage_h';
  SELECT COALESCE(valeur::integer, 48) INTO v_delai_liberal
  FROM public.parametres_litiges WHERE cle = 'delai_contestation_facture_liberal_h';
  SELECT COALESCE(valeur::integer, 60) INTO v_delai_salarie
  FROM public.parametres_litiges WHERE cle = 'delai_contestation_paiement_salarie_j';
  SELECT COALESCE(valeur::integer, 6) INTO v_delai_compo_mois
  FROM public.parametres_litiges WHERE cle = 'delai_comportement_mois';
  v_delai_pointage := COALESCE(v_delai_pointage, 48);
  v_delai_liberal := COALESCE(v_delai_liberal, 48);
  v_delai_salarie := COALESCE(v_delai_salarie, 60);
  v_delai_compo_mois := COALESCE(v_delai_compo_mois, 6);

  IF p_type_litige IN (
    'ABSENCE_SOIGNANT', 'DEPART_ANTICIPE', 'RETARD_IMPORTANT',
    'DESACCORD_HEURES_POINTAGE'
  ) THEN
    SELECT valide_le INTO v_presence_validee
    FROM public.presences
    WHERE mission_id = p_mission_id AND valide_le IS NOT NULL
    ORDER BY valide_le DESC LIMIT 1;
    IF v_presence_validee IS NULL THEN RETURN TRUE; END IF;
    RETURN v_presence_validee + make_interval(hours => v_delai_pointage) > now();
  END IF;

  IF p_type_litige IN ('DESACCORD_MONTANT_FACTURE', 'FRAIS_COMPLEMENTAIRES') THEN
    IF p_facture_id IS NULL THEN RETURN TRUE; END IF;
    SELECT COALESCE(f.emise_le, f.cree_le, f.date_emission::timestamptz),
           f.verification_echeance_le, f.date_paiement
    INTO v_facture_emise, v_facture_verification_echeance, v_facture_payee
    FROM public.factures_honoraires f
    WHERE f.id = p_facture_id;
    IF v_facture_emise IS NULL THEN RETURN FALSE; END IF;

    SELECT m.soignant_assigne_id, m.type_contrat_applique
    INTO v_soignant_id, v_type_applique
    FROM public.missions m WHERE m.id = p_mission_id;
    IF v_type_applique = 'SALARIE' THEN
      v_est_salarie := true;
    ELSIF v_type_applique = 'LIBERAL' THEN
      v_est_salarie := false;
    ELSE
      SELECT COALESCE(s.est_salarie_etablissement, false) INTO v_est_salarie
      FROM public.soignants s WHERE s.id = v_soignant_id;
    END IF;
    IF v_est_salarie AND v_facture_payee IS NOT NULL THEN
      RETURN v_facture_payee + make_interval(days => v_delai_salarie) > now();
    END IF;
    RETURN COALESCE(
      v_facture_verification_echeance,
      v_facture_emise + make_interval(hours => v_delai_liberal)
    ) > now();
  END IF;

  IF p_type_litige IN (
    'COMPORTEMENT_SOIGNANT', 'COMPORTEMENT_ETABLISSEMENT',
    'CONDITIONS_MISSION_NON_RESPECTEES'
  ) THEN
    SELECT m.fin_le INTO v_mission_fin
    FROM public.missions m WHERE m.id = p_mission_id;
    IF v_mission_fin IS NULL THEN RETURN TRUE; END IF;
    RETURN v_mission_fin + make_interval(months => v_delai_compo_mois) > now();
  END IF;

  RETURN TRUE;
END;
$body$;

COMMENT ON FUNCTION public.fn_fenetre_contestation_ouverte(
  public.type_litige, uuid, uuid
) IS 'Fenêtres de contestation calculées depuis les instants produit exacts. Sécurité, non-paiement et autre restent toujours recevables.';

-- Toute SECURITY DEFINER créée ou modifiée ci-dessus est recapturée après sa
-- revue d'identité, de tenancy, d'ACL et de search_path. Le manifeste JSON du
-- 29/07 reste le snapshot historique; cet inventaire SQL est cumulatif.
WITH reviewed(signature, qualified_signature, categorie, justification) AS (
  VALUES
    (
      'fn_signer_mandat_facturation(text,text,text,text)',
      'public.fn_signer_mandat_facturation(text,text,text,text)',
      'RPC_UTILISATEUR_AUTH_INTERNE',
      'RPC authentifiée de compatibilité sans mutation : demande aux anciens clients de recharger et de passer par l Edge canonique.'
    ),
    (
      'fn_signer_mandat_facturation_serveur(uuid,text,text,text,text,text,text,text)',
      'public.fn_signer_mandat_facturation_serveur(uuid,text,text,text,text,text,text,text)',
      'SERVICE_ONLY_REVOQUE',
      'Primitive réservée au service de signature : valide le texte canonique, son empreinte et le profil libéral avant d archiver la preuve.'
    ),
    (
      'fn_revoquer_mandat_facturation(text)',
      'public.fn_revoquer_mandat_facturation(text)',
      'RPC_UTILISATEUR_AUTH_INTERNE',
      'RPC soignant authentifié : révoque uniquement le mandat de auth.uid et conserve la preuve réglementaire.'
    ),
    (
      'fn_modifier_mission_etablissement_v4(uuid,text,text,text,type_profession,numeric,boolean,integer,text,text,text,boolean,jsonb,text)',
      'public.fn_modifier_mission_etablissement_v4(uuid,text,text,text,public.type_profession,numeric,boolean,integer,text,text,text,boolean,jsonb,text)',
      'MIXTE_TENANT_ADMIN',
      'RPC établissement ou admin : vérifie la permission mission puis réinitialise la confirmation TVA lors d une modification de nature.'
    ),
    (
      'fn_confirmer_nature_tva_mission(uuid,text)',
      'public.fn_confirmer_nature_tva_mission(uuid,text)',
      'RPC_UTILISATEUR_AUTH_INTERNE',
      'RPC du soignant libéral assigné : confirme ou conteste la qualification TVA sans interrompre l exécution de la mission.'
    ),
    (
      'fn_admin_lister_revues_tva_missions()',
      'public.fn_admin_lister_revues_tva_missions()',
      'ADMIN_EST_ADMIN_VALIDE',
      'RPC back-office bornée par est_admin : liste les seules divergences TVA nécessitant une proposition Jolene.'
    ),
    (
      'fn_admin_proposer_nature_tva_mission(uuid,text,text)',
      'public.fn_admin_proposer_nature_tva_mission(uuid,text,text)',
      'ADMIN_EST_ADMIN_VALIDE',
      'RPC back-office bornée par est_admin : propose une qualification motivée et exige une nouvelle confirmation du soignant.'
    ),
    (
      'fn_admin_resoudre_litige(uuid,text,text,numeric,numeric,text)',
      'public.fn_admin_resoudre_litige(uuid,text,text,numeric,numeric,text)',
      'ADMIN_EST_ADMIN_VALIDE',
      'RPC back-office existante recapturée après correction facture-scopée, solde cumulé et isolation stricte des paiements par échéance.'
    ),
    (
      'fn_admin_resoudre_litige_complement_honoraires(uuid,text,text,numeric,numeric)',
      'public.fn_admin_resoudre_litige_complement_honoraires(uuid,text,text,numeric,numeric)',
      'ADMIN_EST_ADMIN_VALIDE',
      'RPC back-office bornée par est_admin : émet uniquement le delta positif d une facture payée après accord ou décision tracée.'
    ),
    (
      'fn_preserver_rectification_facture_honoraires()',
      'public.fn_preserver_rectification_facture_honoraires()',
      'SERVICE_ONLY_REVOQUE',
      'Trigger interne sans accès client : interdit la modification ou suppression d une rectification descriptive conservée dix ans.'
    ),
    (
      'fn_admin_solde_correction_facture_honoraires(uuid)',
      'public.fn_admin_solde_correction_facture_honoraires(uuid)',
      'ADMIN_EST_ADMIN_VALIDE',
      'RPC back-office bornée par est_admin : expose le solde cumulé de la chaîne exacte sans donner un accès financier inter-tenant.'
    ),
    (
      'fn_admin_resoudre_litige_intelligent(uuid,text,text,numeric,numeric,text)',
      'public.fn_admin_resoudre_litige_intelligent(uuid,text,text,numeric,numeric,text)',
      'ADMIN_EST_ADMIN_VALIDE',
      'RPC back-office bornée par le résolveur administrateur : choisit avoir, complément, remplacement ou rectification immuable.'
    ),
    (
      'fn_ouvrir_litige_rate_limited(uuid,type_litige,text,uuid)',
      'public.fn_ouvrir_litige_rate_limited(uuid,public.type_litige,text,uuid)',
      'RPC_UTILISATEUR_AUTH_INTERNE',
      'RPC authentifiée : vérifie que l acteur est partie à la mission et cible une facture exacte avant d ouvrir la contestation.'
    ),
    (
      'fn_preparer_commission_complement_honoraires(uuid)',
      'public.fn_preparer_commission_complement_honoraires(uuid)',
      'SERVICE_ONLY_REVOQUE',
      'Primitive service_role : prépare la facture Jolene du seul delta positif et conserve les deux créances juridiquement distinctes.'
    ),
    (
      'fn_preparer_commission_remplacement_honoraires(uuid)',
      'public.fn_preparer_commission_remplacement_honoraires(uuid)',
      'SERVICE_ONLY_REVOQUE',
      'Primitive service_role : rattache la commission au document de remplacement exact sans recalculer les autres périodes.'
    ),
    (
      'fn_preparer_avoir_commission_honoraires(uuid)',
      'public.fn_preparer_avoir_commission_honoraires(uuid)',
      'SERVICE_ONLY_REVOQUE',
      'Primitive service_role : génère l avoir Jolene correspondant à l avoir d honoraires et à la commission historique exacte.'
    ),
    (
      'fn_lister_missions_a_facturer(date)',
      'public.fn_lister_missions_a_facturer(date)',
      'SERVICE_ONLY_REVOQUE',
      'Primitive service_role : alimente la file seulement après mandat v1.4 et confirmation TVA concordante, par période indépendante.'
    ),
    (
      'fn_peut_lire_objet_jolene(text)',
      'public.fn_peut_lire_objet_jolene(text)',
      'RPC_UTILISATEUR_AUTH_INTERNE',
      'Garde Storage authentifiée : autorise une clé exacte de facture aux parties dotées du droit financier, y compris une version archivée.'
    ),
    (
      'fn_emettre_document_facturation_honoraires(uuid,text,text)',
      'public.fn_emettre_document_facturation_honoraires(uuid,text,text)',
      'SERVICE_ONLY_REVOQUE',
      'Primitive service_role : rend PDF et XML atomiquement disponibles, archive la remise et ouvre le délai exact de vérification.'
    ),
    (
      'fn_accepter_document_facturation_honoraires(uuid)',
      'public.fn_accepter_document_facturation_honoraires(uuid)',
      'RPC_UTILISATEUR_AUTH_INTERNE',
      'RPC soignant authentifié : accepte uniquement sa propre pièce émise et refuse tant qu une contestation exacte reste ouverte.'
    ),
    (
      'fn_tracer_contestation_facture_honoraires()',
      'public.fn_tracer_contestation_facture_honoraires()',
      'SERVICE_ONLY_REVOQUE',
      'Trigger interne : horodate la première contestation sur la facture explicitement ciblée sans modifier les autres échéances.'
    )
)
INSERT INTO private.security_definer_inventory (
  signature, categorie, definition_md5, justification, recense_le
)
SELECT
  r.signature,
  r.categorie,
  pg_catalog.md5(p.prosrc),
  r.justification,
  pg_catalog.now()
FROM reviewed r
JOIN pg_catalog.pg_proc p
  ON p.oid = pg_catalog.to_regprocedure(r.qualified_signature)
WHERE p.prosecdef IS TRUE
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;

DO $assert_mandat_v14_security_definer_inventory$
DECLARE
  v_invalide text;
BEGIN
  WITH reviewed(signature, qualified_signature) AS (
    VALUES
      ('fn_signer_mandat_facturation(text,text,text,text)', 'public.fn_signer_mandat_facturation(text,text,text,text)'),
      ('fn_signer_mandat_facturation_serveur(uuid,text,text,text,text,text,text,text)', 'public.fn_signer_mandat_facturation_serveur(uuid,text,text,text,text,text,text,text)'),
      ('fn_revoquer_mandat_facturation(text)', 'public.fn_revoquer_mandat_facturation(text)'),
      ('fn_modifier_mission_etablissement_v4(uuid,text,text,text,type_profession,numeric,boolean,integer,text,text,text,boolean,jsonb,text)', 'public.fn_modifier_mission_etablissement_v4(uuid,text,text,text,public.type_profession,numeric,boolean,integer,text,text,text,boolean,jsonb,text)'),
      ('fn_confirmer_nature_tva_mission(uuid,text)', 'public.fn_confirmer_nature_tva_mission(uuid,text)'),
      ('fn_admin_lister_revues_tva_missions()', 'public.fn_admin_lister_revues_tva_missions()'),
      ('fn_admin_proposer_nature_tva_mission(uuid,text,text)', 'public.fn_admin_proposer_nature_tva_mission(uuid,text,text)'),
      ('fn_admin_resoudre_litige(uuid,text,text,numeric,numeric,text)', 'public.fn_admin_resoudre_litige(uuid,text,text,numeric,numeric,text)'),
      ('fn_admin_resoudre_litige_complement_honoraires(uuid,text,text,numeric,numeric)', 'public.fn_admin_resoudre_litige_complement_honoraires(uuid,text,text,numeric,numeric)'),
      ('fn_preserver_rectification_facture_honoraires()', 'public.fn_preserver_rectification_facture_honoraires()'),
      ('fn_admin_solde_correction_facture_honoraires(uuid)', 'public.fn_admin_solde_correction_facture_honoraires(uuid)'),
      ('fn_admin_resoudre_litige_intelligent(uuid,text,text,numeric,numeric,text)', 'public.fn_admin_resoudre_litige_intelligent(uuid,text,text,numeric,numeric,text)'),
      ('fn_ouvrir_litige_rate_limited(uuid,type_litige,text,uuid)', 'public.fn_ouvrir_litige_rate_limited(uuid,public.type_litige,text,uuid)'),
      ('fn_preparer_commission_complement_honoraires(uuid)', 'public.fn_preparer_commission_complement_honoraires(uuid)'),
      ('fn_preparer_commission_remplacement_honoraires(uuid)', 'public.fn_preparer_commission_remplacement_honoraires(uuid)'),
      ('fn_preparer_avoir_commission_honoraires(uuid)', 'public.fn_preparer_avoir_commission_honoraires(uuid)'),
      ('fn_lister_missions_a_facturer(date)', 'public.fn_lister_missions_a_facturer(date)'),
      ('fn_peut_lire_objet_jolene(text)', 'public.fn_peut_lire_objet_jolene(text)'),
      ('fn_emettre_document_facturation_honoraires(uuid,text,text)', 'public.fn_emettre_document_facturation_honoraires(uuid,text,text)'),
      ('fn_accepter_document_facturation_honoraires(uuid)', 'public.fn_accepter_document_facturation_honoraires(uuid)'),
      ('fn_tracer_contestation_facture_honoraires()', 'public.fn_tracer_contestation_facture_honoraires()')
  )
  SELECT pg_catalog.string_agg(r.signature, ', ' ORDER BY r.signature)
  INTO v_invalide
  FROM reviewed r
  LEFT JOIN pg_catalog.pg_proc p
    ON p.oid = pg_catalog.to_regprocedure(r.qualified_signature)
  LEFT JOIN private.security_definer_inventory i
    ON i.signature = r.signature
  WHERE p.oid IS NULL
     OR p.prosecdef IS NOT TRUE
     OR i.signature IS NULL
     OR i.definition_md5 IS DISTINCT FROM pg_catalog.md5(p.prosrc);

  IF v_invalide IS NOT NULL THEN
    RAISE EXCEPTION
      'Inventaire SECURITY DEFINER mandat v1.4 incomplet ou périmé : %',
      v_invalide;
  END IF;
END;
$assert_mandat_v14_security_definer_inventory$;

NOTIFY pgrst, 'reload schema';
