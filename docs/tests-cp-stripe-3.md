# Tests manuels CP-STRIPE-3 — Checklist Gabrielle

Scope couvert : **H4 complet** (guard factures commission webhook) + **H5** (compensation Checkout orpheline) + **H8 RÉSOLU** (déjà couvert CP-STRIPE-2, confirmation).

## Scénarios automatisables (SQL)

Exécuter :
```bash
psql "$DB_URL" -f tests/stripe/cp-stripe-3.test.sql
```

Couvre 5 scénarios guard webhook FACTURE commission :
- [2.1] Facture EMISE → PAYEE (nominal)
- [2.2] Facture EN_RETARD → PAYEE (relance acceptée)
- [2.3] Facture ANNULEE → guard bloque
- [2.4] Facture BROUILLON → guard bloque
- [2.5] Facture déjà PAYEE préservée (rejeu webhook idempotent)

Attendu : tous `[X.Y] OK`.

## Scénarios manuels H5 (rollback pay-mission)

Impossible à automatiser SQL car H5 teste le try/catch du backend avec création réelle de Stripe Checkout Session.

### Scénario — compensation session orpheline

**Setup** :
1. Compte soignant test LIBERAL avec Stripe Connect onboarding COMPLET
2. Mission TERMINEE + facture honoraires EMISE
3. Edge function stripe-connect-pay-mission v94+ déployée (CP-STRIPE-3)

**Étape A — simuler panne DB** : il n'est pas possible de simuler proprement un échec DB post-Checkout sans patcher le code temporairement. Option réaliste :
1. Modifier en local `stripe-connect-pay-mission/index.ts` pour forcer `throw new Error('test')` juste après création Checkout Session.
2. Déployer cette version temporaire via `supabase functions deploy stripe-connect-pay-mission`.
3. Déclencher un paiement côté UI.
4. Observer :
   - [ ] Réponse 500 avec `error: "CHECKOUT_FAILED_RETRY"` et message "Paiement impossible, veuillez réessayer"
   - [ ] Logs edge function : `CHECKOUT_CREATED_DB_WRITE_FAILED` + `Stripe session ... expired (compensation)`
   - [ ] Stripe dashboard : la Checkout Session créée est bien en statut `expired`
   - [ ] Table `journaux_audit` : entrée `STRIPE_CHECKOUT_ORPHANED_RECOVERED` avec `stripe_session_id` + `db_error`
   - [ ] `stripe_transfers` : aucun row créé pour cette mission (pas de pollution)
5. Restaurer la version propre + redéployer.

### Scénario — Option A stricte (user paye malgré expire)

Ce scénario vérifie le comportement intentionnel "Option A" documenté dans le code :

1. Reproduire H5 ci-dessus mais faire en sorte que `sessions.expire()` échoue (e.g. revoke temporaire du STRIPE_SECRET_KEY).
2. La session reste ouverte côté Stripe.
3. Compléter le paiement depuis l'URL de la session (si encore accessible).
4. Observer le webhook checkout.session.completed :
   - [ ] Branche CONNECT_MISSION_PAYMENT s'exécute
   - [ ] `stripe.transfers.create()` est appelée → soignant est payé sur son Connect account
   - [ ] Aucun row `stripe_transfers` créé en secours (on ne "récupère" pas le flow)
   - [ ] factures_honoraires reste EMISE (le webhook ne trouve pas la facture via metadata existante, ou si oui, la met à PAYEE mais sans row stripe_transfers associé)
   - [ ] Situation visible côté admin : "paiement Stripe réussi, pas de stripe_transfers associé"
   - [ ] Intervention admin requise : INSERT manuel dans stripe_transfers OU refund Stripe

Ce comportement est **intentionnel** — préférer une anomalie visible (audit + réconciliation admin) à un flow "miraculeux" qui masque la cause réelle du bug DB initial.

## Scénarios complémentaires H4 (guard factures commission end-to-end)

### Scénario — guard webhook ANNULEE

1. Créer une facture commission (via admin ou via cron auto-facturation mensuelle si dispo) en statut EMISE.
2. Déclencher un paiement via create-invoice-payment → Checkout Session Stripe créée.
3. **Avant que l'étab paye**, passer la facture en ANNULEE via admin (update manuel).
4. Étab complète le paiement → Stripe capture l'argent → webhook checkout.session.completed arrive.
5. Observer :
   - [ ] Logs : `FACTURE webhook: facture X not in EMISE/EN_RETARD, skipped`
   - [ ] Table `factures` : facture reste ANNULEE (guard bloque UPDATE)
   - [ ] `journaux_audit` : entrée `FACTURE_COMMISSION_PAYEE_SKIP_ANOMALIE` avec `statut_actuel: ANNULEE`
   - [ ] **L'argent EST côté Stripe** mais n'est pas rattaché à une facture plateforme → refund manuel requis

### Scénario — idempotence PAYEE rejoué

1. Facture commission déjà PAYEE.
2. Stripe re-envoie le webhook (simuler via "Resend event" dans Stripe dashboard).
3. Observer :
   - [ ] Logs : `Facture X already PAYEE, skipping duplicate webhook`
   - [ ] Table `factures` : inchangée (date_paiement, stripe_payment_intent_id préservés)
   - [ ] Pas d'audit duplique
   - [ ] Pas d'email FACTURE_PAYEE renvoyé

## Tickets clôturés après validation de cette checklist

- **H4** (guard factures commission) → RÉSOLU
- **H5** (rollback compensation) → RÉSOLU
- **H8** (check statut facture pay-mission) → RÉSOLU (déjà couvert CP-STRIPE-2, confirmation)

Mise à jour `/docs/tickets-inventory-wip.md` à effectuer en fin de CP-STRIPE-3.

## Décision architecturale (Option A vs B)

Documentée dans `stripe-connect-pay-mission/index.ts` ligne ~319 : **Option A (strict)** retenue.
- Rationale : anomalie visible > flow miraculeux.
- Coût : intervention admin si rollback + expire both échouent (rare).
- Bénéfice : traçabilité parfaite, aucune "récupération silencieuse" qui pourrait masquer un bug DB récurrent.
