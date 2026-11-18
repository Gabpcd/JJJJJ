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
        XCTAssertTrue(gateways.favoris is SupabaseFavorisGateway)
        XCTAssertTrue(gateways.push is SupabasePushGateway, "lot 3, T4 : enregistrement et désactivation du token APNs")
        XCTAssertTrue(gateways.mesMissions is SupabaseMesMissionsGateway)
        XCTAssertTrue(gateways.candidature is SupabaseCandidatureGateway, "T6a câble la candidature")
        XCTAssertTrue(gateways.justificatifs is SupabaseJustificatifStorage, "T7 câble les justificatifs d'annulation")
    }

    /// Aucune liste propre à ce monde : les ports encore stubs côté Supabase doivent être
    /// exactement ceux du monde démo (`DemoWorld.gateways()`, figés par la source unique
    /// `DemoWorldTests.portsEnAttenteLot1`, `portsEnAttenteLot2` et `portsEnAttenteLot3`). Une PR qui câble un port
    /// dans un seul monde fait diverger les deux ensembles et rougit ce test. T12 (clôture du lot 1)
    /// exige qu'aucun nom du lot 1 ne reste dans `unwiredPorts`
    /// (`unwiredPorts.filter(Lot1PortsTests.portsLot1.contains).isEmpty`), pas `unwiredPorts.isEmpty` :
    /// les ports des lots 2 et 3 y restent nommés tant que ces lots sont ouverts.
    func testAucunPortNonCable() {
        let supabase = SupabaseGateways.make(client: TestClient.make()).unwiredPorts
        let demo = DemoWorld.gateways().unwiredPorts
        XCTAssertEqual(supabase, demo,
                       "un port doit être câblé dans SupabaseGateways.make(client:) ET DemoWorld.gateways() dans la même PR")
        XCTAssertFalse(supabase.contains("audit"), "T1 câble l'audit")
        XCTAssertFalse(supabase.contains("flags"), "T1 câble les drapeaux")
        XCTAssertFalse(supabase.contains("dashboard"), "T3 câble le tableau de bord")
        XCTAssertFalse(supabase.contains("compte"), "T8 câble la suppression de compte")
        XCTAssertFalse(supabase.contains("favoris"), "T4b câble les favoris")
        XCTAssertFalse(supabase.contains("mesMissions"), "T5 câble Mes missions")
        XCTAssertFalse(supabase.contains("candidature"), "T6a câble la candidature")
        XCTAssertFalse(supabase.contains("pointage"), "lot 2 T3 câble le pointage")
        XCTAssertFalse(supabase.contains("contrats"), "lot 2, T8 câble les contrats")
        XCTAssertFalse(supabase.contains("notation"), "lot 2, T5a câble la notation")
        XCTAssertFalse(supabase.contains("contestation"), "lot 2, T5b câble la contestation")
        XCTAssertFalse(supabase.contains("push"), "lot 3, T4 câble le push")
        XCTAssertFalse(supabase.contains("notifications"), "lot 3, T5 câble le centre de notifications")
        XCTAssertFalse(supabase.contains("profil"), "lot 3, T9 câble le profil")
        XCTAssertFalse(supabase.contains("avatar") || supabase.contains("geocodage"), "lot 3, T10 câble l'avatar et le géocodage")
        let gateways = SupabaseGateways.make(client: TestClient.make())
        XCTAssertTrue(gateways.avatar is EnvoiAvatar, "reçu durable et relecture d'`EnvoiAvatar` sur Supabase Storage")
        XCTAssertTrue(gateways.geocodage is ApiAdresseGeocodage)
    }

    /// L4-T1c, verrou m6 (revue B8 de #1146) : aucun abonnement Realtime ni capture de parrainage dans le monde Supabase
    /// tant que leurs ports restent non câblés (T7a, T6) ; jumelle de `SecondairesLot4Tests` côté démo.
    func testAbonnementRealtimeVerrouilleAvantT7a() {
        let gateways = SupabaseGateways.make(client: TestClient.make())
        XCTAssertEqual(VerrousLot4.abonnementRealtimePermis(gateways.realtime), !gateways.unwiredPorts.contains("realtime"),
                       "abonnement permis si et seulement si le port realtime est câblé")
        XCTAssertEqual(VerrousLot4.parrainageBranche, !gateways.unwiredPorts.contains("parrainage"),
                       "capture du parrainage branchée si et seulement si le port parrainage est câblé")
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
        XCTAssertTrue(gateways.pointage is SupabasePointageGateway, "T3 câble le pointage")
        XCTAssertTrue(gateways.contestation is SupabaseContestationGateway, "T5b câble la contestation")
        XCTAssertTrue(gateways.notation is SupabaseNotationGateway, "T5a câble la notation")
        XCTAssertTrue(gateways.documents is SupabaseDocumentsGateway, "T6 câble les justificatifs")
        XCTAssertTrue(gateways.contrats is SupabaseContratsGateway, "T8 câble les contrats")
        // Fusion des lots 2 et 3 : le bloc du lot 3 suit celui du lot 2 dans `unwiredPorts` ; seuls les noms du lot 2 comptent.
        XCTAssertEqual(gateways.unwiredPorts.filter(["pointage", "contestation", "notation", "documents", "contrats"].contains),
                       [], "lot 2 : les cinq ports sont câblés (T5b en dernier)")
        XCTAssertFalse(gateways.unwiredPorts.contains("notation"))
        XCTAssertFalse(gateways.unwiredPorts.contains("pointage"))
        XCTAssertFalse(gateways.unwiredPorts.contains("documents"))
        XCTAssertFalse(gateways.unwiredPorts.contains("contrats"))
        XCTAssertTrue(gateways.audit is SupabaseAuditGateway, "le câblage du lot 1 reste celui de l'init")
    }

    /// Lot 5 (T1) : même règle pour les ports de l'espace établissement — aucune liste propre à ce monde,
    /// comparaison au monde démo (source unique `DemoWorldTests.portsEnAttenteLot5`).
    func testPortsEtablissementCablesCommeLeMondeDemo() {
        let supabase = SupabaseGateways.make(client: TestClient.make()).etablissement
        let demo = DemoWorld.gateways().etablissement
        XCTAssertEqual(supabase.unwiredPorts, demo.unwiredPorts,
                       "un port établissement doit être câblé dans SupabaseEtablissementGateways ET DemoEtablissementWorld dans la même PR")
        XCTAssertTrue(supabase.session is SupabaseEtabSessionGateway, "T1 câble la session établissement")
        XCTAssertTrue(supabase.audit is SupabaseEtabAuditGateway, "T1 câble l'audit de consultation")
        XCTAssertFalse(supabase.unwiredPorts.contains("etablissement.session"))
        XCTAssertFalse(supabase.unwiredPorts.contains("etablissement.audit"))
        XCTAssertEqual(SupabaseEtablissementGateways.make(client: TestClient.make()).unwiredPorts, supabase.unwiredPorts)
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
