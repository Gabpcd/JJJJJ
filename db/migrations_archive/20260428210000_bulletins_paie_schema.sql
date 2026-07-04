-- Module bulletin de paie SALARIE Jolene — art. R3243-1 Code du travail.
--
-- Jolene génère les bulletins de paie pour les soignants SALARIE/MIXTE
-- (différenciateur métier vs marketplaces classiques qui laissent ça
-- aux établissements clients).
--
-- Architecture :
--   - Le calcul brut/net/cotisations est déjà fait par
--     fn_calculer_cotisations(p_mission_id) qui peuple cotisations_sociales.
--   - Cette migration ajoute la table bulletins_paie qui matérialise un
--     "document bulletin" avec numéro séquentiel immutable, période,
--     totaux dénormalisés (pour requêtes rapides) et lien storage.
--   - Le PDF est généré côté client à partir du bulletin + cotisations.
--   - Trigger auto : à chaque mission TERMINEE pour CDDU/SALARIE on
--     crée le bulletin (et on calcule les cotisations si besoin).
--
-- Conservation : 5 ans minimum (art. L3243-4 CTW). En pratique, la
-- table reste indéfiniment ; trigger append-only empêche DELETE.

-- ───────────────────────────────────────────────────────────────────────
-- TABLE

CREATE TABLE IF NOT EXISTS public.bulletins_paie (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  numero_bulletin text NOT NULL,
  soignant_id uuid NOT NULL REFERENCES public.soignants(id),
  mission_id uuid NOT NULL REFERENCES public.missions(id),
  etablissement_id uuid NOT NULL REFERENCES public.etablissements(id),

  -- Période de paie (= période de la mission)
  periode_debut date NOT NULL,
  periode_fin date NOT NULL,

  -- Totaux dénormalisés (lecture rapide ; détail dans cotisations_sociales)
  salaire_brut numeric NOT NULL,
  total_cotisations_salariales numeric NOT NULL DEFAULT 0,
  total_cotisations_patronales numeric NOT NULL DEFAULT 0,
  net_avant_impot numeric NOT NULL,
  ifm numeric NOT NULL DEFAULT 0,
  icp numeric NOT NULL DEFAULT 0,

  -- Statut + dates
  statut text NOT NULL DEFAULT 'EMIS'
    CHECK (statut IN ('EMIS','PAYE','ANNULE')),
  date_emission date NOT NULL DEFAULT CURRENT_DATE,
  date_paiement date,

  -- Document
  pdf_s3_key text,

  -- Audit
  cree_le timestamptz NOT NULL DEFAULT now(),
  modifie_le timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT bulletins_paie_unique_mission UNIQUE (mission_id),
  CONSTRAINT bulletins_paie_unique_numero_par_soignant UNIQUE (soignant_id, numero_bulletin)
);

CREATE INDEX IF NOT EXISTS idx_bp_soignant ON public.bulletins_paie(soignant_id);
CREATE INDEX IF NOT EXISTS idx_bp_mission ON public.bulletins_paie(mission_id);
CREATE INDEX IF NOT EXISTS idx_bp_etablissement ON public.bulletins_paie(etablissement_id);
CREATE INDEX IF NOT EXISTS idx_bp_periode ON public.bulletins_paie(periode_debut DESC);

-- ───────────────────────────────────────────────────────────────────────
-- NUMÉROTATION SÉQUENTIELLE PAR SOIGNANT
-- Format : BP-{SIRET8 ou UUID8}-{ANNEE}-{SEQ5}, cohérent avec les factures.

CREATE OR REPLACE FUNCTION public.fn_next_bulletin_paie_number(p_soignant_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_siret text;
  v_annee text := to_char(CURRENT_DATE, 'YYYY');
  v_seq int;
  v_lock_key bigint;
BEGIN
  -- Advisory lock par soignant pour éviter les collisions de séquence
  v_lock_key := ('x' || substring(md5(p_soignant_id::text || ':bp') from 1 for 16))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);

  SELECT COALESCE(siret_liberal, '') INTO v_siret FROM soignants WHERE id = p_soignant_id;
  IF v_siret IS NULL OR length(v_siret) < 8 THEN
    v_siret := substring(p_soignant_id::text from 1 for 8);
  ELSE
    v_siret := substring(v_siret from 1 for 8);
  END IF;

  SELECT COALESCE(MAX(
    NULLIF(regexp_replace(numero_bulletin, '^BP-[^-]+-[0-9]{4}-', ''), '')::int
  ), 0) + 1
  INTO v_seq
  FROM bulletins_paie
  WHERE soignant_id = p_soignant_id
    AND numero_bulletin LIKE 'BP-' || v_siret || '-' || v_annee || '-%';

  RETURN format('BP-%s-%s-%s', v_siret, v_annee, lpad(v_seq::text, 5, '0'));
END;
$$;

-- ───────────────────────────────────────────────────────────────────────
-- CRÉATION DU BULLETIN
-- Idempotent : si un bulletin existe déjà pour la mission, on le retourne.
-- Sinon, on calcule les cotisations (si pas déjà fait) et on insère.

