import XCTest
@testable import JoleneCore

/// « Mes disponibilités » (L4-T5, `docs/mobile-swift/LOT4_PLAN.md` §3 T5) sur le monde démo
/// (`DemoDisponibilitesGateway`, fixture `demo-disponibilites.json`) et sur des ports témoins :
/// - la grille est dérivée de l'horloge (lundi Europe/Paris, quatre semaines) à chaque lecture et avant chaque
///   bascule, jamais d'un défaut figé ; rien n'est affiché avant la relecture ;
/// - un jour passé (ou hors grille) n'est jamais envoyé ;
/// - aucune bascule optimiste : la case attend la relecture, une bascule à la fois par case ;
/// - refus serveur verbatim (`fn_definir_disponibilite`), relecture qui ne confirme pas, erreur de transport
///   réconciliée par relecture (jamais de renvoi), session expirée, annulation, epoch périmé.
@MainActor
final class DisponibilitesModelTests: XCTestCase {
    nonisolated private static let lundi = JourParis(iso: "2026-11-02")
    nonisolated private static let mardi = JourParis(iso: "2026-11-03")
    nonisolated private static let mercredi = JourParis(iso: "2026-11-04")
    nonisolated private static let mardiNuit = DispoCle(jour: mardi, creneau: .nuit)
    nonisolated private static let mardiJour = DispoCle(jour: mardi, creneau: .journee)
    nonisolated private static let jeudiNuit = DispoCle(jour: JourParis(iso: "2026-11-05"), creneau: .nuit)
    nonisolated private static let samediSuivant = DispoCle(jour: JourParis(iso: "2026-11-14"), creneau: .journee)
    /// `demo-disponibilites.json` : trois créneaux posés.
    nonisolated private static let fixture: Set<DispoCle> = [mardiJour, jeudiNuit, samediSuivant]
    nonisolated private static let reseau = "Connexion impossible."
    nonisolated private static let expiration = "Votre session a expiré. Reconnectez-vous."

    // MARK: - Témoins

    /// Horloge réglable : minuit franchi pendant que l'écran est affiché.
    private final class Horloge: ClockPort, @unchecked Sendable {
        private let verrou = NSLock()
        private var instant: Date
        init(_ instant: Date) { self.instant = instant }
        func now() -> Date { verrou.withLock { instant } }
        func regler(_ date: Date) { verrou.withLock { instant = date } }
    }

    /// Appels reçus par le port, dans l'ordre.
    private final class Journal: @unchecked Sendable {
        private let verrou = NSLock()
        private var lues: [JourParis] = []
        private var basculees: [(cle: DispoCle, disponible: Bool)] = []
        var lectures: [JourParis] { verrou.withLock { lues } }
        var bascules: [(cle: DispoCle, disponible: Bool)] { verrou.withLock { basculees } }
        /// Rang (1, 2…) de la lecture notée.
        @discardableResult func noter(lecture depuis: JourParis) -> Int { verrou.withLock { lues.append(depuis); return lues.count } }
        func noter(bascule cle: DispoCle, _ disponible: Bool) { verrou.withLock { basculees.append((cle, disponible)) } }
    }

    /// Retient un appel en vol jusqu'à `ouvrir()`.
    private actor Porte {
        private var ouverte = false
        private var attentes: [CheckedContinuation<Void, Never>] = []
        private(set) var arrivees = 0

        func attendre() async {
            arrivees += 1
            guard !ouverte else { return }
            await withCheckedContinuation { attentes.append($0) }
        }

        func ouvrir() {
            ouverte = true
            attentes.forEach { $0.resume() }
            attentes = []
        }
    }

    private struct Panne: Error {}

    /// Port témoin : monde démo par défaut, lecture ou bascule remplacées ; chaque appel est consigné (`rang` : numéro
    /// de la lecture).
    private struct PortTemoin: DisponibilitesPort {
        var demo = DemoDisponibilitesGateway()
        var journal = Journal()
        var lecture: (@Sendable (_ depuis: JourParis, _ rang: Int) async throws -> Set<DispoCle>)?
        var bascule: (@Sendable (DispoCle, Bool) async throws -> IssueDisponibilite)?

        func lister(depuis: JourParis, context: MissionReadContext) async throws -> Set<DispoCle> {
            let rang = journal.noter(lecture: depuis)
            if let lecture { return try await lecture(depuis, rang) }
            return try await demo.lister(depuis: depuis, context: context)
        }

