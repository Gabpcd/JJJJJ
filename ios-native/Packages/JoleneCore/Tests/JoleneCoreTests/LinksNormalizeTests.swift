import XCTest
@testable import JoleneCore

/// Port 1:1 de `describe('normaliserLienJolene')` dans `src/lib/nativeLinks.test.ts`.
final class LinksNormalizeTests: XCTestCase {
    func testConserveQueryEtHashPourUnRecoveryUniversalLink() {
        XCTAssertEqual(JoleneLink.normalize("https://jolene.app/reset-password?code=abc#type=recovery"),
                       "/reset-password?code=abc#type=recovery")
    }

    func testAccepteLesLiensInvitationPscEtMission() {
        XCTAssertEqual(JoleneLink.normalize("https://jolene.app/etab/invitation/token?source=email"),
                       "/etab/invitation/token?source=email")
        XCTAssertEqual(JoleneLink.normalize("https://www.jolene.app/auth/psc/callback?status=success&token_hash=x"),
                       "/auth/psc/callback?status=success&token_hash=x")
        XCTAssertEqual(JoleneLink.normalize("https://app.jolene.app/contrat/contrat-id"), "/contrat/contrat-id")
        XCTAssertEqual(JoleneLink.normalize("/soignant/missions/mission-id"), "/soignant/missions/mission-id")
    }

    func testRejetteLesOriginesPortsEtCheminsProtocolRelativeNonFiables() {
        XCTAssertNil(JoleneLink.normalize("https://evil.example/reset-password#access_token=x"))
        XCTAssertNil(JoleneLink.normalize("https://jolene.app:444/reset-password"))
        XCTAssertNil(JoleneLink.normalize("//evil.example/path"))
        XCTAssertNil(JoleneLink.normalize("/\\evil.example/path"))
        XCTAssertNil(JoleneLink.normalize("soignant/missions"))
        XCTAssertNil(JoleneLink.normalize("javascript:alert(1)"))
    }

    /// Côté web le test conserve `window.location.origin` ; dans l'app native la seule
    /// origine possible est `https://jolene.app` (branche `Capacitor.isNativePlatform()`).
    func testUrlCallbackPubliqueUtiliseOrigineCanonique() throws {
        XCTAssertEqual(try JoleneLink.publicCallbackURL(path: "/reset-password").absoluteString,
                       "https://jolene.app/reset-password")
        XCTAssertEqual(try JoleneLink.publicCallbackURL(path: "https://www.jolene.app/inscription/confirmer?x=1").absoluteString,
                       "https://jolene.app/inscription/confirmer?x=1")
        XCTAssertThrowsError(try JoleneLink.publicCallbackURL(path: "https://evil.example/reset-password")) { error in
            XCTAssertEqual((error as? JoleneError)?.kind, .contract)
        }
    }

    // Cas supplémentaires propres au port Swift (comportements de `new URL()` reproduits).

    func testHoteEtSchemaInsensiblesALaCasse() {
        XCTAssertEqual(JoleneLink.normalize("HTTPS://JOLENE.APP/connexion"), "/connexion")
    }

    func testPort443ExpliciteAccepteCommeEnJS() {
        XCTAssertEqual(JoleneLink.normalize("https://jolene.app:443/connexion"), "/connexion")
    }

    func testCheminVideDevientRacine() {
        XCTAssertEqual(JoleneLink.normalize("https://jolene.app"), "/")
        XCTAssertEqual(JoleneLink.normalize("https://jolene.app?x=1"), "/?x=1")
    }

    func testDoubleSlashInitialDansLeCheminRefuse() {
        XCTAssertNil(JoleneLink.normalize("https://jolene.app//evil.example/path"))
    }

    func testSegmentsPointResolusAvantRoutage() {
        XCTAssertEqual(JoleneLink.normalize("/soignant/../admin/litiges"), "/admin/litiges")
        XCTAssertEqual(JoleneLink.normalize("/soignant/./missions/"), "/soignant/missions/")
        XCTAssertEqual(JoleneLink.normalize("/soignant/missions/.."), "/soignant/")
        XCTAssertEqual(JoleneLink.normalize("/a/%2E%2E/b"), "/b")
    }

    func testChaineVideEtHttpRefuses() {
        XCTAssertNil(JoleneLink.normalize(""))
        XCTAssertNil(JoleneLink.normalize("http://jolene.app/connexion"))
        XCTAssertNil(JoleneLink.normalize("https://jolene.app.evil.example/connexion"))
    }

    func testSplitSepareCheminQueryFragment() {
        let parts = JoleneLink.split(link: "/reset-password?code=abc#type=recovery")
        XCTAssertEqual(parts.path, "/reset-password")
        XCTAssertEqual(parts.query, "code=abc")
        XCTAssertEqual(parts.fragment, "type=recovery")
        let simple = JoleneLink.split(link: "/connexion")
        XCTAssertEqual(simple.path, "/connexion")
        XCTAssertNil(simple.query)
        XCTAssertNil(simple.fragment)
    }
}
