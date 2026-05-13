# CLAUDE.md

> Conventions et règles de travail pour Claude Code sur le projet Jolene.

## Workflow Git — règles non-négociables

Claude Code mène chaque tâche jusqu'au bout en autonomie totale, sans intervention manuelle de Gabrielle sur GitHub :

1. **Branche feature** : créer une branche descriptive si la modification est non-triviale, ou commit direct sur main pour les fixes mineurs (selon le contexte)
2. **Commit + push** : messages Conventional Commits (feat:, fix:, chore:, docs:, refactor:)
3. **Ouverture de PR** automatique via `gh pr create` **ou** `mcp__github__create_pull_request`
4. **Résolution de conflits** : si conflits avec main, résoudre automatiquement. Règle par défaut : en cas de doute, conserver les blocs des DEUX côtés et concatener (jamais supprimer du code existant).
5. **Merge automatique** via `gh pr merge --squash --delete-branch` **ou** `mcp__github__merge_pull_request` (préfère --squash pour garder un historique main propre, sauf instruction contraire)
6. **Surveillance du déploiement** : suivre le workflow `deploy-supabase` jusqu'à confirmation verte avec `gh run watch` **ou**, si gh indisponible, fournir l'URL du run à Gabrielle (`https://github.com/Gabpcd/Jolene/actions?query=branch%3Amain`) pour qu'elle confirme visuellement
7. **Rapport final** : URLs de la PR mergée, du run de workflow, et confirmation que les changements sont bien en prod

### Vérification CI systématique — règle non-négociable (apprise Sprint 7 le 2026-05-13)

**Après PR #174 et #177 mergées avec `Typecheck + build` en échec** (subagents ayant divergé du code local), 5 commits hotfix sur main ont été nécessaires pour ramener la branche en état build. Pour éviter la récidive :

1. **Avant chaque merge** (`mcp__github__merge_pull_request`) : appeler `mcp__github__pull_request_read --method get_check_runs` et vérifier que **TOUS** les checks suivants sont `conclusion: "success"` :
   - `Typecheck + build`
   - `Drift detection (Lovable legacy patterns)`
   - `Lighthouse audit` (warning seulement, pas bloquant si fail isolé)
   - `Vercel Preview Comments`
   Si un check est `in_progress` ou `queued` : attendre (re-check dans 1-2 min). Si un check est `failure` : analyser, fixer en commit sur la branche PR, attendre re-run, vérifier vert AVANT de merger.

2. **Après chaque merge** : refaire un `get_check_runs` sur la PR (ou commit HEAD de main) pour confirmer que le merge commit a aussi passé la CI sur main (les checks ré-tournent à cause du push event).

