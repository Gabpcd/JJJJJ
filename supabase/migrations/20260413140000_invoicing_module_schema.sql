-- ═══════════════════════════════════════════════════════════════════════════
-- PR1 — Module Facturation & Affacturage : schéma, RLS, triggers, RPCs
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Cette migration :
-- 1. Étend factures_honoraires avec les colonnes factor/chorus
-- 2. Crée chorus_submissions (historique PISTE)
-- 3. Crée invoice_audit_log (traçabilité fiscale, append-only)
-- 4. Crée factoring_partners (partenaires affacturage)
-- 5. Étend mandats_facturation_signatures (pdf_url, revoked_at)
-- 6. Crée next_invoice_number(pro_id) — séquence continue par soignant
-- 7. Triggers d'immutabilité sur factures_honoraires
-- 8. Trigger append-only sur invoice_audit_log
-- 9. Trigger auto-audit sur factures_honoraires
-- 10. RLS complètes

-- ─── 1. ALTER factures_honoraires ─────────────────────────────────────────

ALTER TABLE public.factures_honoraires
  ADD COLUMN IF NOT EXISTS factor_assigned BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS factor_id UUID,
  ADD COLUMN IF NOT EXISTS subrogation_mention TEXT,
  ADD COLUMN IF NOT EXISTS facturx_xml_url TEXT,
  ADD COLUMN IF NOT EXISTS chorus_submission_id UUID,
  ADD COLUMN IF NOT EXISTS chorus_submission_status TEXT,
  ADD COLUMN IF NOT EXISTS chorus_last_sync_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS is_public_sector BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS siret_client TEXT,
  ADD COLUMN IF NOT EXISTS service_code_chorus TEXT,
  ADD COLUMN IF NOT EXISTS engagement_juridique TEXT,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- Index pour les requêtes fréquentes
CREATE INDEX IF NOT EXISTS idx_fh_soignant ON public.factures_honoraires(soignant_id);
CREATE INDEX IF NOT EXISTS idx_fh_statut ON public.factures_honoraires(statut);
CREATE INDEX IF NOT EXISTS idx_fh_chorus ON public.factures_honoraires(chorus_submission_status)
  WHERE chorus_submission_status IS NOT NULL;

-- ─── 2. chorus_submissions ────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.chorus_submissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id UUID NOT NULL REFERENCES public.factures_honoraires(id) ON DELETE RESTRICT,
  piste_request_id TEXT,
  payload_xml TEXT,
  response_raw JSONB,
  submission_type TEXT NOT NULL DEFAULT 'SAISIE_API'
    CHECK (submission_type IN ('DEPOT_PDF_API', 'SAISIE_API')),
  status TEXT NOT NULL DEFAULT 'pending_credentials'
    CHECK (status IN ('pending_credentials', 'pending', 'submitted', 'accepted', 'rejected', 'error')),
  error_code TEXT,
  error_message TEXT,
  submitted_at TIMESTAMPTZ,
  last_checked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chorus_sub_invoice ON public.chorus_submissions(invoice_id);
CREATE INDEX IF NOT EXISTS idx_chorus_sub_status ON public.chorus_submissions(status);

-- FK retour sur factures_honoraires
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'fk_fh_chorus_submission'
  ) THEN
    ALTER TABLE public.factures_honoraires
      ADD CONSTRAINT fk_fh_chorus_submission
      FOREIGN KEY (chorus_submission_id)
      REFERENCES public.chorus_submissions(id);
  END IF;
END $$;

-- ─── 3. invoice_audit_log (append-only, traçabilité fiscale) ──────────────

CREATE TABLE IF NOT EXISTS public.invoice_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id UUID NOT NULL REFERENCES public.factures_honoraires(id) ON DELETE RESTRICT,
  action TEXT NOT NULL,
  actor_id UUID,
  payload_before JSONB,
  payload_after JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ial_invoice ON public.invoice_audit_log(invoice_id);
