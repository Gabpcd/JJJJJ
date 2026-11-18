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