3. **Si CI rouge sur main** : créer un commit hotfix IMMÉDIATEMENT (ne pas enchaîner d'autres PRs sur une main cassée — sinon les PRs suivantes héritent du fail et c'est l'avalanche).

4. **`npx tsc -b` local AVANT push de la PR** : reproduit exactement le check `Typecheck + build` du CI. Si KO local → fixer avant push. Si OK local mais KO en CI → divergence sub-agent vs local : `git pull` puis re-vérifier.

5. **Subagents Write/Edit** : après chaque subagent qui crée des fichiers TS/TSX, faire un `npx tsc -b` AVANT de commit/push. Les subagents Sprint 7 ont écrit du code qui compilait pas (imports mauvais path `LayoutAdmin`, props `titre` inexistant sur `Notification`) → 5 hotfix nécessaires.

### Ce que Gabrielle ne fait JAMAIS

- Pousser du code manuellement
- Merger une PR depuis l'interface GitHub
- Résoudre des conflits manuellement
- Cliquer sur "Merge pull request"

### Pré-requis et fallback

- Avant la première opération Git de chaque session, vérifier que `gh` CLI est authentifié (`gh auth status`)
- Si `gh` n'est pas disponible (environnement Claude Code sans `gh`) : utiliser les outils MCP GitHub `mcp__github__*` à la place
- Si NI `gh` NI MCP GitHub ne sont disponibles, signaler immédiatement à Gabrielle pour résolution durable plutôt que de demander un merge manuel
- Si une opération Git échoue (CI cassée, conflit complexe, push rejeté), ne PAS retomber sur "fais-le manuellement" : analyser, corriger, recommencer

### Environnement Claude Code — détection au début de chaque session Git

Au début d'une session impliquant des opérations Git, détecter quelle voie est disponible :

| Outil | Test | Si KO, fallback |
|---|---|---|
| `gh` CLI | `gh auth status` | Tools MCP GitHub `mcp__github__*` |
| MCP GitHub | Lister les tools `mcp__github__*` disponibles dans la session | Demander à Gabrielle de configurer le serveur MCP |
| `git push/pull` | `git fetch origin` | Vérifier que le proxy git local fonctionne |

**Tableau d'équivalences gh CLI ↔ MCP GitHub** :

| Action | `gh` CLI | MCP GitHub |
|---|---|---|
| Créer une PR | `gh pr create --title ... --body ...` | `mcp__github__create_pull_request` |
| Lire une PR | `gh pr view <num>` | `mcp__github__pull_request_read --method get` |
| Lire le diff d'une PR | `gh pr diff <num>` | `mcp__github__pull_request_read --method get_diff` |
| Lire les checks d'une PR | `gh pr checks <num>` | `mcp__github__pull_request_read --method get_check_runs` |
| Merger une PR | `gh pr merge <num> --squash --delete-branch` | `mcp__github__merge_pull_request --merge_method squash` (delete branch via `git push origin --delete` ensuite) |
| Lister les PRs | `gh pr list` | `mcp__github__list_pull_requests` |
| Suivre un workflow run | `gh run watch <id>` | pas d'équivalent MCP — fournir l'URL `actions?query=branch%3Amain` à Gabrielle |
| Status combiné d'un commit | `gh api repos/.../commits/SHA/status` | MCP renvoie 403 — fallback : `mcp__github__pull_request_read get_check_runs` sur la PR du commit |

**Limites connues du MCP GitHub** (à signaler à Gabrielle plutôt que de bloquer) :

- Pas de tool pour supprimer une branche distante
- Pas de tool pour lister/suivre les workflow runs GitHub Actions
- Pas de tool pour lire les logs d'un workflow run
- `mcp__github__get_commit` ne retourne pas les statuses de checks

### Cas particulier — Vercel et Supabase

- Vercel déploie automatiquement chaque branche en Preview, et main en Production
- Supabase déploie via le workflow GitHub Actions `deploy-supabase` uniquement sur main
- Une PR mergée sur main = déclenchement automatique du déploiement Supabase prod
- Vérifier dans le rapport final que le run `deploy-supabase` est passé vert (via `gh run watch` ou en remontant l'URL du run à Gabrielle)

## Règles migrations Supabase

Apprises à la dure le 2026-05-12 (3 deploy-supabase échoués sur Sprint 1 PR 1+2).

1. **Format obligatoire** : `YYYYMMDDHHMMSS_description.sql` (14 chiffres). Pas de `YYYYMMDD_*.sql` (8 chiffres) ni autre — le Supabase CLI rejette silencieusement et la migration n'est jamais enregistrée dans `schema_migrations`.

2. **PAS de `BEGIN;`/`COMMIT;` internes** — le CLI wrap déjà en transaction. Les BEGIN/COMMIT explicites sont redondants et peuvent empêcher l'application de certains `ALTER TYPE`.

3. **Avant tout `INSERT INTO journaux_audit`**, vérifier la CHECK constraint.

4. **Si migration échoue : NE PAS LAISSER LES FICHIERS DANS LE REPO.**

5. **Test deploy manuel si possible** avant push : `supabase db push --dry-run --password ...`

6. **Surveillance post-merge obligatoire** : après merge, vérifier IMMÉDIATEMENT via MCP Supabase.

7. **Dollar-quoting imbriqué interdit avec `$$`** — utiliser tags distincts (`$body$`).

## Règles TypeScript / build (apprises 2026-05-13)

- **Utiliser `npx tsc -b` (pas `--noEmit`) pour valider en local** avant push.
- **Toujours utiliser les valeurs exactes des enums `UserRole`** : `SOIGNANT` | `ADMIN_ETABLISSEMENT` | `ADMIN_PLATEFORME` | `ADMIN_GROUPE`.
- **Colonnes DB non encore dans les types TS générés** : utiliser `as any` ciblé.

## Workflows produits (Sprint 1 + Sprint 2)

### Workflow signature électronique (cf. docs/SIGNATURE_ELECTRONIQUE.md)
### Workflow contrat (cf. docs/TEMPLATES_CONTRATS.md)
### Workflow DPAE (cf. docs/DPAE_OPTION_A.md)
### Restrictions Mediflash (matrice profession x type_etab)

### Sprint 3.5 — Litiges + Annulation + Score + Réclamations
### Sprint 4 — Backend & infra mobile production
### Sprint 4.5 — Anti-triche pointage (cf. docs/ANTI_TRICHE_POINTAGE.md)
### Sprint 5 — Audit frontend exhaustif (cf. docs/AUDIT_FRONTEND_EXHAUSTIF.md)
### Sprint 5.5 — Fixes P0 critiques (8/13 P0 résolus)
### Sprint 5.7 — Fixes 5 P0 majeurs restants (5/5 P0 résolus)
### Sprint 6 — Fixes P1 audit Sprint 5 (12/15 P1 résolus)
### Sprint 7 — P1 restants + P2 cosmétiques (10 PRs)

### Sprint 8 — Polish UX global + briques mobile-first (9 PRs)

Cf. docs/UX_POLISH_STANDARDS.md.

| PR | # | Chantier | Livré |
|---|---|---|---|
| 1 | #182 | Skeletons contextuels + shimmer | 11 skeletons (mission, candidature, profil, KPI, paiement, score, messagerie, admin, contrat PDF, page) + tailwind keyframe shimmer + a11y `role=status` |
| 2 | #183 | EmptyState standardisé | 3 variants (info/success/warning) + cta + ctaSecondaire + compact mode + touch targets 44px |
| 3 | #184 | Toasts unifiés | Hiérarchie durées par type + prop `action` (Undo) + position responsive (bottom mobile / top desktop) + a11y enrichi |
| 4 | #185 | Erreurs API unifiées | `errorMessages.ts` dict SQLSTATE+PostgREST+Auth+HTTP+métier + `useApiCall` hook retry 1/2/4s |
| 5 | #186 | Briques mobile-first | `useViewport` (mobile/tablette/desktop) + 13 presets `inputMode` (EMAIL, TEL, OTP, NIR, SIRET, etc.) |
| 6 | #187 | Admin mobile compat | `BannerAdminMobile` < 640px dismissible + `overflow-x-hidden` `<main>` LayoutAdmin |
| 7 | #188 | ImageOptimisee | `<picture>` WebP fallback + lazy + aspect-ratio (anti-CLS) + fetchpriority |
| 8 | #189 | Wire BoutonsBulkFactures | Intégration AdminFacturation (sélection multiple + actions bulk payées/impayées/CSV) — corrige dead code Sprint 7 |
| 9 | this | Documentation Sprint 8 | docs/UX_POLISH_STANDARDS.md + CLAUDE.md + audit doc badges |

#### Sécurité + garde-fous Sprint 8
- Pas de breaking change sur les APIs (`afficherNotification`, `Skeleton` rétro-compatibles)
- Wiring opt-in : les composants sont disponibles, l'adoption se fait progressivement
- A11y RGAA AA renforcée systématiquement
- Aucune action automatique sur compte/score sans admin

#### Chantiers Sprint 8 reportés (Sprint 8.5)
Le brief Sprint 8 visait 13 PRs sur 12 jours. Les chantiers ci-dessous ont été pré-équipés des briques (utils + composants), mais le **wiring à grande échelle** (refactor de 25+ pages) reste à faire :
- **Mobile-first complet** : remplacer les `<Table>` par `<Card>` empilées sous 768px sur toutes les pages list (FacturationEtablissement, BulletinsPaie, MesFacturesHonoraires, HistoriqueMissions, etc.)
- **EmptyState wiring** : wire `<EmptyState />` dans les ~25 contextes vides identifiés
- **Modales fullscreen mobile** : faire `<Dialog>` -> fullscreen sous `<768px` sur SignerContratOtp, ModaleAnnulation*, ModalRecapMission, etc.
- **Performances Lighthouse cibles** : audit bundle (rollup-plugin-visualizer), lazy modales lourdes, service worker, Lighthouse cibles 90/90/80
- **A11y RGAA AA complet** : axe-core CI integration, labels, skip links, contrastes audit
- **Tests E2E exhaustifs** : workflows complets 3 interfaces sur 3 viewports
- **P2 §10** Fusion AdminLitiges + AdminModeration
- **P2 §12** Actions admin missions (modifier/arrêter/rembourser avec audit trail)
- **P2 §6** Tooltip majorations CCN sur cartes missions
- **P2 §14** Sous-titres WebVTT sur vidéos tuto

#### Bilan Sprint 8
- 8/9 PRs Sprint 8 livrées avec briques transversales solides prêtes à l'emploi
- 1 P2 résolu (BoutonsBulkFactures wired)
- Sprint 8.5 ciblera le wiring à grande échelle des briques + P2 résiduels architecturaux
