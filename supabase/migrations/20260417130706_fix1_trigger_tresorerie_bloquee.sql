-- ============================================================
-- CP-LITIGES-7a FIX 1 — Trigger maj_tresorerie_bloquee (cache SQL-side)
-- ============================================================
-- `litiges.montant_tresorerie_bloquee` (NUMERIC(12,2), ajouté par
-- CP-LITIGES-1) est un cache calculé = SUM(montant_ht) des factures
-- gelées par ce litige (statut_litige = 'EN_ATTENTE_LITIGE').
--
-- Avant ce FIX : le cache était prévu pour être rafraîchi par cron,
-- ce qui laisse une fenêtre d'incohérence entre le gel/dégel d'une
-- facture et la mise à jour du cache (utilisé pour tri dashboard admin).
--
-- Après ce FIX : un trigger AFTER INSERT/UPDATE sur factures_honoraires
-- recalcule le cache en synchrone pour les litiges concernés (OLD+NEW
-- en cas de changement de FK litige_id).
--
-- La fonction fn_recalculer_tresorerie_bloquee(UUID) est aussi exposée
-- pour un éventuel appel manuel / cron de rattrapage.
-- ============================================================

BEGIN;

-- Fonction utilitaire idempotente : recalcule pour un litige donné.
CREATE OR REPLACE FUNCTION public.fn_recalculer_tresorerie_bloquee(
  p_litige_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_total NUMERIC(12,2);
BEGIN
  IF p_litige_id IS NULL THEN
    RETURN;
  END IF;

  SELECT COALESCE(SUM(montant_ht), 0)
    INTO v_total
    FROM public.factures_honoraires
   WHERE litige_id = p_litige_id
     AND statut_litige = 'EN_ATTENTE_LITIGE';

  UPDATE public.litiges
     SET montant_tresorerie_bloquee = v_total
   WHERE id = p_litige_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_recalculer_tresorerie_bloquee(UUID)
  TO service_role;

COMMENT ON FUNCTION public.fn_recalculer_tresorerie_bloquee(UUID) IS
  'CP-LITIGES-7a FIX 1 — recalcule litiges.montant_tresorerie_bloquee '
  'pour un litige (SUM montant_ht des factures gelées EN_ATTENTE_LITIGE). '
  'Appelée en synchrone par le trigger trg_maj_tresorerie_bloquee ; '
  'utilisable aussi en rattrapage (cron / admin).';

-- Fonction trigger : recalcule pour OLD.litige_id et NEW.litige_id.
CREATE OR REPLACE FUNCTION public.trg_fn_maj_tresorerie_bloquee()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.fn_recalculer_tresorerie_bloquee(NEW.litige_id);
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.litige_id IS DISTINCT FROM OLD.litige_id THEN
      PERFORM public.fn_recalculer_tresorerie_bloquee(OLD.litige_id);
    END IF;
    PERFORM public.fn_recalculer_tresorerie_bloquee(NEW.litige_id);
  END IF;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.trg_fn_maj_tresorerie_bloquee() IS
  'CP-LITIGES-7a FIX 1 — trigger function : appelle fn_recalculer_'
  'tresorerie_bloquee pour OLD.litige_id (si FK change) et NEW.litige_id.';

DROP TRIGGER IF EXISTS trg_maj_tresorerie_bloquee
  ON public.factures_honoraires;

-- UPDATE OF inclut litige_id pour traiter le changement de FK.
CREATE TRIGGER trg_maj_tresorerie_bloquee
  AFTER INSERT OR UPDATE OF montant_ht, montant_ttc, statut_litige, litige_id
  ON public.factures_honoraires
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_fn_maj_tresorerie_bloquee();

COMMIT;
