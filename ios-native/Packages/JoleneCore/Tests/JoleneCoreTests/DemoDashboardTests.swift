import XCTest
@testable import JoleneCore

/// Tableau de bord du monde démo (lot 1, T3) : `demo-dashboard.json` assemblé par la même
/// fonction que le monde Supabase (`AccueilAssemblage`), aucun réseau, horloge fixée. Les
/// valeurs attendues sont celles que le XCUITest `DemoAccueilTests` relit à l'écran.
final class DemoDashboardTests: XCTestCase {
    private func tableau() async throws -> DashboardSnapshot {
        try await DemoWorld.gateways().dashboard.dashboard(context: DemoWorld.context, delaiEcran: delaiEcranTest)
    }

    func testTableauDeBordDemoAssembleSansReseau() async throws {
        let snapshot = try await tableau()
        XCTAssertEqual(snapshot.profil?.prenom, "Camille")
        XCTAssertEqual(snapshot.notifsNonLues, 2)
        XCTAssertEqual(snapshot.missionsOublieesCount, 0)
        XCTAssertFalse(snapshot.planningIndisponible)

        XCTAssertEqual(snapshot.prochaines.map(\.id), ["demo-assignee-001", "demo-assignee-002"])
        XCTAssertEqual(snapshot.prochaines.map { AccueilPresentation.planningProchaine($0.planning) },
                       ["jeudi 5 nov. · 08h00 → 16h00", "lundi 9 nov. · 08h00 → 16h00 · créneau 1/2"])
        XCTAssertEqual(snapshot.prochaines.map(\.etablissementNom),
                       ["Établissement fictif République", "Établissement fictif des Lilas"])
        XCTAssertEqual(snapshot.prochaines.compactMap { $0.mission?.record.statut }, ["ASSIGNEE", "ASSIGNEE"])

        XCTAssertEqual(snapshot.pourToi.map(\.id), ["demo-mission-001", "demo-mission-002", "demo-mission-003"])
        XCTAssertEqual(snapshot.pourToi.prefix(AccueilPresentation.nombrePourToiAffiches).map { AccueilPresentation.planningPourToi($0.planning) },
                       ["mardi 3 nov. · 08h00 → 16h00", "mercredi 4 nov. · 08h00 → 16h00"])
        XCTAssertEqual(snapshot.pourToi.first?.mission?.distanceKm, 1.4, "mission enrichie comme dans Explorer")

        let proposition = try XCTUnwrap(snapshot.propositions.first)
        XCTAssertEqual(snapshot.propositions.map(\.id), ["demo-proposition-001"])
        XCTAssertEqual(proposition.proposition.mission.id, "demo-mission-011")
        XCTAssertEqual(proposition.etablissementNom, "Établissement fictif des Lilas")
        XCTAssertEqual(AccueilPresentation.tempsRestant(expireLe: proposition.expireLe, maintenant: DemoWorld.fixedNow), "1h 30min")
        XCTAssertEqual(proposition.mission?.id, "demo-mission-011")

        let gains = try XCTUnwrap(snapshot.gains)
        XCTAssertEqual(AccueilPresentation.texteGains(gains), "💰 Ce mois : 162,40\u{00A0}€ net salarié estimé* sur 1 mission")
        XCTAssertTrue(AccueilPresentation.afficheNoteNetEstime(gains))
        XCTAssertEqual(snapshot.gainsMoisNbMissions, 1)
        XCTAssertEqual(AccueilPresentation.accroche(profil: snapshot.profil, nombreOuvertes: snapshot.pourToi.count),
                       "3 missions près de chez vous — vous pouvez déjà postuler.")
    }

    func testAutreUtilisateurRefuseAvecErreurDemoOnly() async {
        var autre = DemoWorld.context
        autre.userId = "user-1"
        autre.profile.id = "user-1"
        do {
            _ = try await DemoWorld.gateways().dashboard.dashboard(context: autre, delaiEcran: delaiEcranTest)
            XCTFail("la démo ne sert aucun autre utilisateur")
        } catch let error as JoleneError {
            XCTAssertEqual(error, JoleneError(.demoOnly, DemoWorld.messageDemoSeulement))
        } catch {
            XCTFail("type d'erreur inattendu : \(error)")
        }
    }

