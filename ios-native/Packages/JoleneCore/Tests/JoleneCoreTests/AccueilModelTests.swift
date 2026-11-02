import XCTest
@testable import JoleneCore

/// Modèle de l'onglet Accueil (lot 1, T3) : mêmes règles que `MissionsListModel` (annulation
/// jamais affichée en erreur, rafraîchissement sans démontage, session expirée, epoch périmé
/// ignoré), plus la borne `resolutionTimeout` (décision 14) et la relecture à l'apparition au-delà
/// de 60 s (`DashboardSoignant.tsx` : `staleTime: 60_000`).
@MainActor
final class AccueilModelTests: XCTestCase {
    private struct ModelError: Error {}

    /// Port scripté : chaque appel consomme une étape ; `entree` est ouverte dès l'appel, `retenue`
    /// (si présente) retient la réponse jusqu'à son ouverture par le test.
    private final class ScriptedDashboard: DashboardPort, @unchecked Sendable {
        enum Step { case snapshot(DashboardSnapshot), failure(Error) }
        private let lock = NSLock()
        private var steps: [Step]
        private var appels = 0
        let entree = Gate()
        var retenue: Gate?

        init(_ steps: [Step], retenue: Gate? = nil) { self.steps = steps; self.retenue = retenue }

        var calls: Int { lock.lock(); defer { lock.unlock() }; return appels }

        private func next() -> Step {
            lock.lock(); defer { lock.unlock() }
            appels += 1
            return steps.isEmpty ? .snapshot(DashboardSnapshot()) : steps.removeFirst()
        }

        func dashboard(context: MissionReadContext) async throws -> DashboardSnapshot {
            let step = next()
            await entree.open()
            if let retenue { await retenue.wait() }
            switch step {
            case let .snapshot(snapshot): return snapshot
            case let .failure(error): throw error
            }
        }
    }

    /// Horloge que le test fait avancer (relecture au-delà de 60 s).
    private final class HorlogeReglable: ClockPort, @unchecked Sendable {
        private let lock = NSLock()
        private var instant: Date
        init(_ instant: Date) { self.instant = instant }
        func now() -> Date { lock.lock(); defer { lock.unlock() }; return instant }
        func avancer(_ secondes: TimeInterval) { lock.lock(); instant += secondes; lock.unlock() }
    }

