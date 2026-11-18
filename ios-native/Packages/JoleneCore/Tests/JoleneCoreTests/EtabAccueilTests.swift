import XCTest
@testable import JoleneCore

/// Accueil établissement (lot 5, T4) : décodage tolérant de `fn_stats_dashboard_etablissement` (compteurs seulement),
/// planning des 31 prochains jours (port de `construireOccurrencesPlanning`), actions prioritaires (ordre du web,
/// filtrage fail-closed par les booléens servis), modèle d'écran (epoch, partiel, audit best-effort).
final class EtabDashboardDecodingTests: XCTestCase {
    func testFixtureDuDumpDecodeeEnCompteursSeulement() throws {
        let fichier = try DemoFixtures.loadEtabDashboard()
        XCTAssertEqual(fichier.stats, EtabDashboardStats(candidaturesEnAttente: 3, messagesNonLus: 2, litigesOuverts: 1,
                                                         nbFacturesImpayees: 0, aDejaPublie: true))
        XCTAssertEqual(EtabDashboardStats.clesDecodees.sorted(),
                       ["a_deja_publie", "candidatures_en_attente", "litiges_ouverts", "messages_non_lus", "nb_factures_impayees"])
        // Montants et noms de soignants jamais décodés (D15, correction 4) : la réencodée n'en porte aucun.
        let reencode = String(decoding: try JSONEncoder().encode(fichier.stats), as: UTF8.self)
        for interdit in ["commissions", "candidatures_recentes", "missions_assignees_detail", "soignant_nom", "montant"] {
            XCTAssertFalse(reencode.contains(interdit), interdit)
        }
    }

    func testValeursAbsentesNullesNegativesOuMalTypeesValentNil() throws {
        let json = #"{"candidatures_en_attente":null,"messages_non_lus":"2","litiges_ouverts":-1,"a_deja_publie":"oui"}"#
        let stats = try JSONDecoder().decode(EtabDashboardStats.self, from: Data(json.utf8))
        XCTAssertEqual(stats, EtabDashboardStats())
    }
}

final class EtabPlanningAccueilTests: XCTestCase {
    private let maintenant = DemoWorld.fixedNow // 2026-11-02T00:00Z, 01:00 à Paris

    func testFinDeFenetreDerniereMillisecondeDuTrenteEtUniemeJourCivil() {
        XCTAssertEqual(DateHeureParis.isoUTC(EtabPlanningAccueil.finFenetre(maintenant)), "2026-12-03T22:59:59.999Z")
    }

    func testOccurrencesDeLaFenetreTrieesEtPlanningIncompletSignale() async throws {
        let snapshot = try await DemoEtabDashboardGateway().tableauDeBord(context: Self.contexte())
        let planning = try XCTUnwrap(snapshot.planning)
        XCTAssertEqual(planning.occurrences.map(\.id), [
            "demo-etab-mission-nuit:demo-etab-creneau-nuit",
            "demo-etab-mission-en-cours:demo-etab-creneau-en-cours-2",
            "demo-etab-mission-en-cours:demo-etab-creneau-en-cours-3",
            "demo-etab-mission-ouverte:demo-etab-creneau-ouverte-1",
            "demo-etab-mission-ouverte:demo-etab-creneau-ouverte-2",
            "demo-etab-mission-ouverte:demo-etab-creneau-ouverte-3",
            "demo-etab-mission-incomplete:demo-etab-creneau-incomplete-1",
        ], "créneau terminé exclu, tri stable par début (ordre des missions à début égal)")
        XCTAssertEqual(planning.missionsSansPlanning.map(\.id), ["demo-etab-mission-incomplete"])
        XCTAssertEqual(EtabAccueilPresentation.compteurPlanning(planning), "(7 créneaux · 1 à confirmer)")
        XCTAssertFalse(snapshot.lecturePartielle)
        let nuit = planning.occurrences[0]
        XCTAssertEqual(EtabAccueilPresentation.horaire(nuit), "lun. 2 nov. · 00:00 → 08:00 · 8h")
        XCTAssertEqual(EtabAccueilPresentation.statut(nuit.statut), "Assignée")
    }

