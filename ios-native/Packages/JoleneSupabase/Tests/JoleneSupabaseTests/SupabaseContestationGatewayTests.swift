import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Contestation d'une présence sur Supabase (lot 2, T5b, HARD STOP n°4 ; décision 9, D12) : `fn_ouvrir_litige_rate_limited`
/// par trois clés exactes (surcharge canonique), refus `{error}` verbatim, audit `PRESENCE_CONTESTATION`, relecture du
/// litige par `presence_id`, **aucun** appel `fn_creer_notification` ; fenêtre lue au serveur (booléen nu, fail-closed).
final class SupabaseContestationGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let rpcOuverture = "/rest/v1/rpc/fn_ouvrir_litige_rate_limited"
    private let rpcFenetre = "/rest/v1/rpc/fn_fenetre_contestation_ouverte"
    private let rpcAudit = "/rest/v1/rpc/fn_ecrire_audit_safe"
    private let litiges = "/rest/v1/litiges"
    private let presence = "5f0c6a8e-2b1d-4c3e-9a7f-1d2e3c4b5a69"
    private let mission = "7a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseContestationGateway { SupabaseContestationGateway(client: TestClient.make()) }

    func testTroisClesExactesAuditPuisRelectureParPresenceSansNotification() async throws {
        registry.add("POST", rpcOuverture, respond: .json(200,
            #"{"success":true,"litige_id":"l-1","est_informatif":false,"facture_id":null}"#))
        registry.add("POST", rpcAudit, respond: .json(200, #"{"success":true}"#))
        registry.add("GET", litiges, respond: .json(200, """
        [{"id":"l-1","statut":"OUVERT","presence_id":"\(presence)","mission_id":"\(mission)",
          "type_litige":"DESACCORD_HEURES_POINTAGE","cree_le":"2026-11-02T00:00:00+00:00"}]
        """))

        let issue = try await gateway().contester(missionId: mission, presenceId: presence,
                                                  motif: " <b>Heures</b> validées fausses ", context: TestClient.context)
        guard case let .ouverte(litige) = issue else { return XCTFail("contestation ouverte attendue, obtenu \(issue)") }
        XCTAssertEqual(litige.id, "l-1")
        XCTAssertEqual(litige.statut, "OUVERT")

        let appels = registry.requests(to: rpcOuverture)
        XCTAssertEqual(appels.count, 1, "une seule requête")
        let corps = try XCTUnwrap(appels.first?.bodyJSON as? [String: Any])
        XCTAssertEqual(Set(corps.keys), ["p_mission_id", "p_type_litige", "p_motif"], "trois clés exactes (surcharge canonique)")
        XCTAssertEqual(corps["p_type_litige"] as? String, "DESACCORD_HEURES_POINTAGE")
        XCTAssertEqual(corps["p_mission_id"] as? String, mission)
        XCTAssertEqual(corps["p_motif"] as? String, "Heures validées fausses", "motif nettoyé comme sanitizeText")

        let audit = try XCTUnwrap(registry.requests(to: rpcAudit).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(audit["p_action"] as? String, "PRESENCE_CONTESTATION")
        XCTAssertEqual(audit["p_type_ressource"] as? String, "presence")
        XCTAssertEqual(audit["p_id_ressource"] as? String, presence)
        XCTAssertEqual(audit["p_type_acteur"] as? String, "SOIGNANT")

        let lecture = try XCTUnwrap(registry.requests(to: litiges).first)
        XCTAssertEqual(lecture.query("presence_id"), "eq.\(presence)", "relecture par presence_id")
        XCTAssertEqual(lecture.query("select"), SupabaseContestationGateway.colonnes)
        XCTAssertEqual(lecture.query("order"), "cree_le.desc.nullsfirst", "ordre du web (desc : nulls en tête par défaut)")
        XCTAssertFalse(registry.requests.contains { $0.path.contains("creer_notification") || $0.path.contains("notifications") },
                       "aucune notification écrite par le client (le trigger notifie l'établissement)")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testRefusVerbatimSansAuditNiRelecture() async throws {
        let cas = [
            "Fenêtre de contestation fermée pour ce type de litige. Contactez le support.",
            "Un litige de ce type est déjà ouvert pour cette mission.",
            "Trop de litiges ouverts récemment. Réessayez plus tard.",
        ]
        for message in cas {
            registry.reset()
            registry.add("POST", rpcOuverture, respond: .json(200, #"{"error":"\#(message)"}"#))
            let issue = try await gateway().contester(missionId: mission, presenceId: presence,
                                                      motif: "Les heures sont fausses.", context: TestClient.context)
            XCTAssertEqual(issue, .refusee(message: message), "refus serveur verbatim")
            XCTAssertEqual(registry.requests.count, 1, "\(message) : ni audit ni relecture")
        }

        registry.reset()
        registry.add("POST", rpcOuverture, respond: .json(200, #"{"error":"Non authentifié"}"#))
        do {
            _ = try await gateway().contester(missionId: mission, presenceId: presence, motif: "Les heures sont fausses.",
                                              context: TestClient.context)
            XCTFail("session expirée attendue")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        }
    }

    func testLitigeRattacheAUneAutrePresenceReluParSonIdentifiant() async throws {
        registry.add("POST", rpcOuverture, respond: .json(200, #"{"success":true,"litige_id":"l-2"}"#))
        registry.add("POST", rpcAudit, respond: .json(200, #"{"success":true}"#))
        registry.add("GET", litiges, where: { $0.query("presence_id") != nil }, respond: .json(200, "[]"))
        registry.add("GET", litiges, where: { $0.query("id") == "eq.l-2" }, respond: .json(200,
            #"[{"id":"l-2","statut":"OUVERT","presence_id":"autre"}]"#))
        let issue = try await gateway().contester(missionId: mission, presenceId: presence, motif: "Les heures sont fausses.",
                                                  context: TestClient.context)
        XCTAssertEqual(issue, .ouverte(LitigePresence(id: "l-2", statut: "OUVERT", presenceId: "autre")))

        registry.reset()
        registry.add("POST", rpcOuverture, respond: .json(200, #"{"success":true,"litige_id":"l-3"}"#))
        registry.add("POST", rpcAudit, respond: .json(200, #"{"success":true}"#))
        registry.add("GET", litiges, respond: .json(200, "[]"))
        do {
            _ = try await gateway().contester(missionId: mission, presenceId: presence, motif: "Les heures sont fausses.",
                                              context: TestClient.context)
            XCTFail("litige jamais relu : aucun succès fabriqué")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .contract)
        }
    }

    func testFenetreLueAuServeurBooleenNuSinonContrat() async throws {
        registry.add("POST", rpcFenetre, respond: .json(200, "true"))
        let ouverte = try await gateway().fenetreOuverte(missionId: mission, context: TestClient.context)
        XCTAssertTrue(ouverte)
        let corps = try XCTUnwrap(registry.requests(to: rpcFenetre).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(Set(corps.keys), ["p_type_litige", "p_mission_id"])
        XCTAssertEqual(corps["p_type_litige"] as? String, "DESACCORD_HEURES_POINTAGE")

        registry.reset()
        registry.add("POST", rpcFenetre, respond: .json(200, "false"))
        let fermee = try await gateway().fenetreOuverte(missionId: mission, context: TestClient.context)
        XCTAssertFalse(fermee)

        registry.reset()
        registry.add("POST", rpcFenetre, respond: .json(200, #"{"ouverte":true}"#))
        do {
            _ = try await gateway().fenetreOuverte(missionId: mission, context: TestClient.context)
            XCTFail("forme inattendue : refus de contrat (bouton masqué)")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .contract)
        }
    }

    func testLitigeDeLaPresenceReluParPresenceId() async throws {
        registry.add("GET", litiges, respond: .json(200, #"[{"id":"l-9","statut":"EN_DISCUSSION","presence_id":"p"}]"#))
        let lu = try await gateway().litige(presenceId: presence, context: TestClient.context)
        XCTAssertEqual(lu?.statut, "EN_DISCUSSION")
        let lecture = try XCTUnwrap(registry.requests(to: litiges).first)
        XCTAssertEqual(lecture.query("presence_id"), "eq.\(presence)")
        XCTAssertEqual(lecture.query("limit"), "1")

        registry.reset()
        registry.add("GET", litiges, respond: .json(200, "[]"))
        let aucun = try await gateway().litige(presenceId: presence, context: TestClient.context)
        XCTAssertNil(aucun)
    }
}