        func definir(jour: JourParis, creneau: CreneauDispo, disponible: Bool,
                     context: MissionReadContext) async throws -> IssueDisponibilite {
            let cle = DispoCle(jour: jour, creneau: creneau)
            journal.noter(bascule: cle, disponible)
            if let bascule { return try await bascule(cle, disponible) }
            return try await demo.definir(jour: jour, creneau: creneau, disponible: disponible, context: context)
        }
    }

    private func session(_ port: any DisponibilitesPort,
                         horloge: any ClockPort) async throws -> (SessionController, SessionSnapshot) {
        var gateways = DemoWorld.gateways()
        gateways.disponibilites = port
        gateways.clock = horloge
        let controller = SessionController(gateways: gateways)
        let state = await controller.signIn(email: DemoWorld.context.email ?? "", password: "demonstration")
        return (controller, try XCTUnwrap(state.snapshot, "session démo prête attendue, obtenu \(state)"))
    }

    private func modele(_ port: any DisponibilitesPort = DemoDisponibilitesGateway(),
                        horloge: any ClockPort = FixedClock(DemoWorld.fixedNow),
                        charge: Bool = true) async throws -> DisponibilitesModel {
        let (controller, snapshot) = try await session(port, horloge: horloge)
        let model = DisponibilitesModel(controller: controller, snapshot: snapshot)
        if charge { await model.charger() }
        return model
    }

    private func jour(_ iso: String, _ model: DisponibilitesModel) -> JourDisponibilitesAffiche? {
        model.semaines.flatMap(\.jours).first { $0.jour.iso == iso }
    }

    private func instant(_ iso: String) throws -> Date { try DateHeureParis.instantJolene(iso) }

    private func attendre(_ description: String, _ condition: @escaping () async -> Bool) async {
        for _ in 0..<5_000 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("condition jamais atteinte : \(description)")
    }

    // MARK: - Lecture et grille dérivée

    func testChargerDeriveLaGrilleDeLHorlogeEtRelitDepuisAujourdhui() async throws {
        let port = PortTemoin()
        let model = try await modele(port, charge: false)
        XCTAssertEqual(model.etat, .chargement)
        XCTAssertTrue(model.semaines.isEmpty, "rien n'est pré-rempli avant la relecture")
        XCTAssertEqual(model.nombre, 0)

        await model.charger()
        XCTAssertEqual(port.journal.lectures, [Self.lundi], "borne de lecture : jour Paris de l'horloge (MesDisponibilites.tsx l.52-53)")
        XCTAssertEqual(model.etat, .prete(Self.fixture))
        XCTAssertEqual(model.grille?.aujourdhui, Self.lundi)
        XCTAssertEqual(model.semaines.map(\.id), ["dispos-semaine-1", "dispos-semaine-2", "dispos-semaine-3", "dispos-semaine-4"])
        XCTAssertEqual(model.semaines.map(\.entete),
                       ["Semaine du 2 novembre", "Semaine du 9 novembre", "Semaine du 16 novembre", "Semaine du 23 novembre"])
        XCTAssertTrue(model.semaines.allSatisfy { $0.jours.count == 7 })
        let premier = try XCTUnwrap(model.semaines.first?.jours.first)
        XCTAssertEqual(premier.libelle, "Lundi 2 Nov.", "classe CSS `capitalize` du web")
        XCTAssertTrue(premier.estAujourdhui)
        XCTAssertFalse(premier.passe)
        XCTAssertEqual(jour("2026-11-03", model)?.journee, CaseDisponibilite(declaree: true, enCours: false))
        XCTAssertEqual(jour("2026-11-03", model)?.nuit, CaseDisponibilite(declaree: false, enCours: false))
        XCTAssertEqual(jour("2026-11-05", model)?.etat(.nuit), CaseDisponibilite(declaree: true, enCours: false))
        XCTAssertEqual(model.semaines.last?.jours.last?.jour.iso, "2026-11-29")
        XCTAssertEqual(model.nombre, 3)
        XCTAssertNil(model.erreur)
        XCTAssertFalse(model.sessionExpiree)
    }

