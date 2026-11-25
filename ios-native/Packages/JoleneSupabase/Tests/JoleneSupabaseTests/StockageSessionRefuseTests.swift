import Foundation
import JoleneCore
import Security
import Supabase
import XCTest
@testable import JoleneSupabase

/// Troisième parcours STAGING du lot 5 (25/11/2026) : connexion acceptée par Auth, puis `fn_mes_permissions_etab`
/// refusée en « non autorisé » alors que le pré-vol, sous le JWT d'E1, passait. Cause : l'app de simulateur est
/// construite sans signature (`CODE_SIGNING_ALLOWED=NO`), le trousseau refuse l'écriture (-34018), supabase-swift ne
/// lève pas l'échec et chaque requête PostgREST garde la clé publishable en `Authorization`.
final class StockageSessionRefuseTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let permissionsPath = "/rest/v1/rpc/fn_mes_permissions_etab"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    /// Trousseau d'une app de simulateur sans `application-identifier` : toute écriture est refusée.
    private final class TrousseauRefuse: AuthLocalStorage, @unchecked Sendable {
        func store(key: String, value: Data) throws {
            throw KeychainStorageError(operation: "add", status: errSecMissingEntitlement)
        }
        func retrieve(key: String) throws -> Data? { nil }
        func remove(key: String) throws {}
    }

    /// La cause, au niveau du SDK : session acceptée mais non stockée → la lecture suivante part avec la clé publishable
    /// en `Authorization`, jamais avec le jeton de l'utilisateur (rôle `anon` côté PostgREST).
    func testSansSessionStockeeLeSDKEnvoieLaClePublishable() async throws {
        let client = TestClient.make(stockage: TrousseauRefuse())
        registry.add("POST", "/auth/v1/token", respond: .json(200, TestClient.sessionJSON()))
        registry.add("POST", permissionsPath, respond: .json(200, #"{"success":true,"role":null,"etablissement_id":null,"permissions":{}}"#))
        let session = try await client.auth.signIn(email: TestClient.email, password: "motdepasse-test")
        XCTAssertNil(client.auth.currentSession, "l'échec du stockage n'est pas levé par le SDK")
        _ = try await client.rpc("fn_mes_permissions_etab", params: ["p_etablissement_id": AnyJSON.null]).execute()
        let requete = try XCTUnwrap(registry.requests(to: permissionsPath).first)
        XCTAssertEqual(requete.header("Authorization"), "Bearer \(TestClient.publishableKey)")
        XCTAssertNotEqual(requete.header("Authorization"), "Bearer \(session.accessToken)")
    }

    /// Le correctif : la connexion est refusée nommément, avant toute lecture.
    func testConnexionRefuseeQuandLaSessionNEstPasEnregistree() async {
        let gateway = SupabaseAuthGateway(client: TestClient.make(stockage: TrousseauRefuse()))
        registry.add("POST", "/auth/v1/token", respond: .json(200, TestClient.sessionJSON()))
        do {
            _ = try await gateway.signIn(email: TestClient.email, password: "motdepasse-test")
            XCTFail("une session non enregistrée ne doit jamais ouvrir l'espace")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur, JoleneError(.unknown, SupabaseAuthGateway.sessionNonEnregistreeMessage))
            XCTAssertEqual(erreur.detail, JoleneError.detailSessionNonEnregistree)
        } catch {
            XCTFail("erreur inattendue \(type(of: error))")
        }
        XCTAssertTrue(registry.requests(to: permissionsPath).isEmpty, "aucune lecture après le refus")
    }

    func testConnexionAccepteeQuandLaSessionEstRelue() async throws {
        let gateway = SupabaseAuthGateway(client: TestClient.make())
        registry.add("POST", "/auth/v1/token", respond: .json(200, TestClient.sessionJSON()))
        let user = try await gateway.signIn(email: TestClient.email, password: "motdepasse-test")
        XCTAssertEqual(user.id, TestClient.userId)
    }

    /// DEBUG + staging + trousseau refusé → mémoire du processus ; partout ailleurs, le Keychain.
    func testStockageDeSession() {
        XCTAssertTrue(SupabaseGateways.stockageSession(mode: .staging, sonde: { errSecMissingEntitlement }) is StockageMemoire)
        XCTAssertTrue(SupabaseGateways.stockageSession(mode: .staging, sonde: { errSecSuccess }) is KeychainSessionStorage)
        XCTAssertTrue(SupabaseGateways.stockageSession(mode: .production, sonde: { errSecMissingEntitlement }) is KeychainSessionStorage,
                      "jamais de mémoire en production")
    }

    func testSondeDuTrousseauRendLeStatutDEcritureEtNettoie() {
        final class Trousseau: KeychainItemStore, @unchecked Sendable {
            var statut: OSStatus
            var supprimes = 0
            init(_ statut: OSStatus) { self.statut = statut }
            func add(_ attributes: [String: Any]) -> OSStatus { statut }
            func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus { statut }
            func copy(_ query: [String: Any]) -> (status: OSStatus, data: Data?) { (errSecItemNotFound, nil) }
            func delete(_ query: [String: Any]) -> OSStatus { supprimes += 1; return errSecSuccess }
        }
        let refuse = Trousseau(errSecMissingEntitlement)
        XCTAssertEqual(KeychainSessionStorage.statutSonde(store: refuse), errSecMissingEntitlement)
        XCTAssertEqual(refuse.supprimes, 0)
        let ouvert = Trousseau(errSecSuccess)
        XCTAssertEqual(KeychainSessionStorage.statutSonde(store: ouvert), errSecSuccess)
        XCTAssertEqual(ouvert.supprimes, 1, "l'élément témoin est supprimé")
    }

    // MARK: Diagnostic du transport (DEBUG)

    /// Jeton en forme de JWT fabriqué à l'exécution (aucun littéral en forme de secret dans les sources).
    private func jeton(_ charge: String) -> String {
        func segment(_ texte: String) -> String {
            Data(texte.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return [segment(#"{"alg":"HS256"}"#), segment(charge), segment("signature")].joined(separator: ".")
    }

    func testDiagnosticTransportSansJetonNiSecret() {
        let maintenant = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(DiagnosticTransport.decrire(code: "postgrest=42501", jeton: nil, hoteREST: "a.supabase.co", maintenant: maintenant),
                       "postgrest=42501;jwt=non;exp=-;hote=-")
        XCTAssertEqual(DiagnosticTransport.decrire(code: nil, jeton: TestClient.publishableKey, hoteREST: "a.supabase.co", maintenant: maintenant),
                       "http=200;jwt=non;exp=-;hote=-", "une clé publishable n'est pas un JWT")
        let valide = jeton(#"{"sub":"u","exp":1003600,"iss":"https://a.supabase.co/auth/v1"}"#)
        let d = DiagnosticTransport.decrire(code: "http=401", jeton: valide, hoteREST: "A.supabase.co", maintenant: maintenant)
        XCTAssertEqual(d, "http=401;jwt=oui;exp=3600;hote=oui")
        XCTAssertFalse(d.contains(valide.prefix(8)), "jamais le jeton")
        let perime = jeton(#"{"exp":999990,"iss":"https://b.supabase.co/auth/v1"}"#)
        XCTAssertEqual(DiagnosticTransport.decrire(code: "postgrest=PGRST301", jeton: perime, hoteREST: "a.supabase.co", maintenant: maintenant),
                       "postgrest=PGRST301;jwt=oui;exp=-10;hote=non")
        XCTAssertEqual(DiagnosticTransport.decrire(code: "http=403", jeton: jeton(#"{"sub":"u"}"#), hoteREST: nil, maintenant: maintenant),
                       "http=403;jwt=oui;exp=-;hote=-")
    }

    /// Un refus « non autorisé » de fn_mes_permissions_etab emporte le code brut et l'état du jeton envoyé.
    func testRefusNonAutoriseDesPermissionsPorteLeDiagnosticTransport() async {
        registry.add("POST", permissionsPath, respond: .json(401, #"{"code":"42501","message":"permission denied for function fn_mes_permissions_etab","details":null,"hint":null}"#))
        let gateway = SupabaseEtabSessionGateway(client: TestClient.make(stockage: TrousseauRefuse()))
        do {
            _ = try await gateway.permissions(etablissementId: nil)
            XCTFail("refus attendu")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
            XCTAssertEqual(erreur.message, SupabaseErrorMapping.unauthorizedMessage, "message montré inchangé")
            XCTAssertEqual(erreur.detail, "postgrest=42501;jwt=non;exp=-;hote=-")
        } catch {
            XCTFail("erreur inattendue \(type(of: error))")
        }
    }
}
