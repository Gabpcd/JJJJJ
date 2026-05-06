# Tests manuels CP-STRIPE-6 — Hardening Stripe Connect

Scope : **4 tickets RÉSOLUS** (H2 + H9 + H10 + H11). Dernier CP de la Sub-PR D Stripe Connect prod-ready.

## Prérequis

- ✅ Migration `20260420140000_cp_stripe_6_account_deleted_status` appliquée (CHECK statut + SUPPRIME).
- ✅ Helper `_shared/stripe-errors.ts` créé.
- ✅ 3 edge functions refactorées (onboard/status/pay-mission) utilisent `mapStripeError`.
- ✅ stripe-connect-status : cache 5 min + handler SUPPRIME.
- ✅ PageStripeConnect.tsx + ProfilSoignant.tsx : branche SUPPRIME + bouton refresh `?force=true`.
- 🟡 H16 (template email STRIPE_COMPTE_SUPPRIME_SOIGNANT) à créer dans Sub-PR templates.

## Scénarios automatisables (SQL)

```bash
psql "$DB_URL" -f tests/stripe/cp-stripe-6.test.sql
```

Couvre :
- [1.1-1.2] CHECK statut accepte SUPPRIME + 6 statuts au total
- [2.1] UPDATE vers SUPPRIME + charges/payouts désactivés
- [3.1] Cache VALIDE (modifie_le < 5 min)
- [4.1] Cache EXPIRÉ (modifie_le ≥ 5 min)
- [5.1] Idempotence : statut SUPPRIME préservé au rechargement

Attendu : tous `[X.Y] OK`.

## Scénarios end-to-end (manuels)

### 🔍 H9 — Typed error handling

#### A. StripeAuthenticationError
1. Révoquer temporairement `STRIPE_SECRET_KEY` (ou la remplacer par clé invalide).
2. Appeler `stripe-connect-status` depuis l'UI soignant LIBERAL.
3. **Vérifier** :
   - [ ] Réponse 500 avec `{ error: 'STRIPE_AUTH_FAILED', message: 'Configuration Stripe invalide, contactez le support.' }`
   - [ ] Logs : `error` level (pas warn)
   - [ ] Frontend affiche message propre (pas "Une erreur interne est survenue" brut)
4. Restaurer la clé.

#### B. StripeRateLimitError
1. Difficile à reproduire sans saturer l'API Stripe. Peut être simulé via mock ou attendu naturellement en cas de pic.
2. **Attendu** :
   - [ ] Réponse 503 avec `{ error: 'STRIPE_RATE_LIMIT', message: 'Trop de requêtes, réessayez...' }`
   - [ ] Logs : `warn` level

#### C. Erreur inconnue (fallback)
1. Injecter une erreur non-Stripe (ex: `throw new Error('db failure')`) dans l'un des handlers.
2. **Attendu** :
   - [ ] Réponse 500 avec `{ error: 'STRIPE_UNKNOWN_ERROR', message: 'Une erreur interne est survenue.' }`
   - [ ] Logs : `error` level

### 💾 H10 — Cache status

#### A. Cache hit (appels rapprochés)
1. Depuis l'UI soignant LIBERAL, ouvrir la page `/soignant/stripe-connect`.
2. Recharger la page moins de 5 min après.
3. **Vérifier en logs** :
   - [ ] 1er appel : cache miss, appel Stripe API effectué
   - [ ] 2e appel : `cached: true, cache_age_seconds: N` dans la réponse
   - [ ] Pas d'appel Stripe pour le 2e (latence réduite)

#### B. Cache miss (expiration)
1. Attendre 5+ min depuis dernier refresh.
2. Recharger `/soignant/stripe-connect`.
3. **Vérifier** :
   - [ ] `cached: false` dans la réponse
   - [ ] Appel Stripe API effectué
   - [ ] `modifie_le` bumpé en base

#### C. Force refresh (bouton Actualiser)
1. Cliquer sur "Actualiser" dans la page.
2. **Vérifier** :
   - [ ] URL edge function appelée avec `?force=true`
   - [ ] `cached: false` même si appel < 5 min après le précédent
   - [ ] Appel Stripe API effectué

#### D. Invalidation via webhook account.updated
1. Depuis Stripe Dashboard, modifier les infos du compte Connect test (ajouter document, changer adresse).
2. Webhook `account.updated` arrive → UPDATE `stripe_connect_onboarding` (`modifie_le` bumpé).
3. Recharger page soignant.
4. **Vérifier** :
   - [ ] Nouvelles données reflétées immédiatement (cache invalidé via webhook)