    func testJourPasseOuHorsGrilleNonBasculableAucunAppel() async throws {
        // Mercredi 4 novembre 2026, 10 h à Paris : lundi et mardi sont passés.
        let port = PortTemoin()
        let model = try await modele(port, horloge: FixedClock(try instant("2026-11-04T09:00:00Z")))
        XCTAssertEqual(port.journal.lectures, [Self.mercredi])
        XCTAssertEqual(model.etat, .prete([Self.jeudiNuit, Self.samediSuivant]), "lecture depuis aujourd'hui seulement")
        XCTAssertEqual(jour("2026-11-02", model)?.passe, true)
        XCTAssertEqual(jour("2026-11-03", model)?.passe, true)
        XCTAssertEqual(jour("2026-11-04", model)?.passe, false)
        XCTAssertEqual(jour("2026-11-04", model)?.estAujourdhui, true)

        await model.basculer(jour: Self.mardi, creneau: .nuit)
        XCTAssertTrue(port.journal.bascules.isEmpty, "jour passé : jamais envoyé")
        XCTAssertEqual(model.erreur, DisponibilitesTextes.horsFenetre, "même refus que le serveur, verbatim")
        XCTAssertEqual(model.etat, .prete([Self.jeudiNuit, Self.samediSuivant]))
        XCTAssertTrue(model.enCours.isEmpty)

        await model.basculer(jour: JourParis(iso: "2026-12-25"), creneau: .journee)
        await model.basculer(jour: JourParis(iso: "pas-une-date"), creneau: .journee)
        XCTAssertTrue(port.journal.bascules.isEmpty, "jour hors de la grille : jamais envoyé")
        XCTAssertEqual(model.erreur, DisponibilitesTextes.horsFenetre)
    }

    func testMinuitFranchiLaGrilleEstRederiveeAvantLaBascule() async throws {
        // Lundi 2 novembre, 23 h 30 à Paris, puis mardi 3, 0 h 30.
        let horloge = Horloge(try instant("2026-11-02T22:30:00Z"))
        let lundiJour = DispoCle(jour: Self.lundi, creneau: .journee)
        let port = PortTemoin(demo: DemoDisponibilitesGateway(initiales: [lundiJour, Self.mardiNuit]))
        let model = try await modele(port, horloge: horloge)
        XCTAssertEqual(model.grille?.aujourdhui, Self.lundi)
        XCTAssertEqual(model.nombre, 2)

        horloge.regler(try instant("2026-11-02T23:30:00Z"))
        await model.basculer(jour: Self.lundi, creneau: .journee)
        XCTAssertTrue(port.journal.bascules.isEmpty, "le lundi est passé depuis minuit : jamais envoyé")
        XCTAssertEqual(model.grille?.aujourdhui, Self.mardi, "grille re-dérivée de l'horloge, jamais figée au chargement")
        XCTAssertEqual(jour("2026-11-02", model)?.passe, true)
        XCTAssertEqual(jour("2026-11-02", model)?.journee.declaree, false, "un jour passé n'est plus compté ni affiché déclaré")
        XCTAssertEqual(model.nombre, 1)
        XCTAssertEqual(model.erreur, DisponibilitesTextes.horsFenetre)
    }

    // MARK: - Bascule

    func testBasculeConfirmeeParRelecturePuisRetiree() async throws {
        let port = PortTemoin()
        let model = try await modele(port)
        await model.basculer(jour: Self.mardi, creneau: .nuit)
        XCTAssertEqual(port.journal.bascules.map(\.cle), [Self.mardiNuit])
        XCTAssertEqual(port.journal.bascules.map(\.disponible), [true])
        XCTAssertEqual(model.etat, .prete(Self.fixture.union([Self.mardiNuit])))
        XCTAssertEqual(model.nombre, 4)
        XCTAssertNil(model.erreur)
        XCTAssertTrue(model.enCours.isEmpty)

        // Retour sur l'écran : une nouvelle lecture relit l'état conservé par le monde démo.
        await model.charger()
        XCTAssertEqual(model.etat, .prete(Self.fixture.union([Self.mardiNuit])))

        await model.basculer(jour: Self.mardi, creneau: .nuit)
        XCTAssertEqual(port.journal.bascules.map(\.disponible), [true, false], "la cible est l'inverse de l'état relu")
        XCTAssertEqual(model.etat, .prete(Self.fixture))
        XCTAssertEqual(model.nombre, 3)
        XCTAssertNil(model.erreur)
    }