    func testMissionsAssigneesLisiblesEnDetailMaisJamaisDansExplorer() async throws {
        let gateways = DemoWorld.gateways()
        let assignee = try await gateways.missions.mission(id: "demo-assignee-002", context: DemoWorld.context)
        XCTAssertEqual(assignee?.record.statut, "ASSIGNEE")
        XCTAssertEqual(assignee?.creneauxPlanifies.count, 2)
        XCTAssertEqual(assignee?.etablissement?.nom, "Établissement fictif des Lilas")
        let liste = try await gateways.missions.listMissions(context: DemoWorld.context, filters: MissionFilters())
        XCTAssertEqual(liste.count, 30, "Explorer ne liste que les missions ouvertes")
        XCTAssertFalse(liste.contains { $0.id.hasPrefix("demo-assignee-") })
    }

    /// Revue B8 de T3, 2e passe : le détail d'une mission d'Explorer ne lit jamais la fixture du
    /// tableau de bord ; une fixture `demo-dashboard.json` illisible ne casse donc que les missions
    /// ASSIGNEE de l'Accueil, et le dit (erreur levée, jamais un « introuvable » silencieux).
    func testDetailExplorerIndependantDeLaFixtureDuTableauDeBord() async throws {
        let illisible = JoleneError(.contract, "fixture du tableau de bord illisible")
        let port = DemoMissionsGateway(missionsAssignees: { throw illisible })
        let ouverte = try await port.mission(id: "demo-mission-001", context: DemoWorld.context)
        XCTAssertEqual(ouverte?.id, "demo-mission-001", "le détail Explorer reste lisible")
        do {
            _ = try await port.mission(id: "demo-assignee-001", context: DemoWorld.context)
            XCTFail("une mission assignée de l'Accueil sans fixture lisible n'est jamais un « introuvable » silencieux")
        } catch let error as JoleneError {
            XCTAssertEqual(error, illisible)
        }
        let liste = try await port.listMissions(context: DemoWorld.context, filters: MissionFilters())
        XCTAssertEqual(liste.count, 30, "Explorer ne lit pas la fixture du tableau de bord")
    }

    // MARK: - Échec forcé (recette de l'état d'erreur dans l'interface, revue B8 de T3)

    func testEchecForceAuPremierChargementPuisRepriseSurLeTableauDemo() async throws {
        let port = DemoDashboardEchecGateway()
        do {
            _ = try await port.dashboard(context: DemoWorld.context, delaiEcran: delaiEcranTest)
            XCTFail("le premier chargement doit échouer")
        } catch let error as JoleneError {
            XCTAssertEqual(error, JoleneError(.network, SessionController.timeoutMessage), "panne simulée = délai dépassé")
        }
        let reprise = try await port.dashboard(context: DemoWorld.context, delaiEcran: delaiEcranTest)
        let attendu = try await DemoDashboardGateway().dashboard(context: DemoWorld.context, delaiEcran: delaiEcranTest)
        XCTAssertEqual(reprise, attendu, "« Réessayer » relit le tableau de bord démo")
    }

    func testEchecForceNonConsommeParUneTacheAnnulee() async throws {
        let port = DemoDashboardEchecGateway()
        // Tâche annulée avant l'appel (vue qui disparaît) : l'échec reste dû au chargement suivant.
        let annulee = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await port.dashboard(context: DemoWorld.context, delaiEcran: delaiEcranTest)
        }.result
        XCTAssertThrowsError(try annulee.get()) { XCTAssertTrue($0 is CancellationError, "\($0)") }
        do {
            _ = try await port.dashboard(context: DemoWorld.context, delaiEcran: delaiEcranTest)
            XCTFail("l'échec forcé n'a pas été consommé par la tâche annulée")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .network)
        }
        _ = try await port.dashboard(context: DemoWorld.context, delaiEcran: delaiEcranTest)
    }

    func testEchecForceRefuseToutAutreUtilisateur() async {
        var autre = DemoWorld.context
        autre.userId = "user-1"
        autre.profile.id = "user-1"
        do {
            _ = try await DemoDashboardEchecGateway().dashboard(context: autre, delaiEcran: delaiEcranTest)
            XCTFail("la démo ne sert aucun autre utilisateur, même en échec forcé")
        } catch let error as JoleneError {
            XCTAssertEqual(error, JoleneError(.demoOnly, DemoWorld.messageDemoSeulement))
        } catch {
            XCTFail("type d'erreur inattendu : \(error)")
        }
    }
}