    func testRepliPonctuelEtPeriodeGlobaleJamaisEtalee() {
        let ponctuelle = EtabMissionPlanifiee(id: "m-1", intitule: "Ponctuelle", statut: "OUVERTE",
                                              debutLe: "2026-11-03T07:00:00+01:00", finLe: "2026-11-03T15:30:00+01:00", nbCreneaux: nil)
        let longue = EtabMissionPlanifiee(id: "m-2", intitule: "Longue", statut: "ASSIGNEE",
                                          debutLe: "2026-11-03T07:00:00+01:00", finLe: "2026-11-20T19:00:00+01:00", nbCreneaux: 2)
        let planning = EtabPlanningAccueil.construire(missions: [ponctuelle, longue], creneaux: [], maintenant: maintenant)
        XCTAssertEqual(planning.occurrences.map(\.id), ["m-1:mission-ponctuelle-m-1"], "une mission longue n'est jamais étalée")
        XCTAssertEqual(EtabAccueilPresentation.horaire(planning.occurrences[0]), "mar. 3 nov. · 07:00 → 15:30 · 8,5h")
        XCTAssertEqual(planning.missionsSansPlanning.map(\.id), ["m-2"],
                       "repli ponctuel exact (CompletudePlanning) : la mission ponctuelle n'est pas « à confirmer »")
        XCTAssertEqual(EtabAccueilPresentation.periodePrevue(longue), "Période prévue : 3 nov. 2026 → 20 nov. 2026")
    }

    /// Intégration de la vague C (revue B8 de #1160, m4) : « planning à confirmer » est un seul prédicat,
    /// `CompletudePlanning`, à l'Accueil comme sur la carte de la liste des missions (principe « État dérivé »).
    func testPlanningAConfirmerMemeVerdictQueLaListeDesMissions() {
        func creneau(_ id: String, _ mission: String, _ debut: String, _ fin: String?) -> MissionSlot {
            MissionSlot(id: id, missionId: mission, debut: debut, fin: fin, estPause: false, typeCreneau: "PREVISIONNEL")
        }
        let cas: [(EtabMissionPlanifiee, [MissionSlot], Bool)] = [
            // nb_creneaux = 0, aucune ligne, ≤ 24 h : repli ponctuel exact.
            (EtabMissionPlanifiee(id: "p-0", intitule: "Ponctuelle", statut: "OUVERTE", debutLe: "2026-11-03T07:00:00+01:00",
                                  finLe: "2026-11-03T15:00:00+01:00", nbCreneaux: 0), [], true),
            // Nombre égal et fin renseignée, mais fin ≤ début : jamais exact (l'ancien critère local l'acceptait).
            (EtabMissionPlanifiee(id: "p-1", intitule: "Inversée", statut: "OUVERTE", debutLe: "2026-11-04T07:00:00+01:00",
                                  finLe: "2026-11-04T15:00:00+01:00", nbCreneaux: 1),
             [creneau("c-1", "p-1", "2026-11-04T15:00:00+01:00", "2026-11-04T07:00:00+01:00")], false),
            // Borne illisible : jamais exact.
            (EtabMissionPlanifiee(id: "p-2", intitule: "Illisible", statut: "ASSIGNEE", debutLe: "2026-11-05T07:00:00+01:00",
                                  finLe: "2026-11-05T15:00:00+01:00", nbCreneaux: 1),
             [creneau("c-2", "p-2", "pas une date", "2026-11-05T15:00:00+01:00")], false),
            // Exact.
            (EtabMissionPlanifiee(id: "p-3", intitule: "Exacte", statut: "ASSIGNEE", debutLe: "2026-11-06T07:00:00+01:00",
                                  finLe: "2026-11-06T15:00:00+01:00", nbCreneaux: 1),
             [creneau("c-3", "p-3", "2026-11-06T07:00:00+01:00", "2026-11-06T15:00:00+01:00")], true),
        ]
        let planning = EtabPlanningAccueil.construire(missions: cas.map(\.0), creneaux: cas.flatMap(\.1), maintenant: maintenant)
        XCTAssertEqual(planning.missionsSansPlanning.map(\.id), ["p-1", "p-2"])
        for (mission, creneaux, exact) in cas {
            XCTAssertEqual(EtabPlanningAccueil.planningExact(mission, creneaux: creneaux), exact, mission.id)
            let resume = EtabMissionResume(id: mission.id, intitule: mission.intitule, statut: mission.statut,
                                           debutLe: mission.debutLe, finLe: mission.finLe, nbCreneaux: mission.nbCreneaux,
                                           etablissementId: "demo-etab-1")
            XCTAssertEqual(EtabMissionsPresentation.carte(resume, creneaux: creneaux, candidaturesEnAttente: nil).planningAConfirmer,
                           !exact, "\(mission.id) : même verdict sur la carte de la liste des missions")
        }
    }

