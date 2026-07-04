
-- Fix 1: heures_externes — soignant ne peut PAS s'auto-valider
DROP POLICY IF EXISTS pol_hext_insert ON public.heures_externes;
CREATE POLICY pol_hext_insert ON public.heures_externes
  FOR INSERT TO authenticated
  WITH CHECK (
    est_admin()
    OR (
      soignant_id = auth.uid()
      AND statut = 'EN_ATTENTE'
      AND validee_par IS NULL
      AND validee_le IS NULL
      AND motif_rejet IS NULL
    )
  );

-- Fix 2: conversions_liberal — soignant ne peut PAS s'auto-attribuer des avantages financiers
DROP POLICY IF EXISTS pol_conv_insert ON public.conversions_liberal;
CREATE POLICY pol_conv_insert ON public.conversions_liberal
  FOR INSERT TO authenticated
  WITH CHECK (
    est_admin()
    OR (
      soignant_id = auth.uid()
      AND free_transition_eligible = false
      AND taux_prise_en_charge = 0
      AND montant_pris_en_charge = 0
    )
  );
