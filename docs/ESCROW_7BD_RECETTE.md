# Escrow 7b-D — Recette (PR 7, §4.7)

> À dérouler **en mode TEST Stripe**, avant tout flip du flag
> `feature_paiement_rapide_actif`. Le flip ne se fait qu'après recette verte
> **et** validation du diff légal (PR 6, mergée). Ce document est le plan
> exécutable ; il n'allume PAS le flag.

## 0. Pré-requis

- **Clés Stripe TEST** dans les secrets Supabase du projet de test (ou du prod
  basculé en clé test le temps de la recette — à éviter en prod).
- Un **établissement de test** avec mandat SEPA configuré (`setup-sepa`,
  `mode_paiement_commission = 'SEPA_DEBIT'`, `stripe_sepa_payment_method_id`
  renseigné via le PaymentMethod SEPA de test
  `pm_card_...`/`sepa_debit` de Stripe test).
- Un **soignant libéral de test** avec compte Stripe Connect Express **COMPLET**
  et `payouts.schedule.interval = manual` (créé après la PR 1, ou basculé via
  `scripts/backfill-payouts-manual.ts`).
- **Flag armé à 1 UNIQUEMENT sur l'environnement de test** :
  `UPDATE parametres_systeme SET valeur = 1 WHERE cle = 'feature_paiement_rapide_actif';`
  (à remettre à 0 après la recette si l'env de test est partagé).

## 1. Cartes / IBAN de test Stripe utiles

| Cas | Moyen de test Stripe |
|---|---|
| SEPA débit réussi | PaymentMethod SEPA test IBAN `DE89370400440532013000` |
| SEPA débit qui échoue (R-transaction) | IBAN test qui déclenche `charge.failed` (cf. Stripe testing SEPA) |
| Dispute | déclencher `charge.dispute.created` depuis le Dashboard test ou l'API |

## 2. Scénario nominal (débit → validation → release)

1. **Confirmer une mission** libérale (statut → `ASSIGNEE`) pour l'étab + soignant
   de test, éligibles ⚡.
   - ✅ Attendu : une ligne `paiements_escrow` en `INITIE` est créée (trigger
     `trg_escrow_creer_a_confirmation`), avec `methode_debit` = `VIREMENT_INSTANTANE`
     si 1ʳᵉ mission de l'étab, sinon `SEPA` si marge ≥ 8 j.
   - ✅ Audit `ESCROW_INITIE` présent.
2. **Déclencher le débit** : soit attendre le cron `escrow-debit-echeance`
   (horaire), soit l'invoquer manuellement (POST authentifié vault).
   - ✅ Attendu : `paiements_escrow.stripe_payment_intent_id` renseigné, PI SEPA
     en `processing`. Audit `ESCROW_DEBIT_INITIE`. Ligne
     `escrow_exposition_releases` en `ACTIF` (fenêtre 8 semaines).
   - ✅ Vérifier côté Stripe : destination charge (application_fee = commission,
     `transfer_data[destination]` = compte connecté soignant). **`on_behalf_of`
     ABSENT (retiré v15 : Jolene merchant of record via mandat SEPA)** — la recette
     asserte d'ailleurs son absence (S2.2).
3. **Settlement SEPA** (webhook `payment_intent.succeeded`, quelques jours en
   réel / immédiat en test si simulé).
   - ✅ Attendu : `paiements_escrow.statut = DEBITE`. Audit `ESCROW_DEBITE`.
4. **Valider les présences** (étab valide, ou auto-72h).
   - ✅ Attendu : le trigger `trg_escrow_release_on_validation` enfile
     `escrow_release_queue` (EN_ATTENTE) — uniquement quand plus aucune présence
     bloquante (gate 7b-B).
5. **Release** : cron `escrow-release` (*/15).
   - ✅ Attendu : si fonds `available` sur le solde connecté → `payouts.create`
     manuel → `paiements_escrow.statut = PAYE`, `stripe_payout_id` renseigné,
     `escrow_release_queue.statut = TRAITE`, compteur de confiance de l'étab +1.
     Audit `ESCROW_RELEASE_PAYE`.
   - ✅ Webhook `payout.paid` (metadata `ESCROW_RELEASE`) → audit, PAS de
     matching legacy sur `stripe_transfers` (early-return).

## 3. Scénario remboursement AVANT release (reverse_transfer — A5/A6)

1. Escrow en `DEBITE` (pas encore payé). Appeler
   `fn_escrow_rembourser(escrow_id, honoraires_cents, p_annulation_totale := true)`.
   - ✅ Attendu : ligne `stripe_refunds_queue` avec `reverse_transfer = true`,
     `refund_application_fee_cts = commission` (annulation totale → 100 %),
     `absorbe_plateforme = false`, queue `EN_ATTENTE` et
     `paiements_escrow.statut = REMBOURSE_EN_COURS`. Le statut antérieur
     `DEBITE` est mémorisé ; l'exposition n'est pas encore soldée.
2. Cron `process-stripe-refunds`.
   - ✅ Attendu : `refunds.create` avec `reverse_transfer: true` +
     `refund_application_fee: true` → les fonds reviennent du compte connecté,
     l'étab est remboursé et la commission aussi. Tant que Stripe n'a pas
     confirmé `succeeded`, l'escrow reste `REMBOURSE_EN_COURS`. Après cette
     confirmation seulement : queue → `TRAITE`, escrow → `REMBOURSE`,
     exposition → `REGLE`.
   - ✅ Si Stripe confirme `failed` ou `canceled` : queue → `ECHEC`, escrow
     restauré à `DEBITE`, exposition non soldée.
3. Garde-fou **réduction partielle pré-release** : appeler avec
   `p_annulation_totale := false` et la moitié des `honoraires_cents`.
   - ✅ Attendu : réponse structurée `{ success: false, error:
     "REMBOURSEMENT_PARTIEL_PRE_RELEASE_INDISPONIBLE",
     manual_resolution_required: true }` ; aucune ligne ajoutée à
     `stripe_refunds_queue`, escrow toujours `DEBITE`, exposition inchangée.

## 4. Scénario A10.9 — remboursement APRÈS release (absorption plateforme)

1. Escrow en `PAYE` (payout parti). Appeler `fn_escrow_rembourser(...)`, avec
   un montant total ou partiel.
   - ✅ Attendu : le partiel est supporté ; sa commission remboursée est
     calculée au prorata. `absorbe_plateforme = true`,
     `reverse_transfer = false`, queue → `EN_ATTENTE`, escrow →
     `REMBOURSE_EN_COURS` avec statut antérieur `PAYE` mémorisé.
2. Cron `process-stripe-refunds`.
   - ✅ Attendu : `refunds.create` **sans** `reverse_transfer` → Jolene absorbe
     depuis le solde plateforme, **aucun** mouvement forcé sur le compte de la
     soignante (règle A5).
   - ✅ Après confirmation Stripe `succeeded` seulement : queue → `TRAITE`,
     escrow → `REMBOURSE`, exposition → `REGLE`. La soignante conserve
     l'affichage « Versé » puisqu'elle a déjà reçu 100 %.
   - ✅ Si Stripe confirme `failed` ou `canceled` : queue → `ECHEC`, escrow
     restauré à `PAYE`, exposition non soldée.

## 5. Scénario A10.8 — validation avant disponibilité des fonds

1. Valider les présences alors que le PI SEPA est encore `processing` (fonds pas
   `available`).
   - ✅ Attendu : `escrow-release` trouve `available < honoraires` → laisse la
     queue en `EN_ATTENTE`, bumpe `prochaine_tentative_le` (+30 min), audit
     `ESCROW_RELEASE_ATTENTE_FONDS`. Aucune erreur visible côté soignante.
2. Quand les fonds deviennent `available` (prochain passage du cron).
   - ✅ Attendu : release normal → `PAYE`.

## 6. Scénario échec de débit (relance J+3 + gel ⚡)

1. Débit SEPA qui échoue (`payment_intent.payment_failed`, IBAN test rejet).
   - ✅ Attendu : `fn_escrow_marquer_incident('ECHEC')` → `paiements_escrow.statut
     = ECHOUE`, `relance_prevue_le = now + 3j`, l'établissement est **gelé**
     (`escrow_etablissement_etat.gele = true`), `missions_sans_incident` remis à 0.
     Audit `ESCROW_ETAB_GELE`.
2. ✅ Vérifier que le badge ⚡ disparaît des payloads mission de cet étab
   (`fn_etablissements_safe` / `fn_obtenir_missions_swipe` → `paiement_rapide =
   false` car `fn_escrow_etab_eligible` renvoie false sur étab gelé).
3. Déblocage admin : `fn_admin_degeler_escrow_etablissement(etab_id)`.
   - ✅ Attendu : gel levé, audit `ESCROW_ETAB_DEGELE`.

## 7. Scénario dispute SEPA

1. Déclencher `charge.dispute.created` sur une charge escrow.
   - ✅ Attendu : `fn_escrow_marquer_incident('DISPUTE')` → `paiements_escrow.statut
     = DISPUTE`, étab gelé. La dispute est absorbée par Jolene sous le plafond
     §11.1 (pas de reversal forcé sur la soignante).

## 8. Scénario plafond §11.1 (A2)

1. Confirmer des missions escrow jusqu'à approcher le plafond
   (`escrow_plafond_base_cents` = 2 000 € par défaut).
   - ✅ Attendu : au-delà du plafond, `fn_escrow_etab_eligible(etab, montant)`
     renvoie false → **pas de nouvelle ligne escrow**, la mission reste en régime
     standard (badge ⚡ absent), publication normale.
2. Après 3 missions escrow sans incident (`missions_sans_incident ≥ 3`), le
   plafond passe à `escrow_plafond_confiance_cents` = 5 000 €.
   - ✅ Attendu : `fn_escrow_plafond_cents(etab)` renvoie 5 000 €.

## 9. Critère de sortie (GO flip)

Tous les scénarios 2→8 verts **ET** diff légal PR 6 mergé. Alors seulement :

- Migration de flip : `UPDATE parametres_systeme SET valeur = 1 WHERE cle =
  'feature_paiement_rapide_actif';` (via PR migration mergée — jamais MCP direct).
- **Dans la même PR de flip** : réécriture de la copie `PageStripeConnect.tsx`
  (retirer « sans délai / virements automatiques ») et du KPI
  `fn_mes_revenus_connect` (ne plus compter `TRANSFERE` comme reçu) — découvertes
  3 et 4 du mapping.

Tant que ces scénarios ne sont pas tous verts, le flag **reste à 0**.