CREATE INDEX IF NOT EXISTS idx_ial_created ON public.invoice_audit_log(created_at DESC);

-- ─── 4. factoring_partners ────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.factoring_partners (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_name TEXT NOT NULL,
  siret TEXT NOT NULL,
  iban TEXT NOT NULL,
  bic TEXT,
  address TEXT,
  contact_email TEXT,
  subrogation_template TEXT,
  webhook_url TEXT,
  api_credentials JSONB, -- chiffré côté applicatif
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- FK factor_id sur factures_honoraires
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'fk_fh_factor'
  ) THEN
    ALTER TABLE public.factures_honoraires
      ADD CONSTRAINT fk_fh_factor
      FOREIGN KEY (factor_id)
      REFERENCES public.factoring_partners(id);
  END IF;
END $$;

-- ─── 5. Extend mandats_facturation_signatures ─────────────────────────────

ALTER TABLE public.mandats_facturation_signatures
  ADD COLUMN IF NOT EXISTS pdf_url TEXT,
  ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ;

-- ─── 6. next_invoice_number(pro_id) — séquence continue par soignant ──────
--
-- Format : JOL-{SIRET_8_PREMIERS}-{ANNEE}-{SEQ_5_CHIFFRES}
-- Exemple : JOL-12345678-2026-00001
-- La séquence est continue, sans trou, par soignant. Pas de reset annuel
-- automatique (mais le préfixe annuel rend le numéro lisible).
-- Utilise un advisory lock par soignant pour la concurrence.

CREATE OR REPLACE FUNCTION public.next_invoice_number(p_soignant_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_siret TEXT;
  v_year TEXT;
  v_last_seq INTEGER;
  v_next_seq INTEGER;
  v_lock_key BIGINT;
  v_result TEXT;
BEGIN
  -- Advisory lock basé sur le hash du soignant_id pour la concurrence
  v_lock_key := ('x' || left(md5(p_soignant_id::text), 15))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);

  -- Récupérer les 8 premiers chars du SIRET (ou UUID si pas de SIRET)
  SELECT COALESCE(LEFT(siret_liberal, 8), LEFT(p_soignant_id::text, 8))
  INTO v_siret
  FROM soignants WHERE id = p_soignant_id;

  IF v_siret IS NULL THEN
    v_siret := LEFT(p_soignant_id::text, 8);
  END IF;

  v_year := TO_CHAR(CURRENT_DATE, 'YYYY');

  -- Trouver le dernier numéro séquentiel pour ce soignant (toutes années confondues)
  SELECT MAX(
    NULLIF(SPLIT_PART(numero_facture, '-', 4), '')::INTEGER
  ) INTO v_last_seq
  FROM factures_honoraires
  WHERE soignant_id = p_soignant_id
    AND numero_facture LIKE 'JOL-%';

  v_next_seq := COALESCE(v_last_seq, 0) + 1;

  v_result := 'JOL-' || v_siret || '-' || v_year || '-' || LPAD(v_next_seq::TEXT, 5, '0');

  RETURN v_result;
END;
$$;

-- ─── 7. Trigger immutabilité sur factures_honoraires ──────────────────────
--
-- Une fois EMISE, seuls statut, chorus_*, factor_*, updated_at sont modifiables.
-- service_role et admin peuvent bypass.

