# Worker `externalisation_actions` — architecture et opérations

> Sprint 4 PR 2. Worker async qui traite les side-effects enqueués par
> les RPCs Sprint 3.5 (litiges exec, annulation mission, etc.). Cron
> pg_cron toutes les 5 min via `net.http_post` → edge function
> `process-externalisation-actions`.

## Vue d'ensemble

```
Trigger DB (annulation, accord litige, etc.)
        │
        ▼
INSERT externalisation_actions (statut=PENDING)
        │
        ▼ (toutes les 5 min)
pg_cron jolene_process_externalisations
        │
        ▼
edge fn process-externalisation-actions
        │
        ▼
fn_externalisations_a_traiter(50, worker_id) → LOCK + SELECT
        │
        ▼
Dispatch selon type_action :
  ┌─────────────────────────────────────┐
  │ STRIPE_REFUND_TOTAL / _PARTIEL      │ → Stripe API refunds.create
  │ STRIPE_PAYMENT                       │ → Stripe Connect transfers.create
  │ STRIPE_PAYOUT                        │ → (Sprint 5+)
  │ CHORUS_RECYCLER_FACTURE              │ → piste-client OR PENDING_AIFE 24h
  │ DPAE_ANNULATION                      │ → email + push étab Net-Entreprises
  │ EMAIL_NOTIF                          │ → relais send-email
  │ PUSH_NOTIF                           │ → relais send-push
  │ AVOIR_PDF_GENERATION                 │ → HTML + SHA-256 + Storage + INSERT avoirs
  └─────────────────────────────────────┘
        │
        ▼
Success → fn_externalisation_succes
Échec   → fn_externalisation_echec (backoff 1/5/30 min, ou PENDING_AIFE 24h)
```

## Table `externalisation_actions`

| Colonne | Type | Description |
|---|---|---|
| `id` | uuid PK | |
| `type_action` | text | Voir liste ci-dessous |
| `payload` | jsonb | Données spécifiques au type |
| `source` | text | `LITIGE_EXEC` / `ANNULATION_MISSION` / `CRON_ALERTE_ADMIN` / `AUTRE` |
| `source_id` | uuid | ID du litige ou mission source |
| `statut` | text | `PENDING` / `PROCESSING` / `DONE` / `ERROR` / `PENDING_AIFE` / `CANCELLED` |
| `tentatives` | int | Compteur de retry |
| `derniere_tentative_le` | ts | |
| `derniere_erreur` | text | Stack trace si erreur (1000 chars max) |
| `resultat` | jsonb | Données retour Stripe / Chorus / etc. |
| `next_retry_at` | ts | Backoff exponentiel |
| `cron_lock_at` | ts | Lock pris par le worker |
| `cron_lock_par` | text | Worker ID (worker_xxxxxxxx) |
| `cree_le` / `traite_le` | ts | |

## Backoff exponentiel

| Tentative | Délai retry | Statut suivant |
|---|---|---|
| 1ère échec | 1 minute | PENDING |
| 2e échec | 5 minutes | PENDING |
| 3e échec | 30 minutes | PENDING |
| 4e échec | — | **ERROR** + audit + notif admin |

Cas spécial `PENDING_AIFE` (Chorus Pro) :
- Pas d'incrément du compteur tentatives
- Retry à 24h
- Boucle quotidienne jusqu'à activation des scopes côté AIFE

## Distribution lock atomique

`fn_externalisations_a_traiter` utilise `FOR UPDATE SKIP LOCKED` pour
permettre plusieurs workers en parallèle sans double-process :

```sql
WITH selectionnees AS (
  SELECT id FROM externalisation_actions
  WHERE (statut = 'PENDING' AND next_retry_at < NOW())
     OR (statut = 'PENDING_AIFE' AND next_retry_at < NOW())
     OR (statut = 'PROCESSING' AND cron_lock_at < NOW() - INTERVAL '10 min') -- orphelin
  ORDER BY cree_le ASC
  LIMIT 50
  FOR UPDATE SKIP LOCKED
)
UPDATE externalisation_actions a
SET statut = 'PROCESSING', cron_lock_at = NOW(), cron_lock_par = worker_id
FROM selectionnees s WHERE a.id = s.id
RETURNING ...;
```

Récupération d'actions orphelines (worker mort en cours de PROCESSING) :
si `cron_lock_at < NOW() - 10 min`, l'action est re-lock par un autre worker.

## Types d'actions détaillés

### `STRIPE_REFUND_TOTAL` / `STRIPE_REFUND_PARTIEL`

Payload :
```json
{
  "mission_id": "uuid",
  "montant": 50.00,           // optionnel (PARTIEL avec montant fixe)
  "pourcentage": 30,           // optionnel (PARTIEL avec %)
  "motif": "LITIGE_ACCORD_MUTUEL"
}
```

