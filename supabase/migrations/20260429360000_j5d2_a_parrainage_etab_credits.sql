-- J5.D.2.A — Parrainage étab→étab + récompense Stripe 100€ (Option C)
--
-- Schéma DB :
--   * etablissements.code_parrainage (text unique format ETB-XXXXXX, auto-généré + backfill)
--   * etablissements.parraine_par_id (uuid FK self, nullable)
--   * Table parrainages_etablissements (statut PENDING/VALIDATED/EXPIRED, UNIQUE filleul_etab_id)
--   * Table credits_etablissement (montant_eur, motif, applique_le, facture_id nullable)
--
-- Logique :
--   * RPC fn_appliquer_parrainage_etab : filleul applique le code à l'inscription
--   * Trigger validation : AFTER UPDATE missions → si étab filleul a contrat signé + 1 mission ASSIGNEE/TERMINEE
--     → parrainage VALIDATED + crédit 100€ créé + notif parrain
--   * RPC fn_appliquer_credits_disponibles_etab : à brancher dans generate-invoice (next session)
--
-- Anti-abus : cap 10 parrainages validés, SIRET unique filleul, audit anomalie si > 5 mois.

-- 1) Colonnes étabs
ALTER TABLE public.etablissements
  ADD COLUMN IF NOT EXISTS code_parrainage TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS parraine_par_id UUID REFERENCES public.etablissements(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.fn_generer_code_parrainage_etab()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_code TEXT;
BEGIN
  LOOP
    v_code := 'ETB-' || UPPER(substring(encode(gen_random_bytes(6), 'base64') FROM 1 FOR 6));
    v_code := REGEXP_REPLACE(v_code, '[^A-Z0-9-]', '', 'g');
    WHILE LENGTH(v_code) < 10 LOOP
      v_code := v_code || UPPER(substring(encode(gen_random_bytes(2), 'base64') FROM 1 FOR 2));
      v_code := REGEXP_REPLACE(v_code, '[^A-Z0-9-]', '', 'g');
    END LOOP;
    v_code := substring(v_code FROM 1 FOR 10);
    EXIT WHEN NOT EXISTS (SELECT 1 FROM etablissements WHERE code_parrainage = v_code);
  END LOOP;
  RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_auto_code_parrainage_etab()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NEW.code_parrainage IS NULL OR NEW.code_parrainage = '' THEN
    NEW.code_parrainage := public.fn_generer_code_parrainage_etab();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_code_parrainage_etab ON public.etablissements;
CREATE TRIGGER trg_auto_code_parrainage_etab
  BEFORE INSERT ON public.etablissements
  FOR EACH ROW EXECUTE FUNCTION public.fn_auto_code_parrainage_etab();

UPDATE public.etablissements
SET code_parrainage = public.fn_generer_code_parrainage_etab()
WHERE code_parrainage IS NULL;

-- 3) Tables
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'parrainage_etab_statut') THEN
    CREATE TYPE public.parrainage_etab_statut AS ENUM ('PENDING','VALIDATED','EXPIRED');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.parrainages_etablissements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parrain_etab_id UUID NOT NULL REFERENCES public.etablissements(id) ON DELETE CASCADE,
  filleul_etab_id UUID NOT NULL REFERENCES public.etablissements(id) ON DELETE CASCADE,
  code_parrainage TEXT NOT NULL,
  statut public.parrainage_etab_statut NOT NULL DEFAULT 'PENDING',
  valide_le TIMESTAMPTZ,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  mis_a_jour_le TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (filleul_etab_id),
  CHECK (parrain_etab_id <> filleul_etab_id)
);

CREATE INDEX IF NOT EXISTS idx_parrainages_etab_parrain ON public.parrainages_etablissements (parrain_etab_id);
CREATE INDEX IF NOT EXISTS idx_parrainages_etab_filleul ON public.parrainages_etablissements (filleul_etab_id);

