# Matrice de parité soignant (plan §5 lots 1 et 4, §11 jour 10)

Une ligne par route `/soignant/*` de `src/App.tsx` (routes protégées l.312-344, redirections l.384-418).
Statuts possibles : **à faire**, **en cours lot 0**, **natif**, **renvoi web assumé**, **abandonné**. Le lot cible
suit le découpage du plan §5 ; il n'engage rien tant que la ligne n'est pas statuée avec sa preuve.
La preuve est une assertion (XCUITest démo, test STAGING, vecteur golden), jamais une capture seule (plan §4.7).

Critères : lot 1 renseignée à 45 % au moins ; lot 4 100 % statuée, zéro « abandonné » sur les onze parcours
cœur, matrice signée par Gabrielle. Les routes « redirection » du web sont des alias : natif signifie que le
routeur de liens (`JoleneCore/Links/LinkRouter.swift`) envoie l'alias vers l écran natif cible.

Dernière mise à jour : 2026-11-02 (lot 1, T3 revue B8 : ligne Accueil « en cours », preuve XCUITest 3 formats
à acquérir ; T0 : sous-lignes Mes missions / Favoris / détail mission, cibles alignées sur `LOT1_PLAN.md` §1
et §7). Aucune ligne n'est statuée « natif » sans l'URL d'un run vert de `ios-swift-ci.yml` (gate
`Passed`, `skipped = 0`, iPhone, iPad portrait et iPad paysage) qui contient sa preuve : « mergé » ou
« compile » n'est pas « livré » (CLAUDE.md, PRINCIPES §7).

Sous-lignes (préfixées `›`) : une route web qui regroupe plusieurs onglets ou vues est détaillée pour que
chaque preuve soit attribuable ; la ligne de la route passe « natif » quand toutes ses sous-lignes le sont.

