# Tests manuels CP-STRIPE-5 — process-stripe-refunds

Scope : **H3 + A21/T13 RÉSOLUS** — consommation stripe_refunds_queue par cron toutes les 15 min + appel stripe.refunds.create + typed error handling + template REFUND_ECHEC_ADMIN.

## Prérequis

- ✅ Edge function `process-stripe-refunds` v2+ déployée (workflow auto après push)
- ✅ Cron `process-stripe-refunds-15min` créé via MCP (voir Partie E)
- ✅ Vault secret `service_role_key` présent (utilisé par cron pour l'auth)
- ✅ `STRIPE_SECRET_KEY` dans les secrets edge functions

## Scénarios automatisables (SQL)

```bash
psql "$DB_URL" -f tests/stripe/cp-stripe-5.test.sql
```

Couvre :
- [1.1] CHECK statut accepte `EN_ATTENTE / EN_COURS / TRAITE / ECHEC`
- [2.1] SELECT éligibles filtre correctement (EN_ATTENTE + tentatives<3 + dernier_essai>15min)
- [3.1] Lock atomique `EN_ATTENTE → EN_COURS` réussi
- [3.2] Second cron concurrent bloqué (UPDATE 0 rows)
- [4.1] Transition success : EN_COURS → TRAITE + stripe_refund_id + traite_le
- [5.1] Transition retry : EN_COURS → EN_ATTENTE + tentatives++
- [6.1] Transition échec : tentatives=3 → ECHEC permanent
- [7.1] Webhook charge.refunded idempotent (ligne déjà TRAITE préservée)

Attendu : tous `[X.Y] OK`.

## Scénarios end-to-end (impossible à automatiser, Stripe prod requis)

### Scénario A — Refund nominal (test card)

1. Créer un avoir `AUTO_STRIPE` en dev via `fn_admin_resoudre_litige` (flow AVOIR avec facture PAYEE < 120j).
2. Vérifier qu'une ligne apparaît dans `stripe_refunds_queue` (statut EN_ATTENTE).
3. Attendre 15 min (prochain run cron) ou déclencher manuellement :
   ```bash
   curl -X POST https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/process-stripe-refunds \
     -H "Authorization: Bearer $SERVICE_ROLE_KEY"
   ```
4. **Vérifier** :
   - [ ] Retour JSON : `{ success: true, processed: 1, success_count: 1, duration_ms: X }`
   - [ ] `stripe_refunds_queue.statut = 'TRAITE'`, `stripe_refund_id` rempli (format `re_XXX`)
   - [ ] `traite_le` horodaté
   - [ ] Logs edge function : `Refund re_XXX created for queue ...`
   - [ ] Audit `FINANCE_REFUND_TRAITE_IDEMPOTENT` (si idempotence) OU rien si nominal
   - [ ] Webhook `charge.refunded` arrive ensuite (CP-STRIPE-4) → UPDATE idempotent sur ligne TRAITE (no-op)
   - [ ] `factures_honoraires.statut` passe REMBOURSEE + `reference_remboursement`

### Scénario B — Refund déjà traité (idempotence Stripe)

1. Simuler via Stripe Dashboard : créer un refund manuel sur la charge, puis INSERT une ligne `stripe_refunds_queue` avec le même `stripe_payment_intent_id`.
2. Attendre cron → tentative de refund.
3. Stripe retourne `charge_already_refunded`.
4. **Vérifier** :
   - [ ] `stripe_refunds_queue.statut = 'TRAITE'` (idempotence via code `charge_already_refunded`)
   - [ ] `erreur` = "already refunded" (ou message Stripe)
   - [ ] Logs : `charge_already_refunded — marking TRAITE (idempotence)`
   - [ ] Audit `FINANCE_REFUND_TRAITE_IDEMPOTENT` avec `erreur_code: 'charge_already_refunded'`
   - [ ] Pas d'email admin (idempotence considérée comme succès)

### Scénario C — Échec permanent (payment_intent invalide)

1. INSERT ligne avec `stripe_payment_intent_id = 'pi_invalid_test'`.
2. Attendre cron.
3. Stripe retourne `resource_missing` (payment_intent introuvable).
4. **Vérifier** :
   - [ ] Première tentative → `tentatives=1`, statut `EN_ATTENTE` (mais... `resource_missing` est dans PERMANENT_ERROR_CODES → ECHEC direct dès la 1ère tentative)
   - [ ] `stripe_refunds_queue.statut = 'ECHEC'` + `erreur` rempli
   - [ ] Email `REFUND_ECHEC_ADMIN` reçu par tous les admins
   - [ ] Audit `FINANCE_REFUND_ECHEC`

### Scénario D — Retry temporaire (rate limit simulé)

Difficile à simuler sans vraie API Stripe saturée. Alternative :
1. Mocker côté code temporairement en forçant un throw dans la logique.
2. Vérifier transitions :
   - Tentative 1 : EN_COURS → EN_ATTENTE, tentatives=1
   - Tentative 2 (15 min après) : idem, tentatives=2
   - Tentative 3 : EN_COURS → ECHEC (max atteint) + email admin

### Scénario E — StripeAuthenticationError (config cassée)

1. Révoquer temporairement `STRIPE_SECRET_KEY` ou la remplacer par invalide.
2. INSERT une ligne EN_ATTENTE.
3. Attendre cron.
4. **Vérifier** :
   - [ ] Toutes les lignes passent `ECHEC` immédiatement (pas de retry)
   - [ ] Email admin URGENT pour chacune
   - [ ] Logs : `StripeAuthenticationError — ECHEC + alert admin`
5. Restaurer la clé.

### Scénario F — Cron concurrent (lock)

1. Déclencher 2 appels cron en parallèle (curl × 2 quasi simultané).
2. **Vérifier** :
   - [ ] Un seul des deux runs prend chaque ligne (UPDATE conditionnel atomique)
   - [ ] Second run reçoit `0 rows` sur certaines lignes → skip avec log `already locked by another cron`
   - [ ] Pas de double refund Stripe

## Configuration cron vérification

```sql
SELECT jobname, schedule, command, active
FROM cron.job
WHERE jobname = 'process-stripe-refunds-15min';
```

Attendu :
- `schedule` = `*/15 * * * *`
- `active` = `true`
- `command` contient `net.http_post` vers `process-stripe-refunds`

Historique d'exécutions :
```sql
SELECT runid, jobid, job_pid, database, username, command, status, return_message, start_time, end_time
FROM cron.job_run_details
WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'process-stripe-refunds-15min')
ORDER BY start_time DESC
LIMIT 10;
```

## Erreurs Stripe mapping (référence)

| Erreur Stripe | Action |
|---------------|--------|
| `charge_already_refunded` | TRAITE (idempotence) |
| `resource_missing` (payment_intent introuvable) | ECHEC permanent + email |
| `payment_intent_unexpected_state` | ECHEC permanent + email |
| `amount_too_large` | ECHEC permanent + email |
| `charge_disputed` | ECHEC permanent + email |
| `charge_expired` | ECHEC permanent + email |
| `missing_source` | ECHEC permanent + email |
| `StripeAuthenticationError` | ECHEC permanent + email URGENT (config problem) |
| `StripeRateLimitError` | Retry (EN_ATTENTE, tentatives++) |
| `StripeAPIError` / autre | Retry (EN_ATTENTE, tentatives++) |
| Après 3 tentatives retry | ECHEC + email |

## Tickets clôturés

- **H3** (stripe_refunds_queue non consommée) → **RÉSOLU**
- **A21 / T13** (process-stripe-refunds à finaliser) → **RÉSOLU**

## Décisions architecturales

1. **`TRAITE` dès succès refunds.create** (pas d'ENVOYE intermédiaire) : le webhook charge.refunded devient idempotent (pas de transition nécessaire, déjà TRAITE).

2. **Fréquence 15 min** : volume attendu faible (quelques refunds/jour max), latence max 15 min avant premier run acceptable. Permet 3 retries sur ~45 min avant ECHEC permanent.

3. **Lock optimiste via UPDATE conditionnel** : pas de verrous bloquants, scaling horizontal possible si besoin futur.

4. **Stripe Authentication Error → ECHEC direct** : un problème de clé révèle une régression config prod critique, il faut alerter admin sans retry inutile.

5. **`ALREADY_REFUNDED_CODES` → TRAITE idempotent** : si Stripe a déjà traité le refund (manuel dashboard ou race condition), on aligne la DB plutôt que boucler en erreur.