ALTER TABLE public.parrainages_etablissements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_parr_etab_select ON public.parrainages_etablissements;
CREATE POLICY pol_parr_etab_select ON public.parrainages_etablissements FOR SELECT
  USING (parrain_etab_id = mon_etablissement_id() OR filleul_etab_id = mon_etablissement_id() OR (SELECT est_admin()));

DROP POLICY IF EXISTS pol_parr_etab_insert ON public.parrainages_etablissements;
CREATE POLICY pol_parr_etab_insert ON public.parrainages_etablissements FOR INSERT
  WITH CHECK (filleul_etab_id = mon_etablissement_id() OR (SELECT est_admin()));

GRANT SELECT, INSERT ON public.parrainages_etablissements TO authenticated;
GRANT ALL ON public.parrainages_etablissements TO service_role;

-- 4) credits_etablissement
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'credit_etab_motif') THEN
    CREATE TYPE public.credit_etab_motif AS ENUM ('PARRAINAGE');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.credits_etablissement (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  etablissement_id UUID NOT NULL REFERENCES public.etablissements(id) ON DELETE CASCADE,
  montant_eur NUMERIC NOT NULL CHECK (montant_eur > 0),
  motif public.credit_etab_motif NOT NULL,
  parrainage_id UUID REFERENCES public.parrainages_etablissements(id) ON DELETE SET NULL,
  applique_le TIMESTAMPTZ,
  facture_id UUID REFERENCES public.factures(id) ON DELETE SET NULL,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_credits_etab ON public.credits_etablissement (etablissement_id, applique_le);

ALTER TABLE public.credits_etablissement ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_credits_etab_select ON public.credits_etablissement;
CREATE POLICY pol_credits_etab_select ON public.credits_etablissement FOR SELECT
  USING (etablissement_id = mon_etablissement_id() OR (SELECT est_admin()));

GRANT SELECT ON public.credits_etablissement TO authenticated;
GRANT ALL ON public.credits_etablissement TO service_role;

-- 5) Audit constraint étendu
ALTER TABLE public.journaux_audit DROP CONSTRAINT IF EXISTS journaux_audit_action_check;
ALTER TABLE public.journaux_audit ADD CONSTRAINT journaux_audit_action_check CHECK (action = ANY (ARRAY[
  'INSCRIPTION','CONNEXION','DECONNEXION','MODIFICATION_PROFIL','SUPPRESSION_COMPTE',
  'UPLOAD_DOCUMENT','TELECHARGEMENT_DOCUMENT','VERIFICATION_DOCUMENT','VERIFICATION_RPPS',
  'CREATION_MISSION','MODIFICATION_MISSION','ANNULATION_MISSION','CANDIDATURE','ASSIGNATION',
  'POINTAGE','SIGNATURE_CONTRAT','EVALUATION','PAIEMENT','FACTURATION',
  'DONNEES_PERSO_CONSULTATION','DONNEES_PERSO_EXPORT','DONNEES_PERSO_SUPPRESSION',
  'ADMIN_ACTION','SYSTEM','RIB_CONSULTE','RIB_PARTAGE','CONTRAT_SIGNE',
  'DOCUMENT_CONSULTATION','DOCUMENT_TELEVERSEMENT','DONNEES_PERSO_MODIFICATION',
  'EXPORT_RH_PAIE','FINANCE_FACTURE_PAYEE','MISSION_ASSIGNATION','MISSION_CREATION',
  'RGPD_EXPORT_DONNEES','RGPD_SUPPRESSION_COMPTE','RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT',
  'DEGEL_APPLIED','OVERRIDE_CHAMP_POST_GEL','GEL_APPLIED','OVERRIDE_ANTI_SEED',
  'CONNECT_METADATA_MANQUANTE','DOCUMENT_VERIFICATION_AUTO',
  'FACTURE_COMMISSION_PAYEE_SKIP_ANOMALIE','FACTURE_HONORAIRES_PAYEE_SKIP_ANOMALIE',
  'FINANCE_CHARGE_EXPIRED','FINANCE_CHARGE_FAILED','FINANCE_CHARGE_PENDING',
  'FINANCE_CHARGE_REFUNDED','FINANCE_DISPUTE_CLOSE','FINANCE_DISPUTE_OUVERTE',
  'FINANCE_PAYOUT_CANCELED','FINANCE_PAYOUT_CREATED','FINANCE_PAYOUT_FAILED',
  'FINANCE_PAYOUT_PAID','FINANCE_SEPA_CAPTURE','FINANCE_TRANSFER_CONNECT',
  'FINANCE_TRANSFER_CREATED','FINANCE_TRANSFER_FAILED','FINANCE_TRANSFER_REVERSED',
  'FINANCE_TRANSFER_UPDATED','STRIPE_CHECKOUT_ORPHANED_RECOVERED',
  'STRIPE_CONNECT_ACCOUNT_DELETED','ATTESTATION_SANTE_SIGNEE',
  'EXCLUSION_CREEE','EXCLUSION_SUPPRIMEE','FACTURE_GENEREE',
  'MISSION_ANNULATION_SERIE','MISSION_MODIFICATION','PAIEMENT_SOIGNANT_DECLARE_ETAB',
  'RECLAMATION_CREEE','ADMIN_CONSULTATION_ETABLISSEMENT','ADMIN_CONSULTATION_SOIGNANT',
  'DOCUMENT_SUPPRESSION','HEURES_EXTERNES_DECLAREES','MISSION_ANNULATION',
  'NOTE_HONORAIRES_GENEREE','PRESENCE_CONTESTATION','PRESENCE_POINTAGE_ARRIVEE',
  'PRESENCE_VALIDATION','PRESENCE_VALIDATION_LOT','RGPD_CONSENTEMENT_DONNE',
  'PAIEMENT_MONTANT_ECART','FACTURE_COMMISSION_CREATED_VIA_STRIPE',
  'TAUX_COMMISSION_MODIFIE','LITIGE_GEL_SCOPE_MODIFIE','PREFERENCE_NOTIFICATION_MODIFIEE',
  'NOTIFICATION_SKIPPED','SERIE_EMAIL_ENVOYE','SERIE_EMAIL_SKIPPED',
  'FILTRE_CREE','FILTRE_MODIFIE','FILTRE_SUPPRIME',
  'ALERTE_ACTIVEE','ALERTE_DESACTIVEE','ALERTE_ENVOYEE',
  'POOL_URGENCE_NOTIFICATIONS_ENVOYEES','POOL_URGENCE_ACCEPTATION_RAPIDE',
  'POOL_URGENCE_VALIDATION_ETAB','POOL_URGENCE_REFUS_ETAB','POOL_URGENCE_SMS_TOGGLE',
  'FAVORI_AJOUTE','FAVORI_RETIRE','SCORE_FIABILITE_PENALITE_LITIGE',
  'PARRAINAGE_ETAB_APPLIQUE','PARRAINAGE_ETAB_VALIDE','CREDIT_PARRAINAGE_CREE',
  'CREDIT_PARRAINAGE_APPLIQUE','PARRAINAGE_ETAB_ANOMALIE'
]));

