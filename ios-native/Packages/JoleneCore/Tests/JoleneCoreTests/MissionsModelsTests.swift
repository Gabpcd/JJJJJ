import XCTest
@testable import JoleneCore

/// Modèles d'écran Explorer / détail (relecture lot 0) : une annulation de tâche n'est
/// pas une erreur, un rafraîchissement conserve la liste chargée, une session expirée est
/// signalée pour revalidation, un epoch périmé est ignoré.
@MainActor
final class MissionsModelsTests: XCTestCase {
    private struct ModelError: Error {}

    private final class ScriptedMissions: MissionsPort, @unchecked Sendable {
        enum Step { case missions([Mission]), mission(Mission?), failure(Error) }
        private let lock = NSLock()
        private var steps: [Step]
        private(set) var calls = 0
        init(_ steps: [Step]) { self.steps = steps }

        private func next() -> Step {
            lock.lock(); defer { lock.unlock() }
            calls += 1
            return steps.isEmpty ? .missions([]) : steps.removeFirst()
        }

        func profile(userId: String) async throws -> SoignantProfile? { SoignantProfile(id: userId, profession: "IDE") }
        func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] {
            switch next() {
            case let .missions(missions): return missions
            case let .mission(mission): return mission.map { [$0] } ?? []
            case let .failure(error): throw error
            }
        }
        func mission(id: String, context: MissionReadContext) async throws -> Mission? {
            switch next() {
            case let .missions(missions): return missions.first
            case let .mission(mission): return mission
            case let .failure(error): throw error
            }
        }
    }

    private struct ModelAuth: AuthPort {
        func restoreSession() async throws -> AuthenticatedUser? {
            AuthenticatedUser(id: "u-1", email: "u-1@example.invalid", emailConfirmedAt: Date(), appMetadataRole: "SOIGNANT")
        }
        func signIn(email: String, password: String) async throws -> AuthenticatedUser { throw ModelError() }
        func signOut() async throws {}
    }
    private struct ModelRole: RolePort {
        func currentRole() async throws -> RoleResult { RoleResult(role: "SOIGNANT") }
    }

    private func mission(_ id: String) -> Mission {
        let record = MissionRecord(id: id, intitule: "Mission \(id)", description: nil, service: nil, professionRequise: "IDE",
                                   specialiteMedicaleRequise: nil, accepteNonSpecialises: nil, debutLe: "2026-12-01T08:00:00+00:00",
                                   finLe: "2026-12-01T16:00:00+00:00", dureeHeures: 8, nbCreneaux: 1, tauxHoraireBase: 25,
                                   tauxRistPlafonne: nil, ristPlafondApplique: nil, totalBrut: nil, netAPayer: nil, estUrgente: false,
                                   niveauUrgence: nil, statut: "OUVERTE", etablissementId: "e-1", typeContratRecherche: nil,
                                   boosteeLe: nil, modeRemuneration: nil, retrocessionPct: nil)
        return Mission(record: record, etablissement: nil, distanceKm: nil, creneauxPlanifies: [], planningExact: true)
    }

    private func ready(_ missions: ScriptedMissions) async throws -> (SessionController, SessionSnapshot) {
        let controller = SessionController(gateways: Gateways(auth: ModelAuth(), role: ModelRole(), missions: missions))
        let state = await controller.start()
        let snapshot = try XCTUnwrap(state.snapshot, "session prête attendue, obtenu \(state)")
        return (controller, snapshot)
    }

    func testCancellationKeepsLoadingSoTaskRelaunches() async throws {
        let port = ScriptedMissions([.failure(CancellationError()), .failure(JoleneError(.cancelled, "Chargement annulé."))])
        let (controller, snapshot) = try await ready(port)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertEqual(model.state, .loading, "CancellationError : l'état reste .loading")
        await model.load()
        XCTAssertEqual(model.state, .loading, "JoleneError(.cancelled) : l'état reste .loading")
        XCTAssertFalse(model.sessionExpired)
        XCTAssertNil(model.refreshError)
    }

    func testFailureThenSuccess() async throws {
        let port = ScriptedMissions([.failure(JoleneError(.network, "Connexion impossible.")), .missions([mission("a")])])
        let (controller, snapshot) = try await ready(port)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertEqual(model.state, .failed("Connexion impossible."))
        await model.load()
        XCTAssertEqual(model.missions.map(\.id), ["a"])
        XCTAssertEqual(model.mission(id: "a")?.id, "a")
    }

    func testRefreshKeepsLoadedListOnFailureAndCancellation() async throws {
        let port = ScriptedMissions([.missions([mission("a")]), .failure(JoleneError(.network, "Connexion impossible.")),
                                     .failure(CancellationError()), .missions([mission("b")])])
        let (controller, snapshot) = try await ready(port)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertEqual(model.missions.map(\.id), ["a"])
        await model.load()
        XCTAssertEqual(model.missions.map(\.id), ["a"], "la liste reste à l'écran pendant et après un rafraîchissement échoué")
        XCTAssertEqual(model.refreshError, "Connexion impossible.")
        XCTAssertFalse(model.isRefreshing)
        await model.load()
        XCTAssertEqual(model.missions.map(\.id), ["a"], "annulation du pull-to-refresh : liste conservée")
        XCTAssertNil(model.refreshError)
        await model.load()
        XCTAssertEqual(model.missions.map(\.id), ["b"], "le succès remplace la liste")
    }

    func testUnauthorizedRaisesSessionExpiredFlag() async throws {
        let port = ScriptedMissions([.failure(JoleneError(.unauthorized, "Votre session a expiré. Reconnectez-vous."))])
        let (controller, snapshot) = try await ready(port)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertTrue(model.sessionExpired, "l'écran propose une revalidation de session")
        XCTAssertEqual(model.state, .failed("Votre session a expiré. Reconnectez-vous."))
    }

    func testStaleEpochResultIsDiscarded() async throws {
        let port = ScriptedMissions([.missions([mission("a")])])
        let (controller, snapshot) = try await ready(port)
        let model = MissionsListModel(controller: controller, snapshot: snapshot)
        _ = await controller.signOut()
        await model.load()
        XCTAssertEqual(model.state, .loading, "epoch périmé : aucun résultat n'est publié")
        XCTAssertEqual(port.calls, 0, "aucune lecture sans gateways valides")
    }

    func testDetailCancellationAndUnavailable() async throws {
        let port = ScriptedMissions([.failure(CancellationError()), .mission(nil), .mission(mission("a"))])
        let (controller, snapshot) = try await ready(port)
        let model = MissionDetailModel(missionId: "a", initial: nil, controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertNil(model.errorMessage, "annulation : aucune erreur affichée")
        XCTAssertNil(model.mission)
        await model.load()
        XCTAssertEqual(model.errorMessage, MissionDetailModel.unavailableMessage)
        await model.load()
        XCTAssertEqual(model.mission?.id, "a")
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }

    func testDetailKeepsInitialValueOnFailureAndFlagsExpiredSession() async throws {
        let port = ScriptedMissions([.failure(JoleneError(.unauthorized, "expirée"))])
        let (controller, snapshot) = try await ready(port)
        let model = MissionDetailModel(missionId: "a", initial: mission("a"), controller: controller, snapshot: snapshot)
        await model.load()
        XCTAssertEqual(model.mission?.id, "a", "la valeur de la liste reste affichée")
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.sessionExpired)
    }
}