Calcule `amountCents` :
- TOTAL : pas d'amount → remboursement intégral PaymentIntent
- PARTIEL avec montant : `Math.round(montant * 100)`
- PARTIEL avec pourcentage : `total × (% / 100) × 100`

Cas spécial `balance_insufficient` (Stripe error code) → retry au lieu de FAILED.

### `STRIPE_PAYMENT` (Connect transfer)

Payload :
```json
{
  "beneficiaire_id": "uuid_soignant",
  "montant": 220.00,
  "motif": "Indemnité L1243-8"
}
```

Charge le `stripe_account_id` du soignant et appelle
`POST https://api.stripe.com/v1/transfers` avec destination =
`stripe_account_id`. Si soignant sans Stripe Connect : FAILED (admin
doit faire virement manuel SEPA).

### `CHORUS_RECYCLER_FACTURE`

Payload :
```json
{
  "mission_id": "uuid",
  "facture_id": "uuid",
  "motif": "ANNULATION"
}
```

Vérifie `PISTE_OAUTH_SCOPE` (Vault) contient `recyclerFacture`. Si pas
activé (cas actuel jusqu'à déblocage AIFE) → marque **PENDING_AIFE**
avec retry 24h. Implémentation complète post-AIFE.

### `DPAE_ANNULATION`

Payload :
```json
{
  "contrat_id": "uuid",
  "mission_id": "uuid",
  "motif": "ANNULATION_SOIGNANT",
  "echeance_legale_h": 48
}
```

**Option A actuelle** : envoie email + push à l'étab "Annulez la DPAE
dans votre compte Net-Entreprises dans les 48h". Lien direct vers
https://www.net-entreprises.fr/declaration-prealable-embauche/.

Option B future : API tiers déclarant URSSAF directe (Sprint 5+).

### `AVOIR_PDF_GENERATION`

Payload :
```json
{
  "mission_id": "uuid",
  "type": "TOTAL" | "PARTIEL" | "AJUSTEMENT_HORAIRES" | "MIXTE" | "ANNULATION_ETAB",
  "motif_avoir": "LITIGE_ACCORD_MUTUEL" | "ANNULATION_MISSION_*" | etc.,
  "pourcentage": 30,           // optionnel
  "montant": 100,              // optionnel
  "montant_indemnite": 220     // optionnel
}
```

Génère :
- Numéro `AV-YYYYMM-XXXX`
- HTML stylisé charte Jolene (rose)
- SHA-256 du HTML
- Upload Storage bucket `avoirs` (chemin `mission_id/numero.html`)
- INSERT `avoirs` table avec montant_ht, motif, source_*, pdf_storage_path, hash

PDF binaire = côté frontend via jsPDF au moment du download (pattern
Sprint 2 PR 3).

### `EMAIL_NOTIF` / `PUSH_NOTIF`

Relais simple : POST vers `send-email` ou `send-push` edge function avec
le payload tel quel. Utilisé par triggers DB qui veulent enqueuer un
envoi async plutôt que synchrone (cas alerte admin réclamations PR 3 S4).

## Page admin `/admin/externalisations-actions`

Composant `src/pages/admin/AdminExternalisationsActions.tsx` :
- Stats grid : PENDING / PROCESSING / DONE / ERROR / PENDING_AIFE
- Filtres : statut + type_action + recherche source_id / erreur / ID
- Détail action en modal (payload + résultat + erreur)
- Actions admin :
  - **Retry** sur ERROR / PENDING_AIFE → reset PENDING + tentatives=0
  - **Annuler** sur PENDING / PENDING_AIFE / ERROR → CANCELLED + motif

## Monitoring

Métriques exposées par le worker dans la response JSON :
```json
{
  "worker_id": "worker_a1b2c3d4",
  "processed": 42,
  "success": 38,
  "failed": 3,
  "pending_aife": 1,
  "duration_ms": 1234
}
```

À monitorer côté admin :
- Croissance du backlog PENDING → cron 5 min insuffisant, augmenter fréquence
- Croissance du PENDING_AIFE → relance AIFE pour activation scopes
- Croissance du ERROR → root cause investigation (souvent Stripe `balance_insufficient`)

Cron alerte si > 50 actions PENDING > 1h : à implémenter Sprint 5
(actuellement : page admin visible mais pas d'alerte proactive).

## Tests

- ✅ Migration testée en MCP rollback (PR 2 S4)
- ✅ Edge function compile (Deno) — typecheck implicite
- À tester en recette : trigger un litige résolu avec
  `payload_modifications.type = ANNULATION_TOTALE` → vérifier 4 actions
  insérées (STRIPE_REFUND_TOTAL, CHORUS_RECYCLER_FACTURE, DPAE_ANNULATION,
  AVOIR_PDF_GENERATION) → cron 5 min → vérifier statuts DONE / PENDING_AIFE
