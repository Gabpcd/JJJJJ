import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Parrainage sur Supabase (L4-T6) — fiches `fn_obtenir_mes_parrainages` et `fn_appliquer_parrainage` de
/// `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md` :
/// - lecture : `soignants` (`code_parrainage, badge_ambassadeur`, filtre `id`) et la RPC sans paramètre ; une réponse
///   illisible ou `{error}` est une erreur, jamais un parrainage vide ;
/// - application : le code normalisé seul part en `p_code` ; refus définitifs `{error}` restitués verbatim, autres
///   refus et « Non authentifié » à réessayer ; le message serveur de succès n'est jamais rendu, le succès n'est
///   annoncé qu'après la relecture qui montre `mon_parrain` ; un code hors forme ne part jamais.
final class SupabaseParrainageGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let soignants = "/rest/v1/soignants"
    private let lire = "/rest/v1/rpc/fn_obtenir_mes_parrainages"
    private let appliquer = "/rest/v1/rpc/fn_appliquer_parrainage"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseParrainageGateway { SupabaseParrainageGateway(client: TestClient.make()) }

    private static let profil = #"{"code_parrainage":"JOLENE-TEST","badge_ambassadeur":false}"#
    private static let parrainages = """
    {"filleuls":[{"id":"p1","filleul_id":"f1","prenom":"Inès","statut":"EN_ATTENTE","cree_le":"2026-10-20T09:00:00+00:00",
      "filleul_active_le":null,"commission_cumulee_filleul":0,"gmv_cumule_filleul":0,"reste_gmv_avant_prime":500,
      "seuil_gmv":500,"seuil_atteint":false,"prime_versee_le":null,"premiere_mission_le":null,"bonus_heures":0}],
     "total_gains_eur":0,"nb_primes_versees":0,"prime_eur":25,"seuil_gmv_eur":500,"mon_parrain":null}
    """
    private static let avecParrain = """
    {"filleuls":[],"total_gains_eur":0,"nb_primes_versees":0,"prime_eur":25,"seuil_gmv_eur":500,
     "mon_parrain":{"parrain_prenom":"Awa","statut":"EN_ATTENTE","prime_versee_le":null}}
    """

    private func erreur(_ operation: () async throws -> Void) async -> JoleneError? {
        do {
            try await operation()
            return nil
        } catch let error as JoleneError {
            return error
        } catch {
            XCTFail("type d'erreur inattendu : \(error)")
            return nil
        }
    }

    // MARK: - Lecture

    func testEtatLitLeProfilEtLaRPC() async throws {
        registry.add("GET", soignants, respond: .json(200, Self.profil))
        registry.add("POST", lire, respond: .json(200, Self.parrainages))
        let etat = try await gateway().etat(context: TestClient.context)
        XCTAssertEqual(etat.code, "JOLENE-TEST")
        XCTAssertTrue(etat.profilPresent)
        XCTAssertEqual(etat.filleuls.map(\.id), ["f1"])
        XCTAssertEqual(etat.filleuls.first?.statut, "EN_ATTENTE")
        let lecture = try XCTUnwrap(registry.requests(to: soignants).first)
        let parametres = Dictionary(lecture.queryItems.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(parametres["select"], "code_parrainage,badge_ambassadeur", lecture.url.absoluteString)
        XCTAssertEqual(parametres["id"], "eq.\(TestClient.userId)", lecture.url.absoluteString)
        XCTAssertEqual(registry.requests(to: lire).count, 1)
        XCTAssertEqual(registry.requests.count, 2, "deux lectures, aucun renvoi")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testProfilAbsentSansCode() async throws {
        registry.add("GET", soignants, respond: .json(200, "null"))
        registry.add("POST", lire, respond: .json(200, Self.parrainages))
        let etat = try await gateway().etat(context: TestClient.context)
        XCTAssertFalse(etat.profilPresent)
        XCTAssertNil(etat.code)
    }

    func testEtatIllisibleOuRefuseEstUneErreur() async {
        registry.add("GET", soignants, respond: .json(200, Self.profil))
        registry.add("POST", lire, respond: .json(200, #"{"error":"Non authentifié"}"#))
        let session = await erreur { _ = try await self.gateway().etat(context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized)

        registry.reset()
        registry.add("GET", soignants, respond: .json(200, Self.profil))
        registry.add("POST", lire, respond: .json(200, #"{"filleuls":"rien"}"#))
        let forme = await erreur { _ = try await self.gateway().etat(context: TestClient.context) }
        XCTAssertEqual(forme?.kind, .contract)

        registry.reset()
        registry.add("GET", soignants, respond: .networkFailure())
        registry.add("POST", lire, respond: .json(200, Self.parrainages))
        let reseau = await erreur { _ = try await self.gateway().etat(context: TestClient.context) }
        XCTAssertEqual(reseau?.kind, .network)
    }

    // MARK: - Application

    func testSuccesConfirmeParRelectureSansMessageServeur() async throws {
        registry.add("POST", appliquer, respond: .json(200, #"{"success":true,"message":"Code accepté ! Votre prime de 50€ sera versée après votre 1ère mission terminée et 100€ de commission encaissée par Jolene."}"#))
        registry.add("GET", soignants, respond: .json(200, Self.profil))
        registry.add("POST", lire, respond: .json(200, Self.avecParrain))
        let issue = try await gateway().appliquer(code: "demo-xyz", context: TestClient.context)
        XCTAssertEqual(issue, .appliquee, "le message serveur n'est jamais rendu")
        let corps = try XCTUnwrap(registry.requests(to: appliquer).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(corps as NSDictionary, ["p_code": "DEMO-XYZ"] as NSDictionary, "code normalisé seul")
    }

    func testSuccesNonConfirmeEstAReessayer() async throws {
        registry.add("POST", appliquer, respond: .json(200, #"{"success":true,"message":"x"}"#))
        registry.add("GET", soignants, respond: .json(200, Self.profil))
        registry.add("POST", lire, respond: .json(200, Self.parrainages))
        let issue = try await gateway().appliquer(code: "DEMO-XYZ", context: TestClient.context)
        XCTAssertEqual(issue, .aReessayer, "`mon_parrain` absent à la relecture : rien n'est annoncé")
    }

    func testRefusDefinitifsVerbatimEtAutresRefusAReessayer() async throws {
        for message in ["Code de parrainage invalide", "Vous ne pouvez pas vous parrainer vous-même",
                        "Le parrain a atteint la limite de 20 filleuls validés", "Vous avez déjà appliqué un code de parrainage"] {
            registry.reset()
            registry.add("POST", appliquer, respond: .json(200, #"{"error":"\#(message)"}"#))
            let issue = try await gateway().appliquer(code: "ABCD1234", context: TestClient.context)
            XCTAssertEqual(issue, .refusDefinitif(message: message))
            XCTAssertEqual(registry.requests.count, 1, "\(message) : aucune relecture, aucun renvoi")
        }
        for message in ["Non authentifié", "Compte suspendu, supprimé ou désactivé", "Profil soignant introuvable"] {
            registry.reset()
            registry.add("POST", appliquer, respond: .json(200, #"{"error":"\#(message)"}"#))
            let issue = try await gateway().appliquer(code: "ABCD1234", context: TestClient.context)
            XCTAssertEqual(issue, .aReessayer, "\(message) : code conservé")
        }
    }

    func testExceptionEtFormeInattendue() async {
        registry.add("POST", appliquer, respond: .json(400, #"{"code":"P0001","message":"Attribution du parrain non persistée"}"#))
        let exception = await erreur { _ = try await self.gateway().appliquer(code: "ABCD1234", context: TestClient.context) }
        XCTAssertNotNil(exception, "exception PostgREST : erreur, le code est conservé par l'appelant")

        registry.reset()
        registry.add("POST", appliquer, respond: .json(200, #"{"ok":"peut-être"}"#))
        let forme = await erreur { _ = try await self.gateway().appliquer(code: "ABCD1234", context: TestClient.context) }
        XCTAssertEqual(forme?.kind, .contract)
    }

    func testCodeHorsFormeJamaisEnvoye() async {
        for code in ["<script>", "ETB-1234", "ab", "A'B--CD"] {
            registry.reset()
            let refus = await erreur { _ = try await self.gateway().appliquer(code: code, context: TestClient.context) }
            XCTAssertEqual(refus?.kind, .contract, code)
            XCTAssertTrue(registry.requests.isEmpty, "\(code) : aucune requête")
        }
    }
}
