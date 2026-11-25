import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Exclusions sur Supabase (L4-T11) — fiches `fn_mes_exclusions_recues`, `fn_retirer_exclusion`, `fn_exclure_utilisateur`
/// de `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md` : envoyées par PostgREST `exclusions` filtrées sur la session, noms par
/// `fn_etablissements_safe` ; retrait par l'`exclu_id` ; exclusion `p_type = 'SOIGNANT'`, motif vide → null ; refus verbatim ;
/// chaque mutation acceptée est suivie de la relecture des exclusions envoyées.
final class SupabaseExclusionsGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let recuesRPC = "/rest/v1/rpc/fn_mes_exclusions_recues"
    private let retirerRPC = "/rest/v1/rpc/fn_retirer_exclusion"
    private let exclureRPC = "/rest/v1/rpc/fn_exclure_utilisateur"
    private let nomsRPC = "/rest/v1/rpc/fn_etablissements_safe"
    private let etab = "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseExclusionsGateway { SupabaseExclusionsGateway(client: TestClient.make()) }

    private func envoyees(_ json: String? = nil) {
        registry.add("GET", "/rest/v1/exclusions", respond: .json(200, json ?? #"[{"id":"x-1","exclu_id":"\#(etab)","exclu_par":"u","motif":"Retards","type_exclu_par":"SOIGNANT","cree_le":"2026-11-01T10:00:00.123+00:00"}]"#))
        registry.add("POST", nomsRPC, respond: .json(200, #"[{"id":"\#(etab)","nom":"Clinique fictive"}]"#))
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

    func testEnvoyeesFiltreesSurLaSessionAvecNomsSurs() async throws {
        envoyees()
        let liste = try await gateway().envoyees(context: TestClient.context)
        XCTAssertEqual(liste.map(\.excluId), [etab])
        XCTAssertEqual(liste.first?.etablissementNom, "Clinique fictive")
        XCTAssertEqual(liste.first?.motif, "Retards")
        XCTAssertNotNil(liste.first?.creeLe, "horodatage PostgREST à fraction lu")
        let requete = try XCTUnwrap(registry.requests(to: "/rest/v1/exclusions").first)
        XCTAssertEqual(requete.query("exclu_par"), "eq.\(TestClient.context.userId)")
        XCTAssertEqual(requete.query("order"), "cree_le.desc.nullsfirst", "ordre par défaut de PostgreSQL en DESC, comme le web")
        XCTAssertEqual(requete.query("select"), "id,exclu_id,exclu_par,motif,type_exclu_par,cree_le")
    }

    func testNomsIndisponiblesLaissentLIdentifiant() async throws {
        registry.add("GET", "/rest/v1/exclusions", respond: .json(200, #"[{"id":"x-1","exclu_id":"\#(etab)","cree_le":"2026-11-01T10:00:00+00:00"}]"#))
        registry.add("POST", nomsRPC, respond: .json(500, #"{"message":"boom"}"#))
        let liste = try await gateway().envoyees(context: TestClient.context)
        XCTAssertNil(liste.first?.etablissementNom, "l'écran affiche alors l'identifiant, comme le web")
    }

    func testRecuesTableauOuContrat() async throws {
        registry.add("POST", recuesRPC, respond: .json(200, #"[{"id":"r-1","exclu_par":"e-1","type_exclu_par":"ETABLISSEMENT","motif":null,"etablissement_nom":"Clinique B","cree_le":"2026-10-01T00:00:00+00:00"}]"#))
        let recues = try await gateway().recues(context: TestClient.context)
        XCTAssertEqual(recues.map(\.id), ["r-1"])
        XCTAssertEqual(recues.first?.etablissementNom, "Clinique B")

        registry.reset()
        registry.add("POST", recuesRPC, respond: .json(200, #"{"rows":[]}"#))
        let forme = await erreur { _ = try await self.gateway().recues(context: TestClient.context) }
        XCTAssertEqual(forme?.kind, .contract, "jamais une liste vide plausible")
    }

    func testRetraitParExcluIdPuisRelecture() async throws {
        registry.add("POST", retirerRPC, respond: .json(200, #"{"success":true}"#))
        envoyees("[]")
        let issue = try await gateway().retirer(excluId: etab, context: TestClient.context)
        XCTAssertEqual(issue, .relues([]))
        let params = try XCTUnwrap(registry.requests(to: retirerRPC).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(params as? [String: String], ["p_exclu_id": etab], "l'établissement exclu, jamais l'id de ligne")
        XCTAssertEqual(registry.requests(to: "/rest/v1/exclusions").count, 1, "relecture après le retrait")
    }

    func testExclusionTypeSoignantMotifVideNulPuisRelecture() async throws {
        registry.add("POST", exclureRPC, respond: .json(200, #"{"success":true}"#))
        envoyees()
        let issue = try await gateway().exclure(etablissementId: etab, motif: "   ", context: TestClient.context)
        guard case .relues(let liste) = issue else { return XCTFail("relecture attendue, obtenu \(issue)") }
        XCTAssertEqual(liste.map(\.excluId), [etab])
        let params = try XCTUnwrap(registry.requests(to: exclureRPC).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(params["p_exclu_id"] as? String, etab)
        XCTAssertEqual(params["p_type"] as? String, "SOIGNANT", "type de l'auteur")
        XCTAssertTrue(params["p_motif"] is NSNull, "motif.trim() || null")
    }

    func testRefusVerbatimEtSession() async throws {
        for message in ["Exclusion déjà existante", "Impossible de s'exclure soi-même", "Type invalide"] {
            registry.reset()
            registry.add("POST", exclureRPC, respond: .json(200, #"{"success":false,"error":"\#(message)"}"#))
            let issue = try await gateway().exclure(etablissementId: etab, motif: "x", context: TestClient.context)
            XCTAssertEqual(issue, .refusee(message: message))
            XCTAssertTrue(registry.requests(to: "/rest/v1/exclusions").isEmpty, "aucune relecture d'un refus")
        }
        registry.reset()
        registry.add("POST", retirerRPC, respond: .json(200, #"{"success":false,"error":"Exclusion introuvable"}"#))
        let introuvable = try await gateway().retirer(excluId: etab, context: TestClient.context)
        XCTAssertEqual(introuvable, .refusee(message: "Exclusion introuvable"))
        registry.reset()
        registry.add("POST", retirerRPC, respond: .json(200, #"{"success":false,"error":"Non authentifié"}"#))
        let session = await erreur { _ = try await self.gateway().retirer(excluId: self.etab, context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized)
    }
}
