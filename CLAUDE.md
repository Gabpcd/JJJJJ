# CLAUDE.md

> Conventions et règles de travail pour Claude Code sur le projet Jolene.

## Workflow Git — règles non-négociables

1. **Branche feature** : créer une branche descriptive si la modification est non-triviale, ou commit direct sur main pour les fixes mineurs
2. **Commit + push** : messages Conventional Commits (feat:, fix:, chore:, docs:, refactor:)
3. **Ouverture de PR** automatique via `gh pr create` ou `mcp__github__create_pull_request`
4. **Résolution de conflits** : automatique. Règle par défaut : en cas de doute, conserver les blocs des DEUX côtés
5. **Merge automatique** via `gh pr merge --squash` ou `mcp__github__merge_pull_request`
6. **Surveillance du déploiement** : suivre `deploy-supabase` jusqu'à confirmation verte
7. **Rapport final** : URLs de la PR mergée, du run de workflow, confirmation prod

### Vérification CI systématique — règle non-négociable

1. **Avant merge** : `get_check_runs` → tous les checks `success` requis (Typecheck+build, Drift, Lighthouse, Vercel)
2. **Après merge** : refaire `get_check_runs` sur merge commit (push event re-trigger CI)
3. **Si CI rouge sur main** : commit hotfix IMMÉDIATEMENT
4. **`npx tsc -b` local AVANT push** : reproduit le check CI
5. **Subagents Write/Edit** : après chaque subagent qui touche TS/TSX, faire un `npx tsc -b`

## Règles migrations Supabase

1. Format obligatoire `YYYYMMDDHHMMSS_*.sql` (14 chiffres)
2. PAS de `BEGIN;`/`COMMIT;` internes
3. Avant tout `INSERT INTO journaux_audit` : vérifier CHECK constraint
4. Si migration échoue : supprimer le fichier
5. Test deploy manuel `supabase db push --dry-run` si possible
6. Surveillance post-merge via MCP Supabase
7. Dollar-quoting imbriqué interdit avec `$$` — utiliser tags distincts (`$body$`)

## Règles TypeScript / build

- `npx tsc -b` (pas `--noEmit`) pour valider en local
- Valeurs exactes des enums `UserRole` : `SOIGNANT` | `ADMIN_ETABLISSEMENT` | `ADMIN_PLATEFORME` | `ADMIN_GROUPE`
- Colonnes DB non encore dans types TS : utiliser `as any` ciblé

## Workflows produits

### Sprint 1 + 2 — Signature électronique, contrats, DPAE, restrictions Mediflash
### Sprint 3.5 — Litiges + Annulation + Score + Réclamations
### Sprint 4 — Push natif + worker externalisation + Capacitor
### Sprint 4.5 — Anti-triche pointage (cf. docs/ANTI_TRICHE_POINTAGE.md)
### Sprint 5 — Audit frontend exhaustif (cf. docs/AUDIT_FRONTEND_EXHAUSTIF.md)
### Sprint 5.5 — Fixes P0 critiques (8/13 P0 résolus)
### Sprint 5.7 — Fixes 5 P0 majeurs restants (5/5 P0 résolus)
### Sprint 6 — Fixes P1 audit Sprint 5 (12/15 P1 résolus)
### Sprint 7 — P1 restants + P2 cosmétiques (10 PRs)

### Sprint 8 — Polish UX global + briques mobile-first (9 PRs)
Cf. docs/UX_POLISH_STANDARDS.md.

8/9 PRs livrées : Skeletons, EmptyState, Toasts unifiés, useApiCall+errorMessages,
useViewport+inputMobile, BannerAdminMobile, ImageOptimisee, BoutonsBulkFactures wiré, Doc.

### Sprint 8 BIS — Wiring polish UX (4 PRs)
Cf. docs/RESPONSIVE_MOBILE.md.

| PR | # | Chantier | Livré |
|---|---|---|---|
| 1 | #191 | TableOuCartes + DialogResponsive | Briques foundation : `<TableOuCartes>` (table↔cartes selon viewport) + `<DialogResponsive>` (modal fullscreen mobile / centered desktop) |
| 2 | #192 | Wiring EmptyState SOIGNANT | 3 pages migrées : MesAvances, BulletinsPaie, MesFacturesHonoraires (variant info/warning selon mandat) |
| 3 | #193 | Majorations CCN tooltip (P2 §6) | `lib/majorationsCCN.ts` détection nuit/dimanche/férié + badge `+X% CCN` sur CarteMissionSoignant avec tooltip détail (CCN 51 art. 82/83) |
| 4 | this | Documentation Sprint 8 BIS | docs/RESPONSIVE_MOBILE.md + CLAUDE.md |

#### Bilan Sprint 8 BIS
- 1 P2 résolu (§6 majorations breakdown)
- 2 briques foundation prêtes (TableOuCartes + DialogResponsive)
- 3 pages SOIGNANT wirées EmptyState

#### Reportés Sprint 8 ter / Sprint 8.5
- Wiring EmptyState ÉTAB + ADMIN (15+ pages)
- Migration tableaux SOIGNANT vers TableOuCartes (5 pages)
- Migration tableaux ÉTAB vers TableOuCartes (8 pages)
- Migration modales SOIGNANT vers DialogResponsive (8 modales)
- Migration modales ÉTAB vers DialogResponsive (6 modales)
- Performances Lighthouse cibles (bundle audit, lazy modales, ImageOptimisee partout)
- A11y RGAA AA complete (axe-core CI)
- Tests E2E exhaustifs (3 interfaces × 3 viewports)
- P2 §10 fusion AdminLitiges + AdminModeration
- P2 §12 actions admin missions
- P2 §14 sous-titres vidéos tuto
- Admin mobile-first complet (Sprint 8.5 dédié)
