import XCTest
@testable import JoleneCore

/// Confirmation de présence (lot 1, T6c) : visibilité du bloc (parité `DetailMissionSoignant.tsx` l.1414-1440), monde
/// démo (même contrôle que `fn_confirmer_presence_mission`, relecture par la surcouche des missions), textes vouvoyés.
final class PresenceRulesTests: XCTestCase {
    private let maintenant = DemoWorld.fixedNow
    private let userId = DemoWorld.context.userId

    private func record(debutDans heures: Double, statut: String = "ASSIGNEE", assigne: String? = "demo-soignant",
                        confirmee: String? = nil) throws -> MissionRecord {
        var r = try XCTUnwrap(try DemoPresenceGateway.missionJ1()).record
        r.debutLe = DateHeureParis.isoUTC(maintenant.addingTimeInterval(heures * 3600))
        r.statut = statut
        r.soignantAssigneId = assigne
        r.presenceConfirmeeLe = confirmee
        return r
    }

    private func bloc(_ r: MissionRecord) -> PresenceRules.Bloc { PresenceRules.bloc(r, userId: userId, maintenant: maintenant) }

    func testBornesDeLaFenetreDe48Heures() throws {
        XCTAssertEqual(bloc(try record(debutDans: 20)), .aConfirmer)
        XCTAssertEqual(bloc(try record(debutDans: 47.99)), .aConfirmer)
        XCTAssertEqual(bloc(try record(debutDans: 48)), .masque, "strictement moins de 48 h, comme le web")
        XCTAssertEqual(bloc(try record(debutDans: 0)), .masque, "mission démarrée : plus de bloc")
        XCTAssertEqual(bloc(try record(debutDans: -2)), .masque, "passé")
    }

    func testDejaConfirmeeEnCoursEtAutreSoignant() throws {
        XCTAssertEqual(bloc(try record(debutDans: 20, confirmee: "2026-11-01T10:00:00Z")), .confirmee)
        XCTAssertEqual(bloc(try record(debutDans: 120, confirmee: "2026-11-01T10:00:00Z")), .confirmee, "état hors fenêtre, comme le web")
        XCTAssertEqual(bloc(try record(debutDans: 20, statut: "EN_COURS")), .masque, "EN_COURS exclu comme le web")
        XCTAssertEqual(bloc(try record(debutDans: 20, assigne: "autre")), .masque)
        XCTAssertEqual(bloc(try record(debutDans: 20, assigne: nil)), .masque)
        var illisible = try record(debutDans: 20)
        illisible.debutLe = "pas une date"
        XCTAssertEqual(bloc(illisible), .masque)
    }

    func testTextesVouvoyesEtRepli() throws {
        let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let page = try String(contentsOf: racine.appendingPathComponent("src/pages/DetailMissionSoignant.tsx"), encoding: .utf8)
        XCTAssertTrue(page.contains("Confirme ta présence"))
        XCTAssertTrue(page.contains("La mission démarre bientôt — confirme en 1 clic pour rassurer l'établissement."))
        XCTAssertEqual(PresenceRules.Textes.titre, "Confirmez votre présence")
        XCTAssertEqual(PresenceRules.Textes.description, "La mission démarre bientôt — confirmez en 1 clic pour rassurer l'établissement.")
        XCTAssertFalse(PresenceRules.Textes.titre.contains("Je serai là"), "titre du push serveur, jamais un texte d'écran")
        XCTAssertEqual(PresenceRules.messageRefus("Cette mission n'est plus active."), "Cette mission n'est plus active.")
    }

    // MARK: - Monde démo

    func testDemoConfirmeEtRelitParLaSurcoucheDesMissions() async throws {
        let gateways = DemoWorld.gateways()
        let avant = try await gateways.missions.mission(id: DemoPresenceGateway.idMissionJ1, context: DemoWorld.context)
        let initiale = try XCTUnwrap(avant)
        XCTAssertEqual(bloc(initiale.record), .aConfirmer, "mission de recette dans la fenêtre de 48 h")
        XCTAssertTrue(initiale.planningExact)
        let issue = try await gateways.presence.confirmerPresence(missionId: DemoPresenceGateway.idMissionJ1, context: DemoWorld.context)
        let attendu = DateHeureParis.isoUTC(maintenant)
        XCTAssertEqual(issue, .confirmee(presenceConfirmeeLe: attendu))
        let apres = try await gateways.missions.mission(id: DemoPresenceGateway.idMissionJ1, context: DemoWorld.context)
        XCTAssertEqual(apres?.record.presenceConfirmeeLe, attendu, "relue par le monde démo, jamais posée par l'écran")
        XCTAssertEqual(apres.map { bloc($0.record) }, .confirmee)
        // Hors listes : ni l'Accueil ni Mes missions ne changent.
        let dashboard = try DemoFixtures.loadDashboard()
        XCTAssertFalse(dashboard.missionsAssignees.contains { $0.record.id == DemoPresenceGateway.idMissionJ1 })
    }