    func testFinLeLendemainEtDurees() {
        let nuit = EtabOccurrencePlanning(id: "o", missionId: "m", intitule: "Nuit", statut: "EN_COURS",
                                          debut: "2026-11-03T21:00:00+01:00", fin: "2026-11-04T07:15:00+01:00")
        XCTAssertEqual(EtabAccueilPresentation.horaire(nuit), "mar. 3 nov. · 21:00 → mer. 4 nov. · 07:15 (lendemain) · 10,25h")
        XCTAssertEqual(EtabAccueilPresentation.statut("EN_COURS"), "Active")
        XCTAssertEqual(EtabAccueilPresentation.duree(7.5), "7,5")
        XCTAssertEqual(EtabAccueilPresentation.duree(12), "12")
    }

    static func contexte(role: RoleEtab = .proprietaire, epoch: Int = 1) -> EtablissementReadContext {
        EtablissementReadContext(userId: DemoEtablissementWorld.userId, etablissementId: "demo-etab-1", roleEtab: role,
                                 permissions: PermissionsEtab(accordees: Set(PermissionEtab.allCases)), epoch: epoch)
    }
}

final class PrioriteActionsTests: XCTestCase {
    private let profil = EtablissementProfil(id: "etab-1", nom: "Clinique", peutPublierMissions: true)
    private let stats = EtabDashboardStats(candidaturesEnAttente: 3, messagesNonLus: 2, litigesOuverts: 1, nbFacturesImpayees: 0)

    /// Permissions servies par rôle : fixture générée depuis le `CASE` SQL (aucune correspondance écrite ici).
    private func permissions(_ role: String) throws -> PermissionsEtab {
        try XCTUnwrap(try DemoFixtures.loadPermissionsEtab().roles[role], role)
    }

    private func cles(_ role: String, profil: EtablissementProfil? = nil, stats: EtabDashboardStats? = nil) throws -> [CleActionPrioritaire] {
        PrioriteActions.liste(profil: profil ?? self.profil, stats: stats ?? self.stats, permissions: try permissions(role)).map(\.cle)
    }

    func testOrdreEtFiltrageParRole() throws {
        XCTAssertEqual(try cles("PROPRIETAIRE"), [.candidatures, .presences, .litiges, .evaluations, .messages])
        XCTAssertEqual(try cles("ADMIN_GROUPE"), [.candidatures, .presences, .litiges, .evaluations, .messages])
        XCTAssertEqual(try cles("RH"), [.candidatures, .presences, .litiges, .evaluations, .messages])
        XCTAssertEqual(try cles("POINTAGE_ONLY"), [.presences, .messages])
        XCTAssertEqual(try cles("LECTURE_SEULE"), [.messages])
    }

    func testFacturesSousLecturePaiementOuPaiementSeulement() throws {
        var avecFactures = stats
        avecFactures.nbFacturesImpayees = 2
        XCTAssertEqual(try cles("PROPRIETAIRE", stats: avecFactures), [.candidatures, .presences, .litiges, .factures, .evaluations, .messages])
        XCTAssertEqual(try cles("LECTURE_SEULE", stats: avecFactures), [.factures, .messages])
        XCTAssertFalse(try cles("RH", stats: avecFactures).contains(.factures))
        XCTAssertEqual(try cles("POINTAGE_ONLY", stats: avecFactures), [.presences, .messages], "POINTAGE_ONLY : jamais candidatures ni factures")
        let factures = PrioriteActions.liste(profil: profil, stats: avecFactures, permissions: try permissions("PROPRIETAIRE"))
            .first { $0.cle == .factures }
        XCTAssertEqual(factures?.titre, "2 facture(s) à régler")
        XCTAssertEqual(factures?.compteur, 2)
    }

    func testBlocageAvantVerificationPuisToutLeReste() throws {
        var bloque = profil
        bloque.bloqueAutoLe = "2026-11-01T07:00:00.000Z"
        XCTAssertEqual(try cles("POINTAGE_ONLY", profil: bloque), [.blocage, .presences, .messages], "blocage visible de tout membre")
        var bloqueNonVerifie = bloque
        bloqueNonVerifie.peutPublierMissions = false
        XCTAssertEqual(try cles("PROPRIETAIRE", profil: bloqueNonVerifie).prefix(2), [.blocage, .candidatures], "un seul blocage")
        var nonVerifie = profil
        nonVerifie.peutPublierMissions = false
        XCTAssertEqual(try cles("LECTURE_SEULE", profil: nonVerifie), [.verification, .messages])
        nonVerifie.peutPublierMissions = nil
        XCTAssertEqual(try cles("LECTURE_SEULE", profil: nonVerifie).first, .verification, "valeur absente : comme `!peut_publier_missions`")
    }

