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
| Matching hiérarchique | L'ancien sens inverse permettait à un profil IDE de candidater à une mission IADE/IBODE via `accepte_non_specialises`. | Corrigé + testé : IADE/IBODE → mission IDE uniquement ; une mission IADE/IBODE exige la profession spécialisée correspondante. |
| Notifications / emails | Aucun wording affirmant « IDE libéral en mission d'établissement » trouvé. | Sans impact. |
| Templates libéraux | Templates IDEL cabinet et praticiens conservés. | Sans impact : cabinet IDEL et praticiens explicitement AUTORISÉS. |
| Seeds / compte Apple | `scripts/seed-demo.ts` crée un profil salarié et ne fabrique aucune mission. Prod : 0 mission `LIBERAL` au 12/07/2026. | Aligné ; aucune mission IDE libérale d'établissement à purger. |
| Docs historiques d'audit | Décrivent l'ancienne matrice à titre historique. | Hors runtime ; non réécrits, le document canonique est `docs/CONFORMITE.md`. |

## Wordings finaux affichés

- `BLOQUE / AS` : « L'exercice libéral n'est pas ouvert aux aides-soignants (Conseil d'État, 11/02/2025, n°491128). Mission proposée en salarié. »
- `BLOQUE / professions de la lettre` : « L'exercice libéral n'est pas prévu pour cette profession — lettre interministérielle du 30 décembre 2021 (n° D21-031940), validée par le Conseil d'État (11/02/2025, n°491128). Mission proposée en salarié. »
  Deux liens distincts sont affichés : « Lettre D21-031940 (texte original) », puis « Arrêt n°491128 — cas aide-soignant uniquement ». L'arrêt n'est jamais présenté comme l'énumération ou le jugement au fond des autres professions.
- `BLOQUE / centre de santé` : « Au sein d'un centre de santé, les professionnels sont salariés (art. L.6323-1-5 du code de la santé publique). »
- `BLOQUE / sans cadre propre` : « Cette profession n'a pas de cadre d'exercice libéral. Mission proposée en salarié. » Le manipulateur radio reçoit la précision L.4351-1 CSP.
- `NON_PROPOSE` : « Jolene propose cette mission en salarié : l'exercice libéral au sein d'un établissement expose à une requalification. »
- Reframe : « La règle se lit sur la profession demandée par cette mission, pas sur les diplômes du soignant. Un profil IADE peut donc candidater à une mission IDE, qui suit les règles IDE. »
- Reframe 3 200 h : « Tes missions salariées comptent dans les 3 200 h d'expérience requises pour l'installation en libéral. »

Le seed complet relu est celui de `supabase/migrations/20260712161000_finaliser_matrice_modes_exercice.sql` ; la migration de cascade `20260712163000` aligne ensuite le libellé C7 exact sur les cellules de doctrine déjà seedées. La migration corrective `20260713164844` encode deux URL pour ces cellules — copie du texte original de la lettre puis arrêt CE n°491128 explicitement limité au cas aide-soignant — et verrouille la hiérarchie IADE/IBODE → IDE dans son seul sens valide. `20260714053000` corrige sans réécrire l'historique le chemin public effectif du PDF primaire FEHAP. Aucune cellule `public` n'est seedée : elle tombe au défaut `NON_PROPOSE`, pour toutes les professions.

## D4 — cascade structurelle finalisée

Le profil libéral reste valide et ne détermine plus le contrat d'une mission :

1. `fn_resoudre_contrat_mission` résout le contrat depuis `mission.profession_requise`, le type d'établissement et la matrice. Une mission salariée reste accessible quel que soit `soignant.type_exercice`.
2. `fn_soignant_eligible_mission` porte une compatibilité unique pour feed, dashboard, swipe, suggestions, boost, relances, rebooking, pool, no-show/remplacement et notifications. La hiérarchie IADE/IBODE → mission IDE est conservée. Les comptes de test continuent à voir leurs données de démonstration, sans les exposer aux comptes réels.
3. Candidature, premier arrivé, traitement établissement et affectation admin utilisent tous `fn_finaliser_attribution_mission`. Le contrat, le paiement et les documents sont ceux du régime appliqué à la mission.
4. Une candidature salariée peut être déposée avant validation finale des documents ; l'attribution reste bloquée sur les documents `SALARIE_ONLY`/`TOUS`. Le profil libéral n'est jamais réécrit.
5. Les triggers historiques de calcul, cotisations, bulletin de paie, facturation d'honoraires et choix du paiement suivent `type_contrat_applique` et ne rebasculent plus une mission salariée selon le profil.
6. Le plafond de 48 h suit les missions salariées effectivement appliquées, même lorsque le profil global est libéral ; les missions libérales ne sont pas additionnées à ce décompte salarié.
7. Les propositions directes établissement/admin suivent la même résolution : le contrat concret est persisté sur la candidature et l'acceptation passe par l'attribution atomique centrale. Le dashboard renvoie la mission proposée dans la forme imbriquée attendue par la carte. La fenêtre de réponse de 2 h est imposée aussi côté serveur.
8. Le test SQL `tests/lot21/d4-cascade-profession-mission.test.sql` exécute la matrice, IADE × IDE, candidature, traitement, acceptation directe, édition, proposition/acceptation/expiration, paie, plafond 48 h, affectation admin, suggestions, rebooking, boost, feed, pool et notification dans une transaction annulée en fin de test.

Statut D4 : **GO après réussite du test SQL sur une base migrée**.