-- 6) Notifications type CREDIT_PARRAINAGE
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (type = ANY (ARRAY[
  'CANDIDATURE_ACCEPTEE','CANDIDATURE_REFUSEE','CANDIDATURE_PROPOSEE',
  'MISSION_ACCEPTEE','MISSION_ANNULEE','MISSION_TERMINEE','MISSION_URGENTE','MISSION_NON_POURVUE','MISSION_ASSIGNEE',
  'CONTRAT_A_SIGNER','CONTRAT_SIGNE','FACTURE_EMISE','FACTURE_PAYEE',
  'DOCUMENT_EXPIRANT','RAPPEL_DOCUMENTS','DOCUMENT_VERIFIE','DOCUMENT_REJETE',
  'MESSAGE_RECU','MESSAGE_ADMIN','POINTAGE_ARRIVEE','POINTAGE_DEPART','EVALUATION_RECUE','PARRAINAGE',
  'RAPPEL_MISSION','POOL_URGENCE','POOL_URGENCE_ACCEPTATION','SYSTEM',
  'LITIGE_OUVERT','LITIGE_REPONSE','LITIGE_RESOLU','LITIGE_MEDIATION',
  'CHORUS_DEPOSEE','CHORUS_MISE_A_DISPOSITION','CHORUS_PAIEMENT_EN_COURS','CHORUS_PAIEMENT_COMPTABILISE','CHORUS_REJETEE',
  'FAVORI_NOUVELLE_MISSION','CREDIT_PARRAINAGE'
]));

