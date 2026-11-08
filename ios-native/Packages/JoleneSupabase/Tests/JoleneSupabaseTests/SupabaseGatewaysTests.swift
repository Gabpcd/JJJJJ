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
        XCTAssertTrue(gateways.compte is SupabaseAccountGateway)
    }

    /// Aucune liste propre à ce monde : les ports encore stubs côté Supabase doivent être
    /// exactement ceux du monde démo (`DemoWorld.gateways()`, figés par la source unique
    /// `DemoWorldTests.portsEnAttenteLot1` et `portsEnAttenteLot2`). Une PR qui câble un port dans
    /// un seul monde fait diverger les deux ensembles et rougit ce test. T12 (clôture du lot 1)
    /// exige qu'aucun nom du lot 1 ne reste dans `unwiredPorts`
    /// (`unwiredPorts.filter(Lot1PortsTests.portsLot1.contains).isEmpty`), pas `unwiredPorts.isEmpty` :
    /// les ports du lot 2 y restent nommés tant que ce lot est ouvert.
    func testAucunPortNonCable() {
        let supabase = SupabaseGateways.make(client: TestClient.make()).unwiredPorts
        let demo = DemoWorld.gateways().unwiredPorts
        XCTAssertEqual(supabase, demo,
                       "un port doit être câblé dans SupabaseGateways.make(client:) ET DemoWorld.gateways() dans la même PR")
        XCTAssertFalse(supabase.contains("audit"), "T1 câble l'audit")
        XCTAssertFalse(supabase.contains("flags"), "T1 câble les drapeaux")
        XCTAssertFalse(supabase.contains("dashboard"), "T3 câble le tableau de bord")
        XCTAssertFalse(supabase.contains("compte"), "T8 câble la suppression de compte")
    }

    /// Lot 2 (T1) : `câblerLot2(_:client:)` est le seul point d'assignation des cinq ports du lot 2 du
    /// monde Supabase ; tant que leurs tranches ne sont pas livrées, chacun est un stub nommé.
    func testCablerLot2AssigneLesStubsDuLot2() {
        // Revue fraîche de T1 : témoin posé d'abord dans chaque champ du lot 2, puis `câblerLot2` seul ; sans lui,
        // le test resterait vert avec une fonction vide (les défauts de `Gateways` sont déjà des stubs).
        var gateways = SupabaseGateways.make(client: TestClient.make())
        let temoin = PortTemoinLot2()
        gateways.pointage = temoin
        gateways.contestation = temoin
        gateways.notation = temoin
        gateways.documents = temoin
        gateways.contrats = temoin
        XCTAssertFalse(gateways.unwiredPorts.contains("pointage"), "témoin posé")
        SupabaseGateways.câblerLot2(&gateways, client: TestClient.make())
        XCTAssertTrue(gateways.pointage is UnwiredPointagePort, "T3")
        XCTAssertTrue(gateways.contestation is UnwiredContestationPort, "T5b")
        XCTAssertTrue(gateways.notation is UnwiredNotationPort, "T5a")
        XCTAssertTrue(gateways.documents is SupabaseDocumentsGateway, "T6 câble les justificatifs")
        XCTAssertTrue(gateways.contrats is UnwiredContratsPort, "T8")
        XCTAssertEqual(Array(gateways.unwiredPorts.suffix(4)), ["pointage", "contestation", "notation", "contrats"])
        XCTAssertTrue(gateways.audit is SupabaseAuditGateway, "le câblage du lot 1 reste celui de l'init")
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