CREATE OR REPLACE FUNCTION public.fn_creer_bulletin_paie(p_mission_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_mission RECORD;
  v_soignant RECORD;
  v_cot RECORD;
  v_bulletin_id uuid;
  v_numero text;
  v_existing uuid;
  v_type_exercice text;
BEGIN
  SELECT m.id, m.soignant_assigne_id, m.etablissement_id, m.statut, m.debut_le, m.fin_le, m.duree_heures, m.taux_horaire_base
  INTO v_mission
  FROM missions m WHERE m.id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable');
  END IF;
  IF v_mission.soignant_assigne_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Aucun soignant assigné');
  END IF;
  IF v_mission.statut <> 'TERMINEE' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission non terminée');
  END IF;

  -- Vérifier idempotence : déjà émis pour cette mission ?
  SELECT id INTO v_existing FROM bulletins_paie WHERE mission_id = p_mission_id;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'bulletin_id', v_existing, 'already_existed', true);
  END IF;

  -- Vérifier que le soignant est SALARIE ou MIXTE (pas LIBERAL pur)
  SELECT id, type_exercice INTO v_soignant
  FROM soignants WHERE id = v_mission.soignant_assigne_id;
  v_type_exercice := COALESCE(v_soignant.type_exercice, 'SALARIE');
  IF v_type_exercice = 'LIBERAL' THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Bulletin de paie non applicable : le soignant est LIBERAL (la rémunération passe par facture honoraires)');
  END IF;

  -- S'assurer que les cotisations sont calculées
  SELECT * INTO v_cot FROM cotisations_sociales WHERE mission_id = p_mission_id;
  IF v_cot IS NULL THEN
    PERFORM public.fn_calculer_cotisations(p_mission_id);
    SELECT * INTO v_cot FROM cotisations_sociales WHERE mission_id = p_mission_id;
    IF v_cot IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'Calcul cotisations échoué');
    END IF;
  END IF;

  -- Si le calcul a renvoyé type CDDU mais soignant marqué MIXTE/SALARIE :
  -- on continue (CDDU est le type de contrat applicable côté Jolene).
  IF v_cot.type_contrat = 'REMPLACEMENT_LIBERAL' THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Mission classée libéral : pas de bulletin (facture honoraires uniquement)');
  END IF;

  v_numero := public.fn_next_bulletin_paie_number(v_mission.soignant_assigne_id);

  INSERT INTO bulletins_paie (
    numero_bulletin, soignant_id, mission_id, etablissement_id,
    periode_debut, periode_fin,
    salaire_brut, total_cotisations_salariales, total_cotisations_patronales,
    net_avant_impot, ifm, icp,
    statut, date_emission
  ) VALUES (
    v_numero, v_mission.soignant_assigne_id, p_mission_id, v_mission.etablissement_id,
    v_mission.debut_le::date, v_mission.fin_le::date,
    v_cot.salaire_brut, v_cot.total_cotisations_salariales, v_cot.total_cotisations_patronales,
    v_cot.net_avant_impot, COALESCE(v_cot.ifm, 0), COALESCE(v_cot.icp, 0),
    'EMIS', CURRENT_DATE
  )
  RETURNING id INTO v_bulletin_id;

  -- Audit
  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_mission.soignant_assigne_id,
    p_type_acteur := 'SOIGNANT',
    p_action := 'BULLETIN_PAIE_EMIS',
    p_type_ressource := 'bulletin_paie',
    p_id_ressource := v_bulletin_id,
    p_details := jsonb_build_object(
      'numero_bulletin', v_numero,
      'mission_id', p_mission_id,
      'salaire_brut', v_cot.salaire_brut,
      'net_avant_impot', v_cot.net_avant_impot
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'bulletin_id', v_bulletin_id,
    'numero_bulletin', v_numero,
    'salaire_brut', v_cot.salaire_brut,
    'net_avant_impot', v_cot.net_avant_impot
  );
END;
$$;

-- ───────────────────────────────────────────────────────────────────────
-- TRIGGER AUTO : mission passe en TERMINEE → bulletin créé pour SALARIE/MIXTE

CREATE OR REPLACE FUNCTION public.fn_auto_creer_bulletin_paie_trg()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_type text;
BEGIN
  IF NEW.statut = 'TERMINEE' AND (OLD.statut IS DISTINCT FROM 'TERMINEE') AND NEW.soignant_assigne_id IS NOT NULL THEN
    SELECT type_exercice INTO v_type FROM soignants WHERE id = NEW.soignant_assigne_id;
    IF COALESCE(v_type, 'SALARIE') <> 'LIBERAL' THEN
      -- Best-effort : on n'arrête pas le passage en TERMINEE si la création échoue.
      BEGIN
        PERFORM public.fn_creer_bulletin_paie(NEW.id);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'fn_auto_creer_bulletin_paie_trg: %', SQLERRM;
      END;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_creer_bulletin_paie ON public.missions;
CREATE TRIGGER trg_auto_creer_bulletin_paie
  AFTER UPDATE OF statut ON public.missions
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_auto_creer_bulletin_paie_trg();

-- ───────────────────────────────────────────────────────────────────────
-- IMMUTABILITÉ — un bulletin EMIS verrouille brut / cotisations / numéro / dates.

