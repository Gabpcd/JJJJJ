import Foundation
import JoleneCore
import XCTest
@testable import JoleneSupabase

/// Géocodage inverse (lot 3, T10, D15 ; `src/lib/geocodage.ts` l.16-34) : une requête GET vers l'API Adresse, en-tête
/// `Accept` seul (aucun jeton, aucune clé, aucun identifiant), réponse lue comme le web ; tout échec rend nil.
final class ApiAdresseGeocodageTests: XCTestCase {
    private let registry = StubRegistry.shared

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func geocodage() -> ApiAdresseGeocodage {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return ApiAdresseGeocodage(session: URLSession(configuration: configuration))
    }

    func testRequeteSansIdentifiantEtReponseLueCommeLeWeb() async throws {
        registry.add("GET", "/reverse", respond: .json(200, #"""
        {"type":"FeatureCollection","features":[{"type":"Feature","properties":{"label":"Place Bellecour 69002 Lyon","name":"Place Bellecour","postcode":"69002","city":"Lyon"}}]}
        """#))
        let adresse = try await geocodage().adresse(lat: 45.7578, lng: 4.832)
        XCTAssertEqual(adresse, AdresseGeocodee(libelle: "Place Bellecour 69002 Lyon", ville: "Lyon", codePostal: "69002"))
        let requete = try XCTUnwrap(registry.requests.first)
        XCTAssertEqual(requete.url.host, "api-adresse.data.gouv.fr")
        XCTAssertEqual(requete.method, "GET")
        XCTAssertEqual(requete.query("lon"), "4.832")
        XCTAssertEqual(requete.query("lat"), "45.7578")
        XCTAssertEqual(requete.queryItems.count, 2, "seules les coordonnées partent")
        XCTAssertEqual(requete.header("Accept"), "application/json")
        for interdit in ["Authorization", "apikey", "X-Client-Info", "Cookie"] {
            XCTAssertNil(requete.header(interdit), "\(interdit) jamais envoyé au service tiers")
        }
        XCTAssertNil(requete.body)
        XCTAssertEqual(registry.requests.count, 1)
        XCTAssertTrue(registry.unmatched.isEmpty, "requête servie par le stub (chemin `/reverse/`, normalisé `/reverse`)")
    }

    func testEchecsRendentNil() async throws {
        registry.add("GET", "/reverse", respond: .json(503, "{}"))
        let indisponible = try await geocodage().adresse(lat: 45.7, lng: 4.8)
        XCTAssertNil(indisponible, "`if (!res.ok) return null`")
        registry.reset()
        registry.add("GET", "/reverse", respond: .json(200, #"{"features":[]}"#))
        let introuvable = try await geocodage().adresse(lat: 45.7, lng: 4.8)
        XCTAssertNil(introuvable)
        XCTAssertTrue(registry.unmatched.isEmpty)
        registry.reset()
        registry.add("GET", "/reverse", respond: .networkFailure())
        let horsLigne = try await geocodage().adresse(lat: 45.7, lng: 4.8)
        XCTAssertNil(horsLigne, "réseau KO : nil, jamais une erreur")
        registry.reset()
        let nonFini = try await geocodage().adresse(lat: .infinity, lng: 4.8)
        XCTAssertNil(nonFini)
        XCTAssertTrue(registry.requests.isEmpty, "coordonnée non finie : aucune requête")
    }

    func testSessionParDefautEphemereSansCookie() {
        let configuration = ApiAdresseGeocodage.sessionParDefaut.configuration
        XCTAssertEqual(configuration.httpCookieAcceptPolicy, .never)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 10, "best-effort borné")
    }
}