    private struct PretAuth: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? {
            AuthenticatedUser(id: "u-1", email: "u-1@example.invalid", emailConfirmedAt: Date(timeIntervalSince1970: 1_700_000_000),
                              appMetadataRole: "SOIGNANT")
        }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw ModelError() }
        func signOut() async throws {}
    }

    private struct PretMissions: MissionsPort {
        func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: userId, profession: "IDE") }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] { [] }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? { nil }
    }

    private func tableau(_ prenom: String, prochaine: String? = nil) -> DashboardSnapshot {
        var snapshot = DashboardSnapshot(profil: DashboardProfil(prenom: prenom, profession: "IDE", tousDocumentsValides: true, typeExercice: nil))
        if let prochaine {
            let ligne = DashboardMissionLigne(id: prochaine, intitule: "Mission \(prochaine)", service: nil, debutLe: nil, finLe: nil,
                                              statut: "ASSIGNEE", estUrgente: false, tauxHoraireBase: nil, etablissementId: nil, etabNom: nil)
            snapshot.prochaines = [AccueilMission(ligne: ligne, etablissementNom: "Établissement", etablissementVille: nil,
                                                  planning: .indisponible, mission: nil)]
        }
        return snapshot
    }

    private func pret(_ port: ScriptedDashboard, horloge: ClockPort = FixedClock(DemoWorld.fixedNow),
                      timeout: TimeInterval = SessionController.defaultResolutionTimeout) async throws -> (SessionController, SessionSnapshot) {
        var gateways = Gateways(auth: PretAuth(), role: NeutralRole(), missions: PretMissions(), clock: horloge)
        gateways.dashboard = port
        let controller = SessionController(gateways: gateways, resolutionTimeout: timeout)
        let state = await controller.start()
        let snapshot = try XCTUnwrap(state.snapshot, "session prête attendue, obtenu \(state)")
        return (controller, snapshot)
    }

    func testChargementPublieLeTableauEtSonInstant() async throws {
        let port = ScriptedDashboard([.snapshot(tableau("Camille", prochaine: "m-1"))])
        let (controller, snapshot) = try await pret(port)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        XCTAssertEqual(model.state, .loading)
        await model.load()
        XCTAssertEqual(model.tableau?.profil?.prenom, "Camille")
        XCTAssertEqual(model.chargeLe, DemoWorld.fixedNow, "instant de l'horloge des gateways")
        XCTAssertEqual(model.horloge.now(), DemoWorld.fixedNow)
        XCTAssertEqual(model.mission(id: "m-1"), nil, "sans fiche relue, le détail se chargera lui-même")
        XCTAssertFalse(model.sessionExpired)
        XCTAssertEqual(port.calls, 1)
    }

    func testEchecPuisSuccesEtMessageGeneriquePourUneErreurInconnue() async throws {
        let port = ScriptedDashboard([.failure(JoleneError(.network, "Connexion impossible.")), .failure(ModelError()),
                                      .snapshot(tableau("Camille"))])
        let (controller, snapshot) = try await pret(port)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertEqual(model.state, .failed("Connexion impossible."))
        await model.load()
        XCTAssertEqual(model.state, .failed(AccueilModel.genericFailureMessage), "jamais le détail technique d'une erreur inconnue")
        await model.load()
        XCTAssertEqual(model.tableau?.profil?.prenom, "Camille")
    }

    func testRafraichissementConserveLeTableauEnCasDEchecOuDAnnulation() async throws {
        let port = ScriptedDashboard([.snapshot(tableau("A")), .failure(JoleneError(.network, "Connexion impossible.")),
                                      .failure(CancellationError()), .snapshot(tableau("B"))])
        let (controller, snapshot) = try await pret(port)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        await model.load()
        await model.load()
        XCTAssertEqual(model.tableau?.profil?.prenom, "A", "le tableau reste à l'écran après un rafraîchissement échoué")
        XCTAssertEqual(model.refreshError, "Connexion impossible.")
        XCTAssertFalse(model.isRefreshing)
        await model.load()
        XCTAssertEqual(model.tableau?.profil?.prenom, "A", "pull-to-refresh interrompu : tableau conservé")
        XCTAssertNil(model.refreshError)
        await model.load()
        XCTAssertEqual(model.tableau?.profil?.prenom, "B", "le succès remplace le tableau")
    }

    func testAnnulationLaisseLEtatEnChargement() async throws {
        let port = ScriptedDashboard([.failure(CancellationError()), .failure(JoleneError(.cancelled, "Chargement annulé."))])
        let (controller, snapshot) = try await pret(port)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertEqual(model.state, .loading)
        await model.load()
        XCTAssertEqual(model.state, .loading, "`.task` relancera le chargement au prochain affichage")
        XCTAssertNil(model.refreshError)
    }

    func testSessionExpireeSignaleePourRevalidation() async throws {
        let port = ScriptedDashboard([.failure(JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous."))])
        let (controller, snapshot) = try await pret(port)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertTrue(model.sessionExpired)
        XCTAssertEqual(model.state, .failed("Votre session a expiré. Reconnectez-vous."))
    }

    func testEpochPerimeAucunAppel() async throws {
        let port = ScriptedDashboard([.snapshot(tableau("A"))])
        let (controller, snapshot) = try await pret(port)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        _ = await controller.signOut()
        await model.load()
        XCTAssertEqual(model.state, .loading, "epoch périmé : aucun résultat publié")
        XCTAssertEqual(port.calls, 0, "aucune lecture sans gateways valides")
    }

    func testReponseRecueApresUnChangementDIdentiteIgnoree() async throws {
        let retenue = Gate()
        let port = ScriptedDashboard([.snapshot(tableau("Ancienne identité"))], retenue: retenue)
        let (controller, snapshot) = try await pret(port)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        let chargement = Task { await model.load() }
        await port.entree.wait()
        _ = await controller.signOut()
        await retenue.open()
        await chargement.value
        XCTAssertEqual(model.state, .loading, "la réponse d'un epoch périmé n'est jamais publiée")
        XCTAssertNil(model.tableau)
    }

    func testDelaiDepasseEstUneErreurReseauBornee() async throws {
        let retenue = Gate() // jamais ouverte avant la fin du test : port muet
        let port = ScriptedDashboard([.snapshot(tableau("Trop tard"))], retenue: retenue)
        let (controller, snapshot) = try await pret(port, timeout: 0.05)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        let debut = Date()
        await model.load()
        XCTAssertEqual(model.state, .failed(SessionController.timeoutMessage))
        XCTAssertLessThan(Date().timeIntervalSince(debut), 2, "le délai de la session, pas le port, rend la main")
        XCTAssertFalse(model.sessionExpired)
        await retenue.open()
    }

    func testRelectureALApparitionSeulementAuDelaDeSoixanteSecondes() async throws {
        let horloge = HorlogeReglable(DemoWorld.fixedNow)
        let port = ScriptedDashboard([.snapshot(tableau("A")), .snapshot(tableau("B")), .snapshot(tableau("C"))])
        let (controller, snapshot) = try await pret(port, horloge: horloge)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        await model.loadIfStale()
        XCTAssertEqual(port.calls, 1, "premier affichage : chargement")
        horloge.avancer(AccueilModel.delaiRelecture)
        await model.loadIfStale()
        XCTAssertEqual(port.calls, 1, "60 s pile : données encore fraîches")
        horloge.avancer(1)
        await model.loadIfStale()
        XCTAssertEqual(port.calls, 2, "au-delà de 60 s : relecture")
        XCTAssertEqual(model.tableau?.profil?.prenom, "B")
        XCTAssertEqual(AccueilModel.delaiRelecture, 60)
    }

    func testEchecNeRelancePasAutomatiquementALApparition() async throws {
        let port = ScriptedDashboard([.failure(JoleneError(.network, "Connexion impossible.")), .snapshot(tableau("A"))])
        let (controller, snapshot) = try await pret(port)
        let model = AccueilModel(controller: controller, snapshot: snapshot)
        await model.loadIfStale()
        await model.loadIfStale()
        XCTAssertEqual(port.calls, 1, "après un échec, « Réessayer » relance ; l'apparition ne boucle pas")
        await model.load()
        XCTAssertEqual(model.tableau?.profil?.prenom, "A")
    }
}
