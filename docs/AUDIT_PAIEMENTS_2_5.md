# Audit §2.5 — Système de paiement existant (Lot 7 v2, préalable escrow)

> Audit du 02/07/2026 — checklist §2.5 du Lot 7 v2. Conditionne le chantier
> 7b-D « escrow : débit à la confirmation, release après validation des présences ».

## Deux circuits distincts

- **A. Honoraires soignant** (mission libérale) → Stripe **Connect**
  (`stripe-connect-pay-mission` + webhook `transfers.create`).
- **B. Commission Jolene** → capturée à la source dans le paiement Connect
  (libéral + Connect), ou facturée séparément via la table `factures`
  (SEPA `sepa-auto-charge`, carte `create-invoice-payment`, mensuel
  `fn_auto_facturation_mensuelle`).

## Récapitulatif checklist

| # | Point | Statut | Synthèse |
|---|-------|--------|----------|
| 1 | Débit unique mission + 15 % | ⚠️ | Vrai uniquement pour libéral + Connect (Checkout 2 line items → 1 PaymentIntent). Autres circuits = commission seule, honoraires hors Stripe. |
| 2 | Split honoraires/commission, pas de fonds via Jolene | ⚠️ | Modèle « separate charges & transfers » : destinations correctes, MAIS les honoraires transitent par le **solde Stripe plateforme Jolene** avant transfert (pas de `application_fee_amount`/`transfer_data.destination`). |
| 3 | Mandat + factures art. 289 I-2 + réconciliation | ✅/⚠️ | Mentions 289 I-2 OK (`facture-honoraires-pdf.ts:121,408`), garde mandat OK (`generate-invoice:755`). Commission = table `factures` générique ; la facturation mensuelle agrège 1 facture ↔ N missions (asymétrique). |
| 4 | Webhooks → statuts UI | ✅/⚠️ | Couverture très large + idempotence stricte (`fn_stripe_webhook_event_is_new`). Manque `payment_intent.payment_failed` ; matching payout best-effort ; sessions non-paid silencieuses. |
| 5 | Échec paiement → statut + relance | ❌ | Échec visible (EN_RETARD + email `CHARGE_FAILED_ETAB`) mais **aucune relance automatique** : une facture EN_RETARD est définitivement exclue du cron SEPA (`sepa-auto-charge:57-61`). |
| 6 | Remboursement / litige | ✅ | Circuit admin-gated complet (AVOIR → `stripe_refunds_queue`/`process-stripe-refunds` ou virement manuel + `fn_confirmer_remboursement_avoir`), filet webhook `charge.refunded`. Manque `reverse_transfer` côté Connect. |
| 7 | Salarié : zéro Stripe soignante | ✅/⚠️ | Double défense anti-Stripe (`CONTRAT_SALARIE_NON_STRIPE`, `CONTRAT_SALARIE_NON_FACTURE_HONORAIRES`). Commission salariée via `fn_auto_facturation_mensuelle` — **non schedulée** (déclenchement admin manuel). |

## Trous bloquants pour l'escrow (7b-D)

1. **Modèle actuel = paiement post-mission** : `stripe-connect-pay-mission` exige
   `statut = TERMINEE` avant tout débit. « Débit à la confirmation » = inversion
   de la logique (autorisation/débit à l'assignation, capture/release après
   validation des présences).
2. **Pas de phase « held »** : le transfer part immédiatement dans le webhook
   `checkout.session.completed` — aucun état séquestre. Pattern candidat :
   `capture_method: manual` (déjà utilisé dans `create-mission-payment` pour la
   commission) ou transfer différé conditionné à la validation.
3. **Détention des fonds soignant sur le balance Stripe Jolene** — question
   réglementaire (cantonnement / agent PSP / destination charge) à trancher
   AVANT d'allonger la durée de détention avec un escrow. ⚠️ À soumettre à
   l'avocat avec le point placement/mise à disposition.
4. **Aucune gestion d'échec asynchrone SEPA** (R-transactions J+3/J+5) ni
   relance : bloquant pour un préfinancement SEPA à la confirmation.
5. **Aucun lien code entre validation des présences et release** — le gate
   facturation 7b-B (migration `20260702154526`) crée le premier maillon ;
   le release escrow devra s'y brancher.
6. **Réconciliation commission mensuelle 1↔N** + **reverse_transfer manquant** :
   un escrow avec remboursements partiels exige l'adossement strict
   1 mission ↔ 1 paiement ↔ 1 facture.
7. **Cron `fn_auto_facturation_mensuelle` non branché** : à fiabiliser avant
   d'industrialiser tout circuit financier automatique.

## Ce que 7b livre déjà (indépendamment de l'escrow)

- **Gate facturation** (migration `20260702154526`) : la facture FINALE attend
  la validation des présences (manuelle 1 tap ou auto-72h) ; une présence
  contestée gèle finale ET hebdo. Le déclencheur « présences validées » existe
  désormais dans la chaîne — le release escrow s'y branchera.
- **F4 notation 1-tap** : validation étab = valider + noter (un geste) ;
  check-out soignante = sheet 1-tap skippable. Migration `20260702154904`
  (mission EN_COURS + départ pointé = notable).
