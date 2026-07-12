# Audit de cascade — matrice des modes d'exercice

Date : 12/07/2026 · périmètre : section D après validation C1-C7.

## Inventaire d'impact

| Élément | Impact constaté | Statut |
|---|---|---|
| `FormulaireMission` | Ancienne matrice TypeScript + citation CE générique ; décision appliquée à toute paire. | Corrigé : RPC `fn_mode_exercice`, profession requise par la mission, wording et source issus de la table. |
| `ModalRecapMission` | Rejouait une interdiction générique « Mediflash ». | Corrigé : reprend exactement le niveau, le wording et l'URL résolus par la table. |
| `BannerMediflashExplication` | Arrêt erroné n°488367 et généralisation à plusieurs professions. | Corrigé : n°491128 ; précise que le CE juge le seul cas aide-soignant. |
| `RechercheMissions` | Recalculait la matrice depuis `soignant.profession`, donc risque de traiter une IADE comme IADE sur une mission IDE. | Corrigé : aucune règle juridique cliente ; la mission a déjà été validée sur `mission.profession_requise` en DB. |
| Inscription / complétion profil | `PROFESSIONS_NON_LIBERAL` en dur mélangeait validité du profil et règle de mission. | Corrigé : le profil lit `regles_exercice_profession` via `fn_types_exercice_autorises`. |
| Matching hiérarchique | `fn_soignant_compatible_mission` contient déjà IADE/IBODE → mission IDE. | Vérifié + test : profil IADE × mission IDE = compatible ; résolution de mode appelée avec `IDE`. |
| Notifications / emails | Aucun wording affirmant « IDE libéral en mission d'établissement » trouvé. | Sans impact. |
| Templates libéraux | Templates IDEL cabinet et praticiens conservés. | Sans impact : cabinet IDEL et praticiens explicitement AUTORISÉS. |
| Seeds / compte Apple | `scripts/seed-demo.ts` crée un profil salarié et ne fabrique aucune mission. Prod : 0 mission `LIBERAL` au 12/07/2026. | Aligné ; aucune mission IDE libérale d'établissement à purger. |
| Docs historiques d'audit | Décrivent l'ancienne matrice à titre historique. | Hors runtime ; non réécrits, le document canonique est `docs/CONFORMITE.md`. |

## Wordings finaux affichés

- `BLOQUE / AS` : « L'exercice libéral n'est pas ouvert aux aides-soignants (Conseil d'État, 11/02/2025, n°491128). Mission proposée en salarié. »
- `BLOQUE / professions de la lettre` : « L'exercice libéral n'est pas prévu pour cette profession (lettre interministérielle du 30 décembre 2021, n° D21-031940, validée par le Conseil d'État — 11/02/2025, n°491128). Mission proposée en salarié. »
- `BLOQUE / centre de santé` : « Au sein d'un centre de santé, les professionnels sont salariés (art. L.6323-1-5 du code de la santé publique). »
- `BLOQUE / sans cadre propre` : « Cette profession n'a pas de cadre d'exercice libéral. Mission proposée en salarié. » Le manipulateur radio reçoit la précision L.4351-1 CSP.
- `NON_PROPOSE` : « Jolene propose cette mission en salarié : l'exercice libéral au sein d'un établissement expose à une requalification. »
- Reframe : « La règle se lit sur la profession demandée par cette mission, pas sur les diplômes du soignant. Un profil IADE peut donc candidater à une mission IDE, qui suit les règles IDE. »
- Reframe 3 200 h : « Tes missions salariées comptent dans les 3 200 h d'expérience requises pour l'installation en libéral. »

Le seed complet relu est celui de `supabase/migrations/20260712161000_finaliser_matrice_modes_exercice.sql`. Aucune cellule `public` n'est seedée : elle tombe au défaut `NON_PROPOSE`, pour toutes les professions.

## Finding structurel D2 — STOP D4 avant merge

Le profil libéral reste valide, mais le parcours vers une mission salariée n'est pas complet :

1. `getTypesContratSoignant` masque les missions salariées si `types_contrat_acceptes` ne contient que `LIBERAL` ; le feed peut donc être vide.
2. `fn_postuler_mission`, `fn_accepter_mission`, `fn_traiter_candidature` et `fn_assigner_mission_admin` refusent explicitement une mission `SALARIE` à un profil `type_exercice = LIBERAL`.
3. Le compte devrait pouvoir choisir/compléter ses documents salariés au moment de candidater, sans invalider son profil libéral. Ce flux touche matching, candidature, acceptation, documents et génération du contrat : impact structurel au-delà des wordings et seeds.

Conformément à D4, ce finding est documenté mais **non corrigé dans cette PR**. La matrice C peut être relue, testée et mergée indépendamment ; le flux « profil libéral pur → mission salariée » requiert une décision produit explicite sur le basculement contractuel et les documents avant implémentation.