    func testAucunEtatOptimisteEtUneBasculeALaFoisParCase() async throws {
        let porte = Porte()
        let demo = DemoDisponibilitesGateway()
        let port = PortTemoin(demo: demo, bascule: { cle, disponible in
            await porte.attendre()
            return try await demo.definir(jour: cle.jour, creneau: cle.creneau, disponible: disponible, context: DemoWorld.context)
        })
        let model = try await modele(port)
        let premiere = Task { await model.basculer(jour: Self.mardi, creneau: .nuit) }
        await attendre("la bascule est en vol") { await porte.arrivees == 1 }
        XCTAssertEqual(jour("2026-11-03", model)?.nuit, CaseDisponibilite(declaree: false, enCours: true),
                       "aucun état optimiste : la case attend la relecture")
        XCTAssertEqual(jour("2026-11-03", model)?.journee, CaseDisponibilite(declaree: true, enCours: false),
                       "seul le créneau concerné est occupé")
        XCTAssertEqual(model.nombre, 3)

        await model.basculer(jour: Self.mardi, creneau: .nuit)
        XCTAssertEqual(port.journal.bascules.count, 1, "second appui sur la même case : ignoré")

        await porte.ouvrir()
        await premiere.value
        XCTAssertEqual(jour("2026-11-03", model)?.nuit, CaseDisponibilite(declaree: true, enCours: false))
        XCTAssertEqual(model.nombre, 4)
        XCTAssertEqual(port.journal.bascules.count, 1)
    }

    func testRefusServeurVerbatim() async throws {
        // La borne `CURRENT_DATE` du serveur fait foi : ici, un serveur en avance de dix-huit jours sur l'appareil.
        let serveur = DemoDisponibilitesGateway(clock: FixedClock(try instant("2026-11-20T00:00:00Z")))
        let hors = try await modele(serveur)
        await hors.basculer(jour: Self.mardi, creneau: .nuit)
        XCTAssertEqual(hors.erreur, "La disponibilité doit être entre aujourd'hui et J+90")
        XCTAssertEqual(hors.etat, .prete(Self.fixture), "rien n'est modifié sur un refus")
        XCTAssertTrue(hors.enCours.isEmpty)

        for message in ["Profil soignant introuvable", "Créneau invalide"] {
            let port = PortTemoin(bascule: { _, _ in .refusee(message: message) })
            let model = try await modele(port)
            await model.basculer(jour: Self.mardi, creneau: .nuit)
            XCTAssertEqual(model.erreur, message)
            XCTAssertEqual(model.etat, .prete(Self.fixture))
            XCTAssertEqual(port.journal.lectures.count, 1, "aucune relecture d'un refus")
        }

        let muet = try await modele(PortTemoin(bascule: { _, _ in .refusee(message: "") }))
        await muet.basculer(jour: Self.mardi, creneau: .nuit)
        XCTAssertEqual(muet.erreur, DisponibilitesTextes.basculeImpossible, "refus sans message : libellé de repli")
    }

    func testRelectureQuiNeConfirmePasJamaisUnSucces() async throws {
        let model = try await modele(PortTemoin(bascule: { _, _ in .relue([]) }))
        await model.basculer(jour: Self.mardi, creneau: .nuit)
        XCTAssertEqual(model.erreur, DisponibilitesTextes.nonConfirmee)
        XCTAssertEqual(model.etat, .prete([Self.samediSuivant]), "la semaine affichée est celle relue ; les autres semaines restent")
        XCTAssertTrue(model.enCours.isEmpty)
    }

    func testSemaineReluePublieeSansLesJoursPassesNiLesAutresSemaines() async throws {
        // Mercredi 4 novembre : la relecture de la semaine du 2 rend aussi un créneau posé ailleurs (vendredi), une ligne
        // d'un jour passé (lundi) et, hors contrat, une ligne d'une autre semaine.
        let mercrediJour = DispoCle(jour: Self.mercredi, creneau: .journee)
        let vendrediJour = DispoCle(jour: JourParis(iso: "2026-11-06"), creneau: .journee)
        let lundiJour = DispoCle(jour: Self.lundi, creneau: .journee)
        let autreSemaine = DispoCle(jour: JourParis(iso: "2026-11-10"), creneau: .nuit)
        let port = PortTemoin(bascule: { cle, _ in .relue([cle, vendrediJour, lundiJour, autreSemaine]) })
        let model = try await modele(port, horloge: FixedClock(try instant("2026-11-04T09:00:00Z")))
        await model.basculer(jour: Self.mercredi, creneau: .journee)
        XCTAssertEqual(model.etat, .prete([mercrediJour, vendrediJour, Self.samediSuivant]),
                       "semaine remplacée par sa relecture (jeudi nuit n'y est plus), jours passés et autres semaines écartés")
        XCTAssertNil(model.erreur)
    }