-- 7) RPC fn_appliquer_parrainage_etab
CREATE OR REPLACE FUNCTION public.fn_appliquer_parrainage_etab(p_code TEXT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_filleul_id UUID;
  v_parrain_etab RECORD;
  v_filleul_siret TEXT;
  v_existing UUID;
  v_nb_valides INT;
BEGIN
  v_filleul_id := mon_etablissement_id();
  IF v_filleul_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous devez être connecté en tant qu''établissement');
  END IF;

  IF p_code IS NULL OR LENGTH(TRIM(p_code)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Code invalide');
  END IF;

  SELECT id, nom, siret INTO v_parrain_etab FROM etablissements
  WHERE code_parrainage = UPPER(TRIM(p_code));

  IF v_parrain_etab IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Code parrainage introuvable');
  END IF;

  IF v_parrain_etab.id = v_filleul_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous ne pouvez pas vous parrainer vous-même');
  END IF;

  SELECT siret INTO v_filleul_siret FROM etablissements WHERE id = v_filleul_id;
  IF EXISTS (
    SELECT 1 FROM parrainages_etablissements pe
    JOIN etablissements ef ON ef.id = pe.filleul_etab_id
    WHERE ef.siret = v_filleul_siret AND pe.statut = 'VALIDATED'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cet établissement (SIRET) a déjà bénéficié d''un parrainage validé');
  END IF;

  SELECT id INTO v_existing FROM parrainages_etablissements WHERE filleul_etab_id = v_filleul_id;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous avez déjà appliqué un code parrainage');
  END IF;

  SELECT COUNT(*) INTO v_nb_valides FROM parrainages_etablissements
  WHERE parrain_etab_id = v_parrain_etab.id AND statut = 'VALIDATED';
  IF v_nb_valides >= 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cet établissement parrain a atteint la limite de 10 parrainages validés');
  END IF;

  INSERT INTO parrainages_etablissements (parrain_etab_id, filleul_etab_id, code_parrainage, statut)
  VALUES (v_parrain_etab.id, v_filleul_id, UPPER(TRIM(p_code)), 'PENDING');

  UPDATE etablissements SET parraine_par_id = v_parrain_etab.id
  WHERE id = v_filleul_id AND parraine_par_id IS NULL;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_filleul_id,
    p_type_acteur := 'ADMIN_ETABLISSEMENT',
    p_action := 'PARRAINAGE_ETAB_APPLIQUE',
    p_type_ressource := 'etablissement',
    p_id_ressource := v_parrain_etab.id,
    p_details := jsonb_build_object('code_parrainage', UPPER(TRIM(p_code)), 'parrain_nom', v_parrain_etab.nom)
  );

  RETURN jsonb_build_object(
    'success', true,
    'parrain_nom', v_parrain_etab.nom,
    'message', 'Code parrainage appliqué. Votre parrain recevra 100€ de crédit dès votre 1ère mission active.'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_appliquer_parrainage_etab(TEXT) TO authenticated;

-- 8) RPC fn_mes_filleuls_etab
CREATE OR REPLACE FUNCTION public.fn_mes_filleuls_etab()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_etab_id UUID := mon_etablissement_id();
  v_result JSONB;
BEGIN
  IF v_etab_id IS NULL AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'parrainage_id', pe.id,
    'filleul_etab_id', e.id,
    'filleul_nom', e.nom,
    'filleul_ville', e.adresse_ville,
    'statut', pe.statut,
    'cree_le', pe.cree_le,
    'valide_le', pe.valide_le,
    'credit_montant_eur', (
      SELECT SUM(c.montant_eur) FROM credits_etablissement c
      WHERE c.parrainage_id = pe.id
    )
  ) ORDER BY pe.cree_le DESC), '[]'::jsonb)
  INTO v_result
  FROM parrainages_etablissements pe
  JOIN etablissements e ON e.id = pe.filleul_etab_id
  WHERE pe.parrain_etab_id = v_etab_id OR est_admin();

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_mes_filleuls_etab() TO authenticated;

