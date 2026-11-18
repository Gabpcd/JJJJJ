# Matrice de parité établissement (plan §5 lot 5, `LOT5_PLAN.md` §3 T0 et T14)

Une ligne par route établissement de `src/App.tsx` : routes protégées `/etablissement/*` (l.347-376), redirections
(l.409-434), `/etablissement/missions/:id` (l.440), contrat partagé soignant/établissement (l.437-438), invitation
d'équipe (l.433) et inscription établissement (l.288) — **47 lignes**, recomptées depuis `App.tsx` par
`tests/node/contrats-etablissement-ios.node.mjs` (une route ajoutée ou déplacée sur le web rougit la garde).

Colonnes : **Statut natif** — `à faire` tant que la tranche n'a pas livré sa preuve, puis `natif` ou
`renvoi web assumé` (même vocabulaire que `PARITE_SOIGNANT.md`) ; **Cible** — statut visé au lot 5 :
`natif` (écran natif, alias routé vers lui par `LinkRouter.etablissementDestination`, T2b) ou `renvoi web assumé`
(lien Safari `SFSafariViewController`, D16, table unique `RenvoisWebEtab.swift` de T12 ; la session web n'est pas
partagée, reconnexion annoncée par le texte du renvoi). **Zéro « abandonné ».** La preuve est une assertion
(XCUITest démo trois formats, test STAGING relu, vecteur golden), jamais une capture seule (`CLAUDE.md`,
« Protocole de preuve »). La matrice est signée par Gabrielle à la clôture (T14, `LOT5_PLAN.md` §6.7).

Dernière mise à jour : 2026-11-02 (lot 5, T0 : statut cible de chaque route ; aucune ligne statuée avant les
preuves des tranches).

Écarts d'implémentation assumés (consignés ici, `LOT5_PLAN.md` corrections 15, 20-22) :

- `/etablissement/missions/:id` monte `DetailMission.tsx` via `MissionDepuisNotification.tsx` (l.80-83, l.103) : le
  natif lit les candidatures par `fn_lire_candidatures_mission_habilitee` (un appel, cohorte TEST filtrée, noms à
  l'initiale), plus strict que `ListeCandidatures` en PostgREST (LECTURE_SEULE n'y accède pas). Surfaces du même
  écran non reprises, renvoyées au web : alerte « Risque de requalification en CDI au-delà de 150 jours » (D27),
  « Terminer la mission », litige, booster, garantie, soignants recommandés.
- `/etablissement/missions` et `/etablissement/missions/:id` (T5) : ni montant (taux, net estimé, commission, Rist),
  ni regroupement par série, ni recherche par intitulé, ni tri « candidatures d'abord », ni filtre `?periode=mois`,
  ni pastille « Litige » lue dans `litiges`, ni nom du soignant sur la carte (`fn_mes_soignants_etablissement` non
  appelée ; nom lu au détail par `fn_soignant_pour_etablissement`) ; pastille de candidatures réservée à la permission
  `candidatures` ; planning non exact « à confirmer » sur la carte (le web y affiche un repli ponctuel). Republier,
  dupliquer, modifier, annuler, terminer, évaluer : sur jolene.app.
- Candidatures de `/etablissement/missions/:id` (T6, destination `.candidatures`) : ni badge « hors profession »,
  ni statut d'internat, ni régime d'exercice du profil, ni note moyenne, ni détail d'étudiant, ni popover du score
  (D8, D10) ; pas de case du cadre étudiant (étudiant aide-soignant → « Accepter sur jolene.app ») ; mention CGV art. 8
  **non affichée** tant que Gabrielle ne l'a pas validée (HARD STOP n°4) : un lien de navigation neutre vers la page
  des CGV la remplace ; refus de paiement (`fn_trg_gate_assignation_paiement`) verbatim avec un renvoi vers la
  facturation web ; succès annoncé seulement après relecture (`ACCEPTEE` + mission `ASSIGNEE`, ou `REFUSEE`).
- Accueil : « présences à valider » sans compteur jusqu'à T8, « évaluations à faire » en lien web sans compteur
  (aucune source serveur, correction 20) ; aucun graphique ni montant (D15).
- Acceptation native limitée aux missions `SALARIE` hors `MEDECIN` (D25) ; étudiant aide-soignant (cadre étudiant),
  mission `TOUS`/`LIBERAL` ou `MEDECIN` : « Accepter sur jolene.app » ; le refus reste natif.
- Membre de plusieurs établissements : servi sur l'établissement choisi par `mon_etablissement_id()`, comme le web ;
  une divergence ponctuelle renvoie au web (§2.2).