    func testBasculesQuiSeChevauchentChacuneNePublieQueSaCase() async throws {
        let porteA = Porte(), porteB = Porte()
        let a = Self.mardiNuit
        let b = DispoCle(jour: Self.mercredi, creneau: .journee)
        // Cas le plus défavorable : chaque relecture précède l'écriture de l'autre et ne voit que la sienne.
        let port = PortTemoin(bascule: { cle, _ in
            if cle == a {
                await porteA.attendre()
                return .relue([a])
            }
            await porteB.attendre()
            return .relue([b])
        })
        let model = try await modele(port)
        let premiere = Task { await model.basculer(jour: a.jour, creneau: a.creneau) }
        await attendre("la première bascule est en vol") { await porteA.arrivees == 1 }
        let seconde = Task { await model.basculer(jour: b.jour, creneau: b.creneau) }
        await attendre("la seconde bascule est en vol") { await porteB.arrivees == 1 }
        XCTAssertEqual(model.enCours, [a, b], "deux cases distinctes : deux bascules en vol")

        await porteB.ouvrir()
        await seconde.value
        XCTAssertEqual(model.etat, .prete(Self.fixture.union([b])), "relecture en chevauchement : seule la case basculée est publiée")
        await porteA.ouvrir()
        await premiere.value
        XCTAssertEqual(model.etat, .prete(Self.fixture.union([a, b])), "la relecture tardive de la première n'efface pas la seconde")
        XCTAssertNil(model.erreur)
        XCTAssertTrue(model.enCours.isEmpty)
    }

    func testLectureCommenceeAvantUneBasculeNePubliePas() async throws {
        let porte = Porte()
        let demo = DemoDisponibilitesGateway()
        let port = PortTemoin(demo: demo, lecture: { depuis, rang in
            // La deuxième lecture lit l'état d'avant la bascule, puis reste en vol.
            let lues = try await demo.lister(depuis: depuis, context: DemoWorld.context)
            if rang == 2 { await porte.attendre() }
            return lues
        })
        let model = try await modele(port)
        let lecture = Task { await model.charger() }
        await attendre("la deuxième lecture est en vol") { await porte.arrivees == 1 }
        await model.basculer(jour: Self.mardi, creneau: .nuit)
        XCTAssertEqual(model.etat, .prete(Self.fixture.union([Self.mardiNuit])))

        await porte.ouvrir()
        await lecture.value
        XCTAssertEqual(model.etat, .prete(Self.fixture.union([Self.mardiNuit])),
                       "une lecture commencée avant la bascule est caduque : elle n'écrase pas la case relue")
    }

    // MARK: - Erreurs

    func testErreurDeTransportReconcilieeParRelecture() async throws {
        // Le serveur a agi, la réponse s'est perdue : la relecture confirme, sans renvoi.
        let demo = DemoDisponibilitesGateway()
        let recu = PortTemoin(demo: demo, bascule: { cle, disponible in
            _ = try await demo.definir(jour: cle.jour, creneau: cle.creneau, disponible: disponible, context: DemoWorld.context)
            throw JoleneError(.network, Self.reseau)
        })
        let confirmee = try await modele(recu)
        await confirmee.basculer(jour: Self.mardi, creneau: .nuit)
        XCTAssertEqual(confirmee.etat, .prete(Self.fixture.union([Self.mardiNuit])), "relecture : l'écriture a été reçue")
        XCTAssertNil(confirmee.erreur, "la relecture confirme la bascule : aucune erreur affichée")
        XCTAssertEqual(recu.journal.bascules.count, 1, "jamais de renvoi automatique")
        XCTAssertEqual(recu.journal.lectures.count, 2, "relecture après l'échec")

        // Rien n'a été reçu : le message reste, la case relue est inchangée.
        let perdu = PortTemoin(bascule: { _, _ in throw JoleneError(.network, Self.reseau) })
        let inchangee = try await modele(perdu)
        await inchangee.basculer(jour: Self.mardi, creneau: .nuit)
        XCTAssertEqual(inchangee.erreur, Self.reseau)
        XCTAssertEqual(inchangee.etat, .prete(Self.fixture))
        XCTAssertFalse(inchangee.sessionExpiree)
        XCTAssertEqual(perdu.journal.bascules.count, 1)
        XCTAssertEqual(perdu.journal.lectures.count, 2)
        XCTAssertTrue(inchangee.enCours.isEmpty)

        // Relecture impossible : l'état de la case est inconnu, la grille n'est plus affichée.
        let coupe = PortTemoin(lecture: { _, rang in
            if rang > 1 { throw JoleneError(.network, Self.reseau) }
            return Self.fixture
        }, bascule: { _, _ in throw JoleneError(.network, Self.reseau) })
        let inconnue = try await modele(coupe)
        await inconnue.basculer(jour: Self.mardi, creneau: .nuit)
        XCTAssertEqual(inconnue.etat, .echec(DisponibilitesTextes.echecMessage))
        XCTAssertTrue(inconnue.semaines.isEmpty, "jamais une grille dont l'état n'a pas pu être relu")
    }

