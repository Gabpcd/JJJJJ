# Tests manuels CP-STRIPE-4 — Checklist Gabrielle

Scope : **13 events webhook Stripe ajoutés** (H6 RÉSOLU) + **6 nouveaux templates email** + **migration DDL** `stripe_transfers` (dispute + reversed_le + ANNULEE).

## Prérequis

- ✅ Migration `20260420130000_cp_stripe_4_webhook_events` appliquée (vérifiée via script SQL).
- ✅ Stripe Dashboard > Webhooks : 13 nouveaux events activés (confirmé par Gabrielle).
- 🟡 Workflow GitHub Actions post-push CP-STRIPE-4 : édite functions (stripe-webhook v213+, send-email v212+).

## Scénarios automatisables (SQL)

```bash
psql "$DB_URL" -f tests/stripe/cp-stripe-4.test.sql
```

Couvre :
- [1.1] 5 colonnes DDL présentes
- [2.1] CHECK statut accepte `ANNULEE`
- [3.1] CHECK dispute_statut valide
- [4.1] 4 index ajoutés
- [5.1-5.6] UPDATE handlers (payout.paid, transfer.failed/reversed, dispute created/closed, payout.canceled)
- [6.1] charge.refunded → AVOIR passe REMBOURSEE

Attendu : tous `[X.Y] OK`.

## Scénarios end-to-end (Stripe Dashboard > Events → Resend)

### 🔴 Critiques (priorité 1)

#### A. `charge.failed` — paiement étab échoué
1. Simuler via Stripe Dashboard : Resend un event `charge.failed` sur une facture commission EMISE existante.
2. **Vérifier** :
   - [ ] `factures.statut` passe `EN_RETARD`
   - [ ] Email `CHARGE_FAILED_ETAB` reçu par l'étab (subject : "⚠️ Paiement échoué — Facture X")
   - [ ] Audit `FINANCE_CHARGE_FAILED` dans journaux_audit

#### B. `charge.dispute.created` — chargeback étab
1. Utiliser carte test `4000 0000 0000 0259` (Stripe test card dispute) pour simuler un chargeback.
2. Attendre webhook `charge.dispute.created` (peut prendre quelques minutes).
3. **Vérifier** :
   - [ ] `stripe_transfers.dispute_id`, `dispute_statut='OUVERT'`, `dispute_reason`, `dispute_cree_le` remplis
   - [ ] Email `DISPUTE_OUVERTE_ADMIN` reçu par tous les admins (subject : "⚠️ Litige Stripe ouvert — action sous 7 jours")
   - [ ] Audit `FINANCE_DISPUTE_OUVERTE`

#### C. `payout.failed` — payout → banque échoué
1. Impossible à reproduire en test card (payout prod uniquement). Alternative : Resend event depuis Stripe Dashboard.
2. **Vérifier** :
   - [ ] Transfers matchés passent `ECHOUE` + erreur remplie
   - [ ] Email admin `PAYOUT_FAILED_ADMIN` reçu
   - [ ] Email soignant `PAYOUT_FAILED_SOIGNANT` reçu avec message simplifié ("Votre IBAN est invalide" ou "Votre compte bancaire semble fermé")
   - [ ] Audit `FINANCE_PAYOUT_FAILED`

### 🟡 Importants (priorité 2)

#### D. `payout.paid` — argent arrivé soignant
1. Cycle complet : flow Connect pay-mission en test → attendre arrival_date Stripe.
2. **Vérifier** :
   - [ ] Transfers matchés passent `PAYE` + `paye_le` rempli
   - [ ] Email soignant `PAIEMENT_RAPIDE_RECU` avec contexte `CONNECT_PAYOUT_PAID` (subject : "💰 Paiement arrivé sur votre compte bancaire")
   - [ ] Audit `FINANCE_PAYOUT_PAID` avec `transfers_marked: N`

#### E. `transfer.reversed` — transfer annulé côté Stripe
1. Action admin plateforme : reverse un transfer via Stripe Dashboard.
2. **Vérifier** :
   - [ ] `stripe_transfers.statut = REMBOURSE`, `reversed_le` rempli
   - [ ] Audit `FINANCE_TRANSFER_REVERSED`

#### F. `charge.dispute.closed` — dispute résolu
1. Suite scenario B : attendre dispute closed côté Stripe (ou Resend avec status updated).
2. **Vérifier** :
   - [ ] `dispute_statut` passe `CLOS_won` ou `CLOS_lost` (selon résultat)
   - [ ] Email `DISPUTE_CLOSE_ADMIN` reçu (subject : "Litige Stripe clôturé — résultat : won/lost")
   - [ ] Si `lost` : warning affiché dans l'email