    func testCompteursNulsOuAbsentsSansAction() throws {
        let vides = EtabDashboardStats(candidaturesEnAttente: 0, messagesNonLus: nil, litigesOuverts: 0, nbFacturesImpayees: nil)
        XCTAssertEqual(try cles("PROPRIETAIRE", stats: vides), [.presences, .evaluations], "présences et évaluations : sans compteur (correction 20)")
        XCTAssertEqual(PrioriteActions.liste(profil: profil, stats: vides, permissions: .aucune), [])
    }

    func testTextesDuWebAuSingulierEtAuPluriel() {
        XCTAssertEqual(PrioriteActions.Textes.candidatures(1), "1 soignant attend votre réponse")
        XCTAssertEqual(PrioriteActions.Textes.candidatures(3), "3 soignants attendent votre réponse")
        XCTAssertEqual(PrioriteActions.Textes.litiges(1), "1 litige en cours")
        XCTAssertEqual(PrioriteActions.Textes.litiges(2), "2 litiges en cours")
        XCTAssertEqual(PrioriteActions.Textes.messages(1), "1 message non lu")
        XCTAssertEqual(PrioriteActions.Textes.messages(2), "2 messages non lus")
    }

    /// Intégration de la vague C (revue B8 de #1160, m3) : présences et évaluations, sans compteur servi, portent un
    /// libellé neutre qui n'affirme pas qu'il reste quelque chose à faire.
    func testPresencesEtEvaluationsSansCompteurSousUnLibelleNeutre() throws {
        let actions = PrioriteActions.liste(profil: profil, stats: stats, permissions: try permissions("PROPRIETAIRE"))
        let presences = actions.first { $0.cle == .presences }
        let evaluations = actions.first { $0.cle == .evaluations }
        XCTAssertEqual(presences?.titre, "Valider les présences")
        XCTAssertEqual(evaluations?.titre, "Évaluer vos soignants")
        XCTAssertNil(presences?.compteur)
        XCTAssertNil(evaluations?.compteur)
        for titre in [presences?.titre, evaluations?.titre].compactMap({ $0 }) {
            XCTAssertFalse(titre.contains(" à "), "« \(titre) » : jamais un constat « … à valider / à évaluer » sans compteur")
        }
    }

    func testChaqueActionResolueParLaTableDesLiensDeLEspace() throws {
        XCTAssertEqual(PrioriteActions.presentation(chemin: PrioriteActions.Chemins.candidatures),
                       .naviguer(CibleEtablissement(onglet: .missions, statut: "OUVERTE")))
        XCTAssertEqual(PrioriteActions.presentation(chemin: PrioriteActions.Chemins.presences), .naviguer(CibleEtablissement(onglet: .presences)))
        XCTAssertEqual(PrioriteActions.presentation(chemin: PrioriteActions.Chemins.messagerie), .naviguer(CibleEtablissement(onglet: .messages)))
        for chemin in [PrioriteActions.Chemins.litiges, PrioriteActions.Chemins.evaluations, PrioriteActions.Chemins.facturation,
                       PrioriteActions.Chemins.activer] {
            XCTAssertEqual(PrioriteActions.presentation(chemin: chemin), .renvoiWeb(try XCTUnwrap(URL(string: "https://jolene.app\(chemin)"))))
        }
        // Publication (T9) et détail (T5) : natifs dès que leur tranche les déclare livrés, renvoi web avant.
        let publier = PrioriteActions.presentation(chemin: PrioriteActions.Chemins.publier)
        XCTAssertEqual(publier, EtabDestination.publication.ecranLivre
                       ? .naviguer(CibleEtablissement(onglet: .missions, destination: .publication))
                       : .renvoiWeb(try XCTUnwrap(URL(string: "https://jolene.app/etablissement/missions/creer"))))
        let detail = PrioriteActions.presentation(chemin: PrioriteActions.Chemins.mission("m 1/é"))
        XCTAssertEqual(detail, EtabDestination.detailMission(id: "m 1/é").ecranLivre
                       ? .naviguer(CibleEtablissement(onglet: .missions, destination: .detailMission(id: "m 1/é")))
                       : .renvoiWeb(try XCTUnwrap(URL(string: "https://jolene.app/etablissement/missions/m%201%2F%C3%A9"))))
    }
}

@MainActor
final class EtabAccueilModelTests: XCTestCase {
    private actor Script {
        private var etapes: [Result<EtabDashboardSnapshot, JoleneError>]
        private(set) var appels = 0
        init(_ etapes: [Result<EtabDashboardSnapshot, JoleneError>]) { self.etapes = etapes }
        func suivante() -> Result<EtabDashboardSnapshot, JoleneError> {
            appels += 1
            return etapes.count > 1 ? etapes.removeFirst() : etapes[0]
        }
    }