-- 9) RPC fn_mes_credits_etab
CREATE OR REPLACE FUNCTION public.fn_mes_credits_etab()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_etab_id UUID := mon_etablissement_id();
  v_total_dispo NUMERIC;
  v_total_applique NUMERIC;
  v_credits JSONB;
BEGIN
  IF v_etab_id IS NULL AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  SELECT COALESCE(SUM(montant_eur) FILTER (WHERE applique_le IS NULL), 0),
         COALESCE(SUM(montant_eur) FILTER (WHERE applique_le IS NOT NULL), 0)
  INTO v_total_dispo, v_total_applique
  FROM credits_etablissement WHERE etablissement_id = v_etab_id OR est_admin();

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', c.id,
    'montant_eur', c.montant_eur,
    'motif', c.motif,
    'applique_le', c.applique_le,
    'facture_id', c.facture_id,
    'cree_le', c.cree_le
  ) ORDER BY c.cree_le DESC), '[]'::jsonb)
  INTO v_credits
  FROM credits_etablissement c WHERE c.etablissement_id = v_etab_id OR est_admin();

  RETURN jsonb_build_object(
    'total_disponible_eur', v_total_dispo,
    'total_applique_eur', v_total_applique,
    'credits', v_credits
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_mes_credits_etab() TO authenticated;

-- 10) RPC fn_appliquer_credits_disponibles_etab : à brancher dans generate-invoice (next session)
CREATE OR REPLACE FUNCTION public.fn_appliquer_credits_disponibles_etab(p_facture_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_facture RECORD;
  v_etab_id UUID;
  v_credits_dispo NUMERIC;
  v_a_deduire NUMERIC;
  v_credit RECORD;
  v_reste_a_deduire NUMERIC;
BEGIN
  IF NOT (est_admin() OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;

  SELECT id, etablissement_id, montant_ht, montant_ttc, statut, type_document
  INTO v_facture FROM factures WHERE id = p_facture_id;
  IF v_facture IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Facture introuvable');
  END IF;
  IF v_facture.statut <> 'BROUILLON' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Facture non modifiable (statut: ' || v_facture.statut || ')');
  END IF;
  IF v_facture.type_document <> 'FACTURE' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Crédits applicables uniquement sur FACTURE');
  END IF;

  v_etab_id := v_facture.etablissement_id;

  SELECT COALESCE(SUM(montant_eur), 0) INTO v_credits_dispo
  FROM credits_etablissement WHERE etablissement_id = v_etab_id AND applique_le IS NULL;

  IF v_credits_dispo <= 0 THEN
    RETURN jsonb_build_object('success', true, 'credit_applique_eur', 0, 'message', 'Aucun crédit disponible');
  END IF;

  v_a_deduire := LEAST(v_credits_dispo, v_facture.montant_ht);
  v_reste_a_deduire := v_a_deduire;

  FOR v_credit IN
    SELECT id, montant_eur FROM credits_etablissement
    WHERE etablissement_id = v_etab_id AND applique_le IS NULL
    ORDER BY cree_le ASC
  LOOP
    EXIT WHEN v_reste_a_deduire <= 0;
    UPDATE credits_etablissement SET applique_le = NOW(), facture_id = p_facture_id WHERE id = v_credit.id;
    v_reste_a_deduire := v_reste_a_deduire - v_credit.montant_eur;
  END LOOP;

  UPDATE factures
  SET montant_ht = GREATEST(0, montant_ht - v_a_deduire),
      montant_ttc = GREATEST(0, montant_ttc - v_a_deduire)
  WHERE id = p_facture_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_etab_id,
    p_type_acteur := 'SYSTEME',
    p_action := 'CREDIT_PARRAINAGE_APPLIQUE',
    p_type_ressource := 'facture',
    p_id_ressource := p_facture_id,
    p_details := jsonb_build_object('credit_eur', v_a_deduire, 'etablissement_id', v_etab_id)
  );

  RETURN jsonb_build_object('success', true, 'credit_applique_eur', v_a_deduire);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_appliquer_credits_disponibles_etab(UUID) TO service_role;

-- 11) Trigger validation parrainage
CREATE OR REPLACE FUNCTION public.fn_trg_valider_parrainage_etab()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_parrainage RECORD;
  v_filleul_etab RECORD;
  v_credit_id UUID;
  v_nb_validations_mois INT;
