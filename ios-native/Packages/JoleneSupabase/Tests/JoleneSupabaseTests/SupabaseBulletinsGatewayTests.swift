import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Copies officielles des bulletins sur Supabase (L4-T10) — fiches `fn_lister_copies_bulletins`, edge `copies-bulletins`
/// et `fn_signaler_copie_bulletin` de `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md`, tests du plan §3 T10 :
/// `COPIE_ACCES_REFUSE` → refus métier (jamais « session expirée ») ; SHA-256 faux → refus d'intégrité ;
/// `application/json` en 200 → refus ; `RETIREE` non téléchargeable (aucune requête) ; 410 `COPIE_RETIREE` → copie
/// retirée ; `DESTINATAIRE` → relecture `RETIREE` ; une seule requête par appel, aucun renvoi.
final class SupabaseBulletinsGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let lister = "/rest/v1/rpc/fn_lister_copies_bulletins"
    private let signaler = "/rest/v1/rpc/fn_signaler_copie_bulletin"
    private let edge = "/functions/v1/copies-bulletins"
    private static let id = "c0b1e000-0000-4000-8000-000000000001"
    private static let pdf = Data("%PDF-1.4\n% copie de test\n%%EOF\n".utf8)

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func ligneJSON(statut: String = "PUBLIEE", signalee: Bool = false, sha256: String? = nil) -> String {
        """
        {"id":"\(Self.id)","etablissement_id":"e7ab0000-0000-4000-8000-000000000002","etablissement_nom":"Employeur de test",
         "soignant_id":"\(TestClient.userId)","soignant_nom":"Test","soignant_prenom":"Soignant",
         "periode_debut":"2026-10-01","periode_fin":"2026-10-31","statut":"\(statut)","version":1,
         "publie_le":"2026-10-31T09:30:00.123456+00:00","remplace_id":null,"motif_remplacement":null,
         "mission_ids":["a1551000-0000-4000-8000-000000000001"],"taille_octets":\(Self.pdf.count),
         "sha256":"\(sha256 ?? BulletinsTelechargement.sha256(Self.pdf))","signalee":\(signalee)}
        """
    }

    private func copie(statut: StatutCopieBulletin = .publiee, sha256: String? = nil) -> CopieBulletin {
        CopieBulletin(id: Self.id, etablissementId: "e7ab0000-0000-4000-8000-000000000002", employeurNom: "Employeur de test",
                      periodeDebut: "2026-10-01", periodeFin: "2026-10-31", statut: statut, version: 1,
                      publieLe: "2026-10-31T09:30:00.123456+00:00", motifRemplacement: nil, tailleOctets: Self.pdf.count,
                      sha256: sha256 ?? BulletinsTelechargement.sha256(Self.pdf),
                      missionIds: ["a1551000-0000-4000-8000-000000000001"], signalee: false)
    }

    private func exception(_ sqlstate: String, _ message: String) -> String {
        #"{"code":"\#(sqlstate)","message":"\#(message)","details":null,"hint":null}"#
    }

    private func connecte() async throws -> SupabaseClient {
        let client = TestClient.make()
        registry.add("POST", "/auth/v1/token", respond: .json(200, TestClient.sessionJSON()))
        _ = try await SupabaseAuthGateway(client: client).signIn(email: TestClient.email, password: "motdepasse-test")
        return client
    }

    private func pdf(_ status: Int = 200, type: String = "application/pdf", corps: Data = SupabaseBulletinsGatewayTests.pdf) -> StubResponse {
        StubResponse(status: status, headers: ["Content-Type": type, "Cache-Control": "no-store"], body: corps, failure: nil)
    }

    private func erreur(_ operation: () async throws -> Void) async -> Error? {
        do {
            try await operation()
            return nil
        } catch {
            return error
        }
    }

    // MARK: - Liste

    func testListeDecodeeStrictementParametresNuls() async throws {
        registry.add("POST", lister, respond: .json(200, "[\(ligneJSON())]"))
        let copies = try await SupabaseBulletinsGateway(client: TestClient.make()).copies(context: TestClient.context)
        XCTAssertEqual(copies, [copie()])
        let corps = try XCTUnwrap(registry.requests(to: lister).first?.bodyJSON as? [String: Any])
        XCTAssertTrue(corps["p_etablissement_id"] is NSNull)
        XCTAssertTrue(corps["p_mission_id"] is NSNull)
        XCTAssertEqual(registry.requests.count, 1)
    }

    func testCopieAccesRefuseEstUnRefusMetier() async {
        registry.add("POST", lister, respond: .json(403, exception("42501", "COPIE_ACCES_REFUSE")))
        let e = await erreur { _ = try await SupabaseBulletinsGateway(client: TestClient.make()).copies(context: TestClient.context) }
        let jolene = e as? JoleneError
        XCTAssertNotEqual(jolene?.kind, .unauthorized, "42501 COPIE_ACCES_REFUSE n'est pas « session expirée »")
        XCTAssertEqual(jolene?.message, "Impossible de charger les copies des bulletins. Réessayez.")
        XCTAssertEqual(registry.requests(to: lister).count, 1, "aucun renvoi")
    }

    func testUneLigneInvalideRefuseLaListe() async {
        registry.add("POST", lister, respond: .json(200, "[\(ligneJSON(sha256: "ABC"))]"))
        let e = await erreur { _ = try await SupabaseBulletinsGateway(client: TestClient.make()).copies(context: TestClient.context) }
        XCTAssertEqual((e as? JoleneError)?.message, "La liste des copies ne peut pas être vérifiée. Réessayez.")
    }

    // MARK: - Téléchargement

    func testTelechargementVerifie() async throws {
        let client = try await connecte()
        let jeton = try XCTUnwrap(client.auth.currentSession?.accessToken)
        registry.add("POST", edge, respond: pdf())
        let recu = try await SupabaseBulletinsGateway(client: client).telecharger(copie: copie(), context: TestClient.context)
        XCTAssertEqual(recu.donnees, Self.pdf)
        XCTAssertEqual(recu.sha256, BulletinsTelechargement.sha256(Self.pdf))
        let requete = try XCTUnwrap(registry.requests(to: edge).first)
        XCTAssertEqual(registry.requests(to: edge).count, 1)
        XCTAssertEqual(requete.method, "POST")
        XCTAssertEqual(requete.header("Authorization"), "Bearer \(jeton)")
        XCTAssertEqual(requete.header("Cache-Control"), "no-store")
        let corps = try XCTUnwrap(requete.bodyJSON as? [String: String])
        XCTAssertEqual(corps, ["action": "telecharger", "copie_id": Self.id], "corps strict de l'edge")
    }

    func testEmpreinteFausseRefusee() async throws {
        let client = try await connecte()
        registry.add("POST", edge, respond: pdf())
        let e = await erreur {
            _ = try await SupabaseBulletinsGateway(client: client)
                .telecharger(copie: self.copie(sha256: String(repeating: "f", count: 64)), context: TestClient.context)
        }
        XCTAssertEqual(e as? RefusCopieBulletin, .integrite)
    }

    func testJSONEn200Refuse() async throws {
        let client = try await connecte()
        registry.add("POST", edge, respond: .json(200, #"{"ok":true}"#))
        let e = await erreur {
            _ = try await SupabaseBulletinsGateway(client: client).telecharger(copie: self.copie(), context: TestClient.context)
        }
        XCTAssertEqual(e as? RefusCopieBulletin, .indisponible)
    }

    func testCopieRetireeJamaisDemandee() async throws {
        let client = try await connecte()
        let e = await erreur {
            _ = try await SupabaseBulletinsGateway(client: client)
                .telecharger(copie: self.copie(statut: .retiree), context: TestClient.context)
        }
        XCTAssertEqual(e as? RefusCopieBulletin, .retiree)
        XCTAssertTrue(registry.requests(to: edge).isEmpty, "aucune requête pour une copie RETIREE")
    }

    func test410CopieRetiree() async throws {
        let client = try await connecte()
        registry.add("POST", edge, respond: .json(410, #"{"error":"COPIE_RETIREE"}"#))
        let e = await erreur {
            _ = try await SupabaseBulletinsGateway(client: client).telecharger(copie: self.copie(), context: TestClient.context)
        }
        XCTAssertEqual(e as? RefusCopieBulletin, .retiree)
        XCTAssertEqual((e as? RefusCopieBulletin)?.message, "Cette copie a été retirée. Son PDF n’est plus accessible.")
    }

    func testAutresRefusDeLEdge() async throws {
        for (statut, code) in [(403, "COPIE_ACCES_REFUSE"), (409, "COPIE_INTEGRITE_INVALIDE"), (422, "COPIE_PDF_INVALIDE"),
                               (503, "COPIE_SERVICE_INDISPONIBLE"), (410, "AUTRE")] {
            registry.reset()
            let client = try await connecte()
            registry.add("POST", edge, respond: .json(statut, #"{"error":"\#(code)"}"#))
            let e = await erreur {
                _ = try await SupabaseBulletinsGateway(client: client).telecharger(copie: self.copie(), context: TestClient.context)
            }
            XCTAssertEqual(e as? RefusCopieBulletin, .indisponible, code)
            XCTAssertFalse((e as? RefusCopieBulletin)?.message.contains("COPIE") ?? true, "code machine jamais affiché")
        }
    }

    func test401SessionExpiree() async throws {
        let client = try await connecte()
        registry.add("POST", edge, respond: .json(401, #"{"error":"AUTHENTIFICATION_REQUISE"}"#))
        let e = await erreur {
            _ = try await SupabaseBulletinsGateway(client: client).telecharger(copie: self.copie(), context: TestClient.context)
        }
        XCTAssertEqual((e as? JoleneError)?.kind, .unauthorized)
    }

    // MARK: - Signalement

    func testSignalementDestinataireRelitLaCopieRetiree() async throws {
        registry.add("POST", signaler, respond: .json(200, #"{"ok":true}"#))
        registry.add("POST", lister, respond: .json(200, "[\(ligneJSON(statut: "RETIREE", signalee: true))]"))
        let copies = try await SupabaseBulletinsGateway(client: TestClient.make())
            .signaler(copieId: Self.id, motif: .destinataire, context: TestClient.context)
        XCTAssertEqual(copies.first?.statut, .retiree)
        XCTAssertEqual(copies.first?.signalee, true)
        let corps = try XCTUnwrap(registry.requests(to: signaler).first?.bodyJSON as? [String: String])
        XCTAssertEqual(corps, ["p_copie_id": Self.id, "p_motif": "DESTINATAIRE"])
        XCTAssertEqual(registry.requests(to: signaler).count, 1)
        XCTAssertEqual(registry.requests(to: lister).count, 1, "relecture")
    }

    func testSignalementRefuseTexteDuWeb() async {
        for (sqlstate, message) in [("42501", "COPIE_ACCES_REFUSE"), ("22023", "COPIE_MOTIF_INVALIDE")] {
            registry.reset()
            registry.add("POST", signaler, respond: .json(400, exception(sqlstate, message)))
            let e = await erreur {
                _ = try await SupabaseBulletinsGateway(client: TestClient.make())
                    .signaler(copieId: Self.id, motif: .contenu, context: TestClient.context)
            }
            let jolene = e as? JoleneError
            XCTAssertNotEqual(jolene?.kind, .unauthorized, message)
            XCTAssertFalse(jolene?.message.contains("COPIE") ?? true, "code machine jamais affiché")
            XCTAssertTrue(registry.requests(to: lister).isEmpty, "aucune relecture annoncée comme succès")
        }
    }

    func testSignalementSansOkRefuse() async {
        registry.add("POST", signaler, respond: .json(200, #"{}"#))
        let e = await erreur {
            _ = try await SupabaseBulletinsGateway(client: TestClient.make())
                .signaler(copieId: Self.id, motif: .contenu, context: TestClient.context)
        }
        XCTAssertEqual((e as? JoleneError)?.message, "Le signalement n’a pas été confirmé. Réessayez.")
    }
}
