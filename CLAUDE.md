# CLAUDE.md

> Conventions et règles de travail pour Claude Code sur le projet Jolene.

## Workflow Git — règles non-négociables

Claude Code mène chaque tâche jusqu'au bout en autonomie totale, sans intervention manuelle de Gabrielle sur GitHub :

1. **Branche feature** : créer une branche descriptive si la modification est non-triviale, ou commit direct sur main pour les fixes mineurs (selon le contexte)
2. **Commit + push** : messages Conventional Commits (feat:, fix:, chore:, docs:, refactor:)
3. **Ouverture de PR** automatique via `gh pr create`
4. **Résolution de conflits** : si conflits avec main, résoudre automatiquement. Règle par défaut : en cas de doute, conserver les blocs des DEUX côtés et concatener (jamais supprimer du code existant).
5. **Merge automatique** via `gh pr merge --squash --delete-branch` (préfère --squash pour garder un historique main propre, sauf instruction contraire)
6. **Surveillance du déploiement** : suivre le workflow `deploy-supabase` jusqu'à confirmation verte avec `gh run watch`
7. **Rapport final** : URLs de la PR mergée, du run de workflow, et confirmation que les changements sont bien en prod

### Ce que Gabrielle ne fait JAMAIS

- Pousser du code manuellement
- Merger une PR depuis l'interface GitHub
- Résoudre des conflits manuellement
- Cliquer sur "Merge pull request"

### Pré-requis et fallback

- Avant la première opération Git de chaque session, vérifier que `gh` CLI est authentifié (`gh auth status`)
- Si non authentifié, signaler immédiatement à Gabrielle pour résolution durable plutôt que de demander un merge manuel
- Si une opération Git échoue (CI cassée, conflit complexe, push rejeté), ne PAS retomber sur "fais-le manuellement" : analyser, corriger, recommencer

### Cas particulier — Vercel et Supabase

- Vercel déploie automatiquement chaque branche en Preview, et main en Production
- Supabase déploie via le workflow GitHub Actions `deploy-supabase` uniquement sur main
- Une PR mergée sur main = déclenchement automatique du déploiement Supabase prod
- Vérifier dans le rapport final que le run `deploy-supabase` est passé vert