    func testDemoRefusComme_fn_confirmer_presence_mission() async throws {
        let gateways = DemoWorld.gateways()
        let ouverte = try await gateways.presence.confirmerPresence(missionId: "demo-mission-001", context: DemoWorld.context)
        XCTAssertEqual(ouverte, .refusee(message: "Mission introuvable"), "mission non attribuée au soignant")
        var autre = DemoWorld.context
        autre.userId = "user-1"
        autre.profile.id = "user-1"
        do {
            _ = try await gateways.presence.confirmerPresence(missionId: DemoPresenceGateway.idMissionJ1, context: autre)
            XCTFail("un autre utilisateur doit être refusé")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .demoOnly)
        }
    }
}

/// Garde de non-idempotence de `ConfirmationPresenceModel` (revue B8 de T6c, M1) : un seul appel au port pour un double
/// toucher, bloc « confirmée » dès la date relue par la gateway (même si la mission relue ne la porte pas encore), bouton
/// jamais réactivé après un succès ; repli web pour un refus sans message et une erreur d'envoi (m3) ; issue incertaine
/// (succès serveur non relu, délai dépassé) sans aucun nouvel envoi avant une relecture qui conclut (revue B8 delta de
/// #1157, M1).
@MainActor
final class ConfirmationPresenceModelTests: XCTestCase {
    private struct EchecTransport: Error {}

    /// Port espion : compte les appels et répond après un court délai (deux appels se chevaucheraient).
    private final class PortEspion: PresencePort, @unchecked Sendable {
        private let lock = NSLock()
        private var nombre = 0
        private let reponse: Result<PresenceOutcome, Error>

        init(_ reponse: Result<PresenceOutcome, Error>) { self.reponse = reponse }

        var appels: Int { lock.withLock { nombre } }

        func confirmerPresence(missionId: String, context: MissionReadContext) async throws -> PresenceOutcome {
            lock.withLock { nombre += 1 }
            try await Task.sleep(nanoseconds: 50_000_000)
            return try reponse.get()
        }
    }

    private static let dateRelue = "2026-11-02T00:00:00.000Z"

    /// Port lent : répond après `delai` secondes (au-delà du délai de `bounded`, le serveur « a pu écrire »).
    private final class PortLent: PresencePort, @unchecked Sendable {
        private let lock = NSLock()
        private var nombre = 0
        var appels: Int { lock.withLock { nombre } }

        func confirmerPresence(missionId: String, context: MissionReadContext) async throws -> PresenceOutcome {
            lock.withLock { nombre += 1 }
            try await Task.sleep(nanoseconds: 10_000_000_000)
            return .confirmee(presenceConfirmeeLe: "2026-11-02T00:00:00.000Z")
        }
    }

