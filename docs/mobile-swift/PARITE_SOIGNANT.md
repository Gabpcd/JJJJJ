# Matrice de parité soignant (plan §5 lots 1 et 4, §11 jour 10)

Une ligne par route `/soignant/*` de `src/App.tsx` (routes protégées l.312-344, redirections l.384-418).
Statuts possibles : **à faire**, **en cours lot 0**, **natif**, **renvoi web assumé**, **abandonné**. Le lot cible
suit le découpage du plan §5 ; il n'engage rien tant que la ligne n'est pas statuée avec sa preuve.
La preuve est une assertion (XCUITest démo, test STAGING, vecteur golden), jamais une capture seule (plan §4.7).

Critères : lot 1 renseignée à 45 % au moins ; lot 4 100 % statuée, zéro « abandonné » sur les onze parcours
cœur, matrice signée par Gabrielle. Les routes « redirection » du web sont des alias : natif signifie que le
routeur de liens (`JoleneCore/Links/LinkRouter.swift`) envoie l'alias vers l écran natif cible.

Dernière mise à jour : 2026-11-01 (initialisation lot 0, 50 routes ; relecture lot 0 : écart rôle `INCONNU`).

| Route | Écran web (src/App.tsx) | Statut natif | Lot cible | Preuve |
|---|---|---|---|---|
| `/soignant/tableau-de-bord` (l.312) | `DashboardSoignant` | en cours lot 0 (onglet Accueil, contenu lot 1) | 0 (onglet), 1 (contenu) | XCUITest démo JoleneUITests (ios-swift-ci.yml, 3 formats) — en cours |
| `/soignant/profil` (l.313) | `ProfilSoignant` | à faire | 3 | — |
| `/soignant/mon-compte` (l.314) | `MonCompteSoignant` | à faire | 1 | — |
| `/soignant/missions` (l.315) | `MissionsSoignant` | à faire | 1 | — |
| `/soignant/recherche-missions` (l.316) | `RechercheMissions` | en cours lot 0 (Explorer liste) | 0 (lecture), 1 (candidature) | XCUITest démo JoleneUITests (ios-swift-ci.yml, 3 formats) — en cours |
| `/soignant/swipe-missions` (l.317) | `RedirectionSwipeMissions` | à faire | 4 | — |
| `/soignant/missions/serie/:serieId` (l.318) | `DetailSerieSoignant` | à faire | 1 | — |
| `/soignant/missions/:id` (l.319) | `DetailMissionSoignant` | en cours lot 0 (détail mission, lecture) | 0 (lecture), 1 (candidature) | XCUITest démo JoleneUITests (ios-swift-ci.yml, 3 formats) — en cours |
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
- **Lot 1** : tableau de bord, Mes missions, candidature (`fn_confirmer_action_planning_v1`), séries, favoris,
  Mon compte avec suppression de compte (exigence Apple 5.1.1).
- **Lot 2** : présences et pointage, documents, conformité, contrats OTP (alias `/soignant/contrats`, `/soignant/dpae`).
- **Lot 3** : profil, revenus, Stripe Connect, notifications et préférences push, inscription
  native avec le repli `parcours_inscription` du rôle `INCONNU` (`useRole.ts` l.150-165) :
  jusque-là, un compte en cours d'inscription est **renvoyé vers le web** (écart assumé,
  `PRINCIPES.md` §5, `DECISIONS_LOT0.md`).
- **Lot 4** : parcours secondaires ; renvoi web assumé proposé pour premium, prévoyance, mandat et charges
  sociales (décision 3 : WebView bornée ou Safari, à trancher par Gabrielle).
- Aucune ligne n'est « abandonné » à l initialisation ; ce statut exige une décision écrite de Gabrielle.
