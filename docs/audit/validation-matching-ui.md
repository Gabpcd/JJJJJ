# Validation matching enrichi UI — Phase C Session 4 résiduelle

> **Date** : 2026-04-27 · **Méthodo** : audit + fix dans la session
> **Périmètre** : valider que le matching enrichi (livré jour précédent) est cohérent partout, et corriger immédiatement tout écart détecté.

## TÂCHE 1 — Audit code frontend

`getMissionsCompatiblesFilter` est utilisé :

| Fichier | Avant | Après |
|---|---|---|
| `RechercheMissions.tsx` | ✅ | ✅ |
| `MissionsSoignant.tsx` | ✅ | ✅ |
| `fn_dashboard_soignant_complet` (RPC) | 🐛 strict match | ✅ utilise `fn_soignant_compatible_mission` |

**Fix appliqué** : migration `20260427160000_dashboard_soignant_hierarchie_pro.sql`. Le widget « Missions ouvertes » du Dashboard applique désormais la même logique hiérarchie que les autres pages.

## TÂCHE 2 — Tests SQL bout-en-bout

| # | Scénario | Résultat |
|---|---|---|
| A | IDE → mission IBODE souple | ✅ `{success:true}` |
| B | IDE → mission IBODE strict | ✅ FAIL clair `"n'accepte pas les IDE non spécialisés"` |
| C | IBODE → mission IDE | ✅ `{success:true}` |
| D | MEDECIN sans spec → cardio strict | ✅ FAIL clair `"requiert la spécialité Rhumatologie"` (libellé après fix T3) |
| E | Filtre frontend visibilité audit-ide | ✅ correct |
| Bonus | IADE → mission IDE | ✅ `{success:true}` |

**6/6 PASS**.

## TÂCHE 3 — Messages d'erreur

13 cas testés, **tous clairs après fix**.

**Fix appliqué** : migration `20260427160100_postuler_mission_label_specialite.sql`. Le message « Cette mission requiert la spécialité SM48 » devient désormais « Cette mission requiert la spécialité Rhumatologie » via JOIN avec `specialites_medicales(code → label)`.

## TÂCHE 4 — Cohérence UI soignant

**Avant** : `CarteMissionSoignant` affichait uniquement `getLabelProfession(profession_requise)` sans signaler les missions accessibles par hiérarchie.

**Fix appliqué** :
- Helper TS `getMissionMatchInfo(...)` ajouté à `src/lib/profession-hierarchy.ts` : détermine le type de match (EXACT / HIERARCHIE_NATURELLE / HIERARCHIE_SOUPLE / SPECIALITE_SOUPLE) avec label + classes Tailwind + tooltip.
- `CarteMissionSoignant.tsx` : nouveau badge contextuel quand match non-strict :
  - `↓ Mission IDE — accessible` (vert) pour IBODE/IADE voyant mission IDE
  - `🩺 Mission IBODE — ouverte aux IDE` (violet) pour IDE voyant mission IBODE souple
  - `🩺 Spécialité souhaitée — ouverte` (violet) pour médecin sans la spé requise
- Champs ajoutés au SELECT `MissionsSoignant.tsx` et `RechercheMissions.tsx` : `specialite_medicale_requise`, `accepte_non_specialises` (nécessaires au calcul du badge).

## TÂCHE 5 — Cohérence UI étab

**Avant** : `ListeCandidatures` ne distinguait pas les candidats hors profession exacte. L'étab voyait juste prénom + nom + score fiabilité.

**Fix appliqué** :
- Migration `20260427160200_soignant_pour_etablissement_specialite_medicale.sql` : ajoute `specialite_medicale` au RPC `fn_soignant_pour_etablissement` (nécessaire pour le badge médecin sans spé).
- `ListeCandidatures.tsx` :
  - Ajout des props `missionProfession`, `missionSpecialiteMedicale`, `missionAccepteNonSpecialises`.
  - Helper interne `getCandidatMatchBadge(...)` : retourne le label adapté.
  - Badge profession du candidat affiché systématiquement.
  - Badge contextuel si profession ≠ profession requise :
    - `↑ IBODE qualifié IDE` (vert) pour IBODE/IADE candidatant à mission IDE
    - `↓ IDE non spécialisé` (violet) pour IDE candidatant à mission IBODE/IADE souple
    - `🩺 Médecin sans la spécialité requise` (violet) pour médecin sans la spé exacte
- `DetailMission.tsx` :
  - SELECT mission inclut désormais `specialite_medicale_requise, accepte_non_specialises`.
  - Passe les 3 nouvelles props à `<ListeCandidatures>`.

## Synthèse

**Tout est cohérent et testé** : ✅

| Sujet | État |
|---|---|
| Helper `getMissionsCompatiblesFilter` partout | ✅ |
| Dashboard widget aligné sur la hiérarchie | ✅ |
| Tests SQL 6/6 PASS | ✅ |
| Messages d'erreur libellisés | ✅ |
| Badges hiérarchie côté soignant | ✅ |
| Badges candidat côté étab | ✅ |

**Fixes livrés dans la session** :
- 3 migrations SQL (fn_dashboard, fn_postuler_mission, fn_soignant_pour_etablissement)
- 4 modifications frontend (`profession-hierarchy.ts` étendu, `CarteMissionSoignant`, `ListeCandidatures`, `DetailMission`, `MissionsSoignant`, `RechercheMissions` SELECT)

Aucun ticket en backlog — tout traité dans la session.