    func testSessionExpireeAnnulationEtErreurInconnue() async throws {
        let expire = PortTemoin(bascule: { _, _ in throw JoleneError(.unauthorized, Self.expiration) })
        let expiree = try await modele(expire)
        await expiree.basculer(jour: Self.mardi, creneau: .nuit)
        XCTAssertTrue(expiree.sessionExpiree)
        XCTAssertEqual(expiree.erreur, Self.expiration)
        XCTAssertEqual(expire.journal.lectures.count, 1, "session expirée : aucune relecture")
        XCTAssertEqual(expiree.etat, .prete(Self.fixture))

        let annulation = try await modele(PortTemoin(bascule: { _, _ in throw CancellationError() }))
        await annulation.basculer(jour: Self.mardi, creneau: .nuit)
        XCTAssertNil(annulation.erreur, "une annulation n'est jamais une erreur")
        XCTAssertEqual(annulation.etat, .prete(Self.fixture))
        XCTAssertTrue(annulation.enCours.isEmpty)

        let inconnue = try await modele(PortTemoin(bascule: { _, _ in throw Panne() }))
        await inconnue.basculer(jour: Self.mardi, creneau: .nuit)
        XCTAssertEqual(inconnue.erreur, DisponibilitesTextes.basculeImpossible)
    }

    func testChargementEnEchecPuisReessayer() async throws {
        let port = PortTemoin(lecture: { _, rang in
            if rang == 1 { throw JoleneError(.network, Self.reseau) }
            return Self.fixture
        })
        let model = try await modele(port)
        XCTAssertEqual(model.etat, .echec(DisponibilitesTextes.echecMessage), "texte du web, jamais le détail technique")
        XCTAssertTrue(model.semaines.isEmpty)
        XCTAssertEqual(model.nombre, 0)
        XCTAssertFalse(model.sessionExpiree)

        await model.basculer(jour: Self.mardi, creneau: .nuit)
        XCTAssertTrue(port.journal.bascules.isEmpty, "« Réessayez avant de les modifier. » : aucune bascule sans relecture")

        await model.charger()
        XCTAssertEqual(model.etat, .prete(Self.fixture))

        // Une relecture demandée qui échoue sur une grille affichée la retire aussi (comme le web).
        let instable = PortTemoin(lecture: { _, rang in
            if rang == 2 { throw JoleneError(.network, Self.reseau) }
            return Self.fixture
        })
        let relue = try await modele(instable)
        XCTAssertEqual(relue.etat, .prete(Self.fixture))
        await relue.charger()
        XCTAssertEqual(relue.etat, .echec(DisponibilitesTextes.echecMessage))

        let expiree = try await modele(PortTemoin(lecture: { _, _ in throw JoleneError(.unauthorized, Self.expiration) }))
        XCTAssertEqual(expiree.etat, .echec(Self.expiration))
        XCTAssertTrue(expiree.sessionExpiree)

        let annulee = try await modele(PortTemoin(lecture: { _, _ in throw CancellationError() }))
        XCTAssertEqual(annulee.etat, .chargement, "une annulation n'est jamais une erreur")
    }

    func testEpochPerimeAucunAppel() async throws {
        let port = PortTemoin()
        let (controller, snapshot) = try await session(port, horloge: FixedClock(DemoWorld.fixedNow))
        let model = DisponibilitesModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.nombre, 3)
        _ = await controller.signOut()
        await model.basculer(jour: Self.mardi, creneau: .nuit)
        await model.charger()
        XCTAssertTrue(port.journal.bascules.isEmpty, "epoch périmé : aucune écriture")
        XCTAssertEqual(port.journal.lectures.count, 1, "epoch périmé : aucune lecture")
        XCTAssertTrue(model.enCours.isEmpty)
    }
}