| Route | Écran web (src/App.tsx) | Statut natif | Lot cible | Preuve |
|---|---|---|---|---|
| `/soignant/tableau-de-bord` (l.312) | `DashboardSoignant` | en cours (lot 1 T3, preuve XCUITest 3 formats à acquérir : salutation, mes prochaines missions, missions pour vous, missions proposées, gains du mois relus mission par mission, notifications non lues et oubli de pointage en renvoi web `.safari`, état d'erreur et reprise ; bouton calendrier = point d'extension câblé par T5 ; bandeaux `BandeauAlerte48h` et « cumul d'activité » exclus, HARD STOP ; non portés : checklist d'activation, litiges, documents expirants, parrainage, widget de pointage (lot 2) ; écarts assumés avec le web : une fiche mission non relue ne rend « à confirmer » que sa mission (le web : tout le planning), carte des gains masquée si aucun montant n'est positif (le web : « Ce mois :  sur N missions »)) | 1 | — (prévu : `DemoAccueilTests.testAccueilDemo` et `.testAccueilErreurPuisReprise` sur iphone / ipad-portrait / ipad-landscape, gate `ios-swift-ci.yml` vert avec `skipped = 0`, URL du run à consigner ici ; acquis en unitaire : `DemoDashboardTests`, `AccueilAssemblageTests`, `AccueilModelTests`, `DashboardDecodingTests`, `SupabaseDashboardGatewayTests`) |
| `/soignant/profil` (l.313) | `ProfilSoignant` | à faire (lot 1 : soignant au profil incomplet renvoyé vers le web via Safari, décision 3) | 3 | — |
| `/soignant/mon-compte` (l.314) | `MonCompteSoignant` | à faire | 1 | — |
| `/soignant/mon-compte` › Suppression de compte (`SectionConfidentialite`) | edge `delete-account` | à faire (lot 1 T8, Apple 5.1.1 ; texte RGPD verbatim web tant que non validé) | 1 | — (prévu : `DemoCompteTests` + STAGING `soignants.nom = 'Supprimé'` relu, B9 données, décision 13) |
| `/soignant/mon-compte` › Sécurité (biométrie) | — (natif seulement, verrou `LAContext`, décision 1) | à faire | 1 (T9) | — (prévu : `DemoSessionTests`, `BiometricGateTests`, recette appareil Face ID) |
| `/soignant/missions` (l.315) | `MissionsSoignant` | à faire | 1 | — |
| `/soignant/missions` › Candidatures | `MissionsSoignant` onglet `candidatures` | à faire (lot 1 T5 : liste PostgREST `candidatures`, pagination 50, noms via `fn_etablissements_safe`) | 1 | — (prévu : `DemoMesMissionsTests`, `SupabaseMesMissionsGatewayTests`) |
| `/soignant/missions` › À venir | `MissionsSoignant` onglet `a-venir` | à faire (lot 1 T5 : missions ASSIGNEE, ajout au calendrier EventKit un événement par créneau PREVISIONNEL, décision 18) | 1 | — (prévu : `DemoMesMissionsTests`, `CalendarWriterTests`, recette appareil EventKit) |
| `/soignant/missions` › Passées | `MissionsSoignant` onglet `passees` | à faire (lot 1 T5 : pagination 50, montants serveur tels quels) | 1 | — (prévu : `DemoMesMissionsTests`) |
| `/soignant/recherche-missions` (l.316) | `RechercheMissions` | en cours lot 0 (Explorer liste ; lot 1 T4a : filtres, chips, compteur, carte MapKit lecture seule dans le détail ; swipe lot 4) | 0 (lecture), 1 (filtres, candidature) | XCUITest démo JoleneUITests (ios-swift-ci.yml, 3 formats) — en cours ; lot 1 : `DemoExplorerTests` |
| `/soignant/swipe-missions` (l.317) | `RedirectionSwipeMissions` | à faire (routé vers Explorer liste par `LinkRouter`, swipe lot 4) | 4 | — |
| `/soignant/missions/serie/:serieId` (l.318) | `DetailSerieSoignant` | renvoi web assumé au lot 1 (décision 11 : vecteurs golden de sélection de série portés en T2, détail de série natif au lot 4) | 4 (port), 1 (golden) | — (prévu : `RulesSelectionSerieTests`) |
| `/soignant/missions/:id` (l.319) | `DetailMissionSoignant` | en cours lot 0 (détail mission, lecture) | 0 (lecture), 1 (candidature, présence), 2 (pointage) | XCUITest démo JoleneUITests (ios-swift-ci.yml, 3 formats) — en cours |
| `/soignant/missions/:id` › lecture + candidature + confirmation de présence (lot 1), pointage (lot 2) | `DetailMissionSoignant` : POSTULER / ACCEPTER / PROPOSITION via `fn_confirmer_action_planning_v1`, choix de contrat, récapitulatif des créneaux, soft-gate `peut_candidater` (décision 3), bloc « Confirme ta présence » via `fn_confirmer_presence_mission` (décision 16), « Annuler ma participation » via `fn_annuler_mission_soignant` / `fn_annuler_candidature_soignant` (décision 4) ; `BlocConformite` non porté, refus `[CODE DU TRAVAIL]` verbatim (décision 2) | à faire (lot 1 T6a/T6b/T6c/T7) ; pointage `fn_pointer_*` lot 2 | 1 (candidature, présence, annulation), 2 (pointage) | — (prévu : `DemoCandidatureTests`, `DemoPresenceTests`, `DemoAnnulationTests` + STAGING T11 : candidature posée puis relue, proposition acceptée relue, présence relue, annulation relue) |
| `/soignant/mes-documents` (l.320) | `MesDocuments` | à faire | 2 | — |
| `/soignant/disponibilites` (l.321) | `MesDisponibilites` | à faire | 4 | — |
| `/soignant/conformite` (l.322) | `ConformiteSoignant` | à faire | 2 | — |
| `/soignant/presences` (l.323) | `PresencesSoignant` | à faire | 2 | — |
| `/soignant/presences/mission/:id` (l.324) | `DetailPresencesMission` | à faire | 2 | — |
| `/soignant/mes-gains` (l.325) | `MesGains` | à faire | 3 | — |
| `/soignant/mandat-facturation` (l.326) | `MandatFacturation` | à faire | 4 (renvoi web proposé, décision 3) | — |
| `/soignant/score` (l.327) | `PageScoreSoignant` | à faire | 4 | — |
| `/soignant/evaluations` (l.328) | `EvaluationsSoignant` | à faire | 4 | — |
| `/soignant/prevoyance` (l.329) | `PrevoyanceSoignant` | à faire | 4 (renvoi web proposé, décision 3) | — |
| `/soignant/attestation-heures` (l.330) | `AttestationHeures` | à faire | 4 | — |
| `/soignant/passer-en-liberal` (l.331) | `PasserEnLiberal` | à faire | 4 | — |
| `/soignant/exclusions` (l.332) | `ExclusionsSoignant` | à faire | 4 | — |
| `/soignant/premium` (l.333) | `PremiumSoignant` | à faire | 4 (renvoi web proposé, décision 3) | — |
| `/soignant/charges` (l.334) | `ChargesSociales` | à faire | 4 (renvoi web proposé, décision 3) | — |
| `/soignant/notifications` (l.335) | `PageNotifications` | à faire | 3 | — |
| `/soignant/parrainage` (l.336) | `PageParrainage` | à faire | 4 | — |
| `/soignant/messagerie` (l.337) | `PageMessagerie` | à faire | 4 | — |
| `/soignant/litiges` (l.338) | `LitigesContestationsSoignant` | à faire | 4 | — |
| `/soignant/stripe-connect` (l.339) | `PageStripeConnect` | à faire | 3 | — |
| `/soignant/classement` (l.340) | `ClassementSoignants` | à faire | 4 | — |
| `/soignant/parametres/notifications` (l.341) | `PageParametresNotifications` | à faire | 3 | — |
| `/soignant/parametres/recherches-sauvegardees` (l.342) | `PageRecherchesSauvegardees` | à faire | 4 | — |
| `/soignant/pool-urgence` (l.343) | `PoolUrgenceSoignant` | à faire | 4 | — |
| `/soignant/mes-favoris` (l.344) | `MesFavorisSoignant` | à faire | 1 | — |
| `/soignant/mes-favoris` › Missions | `MesFavorisSoignant` onglet missions (`BoutonSauvegarderMission`) | à faire (lot 1 T4b : ajout/retrait via PostgREST `missions_sauvegardees` sous RLS, étoile sur carte et détail, décision 8) | 1 | — (prévu : `DemoFavorisTests`, `SupabaseFavorisGatewayTests`) |
| `/soignant/mes-favoris` › Établissements | `MesFavorisSoignant` onglet établissements | à faire (lot 1 T4b : lecture `fn_mes_favoris_etablissements` + retrait `fn_toggle_favori_etablissement(false)` ; **pas d'ajout** en natif, non exposé sur le web, décision 8) | 1 | — (prévu : `DemoFavorisTests`) |
| `/soignant/mes-matches` (l.384) | redirection vers `/soignant/missions` | à faire | 1 (alias de /soignant/missions) | — |
| `/soignant/documents` (l.385) | redirection vers `/soignant/mes-documents?tab=justificatifs` | à faire | 2 (alias de /soignant/mes-documents) | — |
| `/soignant/planning` (l.390) | redirection vers `/soignant/missions?tab=a-venir` | à faire | 1 (alias de /soignant/missions) | — |
| `/soignant/calendrier-sync` (l.391) | redirection vers `/soignant/missions?tab=a-venir` | à faire | 1 (alias de /soignant/missions) | — |
| `/soignant/reputation` (l.393) | redirection vers `/soignant/profil` | à faire | 3 (alias de /soignant/profil) | — |
| `/soignant/mes-factures-honoraires` (l.395) | redirection vers `/soignant/mes-gains?tab=factures` | à faire | 3 (alias de /soignant/mes-gains) | — |
| `/soignant/mes-avances` (l.396) | redirection vers `/soignant/mes-gains?tab=avances` | à faire | 3 (alias de /soignant/mes-gains) | — |
| `/soignant/bulletins-paie` (l.397) | redirection vers `/soignant/mes-gains?tab=bulletins` | à faire | 3 (alias de /soignant/mes-gains) | — |
| `/soignant/historique-missions` (l.398) | redirection vers `/soignant/missions?tab=passees` | à faire | 1 (alias de /soignant/missions) | — |
| `/soignant/fiabilite` (l.399) | redirection vers `/soignant/score` | à faire | 4 (alias de /soignant/score) | — |
| `/soignant/fiabilite-legacy` (l.400) | redirection vers `/soignant/score` | à faire | 4 (alias de /soignant/score) | — |
| `/soignant/parcours-3200h` (l.401) | redirection vers `/soignant/passer-en-liberal` | à faire | 4 (alias de /soignant/passer-en-liberal) | — |
| `/soignant/dpae` (l.402) | redirection vers `/soignant/mes-documents?tab=dpae` | à faire | 2 (alias de /soignant/mes-documents) | — |
| `/soignant/reclamations` (l.403) | redirection vers `/soignant/litiges?tab=reclamations` | à faire | 4 (alias de /soignant/litiges) | — |
| `/soignant/contrats` (l.404) | redirection vers `/soignant/mes-documents?tab=contrats` | à faire | 2 (alias de /soignant/mes-documents) | — |
| `/soignant/parametres-complet` (l.417) | redirection vers `/soignant/mon-compte` | à faire | 1 (alias de /soignant/mon-compte) | — |
| `/soignant/parametres` (l.418) | redirection vers `/soignant/mon-compte` | à faire | 1 (alias de /soignant/mon-compte) | — |

## Lecture

- **Lot 0** : trois lignes « en cours » (Explorer liste, détail mission en lecture, onglet Accueil en coquille). Elles
  passent « natif » quand `JoleneUITests` les couvre sur iPhone, iPad portrait et iPad paysage (job « UI » de
  `ios-swift-ci.yml`) et que la connexion STAGING est exécutée une fois (`ios-swift-staging.yml`).
- **Lot 1** (`LOT1_PLAN.md` §1, décisions §7 du 02/11/2026) : tableau de bord, Mes missions (3 onglets +
  calendrier EventKit), Explorer filtres/favoris/carte, candidature (`fn_confirmer_action_planning_v1`),
  confirmation de présence (`fn_confirmer_presence_mission`), annulation avec justificatif, Mon compte avec
  suppression de compte (exigence Apple 5.1.1), session durcie (audit, biométrie, drapeaux `fn_param_bool`),
  Universal Links et reset mot de passe (`token_hash` et implicit seulement, décision 7). Les séries restent
  « renvoi web assumé » au lot 1 (décision 11). Comptage du critère « ≥ 45 % renseignée » : sur les 50 routes
  (les sous-lignes `›` précisent la preuve d'une route, elles ne comptent pas comme routes).
- **Lot 2** : présences et pointage, documents, conformité, contrats OTP (alias `/soignant/contrats`, `/soignant/dpae`).
- **Lot 3** : profil, revenus, Stripe Connect, notifications et préférences push, inscription
  native avec le repli `parcours_inscription` du rôle `INCONNU` (`useRole.ts` l.150-165) :
  jusque-là, un compte en cours d'inscription est **renvoyé vers le web** (écart assumé,
  `PRINCIPES.md` §5, `DECISIONS_LOT0.md`).
- **Lot 4** : parcours secondaires ; renvoi web assumé proposé pour premium, prévoyance, mandat et charges
  sociales (décision 3 : WebView bornée ou Safari, à trancher par Gabrielle).
- Aucune ligne n'est « abandonné » à l initialisation ; ce statut exige une décision écrite de Gabrielle.
