-- Compléments du module bulletin de paie / facturation suite aux limitations
-- documentées dans docs/module-bulletin-paie.md et module-facturation.md.
--
-- 1. Colonne soignants.numero_securite_sociale (R3243-1 mention obligatoire).
-- 2. Colonne etablissements.convention_collective (R3243-1).
-- 3. fn_cumul_annuel_paie : RPC pour le cumul annuel à afficher dans le PDF.
-- 4. Trigger trg_bp_passage_paye : flippe bulletins_paie.statut='PAYE' quand
--    paiements_soignant.confirme_par_soignant devient true pour la même mission.

-- ───────────────────────────────────────────────────────────────────────
-- 1. NUMÉRO SÉCURITÉ SOCIALE SOIGNANTS

ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS numero_securite_sociale text;

-- Validation soft (15 chiffres, pas de cast) — laisse passer la valeur null
-- ou l'absence. Le format INSEE complet (1+année+mois+département+commune
-- +ordre+clé) sera vérifié côté UI/RPC à l'enregistrement.
ALTER TABLE public.soignants
  DROP CONSTRAINT IF EXISTS soignants_numero_securite_sociale_format;
ALTER TABLE public.soignants
  ADD CONSTRAINT soignants_numero_securite_sociale_format
  CHECK (numero_securite_sociale IS NULL OR numero_securite_sociale ~ '^[0-9]{13,15}$');

COMMENT ON COLUMN public.soignants.numero_securite_sociale IS
  'NIR (Numéro INSEE de Sécurité Sociale). Mention obligatoire bulletin de paie art. R3243-1 CTW. 13 chiffres ou 15 (avec clé).';

-- ───────────────────────────────────────────────────────────────────────
-- 2. CONVENTION COLLECTIVE ETABLISSEMENTS

ALTER TABLE public.etablissements
  ADD COLUMN IF NOT EXISTS convention_collective text;

COMMENT ON COLUMN public.etablissements.convention_collective IS
  'Convention collective applicable (texte libre IDCC + libellé, ex. "IDCC 0029 - Hospitalisation privée"). Mention obligatoire bulletin de paie art. R3243-1 CTW.';

-- ───────────────────────────────────────────────────────────────────────
-- 3. RPC CUMUL ANNUEL DE PAIE
-- Pour la mention "Cumul annuel" sur le bulletin (R3243-1).

CREATE OR REPLACE FUNCTION public.fn_cumul_annuel_paie(
  p_soignant_id uuid,
  p_annee integer DEFAULT NULL,
  p_jusqu_au date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  WITH params AS (
    SELECT
      COALESCE(p_annee, EXTRACT(YEAR FROM COALESCE(p_jusqu_au, CURRENT_DATE))::int) AS annee,
      COALESCE(p_jusqu_au, CURRENT_DATE) AS jusqu_au
  )
  SELECT jsonb_build_object(
    'annee', (SELECT annee FROM params),
    'jusqu_au', (SELECT jusqu_au FROM params),
    'nombre_bulletins', COALESCE(COUNT(bp.id), 0),
    'cumul_brut', COALESCE(SUM(bp.salaire_brut), 0),
    'cumul_cotisations_salariales', COALESCE(SUM(bp.total_cotisations_salariales), 0),
    'cumul_cotisations_patronales', COALESCE(SUM(bp.total_cotisations_patronales), 0),
    'cumul_net_avant_impot', COALESCE(SUM(bp.net_avant_impot), 0),
    'cumul_ifm', COALESCE(SUM(bp.ifm), 0),
    'cumul_icp', COALESCE(SUM(bp.icp), 0)
  )
  FROM bulletins_paie bp, params
  WHERE bp.soignant_id = p_soignant_id
    AND EXTRACT(YEAR FROM bp.periode_debut) = params.annee
    AND bp.periode_debut <= params.jusqu_au
    AND bp.statut <> 'ANNULE'
    AND (
      bp.soignant_id = auth.uid()
      OR public.est_admin()
    );
$$;

GRANT EXECUTE ON FUNCTION public.fn_cumul_annuel_paie(uuid, integer, date) TO authenticated;

-- ───────────────────────────────────────────────────────────────────────
-- 4. TRIGGER : passage automatique en PAYE quand paiement confirmé

CREATE OR REPLACE FUNCTION public.fn_bp_passage_paye_trg()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- Quand un paiement passe à confirme_par_soignant=true (ou statut='CONFIRME'),
  -- on flippe le bulletin lié à la même mission en PAYE (best-effort).
  IF (NEW.confirme_par_soignant = true AND COALESCE(OLD.confirme_par_soignant, false) = false)
     OR (NEW.statut = 'CONFIRME' AND COALESCE(OLD.statut, '') <> 'CONFIRME') THEN
    BEGIN
      UPDATE public.bulletins_paie
      SET statut = 'PAYE',
          date_paiement = COALESCE(NEW.date_paiement, CURRENT_DATE)
      WHERE mission_id = NEW.mission_id
        AND statut = 'EMIS';
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'fn_bp_passage_paye_trg: %', SQLERRM;
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_bp_passage_paye ON public.paiements_soignant;
CREATE TRIGGER trg_bp_passage_paye
  AFTER UPDATE ON public.paiements_soignant
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_bp_passage_paye_trg();

NOTIFY pgrst, 'reload schema';
