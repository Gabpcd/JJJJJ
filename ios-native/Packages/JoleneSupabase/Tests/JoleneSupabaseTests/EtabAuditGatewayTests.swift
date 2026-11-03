import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Audit de consultation établissement (lot 5 T1, D19) : `fn_ecrire_audit_safe` comme
/// `DashboardEtablissement.tsx` l.421-425, best-effort (contrat du lot 1), uuid nul ou invalide et
/// contexte incohérent refusés avant tout appel réseau.
final class EtabAuditGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let chemin = "/rest/v1/rpc/fn_ecrire_audit_safe"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseEtabAuditGateway { SupabaseEtabAuditGateway(client: TestClient.make()) }

    private func contexte(userId: String = TestClient.userId, etablissementId: String = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b",
                          role: RoleEtab = .rh) -> EtablissementReadContext {
        EtablissementReadContext(userId: userId, etablissementId: etablissementId, roleEtab: role,
                                 permissions: PermissionsEtab(accordees: [.lecture]), epoch: 2)
    }

    private func echec(_ context: EtablissementReadContext, file: StaticString = #filePath, line: UInt = #line) async -> JoleneError? {
        do {
            _ = try await gateway().consultation(page: .tableauDeBord, context: context)
            XCTFail("attendu : refus avant réseau", file: file, line: line)
            return nil
        } catch let error as JoleneError {
            return error
        } catch {
            XCTFail("type d'erreur inattendu : \(error)", file: file, line: line)
            return nil
        }
    }

    func testParametresCommeLeWeb() async throws {
        registry.add("POST", chemin, respond: .json(200, #"{"success":true,"id":"0a0a0a0a-1b1b-4c2c-8d3d-4e4e4e4e4e4e"}"#))
        let resultat = try await gateway().consultation(page: .tableauDeBord, context: contexte(userId: TestClient.userId.uppercased()))
        XCTAssertEqual(resultat, .enregistre)
        let requete = try XCTUnwrap(registry.requests(to: chemin).first)
        let corps = try XCTUnwrap(requete.bodyJSON as? NSDictionary)
        XCTAssertEqual(corps, [
            "p_acteur_id": TestClient.userId,
            "p_type_acteur": "ADMIN_ETABLISSEMENT",
            "p_action": "DONNEES_PERSO_CONSULTATION",
            "p_type_ressource": "etablissement",
            "p_id_ressource": TestClient.userId,
            "p_details": ["page": "dashboard_etablissement"],
            "p_navigateur": "jolene-ios/2.0.0",
        ] as NSDictionary)
        XCTAssertEqual(registry.requests.count, 1)
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testUuidNulOuInvalideRefuseAvantReseau() async {
        for userId in ["00000000-0000-0000-0000-000000000000", "demo-etablissement", "   "] {
            let erreur = await echec(contexte(userId: userId))
            XCTAssertNotNil(erreur, userId)
            XCTAssertTrue(erreur?.kind == .contract || erreur?.kind == .unauthorized, userId)
        }
        let nul = await echec(contexte(userId: "00000000-0000-0000-0000-000000000000"))
        XCTAssertEqual(nul, JoleneError(.contract, SupabaseAuditGateway.ressourceInvalideMessage))
        XCTAssertTrue(registry.requests.isEmpty, "aucun appel réseau")
    }

    func testContexteIncoherentRefuseAvantReseau() async {
        let sansEtablissement = await echec(contexte(etablissementId: ""))
        XCTAssertEqual(sansEtablissement, JoleneError(.unauthorized, EtablissementReadContext.contexteInvalideMessage))
        let roleInconnu = await echec(contexte(role: .inconnu("ADMIN_PLATEFORME")))
        XCTAssertEqual(roleInconnu?.kind, .unauthorized)
        XCTAssertTrue(registry.requests.isEmpty)
    }

    func testBestEffortCommeLeLot1() async throws {
        registry.add("POST", chemin, respond: .json(200, #"{"success":false,"error":"Non authentifié"}"#))
        let refuse = try await gateway().consultation(page: .tableauDeBord, context: contexte())
        XCTAssertEqual(refuse, .nonEnregistre, "un refus serveur n'est jamais une erreur utilisateur")
        registry.reset()
        registry.add("POST", chemin, respond: .json(200, "null"))
        do {
            _ = try await gateway().consultation(page: .tableauDeBord, context: contexte())
            XCTFail("une réponse sans success n'est ni un succès ni un refus")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .contract)
        }
        XCTAssertEqual(registry.requests(to: chemin).count, 1, "aucun renvoi automatique")
    }
}
