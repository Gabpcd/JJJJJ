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
| Suivre un workflow run | `gh run watch <id>` | ❌ pas d'équivalent MCP — fournir l'URL `actions?query=branch%3Amain` à Gabrielle |
| Status combiné d'un commit | `gh api repos/.../commits/SHA/status` | ❌ MCP renvoie 403 — fallback : `mcp__github__pull_request_read get_check_runs` sur la PR du commit |

**Limites connues du MCP GitHub** (à signaler à Gabrielle plutôt que de bloquer) :

- Pas de tool pour supprimer une branche distante → utiliser `git push origin --delete <branch>` ; si le proxy bloque (HTTP 403), demander à Gabrielle de le faire via UI ou en local
- Pas de tool pour lister/suivre les workflow runs GitHub Actions
- Pas de tool pour lire les logs d'un workflow run
- `mcp__github__get_commit` ne retourne pas les statuses de checks

### Cas particulier — Vercel et Supabase

- Vercel déploie automatiquement chaque branche en Preview, et main en Production
- Supabase déploie via le workflow GitHub Actions `deploy-supabase` uniquement sur main
- Une PR mergée sur main = déclenchement automatique du déploiement Supabase prod
- Vérifier dans le rapport final que le run `deploy-supabase` est passé vert (via `gh run watch` ou en remontant l'URL du run à Gabrielle)
