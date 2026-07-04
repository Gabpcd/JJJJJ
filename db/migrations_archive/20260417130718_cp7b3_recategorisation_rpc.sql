-- ============================================================
-- CP-LITIGES-7b-3 — RPC recatégorisation litiges legacy
-- ============================================================
-- Permet à un admin de corriger le type_litige d'un litige marqué
-- `type_legacy = TRUE` ET `type_litige = 'AUTRE'` pour lever le flag
-- legacy et affecter la bonne catégorie métier. Le trigger CP2
-- `fn_trg_litige_mapping_categorie` recalcule `categorie_litige`
-- automatiquement depuis `type_litige` → pas besoin de la poser ici.
--
-- Sécurité : SECURITY DEFINER + guard est_admin() (retour JSONB error
-- pour cohérence avec fn_confirmer_remboursement_avoir / fn_admin_*).
-- Audit : fn_ecrire_audit `LITIGE_RECATEGORISATION_LEGACY`.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_admin_recategoriser_litige_legacy(
  p_litige_id    UUID,
  p_nouveau_type public.type_litige
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_id       UUID := auth.uid();
  v_litige        public.litiges%ROWTYPE;
  v_ancien_type   public.type_litige;
  v_nouvelle_cat  public.categorie_litige;
BEGIN
  IF v_user_id IS NULL OR NOT public.est_admin() THEN
    RETURN jsonb_build_object('error', 'Admin requis.');
  END IF;

  SELECT * INTO v_litige FROM public.litiges WHERE id = p_litige_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Litige introuvable.');
  END IF;

  IF v_litige.type_legacy IS DISTINCT FROM TRUE THEN
    RETURN jsonb_build_object(
      'error', 'Ce litige n''est pas marqué legacy — recatégorisation interdite.'
    );
  END IF;

  IF v_litige.type_litige IS DISTINCT FROM 'AUTRE'::public.type_litige THEN
    RETURN jsonb_build_object(
      'error', 'Seuls les litiges legacy de type AUTRE peuvent être recatégorisés.'
    );
  END IF;

  IF p_nouveau_type IS NULL THEN
    RETURN jsonb_build_object('error', 'Nouveau type requis.');
  END IF;

  v_ancien_type := v_litige.type_litige;

  -- UPDATE : le trigger BEFORE UPDATE fn_trg_litige_mapping_categorie
  -- recalcule categorie_litige depuis type_litige automatiquement.
  UPDATE public.litiges
     SET type_litige = p_nouveau_type,
         type_legacy = FALSE
   WHERE id = p_litige_id
  RETURNING categorie_litige INTO v_nouvelle_cat;

  PERFORM public.fn_ecrire_audit(
    v_user_id, 'ADMIN', 'LITIGE_RECATEGORISATION_LEGACY',
    'litige', p_litige_id, NULL,
    jsonb_build_object(
      'ancien_type', v_ancien_type,
      'nouveau_type', p_nouveau_type,
      'nouvelle_categorie', v_nouvelle_cat,
      'motif_original', v_litige.motif
    ),
    NULL, NULL
  );

  RETURN jsonb_build_object(
    'success', TRUE,
    'litige_id', p_litige_id,
    'ancien_type', v_ancien_type,
    'nouveau_type', p_nouveau_type,
    'nouvelle_categorie', v_nouvelle_cat,
    'type_legacy', FALSE
  );
END;
$$;

COMMENT ON FUNCTION public.fn_admin_recategoriser_litige_legacy(UUID, public.type_litige) IS
  'CP-LITIGES-7b-3 — recatégorise un litige legacy (type_legacy=TRUE, '
  'type_litige=AUTRE). Le trigger fn_trg_litige_mapping_categorie '
  'recalcule categorie_litige. Lève le flag legacy, audit RGPD '
  'LITIGE_RECATEGORISATION_LEGACY. Admin-only.';

REVOKE EXECUTE ON FUNCTION public.fn_admin_recategoriser_litige_legacy(UUID, public.type_litige) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_admin_recategoriser_litige_legacy(UUID, public.type_litige)
  TO authenticated;

COMMIT;
