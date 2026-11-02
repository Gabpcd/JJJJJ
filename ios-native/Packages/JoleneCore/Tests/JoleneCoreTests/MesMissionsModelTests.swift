import XCTest
@testable import JoleneCore

/// Utilisateur restauré par les ports d'auth de ces tests (hors du main actor : lu par les ports).
private let utilisateurMesMissions = AuthenticatedUser(id: "u-1", email: "u-1@example.invalid",
                                                       emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                       appMetadataRole: "SOIGNANT")

/// Modèle de « Mes missions » (lot 1, T5) : mêmes règles que `AccueilModel` (annulation jamais
/// affichée en erreur, relecture sans démontage, session expirée, epoch périmé et lecture dépassée
/// ignorés, borne `resolutionTimeout`), plus la relecture de la première page à chaque sélection
/// d'onglet (web : `setPage(0)` au changement d'onglet) et « Charger plus » (page suivante, sans
/// doublon, seulement après une page pleine).
@MainActor
final class MesMissionsModelTests: XCTestCase {
    private struct ModelError: Error {}

    /// Port scripté : chaque appel consomme l'étape suivante de sa méthode et s'inscrit au journal.
    /// Une étape `retenue` attend l'ouverture de sa barrière (deux lectures se chevauchent).
    private final class ScriptedMesMissions: MesMissionsPort, @unchecked Sendable {
        enum Etape {
            case candidatures([CandidatureRecord])
            case page(MissionsPage)
            case echec(Error)
            case retenue(MissionsPage, entree: Gate, sortie: Gate)
            /// Ne répond jamais (délai de l'écran).
            case muet(Gate)
        }
        private let lock = NSLock()
        private var etapes: [String: [Etape]]
        private var appelsRecus: [String] = []

        init(candidatures: [Etape] = [], aVenir: [Etape] = [], passees: [Etape] = []) {
            etapes = ["candidatures": candidatures, "aVenir": aVenir, "passees": passees]
        }

        var appels: [String] { lock.lock(); defer { lock.unlock() }; return appelsRecus }

        private func suivante(_ methode: String, page: Int?) -> Etape {
            lock.lock(); defer { lock.unlock() }
            appelsRecus.append(page.map { "\(methode) \($0)" } ?? methode)
            guard var file = etapes[methode], !file.isEmpty else { return .echec(nonScripte) }
            let etape = file.removeFirst()
            etapes[methode] = file
            return etape
        }

        private func jouer(_ etape: Etape) async throws -> MissionsPage {
            switch etape {
            case let .page(page): return page
            case let .echec(error): throw error
            case let .retenue(page, entree, sortie):
                await entree.open()
                await sortie.wait()
                return page
            case let .muet(gate):
                await gate.wait()
                throw CancellationError()
            case .candidatures: throw nonScripte
            }
        }

        func candidatures(context: MissionReadContext) async throws -> [CandidatureRecord] {
            switch suivante("candidatures", page: nil) {
            case let .candidatures(lignes): return lignes
            case let .echec(error): throw error
            default: throw nonScripte
            }
        }

        func aVenir(context: MissionReadContext, page: Int) async throws -> MissionsPage {
            try await jouer(suivante("aVenir", page: page))
        }

        func passees(context: MissionReadContext, page: Int) async throws -> MissionsPage {
            try await jouer(suivante("passees", page: page))
        }
    }