BEGIN
  IF NEW.statut NOT IN ('ASSIGNEE','TERMINEE') THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.statut = NEW.statut THEN RETURN NEW; END IF;

  SELECT * INTO v_parrainage FROM parrainages_etablissements
  WHERE filleul_etab_id = NEW.etablissement_id AND statut = 'PENDING';
  IF v_parrainage IS NULL THEN RETURN NEW; END IF;

  SELECT id, nom, contrat_valide INTO v_filleul_etab FROM etablissements WHERE id = NEW.etablissement_id;
  IF v_filleul_etab IS NULL OR COALESCE(v_filleul_etab.contrat_valide, false) = false THEN RETURN NEW; END IF;

  UPDATE parrainages_etablissements
  SET statut = 'VALIDATED', valide_le = NOW(), mis_a_jour_le = NOW()
  WHERE id = v_parrainage.id;

  INSERT INTO credits_etablissement (etablissement_id, montant_eur, motif, parrainage_id)
  VALUES (v_parrainage.parrain_etab_id, 100, 'PARRAINAGE', v_parrainage.id)
  RETURNING id INTO v_credit_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_parrainage.parrain_etab_id, p_type_acteur := 'SYSTEME',
    p_action := 'CREDIT_PARRAINAGE_CREE', p_type_ressource := 'parrainage_etab', p_id_ressource := v_parrainage.id,
    p_details := jsonb_build_object('credit_id', v_credit_id, 'montant_eur', 100, 'filleul_etab_id', NEW.etablissement_id)
  );

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := NEW.etablissement_id, p_type_acteur := 'SYSTEME',
    p_action := 'PARRAINAGE_ETAB_VALIDE', p_type_ressource := 'parrainage_etab', p_id_ressource := v_parrainage.id,
    p_details := jsonb_build_object('parrain_etab_id', v_parrainage.parrain_etab_id, 'mission_id', NEW.id)
  );

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
  VALUES (
    v_parrainage.parrain_etab_id, 'ETABLISSEMENT', 'CREDIT_PARRAINAGE',
    '🎉 +100€ de crédit Jolene !',
    'Votre filleul ' || COALESCE(v_filleul_etab.nom, 'établissement') || ' a activé son compte. 100€ de crédit ont été ajoutés et seront déduits de votre prochaine facture commission.',
    '/etablissement/parrainage'
  );

  SELECT COUNT(*) INTO v_nb_validations_mois FROM parrainages_etablissements
  WHERE parrain_etab_id = v_parrainage.parrain_etab_id
    AND statut = 'VALIDATED' AND valide_le >= DATE_TRUNC('month', NOW());
  IF v_nb_validations_mois > 5 THEN
    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := v_parrainage.parrain_etab_id, p_type_acteur := 'SYSTEME',
      p_action := 'PARRAINAGE_ETAB_ANOMALIE', p_type_ressource := 'etablissement',
      p_id_ressource := v_parrainage.parrain_etab_id,
      p_details := jsonb_build_object('nb_validations_mois', v_nb_validations_mois)
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_valider_parrainage_etab ON public.missions;
CREATE TRIGGER trg_valider_parrainage_etab
  AFTER INSERT OR UPDATE OF statut ON public.missions
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_valider_parrainage_etab();

NOTIFY pgrst, 'reload schema';