CREATE OR REPLACE FUNCTION public.fn_protect_facture_honoraire_immutability()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Bypass pour service_role et admin
  IF COALESCE(current_setting('request.jwt.claim.role', true) = 'service_role', auth.uid() IS NULL) THEN
    RETURN NEW;
  END IF;
  IF est_admin() THEN RETURN NEW; END IF;

  -- Avant EMISE, tout est modifiable
  IF OLD.statut = 'BROUILLON' THEN RETURN NEW; END IF;

  -- Après EMISE : montants, numéro, identités sont verrouillés
  IF NEW.montant_ht IS DISTINCT FROM OLD.montant_ht THEN
    RAISE EXCEPTION 'Facture honoraire émise : montant_ht verrouillé';
  END IF;
  IF NEW.montant_ttc IS DISTINCT FROM OLD.montant_ttc THEN
    RAISE EXCEPTION 'Facture honoraire émise : montant_ttc verrouillé';
  END IF;
  IF NEW.montant_tva IS DISTINCT FROM OLD.montant_tva THEN
    RAISE EXCEPTION 'Facture honoraire émise : montant_tva verrouillé';
  END IF;
  IF NEW.taux_tva IS DISTINCT FROM OLD.taux_tva THEN
    RAISE EXCEPTION 'Facture honoraire émise : taux_tva verrouillé';
  END IF;
  IF NEW.numero_facture IS DISTINCT FROM OLD.numero_facture THEN
    RAISE EXCEPTION 'Facture honoraire émise : numero_facture verrouillé';
  END IF;
  IF NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN
    RAISE EXCEPTION 'Facture honoraire émise : soignant_id verrouillé';
  END IF;
  IF NEW.etablissement_id IS DISTINCT FROM OLD.etablissement_id THEN
    RAISE EXCEPTION 'Facture honoraire émise : etablissement_id verrouillé';
  END IF;
  IF NEW.mission_id IS DISTINCT FROM OLD.mission_id THEN
    RAISE EXCEPTION 'Facture honoraire émise : mission_id verrouillé';
  END IF;
  IF NEW.date_emission IS DISTINCT FROM OLD.date_emission THEN
    RAISE EXCEPTION 'Facture honoraire émise : date_emission verrouillée';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fh_immutability ON public.factures_honoraires;
CREATE TRIGGER trg_fh_immutability
  BEFORE UPDATE ON public.factures_honoraires
  FOR EACH ROW
  EXECUTE FUNCTION fn_protect_facture_honoraire_immutability();

-- ─── 8. Trigger append-only sur invoice_audit_log ─────────────────────────

CREATE OR REPLACE FUNCTION public.fn_block_audit_log_delete()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  RAISE EXCEPTION 'DELETE interdit sur invoice_audit_log (traçabilité fiscale)';
END;
$$;

DROP TRIGGER IF EXISTS trg_ial_no_delete ON public.invoice_audit_log;
CREATE TRIGGER trg_ial_no_delete
  BEFORE DELETE ON public.invoice_audit_log
  FOR EACH ROW
  EXECUTE FUNCTION fn_block_audit_log_delete();

-- Bloquer aussi les UPDATE
CREATE OR REPLACE FUNCTION public.fn_block_audit_log_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  RAISE EXCEPTION 'UPDATE interdit sur invoice_audit_log (traçabilité fiscale)';
END;
$$;

DROP TRIGGER IF EXISTS trg_ial_no_update ON public.invoice_audit_log;
CREATE TRIGGER trg_ial_no_update
  BEFORE UPDATE ON public.invoice_audit_log
  FOR EACH ROW
  EXECUTE FUNCTION fn_block_audit_log_update();

-- ─── 9. Trigger auto-audit sur factures_honoraires ────────────────────────
-- Chaque UPDATE insère automatiquement une ligne d'audit

CREATE OR REPLACE FUNCTION public.fn_fh_auto_audit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  INSERT INTO invoice_audit_log (invoice_id, action, actor_id, payload_before, payload_after)
  VALUES (
    NEW.id,
    CASE
      WHEN TG_OP = 'INSERT' THEN 'CREATED'
      WHEN OLD.statut IS DISTINCT FROM NEW.statut THEN 'STATUS_CHANGE:' || OLD.statut || '->' || NEW.statut
      ELSE 'UPDATED'
    END,
    COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid),
    CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END,
    to_jsonb(NEW)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fh_auto_audit_insert ON public.factures_honoraires;
CREATE TRIGGER trg_fh_auto_audit_insert
  AFTER INSERT ON public.factures_honoraires
  FOR EACH ROW
  EXECUTE FUNCTION fn_fh_auto_audit();

