import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

final class SupabaseGatewaysTests: XCTestCase {
    private let stagingURL = URL(string: "https://mejpriaetwgtcstbgfid.supabase.co")!

    func testSecretKeyIsRefusedBeforeAnyClientIsBuilt() {
        let environment = JoleneEnvironment(mode: .staging, supabaseURL: stagingURL, publishableKey: "sb_secret_abc")
        XCTAssertThrowsError(try SupabaseGateways.make(environment: environment)) { error in
            XCTAssertEqual((error as? JoleneError)?.kind, .environment)
            XCTAssertFalse("\(error)".contains("sb_secret_abc"), "la clé n'apparaît jamais dans l'erreur")
        }
    }

    func testProjectRefOutsideAllowlistIsRefused() {
        let environment = JoleneEnvironment(mode: .production, supabaseURL: stagingURL, publishableKey: "sb_publishable_x")
        XCTAssertThrowsError(try SupabaseGateways.make(environment: environment)) { error in
            XCTAssertEqual((error as? JoleneError)?.kind, .environment)
        }
    }

    func testLegacyJwtKeyIsRefused() {
        let environment = JoleneEnvironment(mode: .staging, supabaseURL: stagingURL, publishableKey: "eyJhbGciOiJIUzI1NiJ9.x.y")
        XCTAssertThrowsError(try SupabaseGateways.make(environment: environment)) { error in
            XCTAssertEqual((error as? JoleneError)?.kind, .environment)
        }
    }

    func testDemoModeNeverBuildsASupabaseClient() {
        let environment = JoleneEnvironment(mode: .demo, supabaseURL: nil, publishableKey: nil)
        XCTAssertThrowsError(try SupabaseGateways.make(environment: environment)) { error in
            XCTAssertEqual((error as? JoleneError)?.kind, .demoOnly)
        }
    }

    func testMakeWithClientAssemblesSupabasePorts() {
        let clock = FixedClock(Date(timeIntervalSince1970: 1))
        let gateways = SupabaseGateways.make(client: TestClient.make(), clock: clock)
        XCTAssertTrue(gateways.auth is SupabaseAuthGateway)
        XCTAssertTrue(gateways.role is SupabaseRoleGateway)
        XCTAssertTrue(gateways.missions is SupabaseMissionsGateway)
        XCTAssertEqual(gateways.clock.now(), Date(timeIntervalSince1970: 1))
        XCTAssertTrue(gateways.audit is SupabaseAuditGateway)
        XCTAssertTrue(gateways.flags is SupabaseFlagsGateway)
    }

    /// Ports du lot 1 que leur tranche n'a pas encore câblés : liste identique à
    /// `DemoWorldTests.portsEnAttenteLot1` (JoleneCore). Chaque PR qui câble un port le retire
    /// des deux listes ; vides à la clôture du lot (T12).
    static let portsEnAttenteLot1 = ["dashboard", "candidature", "presence", "favoris", "mesMissions",
                                     "compte", "recovery", "justificatifs"]

    func testAucunPortNonCable() {
        let gateways = SupabaseGateways.make(client: TestClient.make())
        XCTAssertEqual(gateways.unwiredPorts, Self.portsEnAttenteLot1,
                       "tout port livré doit être câblé dans SupabaseGateways.make(client:) dans la même PR")
    }

    func testClientOptionsUsePkceInjectedStorageAndJoleneHeader() {
        let storage = InMemoryAuthStorage()
        let session = URLSession(configuration: .ephemeral)
        let options = SupabaseGateways.clientOptions(storage: storage, session: session, autoRefreshToken: false)
        XCTAssertEqual(options.auth.flowType, .pkce)
        XCTAssertFalse(options.auth.autoRefreshToken)
        XCTAssertTrue(options.auth.storage is InMemoryAuthStorage)
        XCTAssertTrue(options.global.session === session, "URLSession injectée (transport de test)")
        XCTAssertEqual(options.global.headers, ["X-Client-Info": "jolene-ios/2.0.0"])
        XCTAssertNil(options.auth.accessToken, "auth.accessToken absent : le namespace auth du client reste utilisable")

        let production = SupabaseGateways.clientOptions(storage: KeychainSessionStorage())
        XCTAssertTrue(production.auth.autoRefreshToken)
        XCTAssertTrue(production.auth.storage is KeychainSessionStorage)
        XCTAssertEqual(production.auth.flowType, .pkce)
    }

    func testClientCarriesJoleneHeaderAndPublishableKey() {
        let client = SupabaseGateways.makeClient(url: stagingURL, publishableKey: "sb_publishable_x", storage: InMemoryAuthStorage(), autoRefreshToken: false)
        XCTAssertEqual(client.headers["X-Client-Info"], "jolene-ios/2.0.0", "remplace l'en-tête par défaut du SDK")
        XCTAssertEqual(client.headers["Apikey"] ?? client.headers["apikey"], "sb_publishable_x")
        XCTAssertEqual(JoleneSupabase.clientInfo, "jolene-ios/2.0.0")
    }

    func testEnvironmentFactoryBuildsGatewaysWhenConfigurationIsAccepted() throws {
        try XCTSkipUnless(KeychainSessionStorage.isAvailable(), "Keychain indisponible pour ce processus de test (entitlement)")
        let environment = JoleneEnvironment(mode: .staging, supabaseURL: stagingURL, publishableKey: "sb_publishable_x")
        let gateways = try SupabaseGateways.make(environment: environment)
        XCTAssertTrue(gateways.auth is SupabaseAuthGateway)
        XCTAssertTrue(gateways.role is SupabaseRoleGateway)
        XCTAssertTrue(gateways.missions is SupabaseMissionsGateway)
    }
}