    private struct DashboardScripte: EtabDashboardPort {
        let script: Script
        func tableauDeBord(context: EtablissementReadContext) async throws -> EtabDashboardSnapshot {
            try await script.suivante().get()
        }
    }

    private let tableau = EtabDashboardSnapshot(stats: EtabDashboardStats(candidaturesEnAttente: 1), planning: EtabPlanningAVenir())

    private func pret(_ dashboard: EtabDashboardPort) async throws -> (SessionController, EtablissementSessionSnapshot, DemoEtabAuditGateway) {
        var gateways = DemoWorld.gateways(espace: .etablissement(.init()))
        gateways.etablissement.dashboard = dashboard
        let audit = try XCTUnwrap(gateways.etablissement.audit as? DemoEtabAuditGateway)
        let controller = SessionController(gateways: gateways, resolutionTimeout: 2, espaceEtablissement: .ouvert)
        _ = await controller.start()
        let state = await controller.signIn(email: DemoEspace.emailEtablissement, password: "demonstration")
        return (controller, try XCTUnwrap(state.snapshotEtablissement, "\(state)"), audit)
    }

    func testChargementPublieLeTableauPuisEcritLAuditDeConsultation() async throws {
        let (controller, snapshot, audit) = try await pret(DemoEtabDashboardGateway())
        let model = EtabAccueilModel(controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertEqual(model.tableau?.stats.candidaturesEnAttente, 3)
        XCTAssertEqual(model.chargeLe, DemoWorld.fixedNow)
        await model.dernierAudit?.value
        let journal = await audit.journal()
        XCTAssertEqual(journal, ["DONNEES_PERSO_CONSULTATION etablissement demo-etablissement dashboard_etablissement"])
    }

    func testLectureSecondaireEnEchecAccueilPartiel() async throws {
        let (controller, snapshot, _) = try await pret(DemoEtabDashboardGateway(planningIndisponible: true))
        let model = EtabAccueilModel(controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertEqual(model.tableau?.lecturePartielle, true)
        XCTAssertEqual(model.tableau?.stats.messagesNonLus, 2, "les compteurs restent affichés")
    }

    func testSessionExpireeSansAuditEtEchecGardeLeTableauAuRafraichissement() async throws {
        let script = Script([.success(tableau), .failure(JoleneError(.network, "Réseau indisponible."))])
        let (controller, snapshot, audit) = try await pret(DashboardScripte(script: script))
        let model = EtabAccueilModel(controller: controller, snapshot: snapshot)
        await model.load()
        await model.load()
        XCTAssertEqual(model.tableau, tableau, "un rafraîchissement en échec garde le tableau affiché")
        XCTAssertEqual(model.refreshError, "Réseau indisponible.")
        await model.dernierAudit?.value
        let entrees = await audit.journal()
        XCTAssertEqual(entrees.count, 1, "seule la lecture réussie est auditée")

        let expire = Script([.failure(JoleneError(.unauthorized, "Votre session a expiré."))])
        let (controller2, snapshot2, audit2) = try await pret(DashboardScripte(script: expire))
        let model2 = EtabAccueilModel(controller: controller2, snapshot: snapshot2)
        await model2.load()
        XCTAssertEqual(model2.state, .failed("Votre session a expiré."))
        XCTAssertTrue(model2.sessionExpired)
        let entrees2 = await audit2.journal()
        XCTAssertTrue(entrees2.isEmpty)
        await model2.loadIfStale()
        let appels = await expire.appels
        XCTAssertEqual(appels, 1, "après un échec, seule l'action « Réessayer » relance")
    }

    func testEpochPerimeAucuneLecture() async throws {
        let script = Script([.success(tableau)])
        let (controller, snapshot, _) = try await pret(DashboardScripte(script: script))
        _ = await controller.signOut()
        let model = EtabAccueilModel(controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertEqual(model.state, .loading)
        let appels = await script.appels
        XCTAssertEqual(appels, 0)
    }

    func testRelectureALApparitionSeulementAuDelaDeSoixanteSecondes() async throws {
        let script = Script([.success(tableau)])
        let (controller, snapshot, _) = try await pret(DashboardScripte(script: script))
        let model = EtabAccueilModel(controller: controller, snapshot: snapshot)
        await model.loadIfStale()
        await model.loadIfStale()
        let appels = await script.appels
        XCTAssertEqual(appels, 1, "horloge démo fixe : aucune relecture avant 60 s")
    }
}