    /// Lecture de la mission en échec (`mission(id:)`), le reste délégué : la relecture d'une issue incertaine ne conclut pas.
    private struct MissionsEnPanne: MissionsPort {
        let base: MissionsPort
        func profile(userId: String) async throws -> SoignantProfile? { try await base.profile(userId: userId) }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] {
            try await base.listMissions(context: context, filters: filters)
        }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? {
            throw JoleneError(.network, "Le service ne répond pas.")
        }
    }

    /// Mission relue portant la date écrite par le serveur (`date`), ou relue sans date (`nil`).
    private struct MissionsRelues: MissionsPort {
        let base: MissionsPort
        let date: String?
        func profile(userId: String) async throws -> SoignantProfile? { try await base.profile(userId: userId) }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] {
            try await base.listMissions(context: context, filters: filters)
        }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? {
            var relue = try await base.mission(id: id, context: context)
            relue?.record.presenceConfirmeeLe = date
            return relue
        }
    }

    /// Mission relue remise en ligne (plus attribuée au soignant de la session).
    private struct MissionsDesattribuees: MissionsPort {
        let base: MissionsPort
        func profile(userId: String) async throws -> SoignantProfile? { try await base.profile(userId: userId) }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] {
            try await base.listMissions(context: context, filters: filters)
        }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? {
            var relue = try await base.mission(id: id, context: context)
            relue?.record.statut = "OUVERTE"
            relue?.record.soignantAssigneId = nil
            return relue
        }
    }

    /// Horloge des gateways réglable à la main (m7 : délai de grâce de 30 s après un appel expiré).
    private final class HorlogeReglable: ClockPort, @unchecked Sendable {
        private let lock = NSLock()
        private var instant: Date
        init(_ instant: Date) { self.instant = instant }
        func now() -> Date { lock.withLock { instant } }
        func avancer(_ secondes: TimeInterval) { lock.withLock { instant += secondes } }
    }

    private func modele(_ port: any PresencePort, missions: ((MissionsPort) -> MissionsPort)? = nil,
                        delai: TimeInterval = SessionController.defaultResolutionTimeout,
                        horloge: ClockPort? = nil) async throws
        -> (ConfirmationPresenceModel, MissionRecord) {
        var gateways = DemoWorld.gateways()
        gateways.presence = port
        if let missions { gateways.missions = missions(gateways.missions) }
        if let horloge { gateways.clock = horloge }
        let controller = SessionController(gateways: gateways, resolutionTimeout: delai)
        let state = await controller.signIn(email: DemoWorld.context.email ?? "", password: "demonstration")
        let snapshot = try XCTUnwrap(state.snapshot, "session démo prête attendue, obtenu \(state)")
        let model = ConfirmationPresenceModel(missionId: DemoPresenceGateway.idMissionJ1, controller: controller, snapshot: snapshot)
        await model.charger()
        let record = try XCTUnwrap(try DemoPresenceGateway.missionJ1()).record
        return (model, record)
    }

    func testDoubleToucherUnSeulAppelEtBoutonJamaisReactive() async throws {
        let port = PortEspion(.success(.confirmee(presenceConfirmeeLe: Self.dateRelue)))
        let (model, mission) = try await modele(port)
        XCTAssertEqual(model.bloc(mission), .aConfirmer)
        async let premier = model.confirmer()
        async let second = model.confirmer()
        let issues = await [premier, second]
        XCTAssertEqual(port.appels, 1, "RPC non idempotente : un seul appel pour deux touchers")
        XCTAssertEqual(issues.filter { $0 }.count, 1)
        XCTAssertEqual(model.issue, .confirmee)
        // Relecture de la mission en échec ou en retard : la mission affichée n'a pas la date, le bloc est quand même confirmé.
        XCTAssertNil(mission.presenceConfirmeeLe)
        XCTAssertEqual(model.bloc(mission), .confirmee, "bouton masqué sans attendre la relecture de la mission")
        XCTAssertFalse(model.enCours)
        let encore = await model.confirmer()
        XCTAssertFalse(encore, "aucun nouvel appel après un succès relu")
        XCTAssertEqual(port.appels, 1)
    }

    func testRefusEtErreurDeTransportGardentLeBouton() async throws {
        let refus = PortEspion(.success(.refusee(message: "Cette mission n'est plus active.")))
        let (model, mission) = try await modele(refus)
        _ = await model.confirmer()
        XCTAssertEqual(model.issue, .refus("Cette mission n'est plus active."), "refus serveur verbatim")
        XCTAssertEqual(model.bloc(mission), .aConfirmer)

        let panne = PortEspion(.failure(JoleneError(.network, "Le service ne répond pas.")))
        let (enPanne, missionPanne) = try await modele(panne)
        _ = await enPanne.confirmer()
        XCTAssertEqual(enPanne.issue, .refus("Confirmation impossible."), "repli web pour toute erreur (`error || data?.error`)")
        XCTAssertEqual(enPanne.bloc(missionPanne), .aConfirmer)
        let autre = PortEspion(.failure(EchecTransport()))
        let (inconnu, _) = try await modele(autre)
        _ = await inconnu.confirmer()
        XCTAssertEqual(inconnu.issue, .refus("Confirmation impossible."))
    }

    // MARK: - Issue incertaine (revue B8 delta de #1157, M1)

    /// `{success:true}` puis relecture en échec : texte de relecture, jamais « Confirmation impossible. », et aucun second
    /// appel au port sur un nouvel appui tant qu'aucune relecture n'a conclu (« Actualiser » ne renvoie rien).
    func testEnvoyeeNonRelueAucunNouvelEnvoiTantQuAucuneRelectureNAConclu() async throws {
        let port = PortEspion(.success(.envoyeeNonRelue(message: PresenceRules.Textes.envoyeeNonRelue)))
        let (model, mission) = try await modele(port, missions: { MissionsEnPanne(base: $0) })
        let relire = await model.confirmer()
        XCTAssertTrue(relire, "l'écran relit la mission")
        XCTAssertEqual(model.issue, .incertaine(PresenceRules.Textes.envoyeeNonRelue))
        XCTAssertNotEqual(model.issue, .refus("Confirmation impossible."))
        XCTAssertTrue(model.relectureRequise, "« Actualiser » à la place du bouton")
        XCTAssertEqual(model.bloc(mission), .aConfirmer)
        let encore = await model.confirmer()
        XCTAssertFalse(encore, "aucun nouvel envoi avant une relecture qui conclut")
        XCTAssertEqual(port.appels, 1)
        _ = await model.relire()
        XCTAssertTrue(model.relectureRequise, "relecture en échec : l'issue reste incertaine")
        XCTAssertEqual(model.issue, .incertaine(PresenceRules.Textes.envoyeeNonRelue))
        _ = await model.confirmer()
        XCTAssertEqual(port.appels, 1, "toujours un seul appel")
    }

    /// Délai dépassé de `bounded` : le serveur a pu écrire ; même issue incertaine, aucun second appel.
    func testDelaiDepasseEstUneIssueIncertaineSansNouvelEnvoi() async throws {
        let port = PortLent()
        let (model, _) = try await modele(port, missions: { MissionsEnPanne(base: $0) }, delai: 1)
        _ = await model.confirmer()
        XCTAssertEqual(model.issue, .incertaine(PresenceRules.Textes.envoyeeNonRelue), "jamais un échec annoncé après un délai")
        XCTAssertTrue(model.relectureRequise)
        let encore = await model.confirmer()
        XCTAssertFalse(encore)
        XCTAssertEqual(port.appels, 1)
    }

    /// Après l'accusé `{success:true}` : date relue → confirmée, bouton masqué ; relue sans la date → l'issue RESTE
    /// incertaine (revue B8 de #1158, M1) : la RPC écrit la date sans condition avant de répondre, une lecture sans la date
    /// ne prouve pas la non-réception (PRINCIPES §4). « Actualiser » ne conclut pas non plus ; un seul envoi en tout.
    func testRelectureApresAccuseConfirmeOuResteIncertaine() async throws {
        let incertaine = PresenceOutcome.envoyeeNonRelue(message: PresenceRules.Textes.envoyeeNonRelue)
        let port = PortEspion(.success(incertaine))
        let (confirmee, mission) = try await modele(port, missions: { MissionsRelues(base: $0, date: Self.dateRelue) })
        _ = await confirmee.confirmer()
        XCTAssertEqual(confirmee.issue, .confirmee)
        XCTAssertFalse(confirmee.relectureRequise)
        XCTAssertEqual(confirmee.presenceRelue, Self.dateRelue)
        XCTAssertEqual(confirmee.bloc(mission), .confirmee)
        let encore = await confirmee.confirmer()
        XCTAssertFalse(encore)
        XCTAssertEqual(port.appels, 1)

        let accuse = PortEspion(.success(incertaine))
        let (sansDate, missionSansDate) = try await modele(accuse, missions: { MissionsRelues(base: $0, date: nil) })
        _ = await sansDate.confirmer()
        XCTAssertTrue(sansDate.relectureRequise, "après l'accusé, une relecture sans la date ne conclut pas")
        XCTAssertEqual(sansDate.issue, .incertaine(PresenceRules.Textes.envoyeeNonRelue))
        XCTAssertNotEqual(sansDate.issue, .refus("Confirmation impossible."))
        XCTAssertEqual(sansDate.bloc(missionSansDate), .aConfirmer)
        let relue = await sansDate.relire()
        XCTAssertTrue(relue)
        XCTAssertTrue(sansDate.relectureRequise, "« Actualiser » sans la date : toujours incertaine")
        XCTAssertEqual(sansDate.issue, .incertaine(PresenceRules.Textes.envoyeeNonRelue))
        let encore2 = await sansDate.confirmer()
        XCTAssertFalse(encore2, "aucun envoi")
        XCTAssertEqual(accuse.appels, 1, "un seul appel à l'envoi")
    }

    /// Délai dépassé SANS accusé, puis mission relue sans la date (revue B8 delta de #1158, m7 et m8) : la RPC a pu rester
    /// en vol côté serveur. Avant 30 s depuis le début de l'appel expiré, l'issue reste incertaine (« Actualiser », aucun
    /// envoi) ; à 30 s, une relecture sans la date conclut « non enregistrée », avec un constat neutre, et l'envoi
    /// redevient possible. Horloge des gateways injectée, réglée à la main.
    func testDelaiDepassePuisRelectureSansDateNeConclutQuApres30Secondes() async throws {
        let port = PortLent()
        let horloge = HorlogeReglable(DemoWorld.fixedNow)
        let (model, mission) = try await modele(port, missions: { MissionsRelues(base: $0, date: nil) }, delai: 1,
                                                horloge: horloge)
        XCTAssertEqual(ConfirmationPresenceModel.delaiAvantConclusion, 30)
        _ = await model.confirmer()
        XCTAssertTrue(model.relectureRequise, "relecture immédiate, sans la date : la RPC a pu rester en vol")
        XCTAssertEqual(model.issue, .incertaine(PresenceRules.Textes.envoyeeNonRelue))
        let tropTot = await model.confirmer()
        XCTAssertFalse(tropTot, "aucun envoi avant une relecture qui conclut")
        XCTAssertEqual(port.appels, 1)

        horloge.avancer(29)
        _ = await model.relire()
        XCTAssertTrue(model.relectureRequise, "29 s après le début de l'appel : toujours incertaine")
        XCTAssertEqual(model.issue, .incertaine(PresenceRules.Textes.envoyeeNonRelue))

        horloge.avancer(1)
        _ = await model.relire()
        XCTAssertFalse(model.relectureRequise, "30 s après le début de l'appel, relue sans la date : non enregistrée")
        XCTAssertEqual(model.issue, .nonEnregistree("Votre confirmation n'a pas été enregistrée."), "constat neutre (m8)")
        XCTAssertEqual(PresenceRules.Textes.nonEnregistree, "Votre confirmation n'a pas été enregistrée.")
        XCTAssertEqual(model.bloc(mission), .aConfirmer)
        XCTAssertEqual(port.appels, 1)
        _ = await model.confirmer()
        XCTAssertEqual(port.appels, 2, "nouvel envoi permis après la conclusion")
    }

    /// Après l'accusé, une relecture « mission plus attribuée » ne lève pas le verrou d'envoi (revue B8 delta de #1158,
    /// m6) : aucun message, mais aucun second appel tant que l'écran n'a pas relu la mission.
    func testApresAccuseMissionDesattribueeGardeLeVerrou() async throws {
        let port = PortEspion(.success(.envoyeeNonRelue(message: PresenceRules.Textes.envoyeeNonRelue)))
        let (model, _) = try await modele(port, missions: { MissionsDesattribuees(base: $0) })
        _ = await model.confirmer()
        XCTAssertTrue(model.relectureRequise, "verrou d'envoi gardé après l'accusé")
        XCTAssertNil(model.issue, "plus rien à confirmer : aucun message")
        let encore = await model.confirmer()
        XCTAssertFalse(encore)
        XCTAssertEqual(port.appels, 1)
    }

    /// Délai dépassé sans accusé, mission relue plus attribuée : plus rien à confirmer, l'incertitude est levée.
    func testApresUnDelaiMissionDesattribueeLeveLIncertitude() async throws {
        let (model, _) = try await modele(PortLent(), missions: { MissionsDesattribuees(base: $0) }, delai: 1)
        _ = await model.confirmer()
        XCTAssertFalse(model.relectureRequise)
        XCTAssertNil(model.issue)
    }
}
