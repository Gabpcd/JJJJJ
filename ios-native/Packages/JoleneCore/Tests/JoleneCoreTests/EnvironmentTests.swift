import XCTest
@testable import JoleneCore

/// Garde d'environnement (plan §4.1, critère de sortie lot 0, PORTE_LOT0 1.5) :
/// `load` (priorité argument > variable > Info.plist, mode inconnu refusé, démo sans
/// réseau, surcharges désactivables) et `validate` (clé secrète, JWT legacy, ref hors
/// allowlist, http).
final class EnvironmentTests: XCTestCase {
    private let infoProduction: [String: Any] = [
        "JoleneEnvironment": "production",
        "JoleneSupabaseURL": "https://flripxtsyegjshnhzjkz.supabase.co",
        "JoleneSupabasePublishableKey": "sb_publishable_prod_fictive",
    ]
    private let infoStaging: [String: Any] = [
        "JoleneEnvironment": "staging",
        "JoleneSupabaseURL": "https://mejpriaetwgtcstbgfid.supabase.co",
        "JoleneSupabasePublishableKey": "sb_publishable_staging_fictive",
    ]

    // MARK: load

    func testArgumentWinsOverEnvironmentAndInfoPlist() {
        let env = JoleneEnvironment.load(arguments: ["-JOLENE_MODE", "demo"], environment: ["JOLENE_MODE": "staging"], info: infoProduction)
        XCTAssertEqual(env.mode, .demo)
        XCTAssertNil(env.unknownModeRaw)
        XCTAssertNil(env.supabaseURL, "le mode démo ne porte ni URL ni clé")
        XCTAssertNil(env.publishableKey)
        XCTAssertNoThrow(try env.validate())
    }

    func testEnvironmentVariableWinsOverInfoPlist() {
        let env = JoleneEnvironment.load(arguments: [], environment: ["JOLENE_MODE": "staging"], info: infoProduction)
        XCTAssertEqual(env.mode, .staging)
        XCTAssertEqual(env.supabaseURL?.host, "flripxtsyegjshnhzjkz.supabase.co", "l'URL vient toujours de l'Info.plist")
        XCTAssertThrowsError(try env.validate(), "hôte production refusé pour le mode staging")
    }

    func testInfoPlistAloneSelectsProduction() throws {
        let env = JoleneEnvironment.load(arguments: [], environment: [:], info: infoProduction)
        XCTAssertEqual(env.mode, .production)
        XCTAssertEqual(env.publishableKey, "sb_publishable_prod_fictive")
        XCTAssertNoThrow(try env.validate())
    }

    func testModeIsCaseInsensitiveAndTrimmed() {
        XCTAssertEqual(JoleneEnvironment.load(arguments: ["-JOLENE_MODE", " Staging "], environment: [:], info: infoStaging).mode, .staging)
        XCTAssertEqual(JoleneEnvironment.load(arguments: [], environment: ["JOLENE_MODE": "DEMO"], info: infoStaging).mode, .demo)
    }

    func testUnknownModeIsRefusedInsteadOfFallingBackToProduction() {
        for raw in ["dev", "stagin", "prod", "Production "] where JoleneMode(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased()) == nil {
            let env = JoleneEnvironment.load(arguments: ["-JOLENE_MODE", raw], environment: [:], info: infoProduction)
            XCTAssertEqual(env.unknownModeRaw, raw.trimmingCharacters(in: .whitespaces), "la valeur brute « \(raw) » est conservée")
            XCTAssertNil(env.supabaseURL, "aucune URL de production n'est chargée pour un mode inconnu")
            XCTAssertNil(env.publishableKey, "aucune clé de production n'est chargée pour un mode inconnu")
            XCTAssertThrowsError(try env.validate()) { error in
                let jolene = error as? JoleneError
                XCTAssertEqual(jolene?.kind, .environment)
                XCTAssertTrue(jolene?.message.contains(raw.trimmingCharacters(in: .whitespaces)) == true, "le refus nomme le mode : \(String(describing: jolene?.message))")
                XCTAssertFalse(jolene?.message.contains("sb_publishable") == true, "aucune clé dans le message")
            }
        }
    }

