# Tests manuels CP-STRIPE-2 — Checklist Gabrielle

Scope couvert : H1 (stripe_payment_intent_id), H4 partiel (guard statut factures_honoraires dans branche CONNECT), H7 (notif soignant paiement reçu), H14 (transition EMISE → PAYEE).

## Prérequis

- Compte soignant test LIBERAL avec Stripe Connect onboarding **COMPLET**
- Mission TERMINEE assignée à ce soignant
- Étab test avec Stripe Customer valide
- Edge functions déployées : `stripe-connect-pay-mission`, `stripe-webhook`, `send-email`

## Scénarios à exécuter

### ✅ Scénario nominal — paiement réussi

1. Sur mission TERMINEE, **ne PAS** cliquer "Payer" directement.
2. Générer la facture honoraires (bouton "Générer facture" ou RPC `generate-invoice`).
3. Vérifier : `factures_honoraires.statut = 'EMISE'`, `stripe_payment_intent_id = NULL`.
4. Cliquer "Payer Stripe Connect" côté étab.
5. Compléter le paiement test dans la modale embedded Stripe (carte 4242 4242 4242 4242).
6. Attendre webhook (quelques secondes).
7. **Vérifier en base** :
   - `factures_honoraires.statut = 'PAYEE'`
   - `factures_honoraires.stripe_payment_intent_id = 'pi_XXX'`
   - `factures_honoraires.date_paiement = aujourd'hui`
   - `stripe_transfers.statut = 'TRANSFERE'`
   - `missions.commission_facturee = TRUE`
8. **Vérifier inbox soignant** : email "Paiement reçu pour votre mission — FH-XXX" reçu. Contenu : montant, numero facture, mission, étab, CTA "Voir mes factures".
9. **Vérifier UI soignant** : page `/soignant/mes-factures-honoraires` affiche la facture avec badge "Payée".

### ❌ Scénario facture non générée — blocage propre

1. Sur mission TERMINEE, **ne PAS** générer la facture.
2. Cliquer "Payer Stripe Connect" côté étab.
3. **Vérifier** : toast d'erreur durée 8s "Facture honoraires non générée. Cliquez sur 'Générer facture' avant de payer." (pas "FACTURE_NON_GENEREE" code brut).
4. **Vérifier** : aucune Checkout Session créée dans le dashboard Stripe (pas de session orpheline).
5. **Vérifier en base** : `stripe_transfers` pas d'INSERT pour cette mission.

### 🛡️ Scénario facture ANNULEE — guard actif

1. Créer une mission TERMINEE + générer facture (statut EMISE).
2. Admin annule la facture manuellement : `UPDATE factures_honoraires SET statut = 'ANNULEE' WHERE id = X`.
3. Déclencher directement le webhook Stripe (via Stripe CLI ou via event re-send dans dashboard) avec `session.metadata.facture_honoraires_id = X`.
4. **Vérifier en base** :
   - `factures_honoraires.statut = 'ANNULEE'` (inchangé)
   - `factures_honoraires.stripe_payment_intent_id = NULL` (inchangé)
5. **Vérifier logs** : console.warn "facture_honoraires X not in EMISE/EN_RETARD, skipped"
6. **Vérifier `journaux_audit`** : entrée avec `action = 'FACTURE_HONORAIRES_PAYEE_SKIP_ANOMALIE'`.

### 🔁 Scénario idempotence rejeu webhook

1. Reprendre la session du scénario nominal qui a déjà réussi.
2. Redéclencher le webhook via "Resend event" dans Stripe dashboard.
3. **Vérifier en base** : aucun changement (statut reste PAYEE, stripe_payment_intent_id reste identique).
4. **Vérifier inbox** : pas de 2e email (ou 2e email acceptable mais pas bloquant — webhook est idempotent pour la DB, pas pour les emails).

### 📬 Scénario send-email échoue — paiement non bloqué

1. Scénario nominal, mais couper temporairement le secret `RESEND_API_KEY` ou équivalent.
2. Déclencher paiement → webhook.
3. **Vérifier** : la facture passe quand même à PAYEE + stripe_payment_intent_id rempli.
4. **Vérifier logs** : console.error "send-email PAIEMENT_RAPIDE_RECU failed".
5. Restaurer le secret.

## UI/UX complémentaires à valider visuellement

- [ ] Bouton "Payer Stripe Connect" reste fonctionnel (pas de régression).
- [ ] Loading spinner affiché pendant l'appel.
- [ ] Toast info si `already_paid` (scénario préexistant, pas cassé).
- [ ] Après paiement réussi, le tableau des missions se rafraîchit (côté étab).
- [ ] La liste `MesFacturesHonoraires` soignant affiche le bon statut PAYEE avec la bonne date.

## Tests SQL automatisés

Pour la logique SQL (guard statut, lookup facture) : voir `tests/stripe/cp-stripe-2.test.sql`.

Exécution :
```bash
psql "$DB_URL" -f tests/stripe/cp-stripe-2.test.sql
```

Attendu : tous `[X.Y] OK`, aucun FAIL.

## Tickets clôturés à la fin

Une fois tous les scénarios validés :

- H1 → RÉSOLU (stripe_payment_intent_id propagation OK)
- H4 → PARTIEL RÉSOLU (guard factures_honoraires OK ; guard factures commission reste à faire dans CP-STRIPE-3)
- H7 → RÉSOLU (notif soignant OK)
- H14 → RÉSOLU (transition PAYEE OK)

Mise à jour `/docs/tickets-inventory-wip.md` à faire en fin de CP.