    private struct PretAuth: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? { utilisateurMesMissions }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw ModelError() }
        func signOut() async throws {}
    }

    private struct PretMissions: MissionsPort {
        func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: userId, profession: "IDE") }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
    }

    private func mission(_ id: String) -> Mission {
        let record = MissionRecord(id: id, intitule: "Mission \(id)", description: nil, service: nil, professionRequise: "IDE",
                                   specialiteMedicaleRequise: nil, accepteNonSpecialises: nil, debutLe: "2026-11-05T07:00:00.000Z",
                                   finLe: "2026-11-05T15:00:00.000Z", dureeHeures: 8, nbCreneaux: 1, tauxHoraireBase: 27,
                                   tauxRistPlafonne: nil, ristPlafondApplique: false, totalBrut: nil, netAPayer: nil,
                                   estUrgente: false, niveauUrgence: nil, statut: "ASSIGNEE", etablissementId: "e-1",
                                   typeContratRecherche: "SALARIE", boosteeLe: nil, modeRemuneration: nil, retrocessionPct: nil)
        return Mission(record: record, etablissement: nil, distanceKm: nil, creneauxPlanifies: [], planningExact: true)
    }

    private func page(_ ids: [String], page numero: Int = 0, aSuivre: Bool = false,
                      finances: [String: MissionGainLigne] = [:]) -> MissionsPage {
        var lue = MissionsPage(missions: ids.map(mission), page: numero, aSuivre: aSuivre)
        lue.finances = finances
        return lue
    }

    private func finance(_ id: String) -> MissionGainLigne {
        MissionGainLigne(id: id, typeContratApplique: "LIBERAL", typeContratRecherche: nil, totalBrut: nil, netAPayer: 100, netEstime: nil)
    }

    private func pret(_ port: ScriptedMesMissions, timeout: TimeInterval = SessionController.defaultResolutionTimeout)
        async throws -> (SessionController, SessionSnapshot) {
        var gateways = Gateways(auth: PretAuth(), role: NeutralRole(), missions: PretMissions(), clock: FixedClock(DemoWorld.fixedNow))
        gateways.mesMissions = port
        let controller = SessionController(gateways: gateways, resolutionTimeout: timeout)
        let state = await controller.start()
        let snapshot = try XCTUnwrap(state.snapshot, "session prête attendue, obtenu \(state)")
        return (controller, snapshot)
    }

    // MARK: - Lecture

    func testOngletParDefautAVenirEtPremiereLecture() async throws {
        let port = ScriptedMesMissions(aVenir: [.page(page(["m-1", "m-2"]))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        XCTAssertEqual(model.onglet, .aVenir, "onglet du web par défaut")
        XCTAssertEqual(model.aVenir.contenu, .chargement)
        await model.charger()
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["m-1", "m-2"])
        XCTAssertEqual(model.aVenir.page, 0)
        XCTAssertFalse(model.aVenir.aSuivre)
        XCTAssertFalse(model.aVenir.rafraichissement)
        XCTAssertEqual(model.horloge.now(), DemoWorld.fixedNow, "horloge des gateways de la session")
        XCTAssertEqual(model.mission(id: "m-2")?.id, "m-2", "valeur initiale du détail")
        XCTAssertEqual(port.appels, ["aVenir 0"])
        XCTAssertEqual(model.candidatures.contenu, .chargement, "les autres onglets ne sont lus qu'à leur sélection")
    }

    func testChaqueSelectionDOngletRelitSaPremierePage() async throws {
        var candidature = CandidatureRecord(id: "c-1", missionId: "m-9", statut: "EN_ATTENTE", message: nil, typeContratChoisi: nil, creeLe: nil)
        candidature.mission = mission("m-9")
        let port = ScriptedMesMissions(candidatures: [.candidatures([candidature]), .candidatures([])],
                                       aVenir: [.page(page(["m-1"]))],
                                       passees: [.page(page(["m-5"], finances: ["m-5": finance("m-5")]))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot, onglet: .candidatures)
        await model.charger()
        XCTAssertEqual(model.candidatures.elements.map(\.id), ["c-1"])
        XCTAssertEqual(model.mission(id: "m-9")?.id, "m-9")
        await model.selectionner(.passees)
        XCTAssertEqual(model.onglet, .passees)
        XCTAssertEqual(model.passees.elements.map(\.id), ["m-5"])
        XCTAssertEqual(model.finances["m-5"]?.netAPayer, 100)
        await model.selectionner(.aVenir)
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["m-1"])
        await model.selectionner(.candidatures)
        XCTAssertEqual(model.candidatures.elements, [], "relue à la sélection : la candidature retirée disparaît")
        XCTAssertEqual(port.appels, ["candidatures", "passees 0", "aVenir 0", "candidatures"])
    }

    func testRelectureConserveLaListeEtExposeSonErreur() async throws {
        let port = ScriptedMesMissions(aVenir: [.page(page(["m-1"])), .echec(JoleneError(.network, "Connexion impossible.")),
                                                .echec(CancellationError()), .page(page(["m-2"]))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        await model.charger()
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["m-1"], "la liste reste à l'écran après une relecture échouée")
        XCTAssertEqual(model.aVenir.erreurRafraichissement, "Connexion impossible.")
        XCTAssertFalse(model.aVenir.rafraichissement)
        await model.charger()
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["m-1"], "relecture interrompue : liste conservée")
        XCTAssertNil(model.aVenir.erreurRafraichissement)
        await model.charger()
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["m-2"], "le succès remplace la liste")
    }

    func testEchecDePremiereLectureEtMessageGenerique() async throws {
        let port = ScriptedMesMissions(passees: [.echec(JoleneError(.network, "Connexion impossible.")), .echec(ModelError()),
                                                 .page(page(["m-1"]))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot, onglet: .passees)
        await model.charger()
        XCTAssertEqual(model.passees.contenu, .echec("Connexion impossible."))
        await model.charger()
        XCTAssertEqual(model.passees.contenu, .echec(MesMissionsModel.genericFailureMessage), "jamais le détail technique")
        await model.charger()
        XCTAssertEqual(model.passees.elements.map(\.id), ["m-1"], "« Réessayer » relit")
    }

    func testAnnulationLaisseLEtatEnChargement() async throws {
        let port = ScriptedMesMissions(aVenir: [.echec(CancellationError()), .echec(JoleneError(.cancelled, "Chargement annulé."))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.aVenir.contenu, .chargement)
        await model.charger()
        XCTAssertEqual(model.aVenir.contenu, .chargement, "`.task` relancera la lecture au prochain affichage")
        XCTAssertNil(model.aVenir.erreurRafraichissement)
    }

    func testSessionExpireeSignaleePourRevalidation() async throws {
        let port = ScriptedMesMissions(candidatures: [.echec(JoleneError(.unauthorized, SessionController.sessionExpiredMessage)), .candidatures([])])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot, onglet: .candidatures)
        await model.charger()
        XCTAssertTrue(model.sessionExpired)
        XCTAssertEqual(model.candidatures.contenu, .echec(SessionController.sessionExpiredMessage))
        await model.charger()
        XCTAssertFalse(model.sessionExpired, "une lecture réussie lève l'indicateur")
        XCTAssertEqual(model.candidatures.contenu, .chargee([]))
    }

    // MARK: - Pages

    func testChargerPlusAjouteSansDoublonPuisSArreteApresUnePageIncomplete() async throws {
        let port = ScriptedMesMissions(aVenir: [.page(page(["m-1", "m-2"], aSuivre: true)),
                                                .page(page(["m-2", "m-3"], page: 1, aSuivre: false))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertTrue(model.aVenir.aSuivre)
        await model.chargerPlus()
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["m-1", "m-2", "m-3"], "page suivante ajoutée, doublon écarté")
        XCTAssertEqual(model.aVenir.page, 1)
        XCTAssertFalse(model.aVenir.aSuivre)
        XCTAssertFalse(model.aVenir.chargementSuite)
        await model.chargerPlus()
        XCTAssertEqual(port.appels, ["aVenir 0", "aVenir 1"], "aucune lecture après une page incomplète")
    }

    func testChargerPlusEnEchecConserveLaListeEtNExistePasPourLesCandidatures() async throws {
        let port = ScriptedMesMissions(candidatures: [.candidatures([])],
                                       aVenir: [.page(page(["m-1"], aSuivre: true)), .echec(JoleneError(.network, "Connexion impossible.")),
                                                .page(page(["m-2"], page: 1))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        await model.chargerPlus()
        XCTAssertEqual(port.appels, [], "rien avant une première page lue")
        await model.charger()
        await model.chargerPlus()
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["m-1"])
        XCTAssertEqual(model.aVenir.erreurSuite, "Connexion impossible.")
        XCTAssertNil(model.aVenir.erreurRafraichissement, "l'échec d'une page suivante n'est pas une relecture échouée")
        XCTAssertTrue(model.aVenir.aSuivre, "« Charger plus » reste proposé")
        await model.chargerPlus()
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["m-1", "m-2"])
        XCTAssertNil(model.aVenir.erreurSuite)
        await model.selectionner(.candidatures)
        await model.chargerPlus()
        XCTAssertEqual(port.appels, ["aVenir 0", "aVenir 1", "aVenir 1", "candidatures"], "aucune page suivante pour les candidatures")
    }

    func testFinancesDesPasseesFusionneesPuisRemplaceesALaRelecture() async throws {
        let port = ScriptedMesMissions(passees: [.page(page(["m-1"], aSuivre: true, finances: ["m-1": finance("m-1")])),
                                                 .page(page(["m-2"], page: 1, finances: ["m-2": finance("m-2")])),
                                                 .page(page(["m-1"], finances: ["m-1": finance("m-1")]))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot, onglet: .passees)
        await model.charger()
        await model.chargerPlus()
        XCTAssertEqual(Set(model.finances.keys), ["m-1", "m-2"])
        await model.charger()
        XCTAssertEqual(Set(model.finances.keys), ["m-1"], "première page relue : colonnes de la page relue seulement")
        XCTAssertEqual(model.passees.elements.map(\.id), ["m-1"])
    }

    // MARK: - Identité, chevauchement, délai

    func testEpochPerimeAucunAppel() async throws {
        let port = ScriptedMesMissions(aVenir: [.page(page(["m-1"]))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        _ = await controller.signOut()
        await model.charger()
        XCTAssertEqual(model.aVenir.contenu, .chargement, "epoch périmé : aucun résultat publié")
        XCTAssertEqual(port.appels, [], "aucune lecture sans gateways valides")
    }

    func testReponseApresUnChangementDIdentiteIgnoree() async throws {
        let entree = Gate()
        let sortie = Gate()
        let port = ScriptedMesMissions(aVenir: [.retenue(page(["ancienne"]), entree: entree, sortie: sortie)])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        let lecture = Task { await model.charger() }
        await entree.wait()
        _ = await controller.signOut()
        await sortie.open()
        await lecture.value
        XCTAssertEqual(model.aVenir.contenu, .chargement, "réponse de l'identité précédente abandonnée")
    }

    func testLectureDepasseeParUnePlusRecenteIgnoree() async throws {
        let entree = Gate()
        let sortie = Gate()
        let port = ScriptedMesMissions(aVenir: [.retenue(page(["lente"]), entree: entree, sortie: sortie), .page(page(["recente"]))])
        let (controller, snapshot) = try await pret(port)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        let lente = Task { await model.charger() }
        await entree.wait()
        await model.charger()
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["recente"])
        await sortie.open()
        await lente.value
        XCTAssertEqual(model.aVenir.elements.map(\.id), ["recente"], "la réponse plus lente d'une lecture dépassée est ignorée")
        XCTAssertFalse(model.aVenir.rafraichissement)
    }

    func testLectureBorneeAuDelaiDeResolution() async throws {
        let jamais = Gate()
        let port = ScriptedMesMissions(aVenir: [.muet(jamais)])
        let (controller, snapshot) = try await pret(port, timeout: 0.2)
        let model = MesMissionsModel(controller: controller, snapshot: snapshot)
        await model.charger()
        XCTAssertEqual(model.aVenir.contenu, .echec(SessionController.timeoutMessage), "un port muet rend l'erreur générique de délai")
        await jamais.open()
    }
}
