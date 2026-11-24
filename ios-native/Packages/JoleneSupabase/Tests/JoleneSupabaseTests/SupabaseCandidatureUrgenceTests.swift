import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Acceptation rapide du pool (L4-T11) : `CandidaturePort.confirmer(.urgence)` sur `fn_confirmer_action_planning_v1`, qui
/// contrôle le planning puis délègue à `fn_accepter_mission_urgence(p_mission_id)` (fiche « Lot 4 — actions SWIPE_LIKE et
/// URGENCE ») : planning exact obligatoire, `p_choix_contrat` null, succès annoncé seulement après relecture de la
/// candidature en `EN_ATTENTE_VALIDATION_ETAB`, refus verbatim, `choix_requis` relayé (jamais rejoué).
final class SupabaseCandidatureUrgenceTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let missionId = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
    private let candidatureId = "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"
    private let rpc = "/rest/v1/rpc/fn_confirmer_action_planning_v1"
    private let creneaux = [CreneauConfirme(debut: "2026-12-01T19:00:00Z", fin: "2026-12-02T07:00:00Z")]

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func accepter(choix: String? = "SALARIE") async throws -> CandidatureOutcome {
        try await SupabaseCandidatureGateway(client: TestClient.make())
            .confirmer(action: .urgence, missionId: missionId, creneaux: creneaux, message: nil, choixContrat: choix,
                       candidatureId: nil, context: TestClient.context)
    }

    private func reponse(_ json: String) { registry.add("POST", rpc, respond: .json(200, json)) }

    private func candidatureJSON(_ statut: String) -> String {
        #"[{"id":"\#(candidatureId)","statut":"\#(statut)","message":"Acceptation rapide via pool urgence","type_contrat_choisi":"SALARIE","cree_le":"2026-11-18T00:00:00+00:00","mission_id":"\#(missionId)"}]"#
    }

    private func erreur(_ operation: () async throws -> Void) async -> JoleneError? {
        do {
            try await operation()
            return nil
        } catch let error as JoleneError {
            return error
        } catch {
            XCTFail("type d'erreur inattendu : \(error)")
            return nil
        }
    }

    func testSuccesReluEnAttenteDeValidationEtablissement() async throws {
        reponse(#"{"success":true,"candidature_id":"\#(candidatureId)","choix_contrat":"SALARIE","profession_requise":"IDE","message":"Acceptation enregistrée. En attente de validation par l'établissement."}"#)
        registry.add("GET", "/rest/v1/candidatures", respond: .json(200, candidatureJSON("EN_ATTENTE_VALIDATION_ETAB")))
        let issue = try await accepter()
        XCTAssertEqual(issue, .confirmed(candidatureId: candidatureId, contratId: nil))
        let envoye = try XCTUnwrap(registry.requests(to: rpc).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(envoye["p_action"] as? String, "URGENCE")
        XCTAssertTrue(envoye["p_choix_contrat"] is NSNull, "null comme le web : la RPC déléguée l'ignore")
        XCTAssertTrue(envoye["p_message"] is NSNull)
        XCTAssertEqual((envoye["p_creneaux_confirmes"] as? [[String: String]])?.count, 1, "planning exact affiché")
        XCTAssertEqual(registry.requests(to: "/rest/v1/candidatures").first?.query("id"), "eq.\(candidatureId)")
        XCTAssertTrue(registry.requests(to: "/rest/v1/rpc/fn_ecrire_audit_safe").isEmpty)
    }

    func testRelectureQuiNeMontrePasLaValidationEnAttenteEstUneErreur() async throws {
        for relue in [candidatureJSON("EN_ATTENTE"), "[]"] {
            registry.reset()
            reponse(#"{"success":true,"candidature_id":"\#(candidatureId)"}"#)
            registry.add("GET", "/rest/v1/candidatures", respond: .json(200, relue))
            let refus = await erreur { _ = try await self.accepter() }
            XCTAssertEqual(refus, JoleneError(.contract, SupabaseCandidatureGateway.relectureMessage))
            XCTAssertEqual(registry.requests(to: rpc).count, 1, "aucun renvoi")
        }
    }

    func testRefusVerbatimDontDocumentsManquants() async throws {
        let cas: [(String, String?)] = [
            ("Mission urgente non disponible", nil),
            ("Profession ou spécialité incompatible", nil),
            ("Accès refusé", nil),
            ("Vous avez déjà candidaté à cette mission", nil),
            ("Vos documents ne sont pas validés pour cette mission salarie", "SALARIE"),
        ]
        for (message, documents) in cas {
            registry.reset()
            let suffixe = documents.map { #","documents_requis_pour":"\#($0)""# } ?? ""
            reponse(#"{"success":false,"error":"\#(message)"\#(suffixe)}"#)
            let issue = try await accepter()
            XCTAssertEqual(issue, .refusee(code: nil, message: message, documentsRequisPour: documents))
            XCTAssertTrue(registry.requests(to: "/rest/v1/candidatures").isEmpty, "aucune relecture d'un refus")
        }
    }

    func testChoixRequisRelayeJamaisRejoue() async throws {
        reponse(#"{"success":false,"choix_requis":true,"error":"Choisissez votre mode de contrat.","options":[{"value":"SALARIE","label":"Salarié (CDD / bulletin de paie)"},{"value":"LIBERAL","label":"Libéral (note d'honoraires)"}]}"#)
        let issue = try await accepter(choix: nil)
        guard case .choixRequis(let options) = issue else { return XCTFail("choix requis attendu, obtenu \(issue)") }
        XCTAssertEqual(options.map(\.value), ["SALARIE", "LIBERAL"])
        XCTAssertEqual(registry.requests(to: rpc).count, 1, "jamais rejoué avec un choix")
    }

    func testPlanningVideJamaisEnvoye() async {
        let refus = await erreur {
            _ = try await SupabaseCandidatureGateway(client: TestClient.make())
                .confirmer(action: .urgence, missionId: self.missionId, creneaux: [], message: nil, choixContrat: nil,
                           candidatureId: nil, context: TestClient.context)
        }
        XCTAssertEqual(refus?.message, SupabaseCandidatureGateway.planningRequisMessage)
        XCTAssertTrue(registry.requests.isEmpty)
    }
}