#### G. `charge.refunded` — refund exécuté
1. Déclencher refund via `stripe-refunds-queue` ou manuel dashboard.
2. **Vérifier** :
   - [ ] Si ligne `stripe_refunds_queue` existe : passe `TRAITE` + `traite_le`
   - [ ] Si AVOIR factures_honoraires associé : passe `REMBOURSEE` + `date_remboursement` + `reference_remboursement`
   - [ ] Audit `FINANCE_CHARGE_REFUNDED`

#### H. `payout.canceled` — payout annulé
1. Annuler un payout en cours via Stripe Dashboard.
2. **Vérifier** :
   - [ ] Transfers liés passent `ANNULEE`
   - [ ] Email admin `PAYOUT_CANCELED_ADMIN`
   - [ ] Audit `FINANCE_PAYOUT_CANCELED`

### 🟢 Informatifs (priorité 3)

#### I. `transfer.created`, `transfer.updated`, `payout.created`, `charge.pending`, `charge.expired`
- Aucune UI/notif — audit only.
- **Vérifier** : entrées `FINANCE_*_CREATED/UPDATED/PENDING/EXPIRED` dans `journaux_audit` après chaque event déclenché.

## Tests templates email (render check)

```bash
# Depuis /admin/emails (AdminEmails.tsx) — bouton "Send test" pour chacun :
- CHARGE_FAILED_ETAB
- DISPUTE_OUVERTE_ADMIN
- DISPUTE_CLOSE_ADMIN
- PAYOUT_FAILED_ADMIN
- PAYOUT_FAILED_SOIGNANT
- PAYOUT_CANCELED_ADMIN
- PAIEMENT_RAPIDE_RECU avec data.contexte='CONNECT_PAYOUT_PAID'
```

**Vérifier** :
- [ ] Subject correct (emoji/wording)
- [ ] Variables remplacées (pas de `{variable}` brut)
- [ ] Style Jolene (rose #E04590, layout WRAPPER)
- [ ] Bouton CTA cliquable vers la bonne route

## Stripe Dashboard — config à valider (prod Live)

Avant passage Live, vérifier que l'endpoint webhook Live a les 13 events (identiques au test dashboard) :

- `charge.failed`, `charge.pending`, `charge.expired`, `charge.refunded`
- `charge.dispute.created`, `charge.dispute.closed`
- `transfer.created`, `transfer.updated`, `transfer.reversed`, `transfer.failed`
- `payout.created`, `payout.paid`, `payout.failed`, `payout.canceled`

Plus les 6 events déjà configurés : `checkout.session.completed`, `payment_intent.succeeded`, `charge.succeeded`, `invoice.payment_failed`, `checkout.session.expired`, `account.updated`.

## Tickets clôturés

- **H6** (events webhook Connect manquants) → **RÉSOLU** après validation checklist.
- H7 (notif soignant) : déjà RÉSOLU CP-STRIPE-2, extension 3e contexte CP-STRIPE-4.
- H15 futur éventuel : UI admin disputes — non traité dans CP-STRIPE-4.

## Décisions architecturales

1. **Matching payout → transfers** : fait via `stripe_payout_id` si déjà set, sinon via `OR stripe_payout_id.is.null AND statut=TRANSFERE`. Limite : un payout regroupe plusieurs transfers du même Connect account ; le matching par statut=TRANSFERE marque tous les transfers "candidats". Acceptable en MVP, à raffiner si besoin (lire balance_transactions Stripe pour précision).

2. **Audit only vs UPDATE DB** : les events informatifs (`transfer.created/updated`, `payout.created`, `charge.pending/expired`) ne font pas d'UPDATE DB pour éviter la pollution. Si besoin de tracking plus fin, audit entries suffisent.

3. **Dispute status CHECK** : enum ouvert (`OUVERT`, `CLOS_won`, `CLOS_lost`, `CLOS_warning_closed`, `CLOS_warning_needs_response`, `CLOS_charge_refunded`). Nouvelles valeurs Stripe à venir nécessiteront update CHECK.

4. **Transfer.failed utilise PAYOUT_FAILED_ADMIN** : mutualisation template (mécanisme d'échec proche). Si besoin de différenciation, split en TRANSFER_FAILED_ADMIN dédié.
