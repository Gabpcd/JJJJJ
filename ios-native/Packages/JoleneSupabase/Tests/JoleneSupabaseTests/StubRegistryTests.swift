import Foundation
import XCTest

/// Contrat du transport de test (`StubRegistry.resolve`) : une requête dont la tâche était déjà annulée à son
/// arrivée n'est ni enregistrée ni servie, elle n'est jamais « partie ». Une requête vivante est toujours
/// enregistrée, avec ou sans stub.
final class StubRegistryTests: XCTestCase {
    private let registry = StubRegistry.shared

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func requete(_ chemin: String) -> RecordedRequest {
        RecordedRequest(URLRequest(url: URL(string: "https://exemple.test\(chemin)")!))
    }

    func testRequeteAnnuleeNiEnregistreeNiServie() {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[]"))
        guard case .annulee = registry.resolve(requete("/rest/v1/missions"), annulee: { true }) else {
            return XCTFail("attendu : requête annulée ignorée")
        }
        XCTAssertTrue(registry.requests.isEmpty)
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testRequeteVivanteEnregistreeAvecOuSansStub() {
        registry.add("GET", "/rest/v1/missions", respond: .json(200, "[]"))
        guard case .reponse(let reponse) = registry.resolve(requete("/rest/v1/missions"), annulee: { false }) else {
            return XCTFail("attendu : stub servi")
        }
        XCTAssertEqual(reponse.status, 200)
        guard case .sansStub = registry.resolve(requete("/rest/v1/inconnu")) else {
            return XCTFail("attendu : requête sans stub")
        }
        XCTAssertEqual(registry.requests.map(\.path), ["/rest/v1/missions", "/rest/v1/inconnu"])
        XCTAssertEqual(registry.unmatched.map(\.path), ["/rest/v1/inconnu"])
    }
}