### ❌ H11 — Compte Stripe supprimé

#### A. Compte supprimé côté Stripe
1. Depuis Stripe Dashboard, supprimer un compte Connect test.
2. Appeler `stripe-connect-status` depuis l'UI soignant.
3. **Vérifier** :
   - [ ] Réponse 200 (pas 500) avec `{ statut: 'SUPPRIME', message: '...', onboarding_complete: false }`
   - [ ] `stripe_connect_onboarding.statut` = 'SUPPRIME' en DB
   - [ ] `charges_enabled = false`, `payouts_enabled = false`
   - [ ] Audit entry `STRIPE_CONNECT_ACCOUNT_DELETED` dans journaux_audit
   - [ ] UI affiche la nouvelle branche avec :
     - Bandeau rouge "Compte Stripe supprimé"
     - Explication (clôture, fraude, décision admin)
     - Bouton "Recommencer l'onboarding"
     - Bouton "Contacter le support"

#### B. Idempotence : statut déjà SUPPRIME
1. Recharger la page après détection SUPPRIME.
2. **Vérifier** :
   - [ ] Pas de nouvel appel `stripe.accounts.retrieve` (short-circuit via statut='SUPPRIME' en cache)
   - [ ] UI affiche toujours la branche SUPPRIME
   - [ ] Pas de nouvelle audit entry

#### C. Recréation après suppression
1. Depuis la branche SUPPRIME, cliquer "Recommencer l'onboarding".
2. Flow `stripe-connect-onboard` crée un NOUVEAU compte Connect Stripe.
3. **Vérifier** :
   - [ ] Nouveau `stripe_account_id` en DB (différent du précédent)
   - [ ] `statut` passe à `EN_COURS` (puis COMPLET après complétion)
   - [ ] Tests paiement OK sur le nouveau compte

### 📋 H2 — Consommation DDL Sub-PR 2 quater

Aucun test spécifique : H2 est résolu par cumul des CPs précédents (CP2-3-4-5). Vérification finale :

```sql
-- Scan : les edge functions Stripe référencent-elles les colonnes Sub-PR 2 quater ?
-- Résultat attendu : oui pour stripe-webhook (dispute_*, reversed_le, stripe_payout_id, paye_le, type_document)
--                   + process-stripe-refunds (stripe_refund_id, tentatives, dernier_essai_le)
```

## Validation workflow GitHub Actions

Après push commit CP-STRIPE-6 :
- [ ] Workflow #N déclenché automatiquement
- [ ] Job `deploy-migrations` : applique `20260420140000_cp_stripe_6_account_deleted_status` (ou no-op si déjà appliquée via MCP)
- [ ] Job `deploy-functions` : redéploie 37 functions incluant les 3 Stripe modifiées + shared/
- [ ] Workflow vert

## Tickets clôturés

- **H2** (edge functions ignorent DDL FIX 9) → **RÉSOLU** (via CP2-3-4-5 cumulés)
- **H9** (typed Stripe errors) → **RÉSOLU** (helper `_shared/stripe-errors.ts`)
- **H10** (cache stripe-connect-status) → **RÉSOLU** (via `modifie_le` + `?force=true`)
- **H11** (compte Stripe supprimé gracieux) → **RÉSOLU** (catch dédié + statut SUPPRIME + UI)

Nouveau ticket ouvert :
- **H15** (UI admin disputes, P2, 8h)
- **H16** (email STRIPE_COMPTE_SUPPRIME_SOIGNANT, P2, 2h)

## Sub-PR D — état final

Tous les tickets H1→H14 de la Sub-PR D sont clos :

| CP | Livré | Tickets |
|----|-------|---------|
| CP-STRIPE-1 | ✅ | H12, H13 (faux positifs) |
| CP-STRIPE-2 | ✅ | H1, A20, H7, H14 |
| CP-STRIPE-3 | ✅ | H4, H5, H8 |
| CP-STRIPE-4 | ✅ | H6 |
| CP-STRIPE-5 | ✅ | H3, A21/T13 |
| CP-STRIPE-6 | ✅ | **H2, H9, H10, H11** |

**Sub-PR D complète : 14 tickets résolus sur 14**. Stripe Connect prod-ready.

Tickets suivi (futurs Sub-PRs) : H15 (UI admin disputes), H16 (email compte supprimé).
