# Validation matching enrichi UI

> **Date** : 2026-04-27 · **Branche** : `audit/validation-matching`
> **Méthodo** : lecture code + tests SQL via MCP Supabase, comptes audit-* déjà créés en Phase 1.
> **Périmètre** : valider que le matching enrichi livré (helper hiérarchie + spécialité) est cohérent partout dans l'UI.

## Sommaire

- [TÂCHE 1 — Audit code frontend](#tache-1--audit-code-frontend)
- [TÂCHE 2 — Tests SQL bout-en-bout](#tache-2--tests-sql-bout-en-bout)
- [TÂCHE 3 — Messages d'erreur](#tache-3--messages-derreur)
- [TÂCHE 4 — Cohérence UI](#tache-4--coherence-ui)
- [Synthèse](#synthese)

## TÂCHE 1 — Audit code frontend

`getMissionsCompatiblesFilter` est utilisé :

| Fichier | Usage | Statut |
|---|---|---|
| `src/pages/RechercheMissions.tsx:19,150` | Filtre missions visibles | ✅ |
| `src/pages/MissionsSoignant.tsx:21,117` | Onglet « Disponibles » | ✅ |

**Bug trouvé** :

🐛 **P1 — Dashboard widget "missions ouvertes" utilise strict match**

`fn_dashboard_soignant_complet` (RPC backend appelée par `DashboardSoignant.tsx:62`) filtre les missions affichées dans le widget « Missions ouvertes » (3 missions max) avec :

```sql
WHERE m.statut = 'OUVERTE'
  AND (v_profession IS NULL OR m.profession_requise = v_profession)
```

C'est un **strict match incohérent** avec `RechercheMissions` et `MissionsSoignant` qui utilisent désormais la hiérarchie. Conséquence :
- Un IBODE ne voit pas les missions IDE sur son dashboard, mais les voit en allant sur `/soignant/missions` ou `/soignant/recherche-missions`.
- Un IDE ne voit pas les missions IBODE/IADE acceptant non-spécialisés sur son dashboard.

Impact métier : modéré (limité à 3 missions sur le dashboard, pas bloquant car l'utilisateur peut candidater via les autres pages). Mais incohérence visible.

**Recommandation fix** : étendre le `WHERE` du widget avec la même logique que `fn_soignant_compatible_mission`. Migration courte.

## TÂCHE 2 — Tests SQL bout-en-bout

Setup : missions test créées via `fn_creer_mission` avec compte `audit-hopital@jolene-test.dev`. Comptes soignants audit-* mis à jour avec `tous_documents_valides=true` + RCP valide pour passer les checks documentaires.

| # | Scénario | Attendu | Obtenu | Statut |
|---|---|---|---|---|
| A | IDE → mission IBODE souple (`accepte_non_spec=true`) | PASS | `{success: true, choix_contrat: SALARIE}` | ✅ PASS |
| B | IDE → mission IBODE strict (`accepte_non_spec=false`) | FAIL clair | `{error: "Cette mission IBODE n'accepte pas les IDE non spécialisés."}` | ✅ PASS |
| C | IBODE → mission IDE | PASS | `{success: true, choix_contrat: SALARIE}` | ✅ PASS |
| D | MEDECIN sans spec → mission cardio strict | FAIL clair | `{error: "Cette mission requiert la spécialité SM48."}` | ✅ PASS |
| E (frontend filter) | audit-ide voit IBODE souple + IDE, ne voit PAS IBODE strict | OK | requête `.or()` retourne 2 missions visibles | ✅ PASS |
| Bonus | IADE → mission IDE | PASS | `{success: true}` | ✅ PASS |

**6/6 PASS**. Le matching enrichi backend + frontend filter est fonctionnel.

SQL exact utilisé pour les tests :

```sql
-- Pattern pour chaque scénario candidature :
SELECT pg_temp.run_test('audit-{prof}@jolene-test.dev', 'AUDIT TEST mission ...');

-- Sc.E (visibilité côté audit-ide) :
SELECT intitule, profession_requise, accepte_non_specialises
FROM missions
WHERE statut = 'OUVERTE'
  AND (profession_requise = 'IDE'
       OR (profession_requise IN ('IBODE','IADE') AND accepte_non_specialises = true));
```

## TÂCHE 3 — Messages d'erreur

Audit des messages retournés par `fn_postuler_mission` :

| Cas | Message | Qualité |
|---|---|---|
| Mission introuvable | `Mission introuvable` | ✅ clair |
| Mission fermée | `Cette mission n'est plus disponible` | ✅ clair |
| Mission non-candidature | `Cette mission n'accepte pas les candidatures` | ✅ clair |
| Profil soignant absent | `Profil soignant introuvable` | ✅ clair |
| Profession incompatible (cas général) | `Votre profession ne correspond pas à la mission requise (IDE).` | ✅ clair |
| Spécialité médicale requise | `Cette mission requiert la spécialité SM48.` | ⚠️ technique : code spécialité brut au lieu du label |
| IDE sur IBODE strict | `Cette mission IBODE n'accepte pas les IDE non spécialisés.` | ✅ clair |
| Exclusion étab | `Accès refusé.` | ⚠️ vague (mais probablement intentionnel pour ne pas révéler l'exclusion) |
| Mission salarié pour libéral | `Cette mission est réservée aux salariés.` | ✅ clair |
| RCP manquante | `Assurance Responsabilité Civile Professionnelle (RCP) manquante ou expirée. Veuillez la téléverser dans vos documents.` | ✅ très clair |
| Documents non validés J-7 | `Documents obligatoires non validés (mission < 7 jours).` | ✅ clair |
| Déjà postulé | `Vous avez déjà postulé à cette mission` | ✅ clair |
| MIXTE choix contrat manquant | `Veuillez choisir votre mode de contrat.` + options | ✅ très clair |

**Findings T3** :

⚠️ **P2 — Code spécialité brut affiché à l'utilisateur** : `Cette mission requiert la spécialité SM48.` Le code SM48 (cardio) devrait être traduit en libellé humain. Une table `specialites_medicales` (cf. `ans-specialites-nomenclature.json` dans `docs/`) permet ce mapping.

Recommandation : récupérer le libellé via JOIN dans `fn_postuler_mission` ou via une fonction helper SQL `fn_label_specialite_medicale(text) RETURNS text`.

## TÂCHE 4 — Cohérence UI

Lecture des composants `CarteMission.tsx` et `CarteMissionSoignant.tsx` :

```tsx
// CarteMission.tsx:80
{m.service && `${m.service} · `}{getLabelProfession(m.profession_requise)}
```

L'UI affiche **uniquement le label de la profession requise**, sans indicateur si la mission est accessible par hiérarchie ou souplesse.

**Backlog UX (non critique)** :

📋 **Backlog UX-1 — Badge "Mission spécialisée" pour IDE voyant une mission IBODE souple**

Quand un IDE voit dans sa liste une mission `profession_requise=IBODE` avec `accepte_non_specialises=true`, l'UI ne signale pas que :
1. C'est une mission spécialisée (IBODE > IDE)
2. L'étab a coché "ouvert aux non-spécialisés" — donc le soignant peut candidater

Recommandation : ajouter un petit badge (ex : `🩺 IBODE · ouvert aux IDE`) sur la carte. Pas bloquant ; UX nice-to-have.

📋 **Backlog UX-2 — Badge "Hiérarchie naturelle" pour IBODE/IADE voyant une mission IDE**

Quand un IBODE voit une mission IDE dans sa liste, le label affiché est "Infirmier Diplômé d'État" alors que le soignant lui est IBODE. Pas confus en pratique (c'est un downgrade volontaire) mais on pourrait clarifier d'un badge `↓ IDE de base — accessible avec votre diplôme IBODE`.

📋 **Backlog UX-3 — Filtrage spécialité médecin côté UI**

Pour les médecins, l'UI ne propose pas de filtrer les missions par spécialité (RechercheMissions.tsx propose un filtre profession mais pas spécialité). Le backend gère le matching, mais l'UI pourrait pré-filtrer pour éviter au médecin de voir des missions inaccessibles à cause de spécialité requise non matchée.

Tous ces items sont **non critiques** — fonctionnalité en place, juste l'UX qui pourrait être plus explicite.

## Synthèse

| Sévérité | # | Description |
|---|---|---|
| **P0** | **0** | — |
| **P1** | **1** | Dashboard widget "missions ouvertes" utilise strict match (incohérence) |
| **P2** | **1** | Code spécialité brut (SM48) affiché dans message d'erreur |
| **Backlog UX** | 3 | Badges hiérarchie / souplesse / filtre spécialité médecin |

**Tests fonctionnels** : 6/6 PASS sur les scénarios cross-matching + visibilité.

### Recommandation

**P1 Dashboard** : à fixer rapidement (migration courte qui réplique la logique `fn_soignant_compatible_mission` dans le RPC `fn_dashboard_soignant_complet`). Pas bloquant car les autres pages affichent correctement les missions hiérarchiques, mais incohérence visible côté utilisateur.

**P2 Spécialité** : à fixer quand on touchera à l'i18n des messages. Pas urgent.

**Backlog UX** : à arbitrer — pas bloquant fonctionnellement.

### Cleanup à faire après validation

Test artifacts à supprimer :
```sql
DELETE FROM candidatures WHERE mission_id IN (SELECT id FROM missions WHERE intitule LIKE 'AUDIT TEST%');
DELETE FROM missions WHERE intitule LIKE 'AUDIT TEST%';
DELETE FROM documents_soignants WHERE s3_cle LIKE 'audit/rcp-%';
-- Comptes audit-* gardés pour Phase 2 navigateur (à supprimer après).
```