DROP TRIGGER IF EXISTS trg_fh_auto_audit_update ON public.factures_honoraires;
CREATE TRIGGER trg_fh_auto_audit_update
  AFTER UPDATE ON public.factures_honoraires
  FOR EACH ROW
  EXECUTE FUNCTION fn_fh_auto_audit();

-- ─── 10. updated_at auto ──────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_fh_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fh_updated_at ON public.factures_honoraires;
CREATE TRIGGER trg_fh_updated_at
  BEFORE UPDATE ON public.factures_honoraires
  FOR EACH ROW
  EXECUTE FUNCTION fn_fh_updated_at();

-- ─── 11. RLS ──────────────────────────────────────────────────────────────

-- chorus_submissions
ALTER TABLE public.chorus_submissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "chorus_sub_select" ON public.chorus_submissions;
CREATE POLICY "chorus_sub_select" ON public.chorus_submissions
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM factures_honoraires fh
      WHERE fh.id = chorus_submissions.invoice_id
        AND (fh.soignant_id = auth.uid() OR est_admin())
    )
  );

DROP POLICY IF EXISTS "chorus_sub_insert_service" ON public.chorus_submissions;
CREATE POLICY "chorus_sub_insert_service" ON public.chorus_submissions
  FOR INSERT TO authenticated
  WITH CHECK (est_admin());

DROP POLICY IF EXISTS "chorus_sub_update_service" ON public.chorus_submissions;
CREATE POLICY "chorus_sub_update_service" ON public.chorus_submissions
  FOR UPDATE TO authenticated
  USING (est_admin());

-- invoice_audit_log
ALTER TABLE public.invoice_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ial_select" ON public.invoice_audit_log;
CREATE POLICY "ial_select" ON public.invoice_audit_log
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM factures_honoraires fh
      WHERE fh.id = invoice_audit_log.invoice_id
        AND (fh.soignant_id = auth.uid() OR est_admin())
    )
  );

-- INSERT autorisé (trigger auto-audit + service_role)
DROP POLICY IF EXISTS "ial_insert" ON public.invoice_audit_log;
CREATE POLICY "ial_insert" ON public.invoice_audit_log
  FOR INSERT TO authenticated
  WITH CHECK (true);

-- factoring_partners
ALTER TABLE public.factoring_partners ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "fp_select" ON public.factoring_partners;
CREATE POLICY "fp_select" ON public.factoring_partners
  FOR SELECT TO authenticated
  USING (active = true OR est_admin());

DROP POLICY IF EXISTS "fp_admin" ON public.factoring_partners;
CREATE POLICY "fp_admin" ON public.factoring_partners
  FOR ALL TO authenticated
  USING (est_admin());

-- factures_honoraires — compléter les policies existantes
-- Le soignant voit ses propres factures
DROP POLICY IF EXISTS "fh_select_own" ON public.factures_honoraires;
CREATE POLICY "fh_select_own" ON public.factures_honoraires
  FOR SELECT TO authenticated
  USING (soignant_id = auth.uid() OR etablissement_id = mon_etablissement_id() OR est_admin());

-- L'établissement ne peut lire que les factures qui lui sont adressées
-- (déjà couvert par la policy ci-dessus via mon_etablissement_id())

-- ─── 12. Auto-detect secteur public sur INSERT ───────────────────────────

CREATE OR REPLACE FUNCTION public.fn_fh_detect_public_sector()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.etablissement_id IS NOT NULL THEN
    SELECT est_secteur_public INTO NEW.is_public_sector
    FROM etablissements WHERE id = NEW.etablissement_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fh_detect_public ON public.factures_honoraires;
CREATE TRIGGER trg_fh_detect_public
  BEFORE INSERT ON public.factures_honoraires
  FOR EACH ROW
  EXECUTE FUNCTION fn_fh_detect_public_sector();
