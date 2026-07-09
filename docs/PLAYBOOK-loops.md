# PLAYBOOK — boucles Claude Code (goal / loop / schedule)

> Comment installer des boucles de travail autonomes sur Jolene : recette
> d'acceptation, babysitting de PR, surveillance Sentry, et routage modèle.

## 1. `/goal` — recette d'acceptation (stop-hook)

`/goal <condition détaillée>` pose un **stop-hook de session** : Claude ne peut
pas rendre la main tant que la condition n'est pas prouvée. C'est l'outil des
**recettes** : on décrit l'état final vérifiable (fichiers présents, commandes
qui sortent en 0, preuves au transcript), pas les étapes.

Bonnes pratiques :
- Écrire la condition comme une **checklist falsifiable** (« `npm run
  test:guards` sort en 0 », pas « les guards marchent »).
- Toujours borner : « Stop après N turns » — sinon la boucle peut tourner
  longtemps sur un critère impossible.
- Interdire explicitement d'affaiblir les vérifications (« corriger le code,
  jamais les motifs ») : sans cette clause, le chemin le plus court vers la
  condition est de détendre le test.
- `/goal clear` libère le hook si la recette doit être abandonnée.

Exemple type (celui qui a installé ce dispositif) : exiger
`tests/non-regression/` complet + preuves `node --check`, `bash -n`,
`playwright --list`, `npm run test:guards` == 0, en ≤ 15 turns.

## 2. `/loop 15m` — babysitting de PR

`/loop 15m <prompt>` relance le même prompt toutes les 15 minutes dans la
session. Usage principal : **suivre une PR jusqu'au merge** (checks GitHub +
Vercel), conformément à la règle CLAUDE.md « Vérification CI systématique ».

Prompt type :

```
/loop 15m Vérifie la PR #NNN : check-runs GitHub (Typecheck+build, Drift,
Lighthouse) + déploiement Vercel. Si tout est vert → squash-merge, puis
re-vérifie les check-runs du commit de merge sur main. Si un check est rouge →
lis les logs, corrige, push, et attends le tour suivant. Ne merge jamais rouge.
```

- 15 min ≈ le temps d'un run CI complet : inutile de poller plus vite.
- La boucle s'arrête (`/loop stop` ou fin de session) quand la PR est mergée
  et que main est vert.

## 3. `/schedule` — surveillance Sentry toutes les 4 h

`/schedule` crée un agent cloud récurrent (cron), indépendant de la session
locale. Usage : **veille Sentry** sur la prod Jolene.

Routine type (cron `0 */4 * * *`) :

```
Liste les issues Sentry nouvelles ou en pic depuis 4 h sur le projet Jolene
(MCP Sentry). Pour chaque issue nouvelle : résume la stack, identifie le
fichier/commit suspect, et si le fix est évident ouvre une PR de hotfix ;
sinon crée un rapport détaillé. Ne touche à rien en prod sans PR.
```

- 4 h = assez fréquent pour attraper une régression de déploiement, assez
  espacé pour ne pas brûler du quota sur un backlog stable.
- L'agent schedulé n'a pas les credentials interactifs de la session : vérifier
  que les MCP nécessaires (Sentry, GitHub) sont accessibles en headless.

## 4. Routage modèle — Opus vs Sonnet

Règle de routage des boucles et subagents :

| Tâche | Modèle |
|---|---|
| Recette `/goal`, refactor, diagnostic CI rouge, écriture SQL/RLS | **Opus** (ou mieux) — raisonnement long, contexte CLAUDE.md dense |
| Boucle `/loop` de polling (lire des checks, comparer des statuts) | **Sonnet** — mécanique, fréquent, coût maîtrisé |
| Routine `/schedule` de veille (résumé Sentry, tri d'issues) | **Sonnet** par défaut, escalade Opus si un fix doit être codé |
| Subagents de fan-out (grep massif, inventaires) | **Sonnet/Haiku** — volume, pas de décision |

Principe : **le modèle cher décide, le modèle rapide surveille.** Une boucle
qui tourne toutes les 15 min sur Opus coûte ~10× la même sur Sonnet pour un
travail de lecture de statuts ; à l'inverse, économiser sur le modèle qui
écrit une migration ou résout un CI rouge se paie en hotfixes.

## 5. Articulation avec le dispositif non-régression

- `npm run test:regression` enchaîne guards → schéma → invoicing → e2e mobile ;
  c'est la commande que les boucles exécutent avant tout merge.
- `npm run test:schema` exige `SUPABASE_DB_URL` (env ou `.env`) — dans une
  boucle cloud, la fournir via secret, jamais en dur dans le prompt.
- `tests/non-regression/sql/audit-insert.test.sql` : uniquement base
  locale/branche (rollback intégral), **jamais en prod**.