    func testMissingModeIsRefused() {
        let env = JoleneEnvironment.load(arguments: [], environment: [:], info: ["JoleneSupabaseURL": "https://flripxtsyegjshnhzjkz.supabase.co"])
        XCTAssertEqual(env.unknownModeRaw, "")
        XCTAssertThrowsError(try env.validate()) { error in
            XCTAssertEqual((error as? JoleneError)?.message, JoleneEnvironment.unknownModeMessage(""))
        }
    }

    func testOverridesAreIgnoredWhenDisallowed() {
        // Build Release : `-JOLENE_MODE demo` et `JOLENE_MODE=staging` ne changent rien, l'Info.plist fait foi.
        let env = JoleneEnvironment.load(arguments: ["-JOLENE_MODE", "demo"], environment: ["JOLENE_MODE": "staging"],
                                         info: infoProduction, allowOverrides: false)
        XCTAssertEqual(env.mode, .production)
        XCTAssertNil(env.unknownModeRaw)
        XCTAssertEqual(env.publishableKey, "sb_publishable_prod_fictive")
        XCTAssertNoThrow(try env.validate())
    }

    func testDemoRefusesAnyURLOrKey() {
        var env = JoleneEnvironment(mode: .demo, supabaseURL: nil, publishableKey: nil)
        XCTAssertNoThrow(try env.validate())
        env.publishableKey = "sb_publishable_x"
        XCTAssertThrowsError(try env.validate())
        env = JoleneEnvironment(mode: .demo, supabaseURL: URL(string: "https://mejpriaetwgtcstbgfid.supabase.co"), publishableKey: nil)
        XCTAssertThrowsError(try env.validate())
    }

    // MARK: validate

    private func staging(key: String?, url: String? = "https://mejpriaetwgtcstbgfid.supabase.co") -> JoleneEnvironment {
        JoleneEnvironment(mode: .staging, supabaseURL: url.flatMap(URL.init(string:)), publishableKey: key)
    }

    func testSecretKeyIsRefusedWithoutEchoingIt() {
        XCTAssertThrowsError(try staging(key: "sb_secret_abc").validate()) { error in
            let message = (error as? JoleneError)?.message ?? ""
            XCTAssertTrue(message.contains("secrète"))
            XCTAssertFalse(message.contains("sb_secret_abc"))
        }
        XCTAssertThrowsError(try staging(key: "service_role_xyz").validate())
    }

    func testLegacyJwtKeyIsRefused() {
        XCTAssertThrowsError(try staging(key: "eyJhbGciOiJIUzI1NiJ9.x.y").validate())
    }

    func testMissingKeyIsRefused() {
        XCTAssertThrowsError(try staging(key: nil).validate())
        XCTAssertThrowsError(try staging(key: "").validate())
    }

    func testProjectRefOutsideAllowlistIsRefused() {
        XCTAssertThrowsError(try staging(key: "sb_publishable_x", url: "https://flripxtsyegjshnhzjkz.supabase.co").validate())
        XCTAssertThrowsError(try staging(key: "sb_publishable_x", url: "https://autre.supabase.co").validate())
        XCTAssertThrowsError(try staging(key: "sb_publishable_x", url: "https://mejpriaetwgtcstbgfid.supabase.co.evil.example").validate())
    }

    func testPlainHttpIsRefused() {
        XCTAssertThrowsError(try staging(key: "sb_publishable_x", url: "http://mejpriaetwgtcstbgfid.supabase.co").validate())
        XCTAssertThrowsError(try staging(key: "sb_publishable_x", url: nil).validate())
    }

    func testAcceptedConfigurationsPerMode() {
        XCTAssertNoThrow(try staging(key: "sb_publishable_x").validate())
        let production = JoleneEnvironment(mode: .production, supabaseURL: URL(string: "https://flripxtsyegjshnhzjkz.supabase.co"), publishableKey: "sb_publishable_y")
        XCTAssertNoThrow(try production.validate())
    }
}
