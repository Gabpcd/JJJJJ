# Audit RLS et secrets — Sprint 3 PR 7

> Audit effectué via MCP Supabase. Rapporte les tables sans RLS, les
> policies faibles, et confirme l'absence de secrets en clair dans le repo.

## Tables sensibles — RLS strict vérifié

| Table | RLS | Policies | Statut |
|---|---|---|---|
| `factures_honoraires` | ✅ | SELECT owner + admin, INSERT/UPDATE service_role | ✅ |
| `paiements_soignants` | ✅ | SELECT owner + admin | ✅ |
| `contrats_mission` | ✅ | SELECT parties + admin | ✅ |
| `signatures_contrats` | ✅ | SELECT parties + admin, INSERT/UPDATE bloqué (RPC only) | ✅ |
| `journaux_audit` | ✅ | SELECT admin only | ✅ |
| `presences` | ✅ | SELECT owner + admin étab + admin | ✅ |
| `soignants` | ✅ | SELECT owner + admin + match-recherche public anonymisé | ✅ |
| `etablissements` | ✅ | SELECT public limité + admin étab full | ✅ |
| `tokens_push` | ✅ | SELECT/INSERT/UPDATE/DELETE owner uniquement (+GRANT DELETE service_role PR 1 S3) | ✅ |
| `documents_soignants` | ✅ | SELECT owner + admin | ✅ |
| `missions` | ✅ | SELECT public (publiées) + owner + admin | ✅ |
| `candidatures` | ✅ | SELECT parties + admin | ✅ |
| `litiges` | ✅ | SELECT parties + admin médiation | ✅ |
| `signature_rate_limit_ip` | ✅ | DENY ALL authenticated (interne, service_role bypass) | ✅ |

## Tables techniques sans RLS (whitelist)

- `spatial_ref_sys` — PostGIS, données publiques
- `cron.job` / `cron.job_run_details` — schéma pg_cron, accès superuser seul

## Audit secrets dans le code

```bash
git log --all --full-history --grep -E 'API_KEY|SECRET|TOKEN|PASSWORD' -i
```

- Pas de secret en clair commit (vérifié `git log` + scan `.env*`, `vault/`, `.config`)
- Tous les secrets passent par `Deno.env.get('XXX')` côté edge functions
- Frontend : `VITE_SUPABASE_PUBLISHABLE_KEY` est PUBLIC par design (sécurisé via RLS)
- Vault Supabase utilisé pour `service_role_key` (lu via `vault.decrypted_secrets`)

## Recommandations post-Sprint 3

### P1 (Sprint 4)
- **search_path strict** : refactor toutes les fonctions PL/pgSQL avec
  `SET search_path = ''` (au lieu de `public, extensions` actuel) pour
  bloquer les injections prepared statements. Impact : ~80 fonctions à toucher.
- **2FA admin obligatoire** : forcer MFA via Supabase Auth pour les
  comptes ADMIN_PLATEFORME et ADMIN_GROUPE.
- **Audit RLS automatisé** : exécuter `fn_audit_rls_strict()` chaque semaine
  via cron et alerter Sentry si nouvelles tables sans RLS.

### P2 (Sprint 5+)
- **Chiffrement at-rest renforcé** : utiliser pgsodium pour les colonnes
  les plus sensibles (NIR, RPPS, IBAN — déjà chiffrés au niveau infra Supabase
  mais pgsodium ajoute une couche app-level).
- **WORM journaux_audit** : empêcher UPDATE/DELETE sur journaux_audit
  (immutable audit trail).

## Rate-limit recap (Sprint 3 PR 7)

| Endpoint | Limite | Couche |
|---|---|---|
| `fn_envoyer_otp_signature` | 3 SMS / 24h / contrat × rôle | Backend SQL (PR 1 S2) |
| Rate-limit IP signature | 5 envois / h / IP | `fn_check_rate_limit_ip_signature` (PR 7 S3) |
| `verify-siret` | 20 / min / IP | `_shared/rate-limit.ts` in-memory |
| `verify-rpps` | 10 / min / IP | `_shared/rate-limit.ts` in-memory |
| `register-soignant` | 5 / h / IP | Turnstile captcha + rate-limit |
| `register-etablissement` | 5 / h / IP | Turnstile captcha + rate-limit |

## Index ajoutés PR 7 S3

- `idx_journaux_audit_action_acteur` : recherche logs admin
- `idx_journaux_audit_ip` (GIN partial) : recherche par IP dans details JSON
- `idx_signatures_contrats_ip` : analyse forensic signatures par IP

## Captcha Turnstile

Confirmé en place sur :
- Inscription soignant + étab
- Connexion (3e tentative échouée)
- Reset password
- Reverify RPPS

**Manque (Sprint 4)** : Turnstile sur 3e tentative OTP signature.
