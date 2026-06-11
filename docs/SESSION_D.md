# Session D — Refonte complète de l'interface admin (11/06/2026)

> Exécution du volet « Session D » de [STRATEGIE_UX_REFONTE.md](STRATEGIE_UX_REFONTE.md) :
> sidebar 8→5 groupes, pattern « file de travail » sur toutes les listes, recherche
> globale ⌘K, drill-down cockpit, audit page par page (méthode Sprint 11).

## PRs livrées

| Lot | PR | Contenu |
|---|---|---|
| D-0 | — | Inventaire multi-agents des 43 pages admin (17 agents) → [AUDIT_ADMIN_SESSION_D.md](AUDIT_ADMIN_SESSION_D.md) |
| D-1 | #531 | Sidebar 8 entrées → 5 groupes (Pilotage, Utilisateurs, Opérations, Finances, Système) |
| D-2 | #533 | Recherche globale ⌘K : RPC `fn_admin_recherche_globale` + palette cmdk (utilisateurs, missions, factures, pages) |
| D-3 | #535 | File de travail — groupe Utilisateurs + composant partagé `FileDeTravail` |
| D-4 | #537 | File de travail — groupe Opérations (missions, contrats, planning, pool urgence, templates) |
| D-5 | #538 | File de travail — groupe Finances (facturation, mandats, Chorus Pro, affacturage, taux, vue d'ensemble) |
| D-6 | #536 | Cockpit fondateur : drill-down par graphique (acquisition nominative, revenus par établissement) |
| D-7 | (cette PR) | Doc d'audit + corrections copy/quick-wins sur ~30 pages non couvertes par D-3/D-4/D-5 |

## Décisions techniques

### Sidebar 5 groupes sans toucher au RBAC (D-1)
Les périmètres d'accès restent les **8 clés historiques** de `equipe_admin.acces_groupes`
(gérées sur /admin/fondateur/equipe). Chaque item de nav porte sa clé `acces` : la
structure visuelle est découplée des droits. Sans ce découplage, fusionner « Dashboard »
et « Fondateur » dans « Pilotage » aurait donné l'accès cockpit/salaires/levée à tout
membre n'ayant que le périmètre Dashboard. Aucune migration, aucun droit modifié.

### Pattern « file de travail » (D-3/D-4/D-5)
Composant partagé `src/components/admin/FileDeTravail.tsx` : section « À traiter »
toujours en tête (compteur rouge, plus anciens/urgents d'abord, EmptyState succès
mascotte quand purgée), « Historique » replié par défaut.

Limites connues du composant (état replié interne, section masquée à 0 résultat) :
sur les pages à refetch plein écran ou à chips de filtre dans l'historique
(AdminMissions, AdminFacturation), la structure est **répliquée** avec l'état
d'ouverture porté par la page. Pages déjà conformes (files pures, plus ancien
d'abord) inchangées : Litiges, Réclamations ×2, Triage scores, Heures externes,
Vérif. établissements, Impayées, Alertes pointage, Modération (hors Avoirs).

### Recherche globale (D-2)
`fn_admin_recherche_globale(p_query)` — garde `est_admin()` (réponse vide si non
admin), STABLE SECURITY DEFINER, 5 résultats max par catégorie. Palette cmdk avec
`shouldFilter={false}` (résultats serveur, debounce 250 ms) + accès rapide aux pages
de la sidebar filtrées RBAC. Atterrissages : fiche utilisateur, détail mission, et
`/admin/facturation?q=` (le champ recherche lit `?q=` et l'historique s'ouvre seul).

## Dette et signaux relevés (hors périmètre Session D)

- **Drift DB ↔ migrations** : `fn_rechercher_utilisateurs` existe en prod sans
  migration dans le repo ; la version corrigée de `fn_admin_cockpit_fondateur`
  (`debut_le` au lieu de `date_debut`) n'est pas non plus dans le repo. À
  resynchroniser (schema-snapshot ou migration de rattrapage).
- **Workflow Playwright E2E désactivé manuellement** sur GitHub Actions : la CI
  des PRs = typecheck + build + drift detection + Lighthouse. À réactiver quand
  les E2E seront stabilisés.
- **Doublons fonctionnels** identifiés par l'inventaire (backlog, non tranchés en
  Session D) : trois pages listent les établissements et leur statut de
  vérification (Utilisateurs / Vérif. établissements / Sales « Étab. Jolene ») ;
  Calendrier vs Planning global se recouvrent partiellement ; AdminSales
  « Groupes » vs AdminGroupes (homonymie trompeuse, fonctions différentes).
- **AdminSales** : `ajouterAuPipeline` côté soignants fait un insert simple (doublon
  à chaque clic) là où le côté établissements fait un upsert — corrigé si listé en
  D-7, sinon backlog.
- **Bug latent — litige forcé (AdminModeration)** : le formulaire envoie à
  `fn_admin_creer_litige_force` des types (PAIEMENT, QUALITE, CONTRAT…) absents de
  l'enum Postgres `type_litige` (valeurs réelles : NON_PAIEMENT, ABSENCE_SOIGNANT…,
  cf. `src/components/admin/litiges/types.ts`) — l'appel échoue pour tout sauf
  AUTRE. À corriger côté formulaire (mapper sur les vraies valeurs).
- Le backlog complet (203 problèmes de copy, 242 quick wins) est dans
  [AUDIT_ADMIN_SESSION_D.md](AUDIT_ADMIN_SESSION_D.md) avec lignes et citations.

## Méthode

Inventaire : 17 agents parallèles, une fiche structurée par page (listes, statuts
actionnables vs historiques, doublons, copy, quick wins). Refontes : un agent par
page avec la fiche d'audit en consigne, fichiers disjoints, vérification
`tsc -b` + `vite build` centralisée avant chaque PR. CI verte exigée avant chaque
merge (squash). Migration D-2 déployée par `deploy-supabase` (run vert vérifié).
