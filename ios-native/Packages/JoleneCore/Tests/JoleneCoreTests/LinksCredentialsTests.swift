import XCTest
@testable import JoleneCore

/// Port 1:1 de `describe('extraireRecoveryCredentials')` dans `src/lib/nativeLinks.test.ts`,
/// plus la lecture signup de `src/pages/ConfirmationInscription.tsx`.
final class LinksCredentialsTests: XCTestCase {
    func testExtraitLeFluxImplicitDepuisLeFragment() {
        XCTAssertEqual(
            AuthCallbackCredentials.recovery(search: "", fragment: "#access_token=access&refresh_token=refresh&type=recovery"),
            .implicit(accessToken: "access", refreshToken: "refresh"))
    }

    func testExtraitPkceEtTokenHashDepuisLaQueryString() {
        XCTAssertEqual(AuthCallbackCredentials.recovery(search: "?code=pkce", fragment: ""), .pkce(code: "pkce"))
        XCTAssertEqual(AuthCallbackCredentials.recovery(search: "?code=pkce&type=recovery", fragment: ""), .pkce(code: "pkce"))
        XCTAssertEqual(AuthCallbackCredentials.recovery(search: "?token_hash=hash&type=recovery", fragment: ""),
                       .tokenHash(tokenHash: "hash", otpType: "recovery"))
    }

    func testRefuseLesIdentifiantsDeSessionNonExplicitementRecovery() {
        XCTAssertNil(AuthCallbackCredentials.recovery(search: "", fragment: "#access_token=access&refresh_token=refresh"))
        XCTAssertNil(AuthCallbackCredentials.recovery(search: "?token_hash=hash", fragment: ""))
        XCTAssertNil(AuthCallbackCredentials.recovery(search: "?code=oauth&type=signup", fragment: ""))
    }

    // Cas supplémentaires.

    func testPrefixesOptionnelsEtDecodageURLSearchParams() {
        XCTAssertEqual(AuthCallbackCredentials.recovery(search: "code=a%2Bb+c", fragment: "type=recovery"), .pkce(code: "a+b c"))
        XCTAssertEqual(AuthCallbackCredentials.recovery(search: "?code=premier&code=second", fragment: ""), .pkce(code: "premier"))
        XCTAssertNil(AuthCallbackCredentials.recovery(search: "", fragment: ""))
        XCTAssertNil(AuthCallbackCredentials.recovery(search: "?code=", fragment: ""))
    }

    func testVarianteSurLienNormalise() {
        XCTAssertEqual(AuthCallbackCredentials.recovery(link: "/reset-password?code=abc#type=recovery"), .pkce(code: "abc"))
        XCTAssertEqual(AuthCallbackCredentials.recovery(link: "/reset-password#access_token=a&refresh_token=r&type=recovery"),
                       .implicit(accessToken: "a", refreshToken: "r"))
    }

    func testSignupAccepteLesTroisFormatsAvecTypeSignupOuEmail() {
        XCTAssertEqual(AuthCallbackCredentials.signup(search: "?code=pkce", fragment: ""), .pkce(code: "pkce"))
        XCTAssertEqual(AuthCallbackCredentials.signup(search: "?token_hash=h&type=signup", fragment: ""),
                       .tokenHash(tokenHash: "h", otpType: "signup"))
        XCTAssertEqual(AuthCallbackCredentials.signup(search: "?token_hash=h&type=email", fragment: ""),
                       .tokenHash(tokenHash: "h", otpType: "email"))
        XCTAssertEqual(AuthCallbackCredentials.signup(search: "", fragment: "#access_token=a&refresh_token=r&type=signup"),
                       .implicit(accessToken: "a", refreshToken: "r"))
    }

    func testSignupRefuseTypeEtrangerImplicitSansTypeEtTokenHashSansType() {
        XCTAssertNil(AuthCallbackCredentials.signup(search: "?code=pkce&type=recovery", fragment: ""))
        XCTAssertNil(AuthCallbackCredentials.signup(search: "", fragment: "#access_token=a&refresh_token=r"))
        XCTAssertNil(AuthCallbackCredentials.signup(search: "?token_hash=h", fragment: ""))
        XCTAssertNil(AuthCallbackCredentials.signup(search: "", fragment: ""))
    }

    func testDescriptionNeRevelJamaisLesValeurs() {
        let secrets = ["access-secret", "refresh-secret", "code-secret", "hash-secret"]
        let cases: [AuthCallbackCredentials] = [
            .implicit(accessToken: "access-secret", refreshToken: "refresh-secret"),
            .pkce(code: "code-secret"),
            .tokenHash(tokenHash: "hash-secret", otpType: "recovery"),
        ]
        for credentials in cases {
            let rendered = "\(credentials)" + String(reflecting: credentials)
            for secret in secrets { XCTAssertFalse(rendered.contains(secret), rendered) }
            XCTAssertTrue(rendered.contains("masqu"), rendered)
        }
    }
}