| Route | Écran web (src/App.tsx) | Statut natif | Cible | Tranche | Preuve prévue |
|---|---|---|---|---|---|
| `/etablissement/tableau-de-bord` (l.352) | `DashboardEtablissement` | à faire | natif (Accueil : actions prioritaires sans graphique) | T4 | `DemoEtabAccueilTests` (3 formats), `PrioriteActionsTests` par rôle |
| `/etablissement/dashboard` (l.433) | redirection → `/etablissement/tableau-de-bord` | à faire | natif (alias de l'Accueil) | T2b | `EtabRouteTests` |
| `/etablissement/missions` (l.360) | `ListeMissions` | à faire | natif (liste par statut paginée, compteurs, sans montant) | T5 | `DemoEtabMissionsTests`, `SupabaseEtabMissionsGatewayTests` |
| `/etablissement/missions/:id` (l.443) | `MissionDepuisNotification` → `DetailMission` | à faire | natif (détail, planning, soignant, liens candidatures / pointage / présences / contrat / message) | T5, T6, T7 | `DemoEtabMissionsTests`, `DemoEtabCandidaturesTests`, `DemoEtabPointageTests` ; STAGING « candidature acceptée relue » et « QR décodé » (T13) |
| `/etablissement/missions/creer` (l.361) | `CreerMission` | à faire | natif partiel (mission simple ou urgente, salariée, taux horaire ; libéral, tous contrats, MEDECIN, récurrence avancée et duplication en renvoi web, D8) | T9 | `DemoEtabPublicationTests`, `PublicationPayloadTests` ; STAGING « mission simple créée et relue » (T13) |
| `/etablissement/presences` (l.363) | `PresencesEtablissement` | à faire | natif (onglets à valider / en cours / validées / alertes, validation, lot, contestation, note) | T8 (B9) | `DemoEtabPresencesTests` ; STAGING « présence validée relue » (T13) |
| `/etablissement/presences/mission/:id` (l.379) | `DetailPresencesMission` | à faire | natif (présences de la mission et code rotatif, sans montants ni simulation de paie) | T7, T8 | `DemoEtabPointageTests`, `DemoEtabPresencesTests` |
| `/etablissement/contrats` (l.364) | `ListeContrats` | à faire | natif (liste, lecture serveur, permission `contrats`) | T10 | `DemoEtabContratsTests` |
| `/etablissement/assurance` (l.424) | redirection → `/etablissement/contrats` | à faire | natif (alias des contrats) | T2b | `EtabRouteTests` |
| `/etablissement/contrat-plateforme` (l.434) | redirection → `/etablissement/contrats` | à faire | natif (alias des contrats) | T2b | `EtabRouteTests` |
| `/contrat/:id` (l.440) | `ContratMission` (soignant et établissement) | à faire | natif (signature OTP établissement seulement ; CDD à préparer et signature manuscrite en renvoi web) | T10, T2b | `DemoEtabContratsTests`, `DeepLinkCoordinatorTests` (écran de l'espace courant) |
| `/etablissement/messagerie` (l.377) | `PageMessagerie` | à faire | natif (port messagerie du lot 4 en contexte établissement) | T11 | `DemoEtabMessagerieTests` |
| `/etablissement/mon-compte` (l.353) | `MonCompteEtablissement` | à faire | natif minimal (nom, logo, rôle d'équipe, déconnexion, renvois web, suppression = lien web) | T12 | `DemoEtabCompteTests`, `RenvoisWebEtabTests` |
| `/etablissement/score` (l.350) | `PageScoreEtablissement` | à faire | renvoi web assumé | T12 | `RenvoisWebEtabTests` (chemin présent dans `App.tsx`) |
| `/etablissement/mes-reclamations` (l.351) | `MesReclamationsEtab` | à faire | renvoi web assumé | T12 | `RenvoisWebEtabTests` |
| `/etablissement/reclamations` (l.437) | redirection → `/etablissement/litiges?tab=reclamations` | à faire | renvoi web assumé | T2b, T12 | `EtabRouteTests` (`.safari`) |
| `/etablissement/activer` (l.354) | `ActiverEtablissement` | à faire | renvoi web assumé (CTA du bandeau de vérification de l'Accueil) | T4, T12 | `DemoEtabAccueilTests` (URL routée) |
| `/etablissement/finaliser-inscription` (l.412) | redirection → `/etablissement/activer` | à faire | renvoi web assumé | T2b | `EtabRouteTests` |
| `/etablissement/verification` (l.413) | redirection → `/etablissement/activer` | à faire | renvoi web assumé | T2b | `EtabRouteTests` |
| `/etablissement/parametres/notifications` (l.355) | `PageParametresNotifications` | à faire | renvoi web assumé | T12 | `RenvoisWebEtabTests` |
| `/etablissement/parametres/recherches-sauvegardees` (l.356) | `PageRecherchesSauvegardees` | à faire | renvoi web assumé | T12 | `RenvoisWebEtabTests` |
| `/etablissement/parametres` (l.357) | `Parametres` | à faire | renvoi web assumé (dont suppression du compte `?tab=securite#suppression-compte`, D17) | T12 | `RenvoisWebEtabTests`, `DemoEtabCompteTests` |
| `/etablissement/profil` (l.422) | redirection → `/etablissement/parametres?tab=profil` | à faire | renvoi web assumé | T2b | `EtabRouteTests` |
| `/etablissement/mon-groupe` (l.425) | redirection → `/etablissement/parametres?tab=groupe` | à faire | renvoi web assumé | T2b | `EtabRouteTests` |
| `/etablissement/exclusions` (l.428) | redirection → `/etablissement/parametres?tab=exclusions` | à faire | renvoi web assumé | T2b | `EtabRouteTests` |
| `/etablissement/api` (l.429) | redirection → `/etablissement/parametres?tab=securite` | à faire | renvoi web assumé | T2b, T12 | `EtabRouteTests`, `RenvoisWebEtabTests` |
| `/etablissement/soignants` (l.358) | `RechercheSoignantsEtab` | à faire | renvoi web assumé (annuaire) | T12 | `RenvoisWebEtabTests` |
| `/etablissement/soignants/:id` (l.359) | `ProfilSoignantEtablissement` | à faire | renvoi web assumé (annuaire) | T2b | `EtabRouteTests` |
| `/etablissement/missions/:id/modifier` (l.362) | `ModifierMission` | à faire | renvoi web assumé (modification et annulation) | T5 | `DemoEtabMissionsTests` (`etab-mission-web-modifier`) |
| `/etablissement/facturation` (l.365) | `FacturationEtablissement` | à faire | renvoi web assumé (facturation, SEPA ; aussi après un refus de paiement à l'acceptation) | T6, T12 | `RenvoisWebEtabTests`, `SupabaseEtabCandidaturesGatewayTests` (`paiementNonConfigure`) |
| `/etablissement/facturation/:id` (l.366) | `DetailFacture` | à faire | renvoi web assumé | T2b | `EtabRouteTests` |
| `/etablissement/obligations` (l.435) | redirection → `/etablissement/facturation` | à faire | renvoi web assumé | T2b | `EtabRouteTests` |
| `/etablissement/export-paie` (l.367) | `ExportPaie` | à faire | renvoi web assumé | T12 | `RenvoisWebEtabTests` |
| `/etablissement/rh` (l.368) | `DashboardRH` | à faire | renvoi web assumé | T12 | `RenvoisWebEtabTests` |
| `/etablissement/analytics` (l.423) | redirection → `/etablissement/rh?tab=analytics` | à faire | renvoi web assumé | T2b | `EtabRouteTests` |
| `/etablissement/notifications` (l.369) | `PageNotifications` | à faire | renvoi web assumé (centre de notifications plein écran) | T12 | `RenvoisWebEtabTests` |
| `/etablissement/premium` (l.370) | `PremiumEtablissement` | à faire | renvoi web assumé | T12 | `RenvoisWebEtabTests` |
| `/etablissement/chorus-config` (l.371) | `ChorusConfig` | à faire | renvoi web assumé | T12 | `RenvoisWebEtabTests` |
| `/etablissement/pool-urgence` (l.372) | `PoolUrgenceEtablissement` | à faire | renvoi web assumé | T12 | `RenvoisWebEtabTests` |
| `/etablissement/mes-favoris` (l.373) | `MesFavorisEtablissement` | à faire | renvoi web assumé | T12 | `RenvoisWebEtabTests` |
| `/etablissement/parrainage` (l.374) | `PageParrainageEtablissement` | à faire | renvoi web assumé | T12 | `RenvoisWebEtabTests` |
| `/etablissement/equipe` (l.375) | `EquipeEtablissement` | à faire | renvoi web assumé (lien visible avec `gerer_equipe`) | T12 | `RenvoisWebEtabTests`, `DemoEtabCompteTests` par rôle |
| `/etablissement/evaluations-a-faire` (l.376) | `EvaluationsAFaireEtab` | à faire | renvoi web assumé (action prioritaire sans compteur, correction 20) | T4, T12 | `DemoEtabAccueilTests`, `RenvoisWebEtabTests` |
| `/etablissement/litiges` (l.378) | `LitigesEtablissement` | à faire | renvoi web assumé (action prioritaire « litiges » vers le web) | T4, T12 | `DemoEtabAccueilTests`, `RenvoisWebEtabTests` |
| `/contrat/:id/certificat` (l.441) | `CertificatSignaturePage` | à faire | renvoi web assumé (certificat de signature) | T2b | `EtabRouteTests` |
| `/etab/invitation/:token` (l.436) | `AccepterInvitationEtab` | à faire | renvoi web assumé (invitation d'équipe) | T2b | `EtabRouteTests` |
| `/inscription/etablissement` (l.291) | `InscriptionRapide` (type `ETABLISSEMENT`) | à faire | renvoi web assumé (inscription établissement) | T2b | `EtabRouteTests` |
