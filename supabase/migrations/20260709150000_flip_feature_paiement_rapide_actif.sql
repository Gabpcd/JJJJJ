-- Flip ⚡ : activation du paiement rapide (escrow 7b-D) en production.
--
-- Bascule le paramètre global feature_paiement_rapide_actif de 0 → 1. Lu par
-- fn_param_num() dans : le trigger de création d'escrow
-- (fn_trg_escrow_creer_a_confirmation), l'exposition mission (paiement_rapide),
-- le bonus scoring ⚡ et fn_mes_missions.
--
-- GATING (l'escrow ne se déclenche PAS globalement) : même à 1, un
-- paiements_escrow n'est créé QUE pour une mission LIBERAL dont
-- l'établissement a mode_paiement_commission='SEPA_DEBIT' + un mandat SEPA
-- (stripe_sepa_payment_method_id) ET est éligible (fn_escrow_etab_eligible :
-- pas gelé, sous plafond A2), le soignant devant avoir un compte Connect
-- COMPLET pour le débit et le payout. Aucun effet rétroactif : seules les
-- confirmations de mission POSTÉRIEURES au flip enfilent un escrow.
--
-- Validé par la recette escrow de bout en bout en mode test Stripe (run #12,
-- 09/07/2026 : 14 PASS · 0 FAIL · 0 MANUEL, invariant solde plateforme vérifié
-- à chaque étape — les honoraires vont directement au compte connecté du
-- soignant, seule la commission entre sur le solde Jolene). Prérequis prod
-- déployés : mandat SEPA sans on_behalf_of, trigger enqueue au DEBITE
-- (20260709130000), audit escrow direct.
--
-- Rollback : UPDATE public.parametres_systeme SET valeur = 0
--            WHERE cle = 'feature_paiement_rapide_actif';

INSERT INTO public.parametres_systeme (cle, valeur, label, description, categorie, cablee, maj_le)
VALUES (
  'feature_paiement_rapide_actif', 1,
  'Paiement rapide ⚡ (escrow) actif',
  'Active le séquestre escrow 7b-D : débit SEPA à la confirmation, virement au soignant après validation des présences. Gating : mission LIBERAL + étab SEPA éligible.',
  'paiements', true, now()
)
ON CONFLICT (cle) DO UPDATE
  SET valeur = 1, cablee = true, maj_le = now();
