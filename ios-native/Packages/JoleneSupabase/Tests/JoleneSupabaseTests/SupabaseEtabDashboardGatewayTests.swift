import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Accueil établissement sur Supabase (lot 5, T4) : `fn_stats_dashboard_etablissement` décodée en compteurs, planning
/// des 31 prochains jours lu en PostgREST (filtres du web, créneaux par la pagination vérifiée du lot 0), lecture
/// secondaire en échec → Accueil partiel, jamais un échec de l'écran.
final class SupabaseEtabDashboardGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let statsPath = "/rest/v1/rpc/fn_stats_dashboard_etablissement"
    private let etablissementId = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
    /// 2026-11-02T00:00Z (01:00 à Paris).
    private let maintenant = Date(timeIntervalSince1970: 1_793_577_600)

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseEtabDashboardGateway {
        SupabaseEtabDashboardGateway(client: TestClient.make(), clock: FixedClock(maintenant))
    }

    private var contexte: EtablissementReadContext {
        EtablissementReadContext(userId: "8a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d", etablissementId: etablissementId, roleEtab: .rh,
                                 permissions: PermissionsEtab(accordees: [.lecture, .missions, .candidatures]), epoch: 1)
    }

    private let stats = """
    {"a_deja_publie":true,"total_missions":4,"missions_ouvertes":1,"missions_assignees":1,"missions_en_cours":0,
     "missions_terminees":2,"missions_terminees_ce_mois":0,"soignants_ce_mois":1,"commissions_cumulees":1250.5,
     "commissions_impayees":300,"nb_factures_impayees":2,"pool_urgence_count":0,"messages_non_lus":4,"missions_a_payer":0,
     "litiges_ouverts":0,"candidatures_en_attente":5,
     "candidatures_recentes":[{"candidature_id":"c-1","soignant_nom":"Prénom Nom"}],
     "missions_assignees_detail":[{"mission_id":"m-9","soignant_nom":"Prénom Nom"}]}
    """

    func testCompteursEtPlanningDesTrenteEtUnJours() async throws {
        registry.add("POST", statsPath, respond: .json(200, stats))
        registry.add("GET", "/rest/v1/missions", respond: .json(200, """
        [{"id":"m-1","intitule":"Nuit","statut":"ASSIGNEE","debut_le":"2026-11-02T20:00:00+00:00","fin_le":"2026-11-03T06:00:00+00:00","nb_creneaux":1}]
        """))
        registry.add("GET", "/rest/v1/mission_creneaux", respond: .json(200, """
        [{"id":"s-1","mission_id":"m-1","debut":"2026-11-02T20:00:00+00:00","fin":"2026-11-03T06:00:00+00:00","est_pause":false,"type_creneau":"PREVISIONNEL"}]
        """, headers: ["Content-Range": "0-0/1"]))

        let tableau = try await gateway().tableauDeBord(context: contexte)
        XCTAssertEqual(tableau.stats, EtabDashboardStats(candidaturesEnAttente: 5, messagesNonLus: 4, litigesOuverts: 0,
                                                         nbFacturesImpayees: 2, aDejaPublie: true))
        XCTAssertEqual(tableau.planning?.occurrences.map(\.id), ["m-1:s-1"])
        XCTAssertEqual(tableau.planning?.missionsSansPlanning, [])

        let missions = try XCTUnwrap(registry.requests(to: "/rest/v1/missions").first)
        XCTAssertEqual(missions.query("select"), SupabaseEtabDashboardGateway.missionsSelect, "aucun montant, aucun soignant")
        XCTAssertEqual(missions.query("etablissement_id"), "eq.\(etablissementId)", "établissement confirmé par le serveur (D2)")
        XCTAssertEqual(missions.query("fin_le"), "gte.2026-11-02T00:00:00.000Z")
        XCTAssertEqual(missions.query("debut_le"), "lte.2026-12-03T22:59:59.999Z")
        XCTAssertEqual(missions.query("statut"), "in.(OUVERTE,ASSIGNEE,EN_COURS)")
        XCTAssertEqual(missions.query("order"), "debut_le.asc.nullslast")
        let creneaux = try XCTUnwrap(registry.requests(to: "/rest/v1/mission_creneaux").first)
        XCTAssertEqual(creneaux.query("mission_id"), "in.(m-1)")
        XCTAssertEqual(creneaux.query("type_creneau"), "eq.PREVISIONNEL")
        XCTAssertEqual(creneaux.query("est_pause"), "eq.false")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testPlanningEnEchecAccueilPartielSansErreur() async throws {
        registry.add("POST", statsPath, respond: .json(200, stats))
        registry.add("GET", "/rest/v1/missions", respond: .json(500, #"{"code":"XX000","message":"boom","details":null,"hint":null}"#))
        let tableau = try await gateway().tableauDeBord(context: contexte)
        XCTAssertNil(tableau.planning)
        XCTAssertTrue(tableau.lecturePartielle)
        XCTAssertEqual(tableau.stats.candidaturesEnAttente, 5)
    }

    func testAucuneMissionAucuneLectureDeCreneaux() async throws {
        registry.add("POST", statsPath, respond: .json(200, stats))
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[]"))
        let tableau = try await gateway().tableauDeBord(context: contexte)
        XCTAssertEqual(tableau.planning, EtabPlanningAVenir())
        XCTAssertTrue(registry.requests(to: "/rest/v1/mission_creneaux").isEmpty)
    }

    func testRefusVerbatimFormesInattenduesEtContexteInvalide() async throws {
        registry.add("POST", statsPath, respond: .json(200, #"{"error":"Établissement introuvable"}"#))
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[]"))
        do {
            _ = try await gateway().tableauDeBord(context: contexte)
            XCTFail("attendu : refus")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur, JoleneError(.unknown, "Établissement introuvable"), "message serveur verbatim")
        }
        for corps in ["null", "[]", #"{"success":false,"error":"Non autorisé"}"#] {
            registry.reset()
            registry.add("POST", statsPath, respond: .json(200, corps))
            registry.add("GET", "/rest/v1/missions", respond: .json(200, "[]"))
            do {
                _ = try await gateway().tableauDeBord(context: contexte)
                XCTFail("attendu : refus (\(corps))")
            } catch let erreur as JoleneError {
                XCTAssertNotEqual(erreur.kind, .network, corps)
            }
        }
        registry.reset()
        var invalide = contexte
        invalide.etablissementId = " "
        do {
            _ = try await gateway().tableauDeBord(context: invalide)
            XCTFail("attendu : contexte refusé")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        }
        XCTAssertTrue(registry.requests.isEmpty, "contexte incohérent refusé avant tout appel réseau")
    }
}