CREATE OR REPLACE FUNCTION public.fn_protect_bulletin_paie_immutability()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
  v_role text := current_setting('role', true);
  v_is_admin boolean;
BEGIN
  -- Bypass : service_role et admins peuvent tout
  v_is_admin := COALESCE((SELECT public.est_admin()), false);
  IF v_role = 'service_role' OR v_is_admin THEN
    NEW.modifie_le := now();
    RETURN NEW;
  END IF;

  IF OLD.statut = 'EMIS' OR OLD.statut = 'PAYE' THEN
    IF NEW.numero_bulletin IS DISTINCT FROM OLD.numero_bulletin
       OR NEW.salaire_brut IS DISTINCT FROM OLD.salaire_brut
       OR NEW.total_cotisations_salariales IS DISTINCT FROM OLD.total_cotisations_salariales
       OR NEW.net_avant_impot IS DISTINCT FROM OLD.net_avant_impot
       OR NEW.periode_debut IS DISTINCT FROM OLD.periode_debut
       OR NEW.periode_fin IS DISTINCT FROM OLD.periode_fin
       OR NEW.soignant_id IS DISTINCT FROM OLD.soignant_id
       OR NEW.mission_id IS DISTINCT FROM OLD.mission_id
       OR NEW.etablissement_id IS DISTINCT FROM OLD.etablissement_id
       OR NEW.date_emission IS DISTINCT FROM OLD.date_emission
    THEN
      RAISE EXCEPTION 'Bulletin de paie % : modification interdite après émission (art. L3243-4 CTW). Champs verrouillés : numero, montants, dates, identités.',
        OLD.numero_bulletin;
    END IF;
  END IF;

  NEW.modifie_le := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_bp_immutability ON public.bulletins_paie;
CREATE TRIGGER trg_bp_immutability
  BEFORE UPDATE ON public.bulletins_paie
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_protect_bulletin_paie_immutability();

-- DELETE bloqué (sauf service_role / admin)
CREATE OR REPLACE FUNCTION public.fn_block_bulletin_paie_delete()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
  v_role text := current_setting('role', true);
  v_is_admin boolean := COALESCE((SELECT public.est_admin()), false);
BEGIN
  IF v_role = 'service_role' OR v_is_admin THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'Bulletin de paie % : suppression interdite (conservation 5 ans art. L3243-4 CTW)', OLD.numero_bulletin;
END;
$$;

DROP TRIGGER IF EXISTS trg_bp_no_delete ON public.bulletins_paie;
CREATE TRIGGER trg_bp_no_delete
  BEFORE DELETE ON public.bulletins_paie
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_block_bulletin_paie_delete();

-- ───────────────────────────────────────────────────────────────────────
-- RLS

ALTER TABLE public.bulletins_paie ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bp_select_own ON public.bulletins_paie;
CREATE POLICY bp_select_own ON public.bulletins_paie
  FOR SELECT TO authenticated
  USING (
    soignant_id = auth.uid()
    OR etablissement_id = public.mon_etablissement_id()
    OR public.est_admin()
  );

-- Pas de policy INSERT/UPDATE/DELETE pour authenticated : seules les RPC
-- SECURITY DEFINER (fn_creer_bulletin_paie, etc.) peuvent écrire.
-- service_role + admin gardent leur bypass via les triggers.

GRANT SELECT ON public.bulletins_paie TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_creer_bulletin_paie(uuid) TO authenticated;

-- ───────────────────────────────────────────────────────────────────────
-- LISTE BULLETINS DU SOIGNANT CONNECTÉ (pour la page UI)

CREATE OR REPLACE FUNCTION public.fn_mes_bulletins_paie()
RETURNS TABLE (
  id uuid,
  numero_bulletin text,
  mission_id uuid,
  etablissement_id uuid,
  etablissement_nom text,
  mission_intitule text,
  periode_debut date,
  periode_fin date,
  salaire_brut numeric,
  total_cotisations_salariales numeric,
  net_avant_impot numeric,
  ifm numeric,
  icp numeric,
  statut text,
  date_emission date,
  date_paiement date,
  pdf_s3_key text,
  cree_le timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT bp.id, bp.numero_bulletin, bp.mission_id, bp.etablissement_id,
    e.nom AS etablissement_nom, m.intitule AS mission_intitule,
    bp.periode_debut, bp.periode_fin,
    bp.salaire_brut, bp.total_cotisations_salariales, bp.net_avant_impot,
    bp.ifm, bp.icp, bp.statut, bp.date_emission, bp.date_paiement,
    bp.pdf_s3_key, bp.cree_le
  FROM bulletins_paie bp
  LEFT JOIN missions m ON m.id = bp.mission_id
  LEFT JOIN etablissements e ON e.id = bp.etablissement_id
  WHERE bp.soignant_id = auth.uid()
  ORDER BY bp.periode_debut DESC, bp.cree_le DESC;
$$;

GRANT EXECUTE ON FUNCTION public.fn_mes_bulletins_paie() TO authenticated;

NOTIFY pgrst, 'reload schema';
