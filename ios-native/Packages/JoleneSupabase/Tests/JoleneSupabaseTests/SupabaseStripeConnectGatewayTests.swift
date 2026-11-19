import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Edges Stripe Connect (lot 3, T14a, B9 ; liste de tests du blueprint §3 T14a, côté Supabase), d'après les fiches
/// « Edge `stripe-connect-status` » et « Edge `stripe-connect-onboard` » de `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md` :
/// - onboarding en `POST` avec l'en-tête `Origin: https://jolene.app` (correction 1) et le Bearer de la session ;
/// - 403 `ORIGINE_NON_AUTORISEE` → erreur de contrat ; 403 `TEST_ACCOUNT_PAYMENT_DISABLED` → compte de test ;
/// - statut en `POST`, `?force=true` seulement quand demandé (correction 17) ; `COMPLET` sans ses drapeaux → erreur.
final class SupabaseStripeConnectGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let statutChemin = "/functions/v1/stripe-connect-status"
    private let onboardChemin = "/functions/v1/stripe-connect-onboard"
    private let soignantsChemin = "/rest/v1/soignants"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func connecte() async throws -> SupabaseClient {
        let client = TestClient.make()
        registry.add("POST", "/auth/v1/token", respond: .json(200, TestClient.sessionJSON()))
        _ = try await SupabaseAuthGateway(client: client).signIn(email: TestClient.email, password: "motdepasse-test")
        return client
    }

    // MARK: - stripe-connect-onboard

    func testOnboardingEnvoieOrigineJoleneEtRendLeLien() async throws {
        let client = try await connecte()
        let jeton = try XCTUnwrap(client.auth.currentSession?.accessToken)
        registry.add("POST", onboardChemin, respond: .json(200, #"{"success":true,"url":"https://connect.stripe.com/setup/e/acct_1","account_id":"acct_1"}"#))

        let resultat = try await SupabaseStripeConnectGateway(client: client).lienOnboarding(context: TestClient.context)

        XCTAssertEqual(resultat, .lien(URL(string: "https://connect.stripe.com/setup/e/acct_1")!))
        let requete = try XCTUnwrap(registry.requests(to: onboardChemin).first)
        XCTAssertEqual(registry.requests(to: onboardChemin).count, 1, "un seul appel")
        XCTAssertEqual(requete.method, "POST")
        XCTAssertEqual(requete.header("Origin"), "https://jolene.app", "sans Origin : 403 ORIGINE_NON_AUTORISEE (correction 1)")
        XCTAssertEqual(requete.header("Authorization"), "Bearer \(jeton)")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func test403OrigineNonAutoriseeEstUneErreurDeContrat() async throws {
        let client = try await connecte()
        registry.add("POST", onboardChemin, respond: .json(403, #"{"error":"ORIGINE_NON_AUTORISEE"}"#))
        do {
            _ = try await SupabaseStripeConnectGateway(client: client).lienOnboarding(context: TestClient.context)
            XCTFail("erreur de contrat attendue")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .contract)
            XCTAssertFalse(erreur.message.contains("ORIGINE"), "code machine jamais affiché")
        }
    }

    func test403TestAccountPaymentDisabledEstLeCompteTest() async throws {
        let client = try await connecte()
        registry.add("POST", onboardChemin, respond: .json(403, #"{"error":"TEST_ACCOUNT_PAYMENT_DISABLED"}"#))
        let resultat = try await SupabaseStripeConnectGateway(client: client).lienOnboarding(context: TestClient.context)
        XCTAssertEqual(resultat, .compteTest)
    }

    func test403NonLiberalEstNonEligibleEtAutreRefusVerbatim() async throws {
        let client = try await connecte()
        let texte = "Stripe Connect est réservé aux soignants en exercice libéral ou mixte"
        registry.add("POST", onboardChemin, respond: .json(403, #"{"error":"\#(texte)"}"#))
        let gateway = SupabaseStripeConnectGateway(client: client)
        let nonEligible = try await gateway.lienOnboarding(context: TestClient.context)
        XCTAssertEqual(nonEligible, .nonEligible(message: texte))
        registry.reset()
        let autre = try await connecte()
        registry.add("POST", onboardChemin, respond: .json(402, #"{"error":"card_declined","message":"Paiement refusé par Stripe."}"#))
        let refus = try await SupabaseStripeConnectGateway(client: autre).lienOnboarding(context: TestClient.context)
        XCTAssertEqual(refus, .refuse(code: "card_declined", message: "Paiement refusé par Stripe."))
    }

    func test401SurLOnboardingEstUneSessionExpireeJamaisUnRefusAffiche() async throws {
        let client = try await connecte()
        registry.add("POST", onboardChemin, respond: .json(401, #"{"error":"Non autorisé"}"#))
        do {
            _ = try await SupabaseStripeConnectGateway(client: client).lienOnboarding(context: TestClient.context)
            XCTFail("session expirée attendue")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        }
    }

    func test503ClassificationIndisponibleDonneLeRepliDuWebSansCode() async throws {
        let client = try await connecte()
        registry.add("POST", onboardChemin, respond: .json(503, #"{"error":"TEST_ACCOUNT_CLASSIFICATION_UNAVAILABLE"}"#))
        let resultat = try await SupabaseStripeConnectGateway(client: client).lienOnboarding(context: TestClient.context)
        XCTAssertEqual(resultat, .refuse(code: "TEST_ACCOUNT_CLASSIFICATION_UNAVAILABLE",
                                         message: "Erreur lors de la connexion à Stripe. Veuillez réessayer."),
                       "repli du web l.146 ; le code machine n'est jamais le texte affiché")
    }

    // MARK: - soignants (exercice, lu avant tout appel d'edge)

    func testExerciceLitLesTroisColonnesDuSoignantSansAucunAppelDEdge() async throws {
        let cas: [(String, ExerciceConnect)] = [
            (#"{"type_exercice":"SALARIE","statut_liberal":null,"est_compte_test":false}"#,
             ExerciceConnect(typeExercice: "SALARIE", statutLiberal: nil, estCompteTest: false)),
            (#"{"type_exercice":"LIBERAL","statut_liberal":"ACTIF","est_compte_test":true}"#,
             ExerciceConnect(typeExercice: "LIBERAL", statutLiberal: "ACTIF", estCompteTest: true)),
        ]
        for (corps, attendu) in cas {
            registry.reset()
            let client = try await connecte()
            registry.add("GET", soignantsChemin, respond: .json(200, corps))
            let lu = try await SupabaseStripeConnectGateway(client: client).exercice(context: TestClient.context)
            XCTAssertEqual(lu, attendu, corps)
            let lecture = try XCTUnwrap(registry.requests(to: soignantsChemin).first)
            XCTAssertEqual(lecture.query("select"), "type_exercice,statut_liberal,est_compte_test")
            XCTAssertEqual(lecture.query("id"), "eq.\(TestClient.userId)")
            XCTAssertTrue(registry.requests(to: statutChemin).isEmpty && registry.requests(to: onboardChemin).isEmpty,
                          "lecture de l'exercice : aucun appel Stripe")
            XCTAssertTrue(registry.unmatched.isEmpty)
        }
        XCTAssertFalse(cas[0].1.estLiberal, "salarié : mode salarié, sans appel d'edge (modèle)")
        XCTAssertTrue(cas[1].1.compteTest, "compte de test décodé : écran du compte de test, sans appel d'edge (modèle)")
    }

    func testExerciceSansLigneEstUneErreurSansAppelDEdge() async throws {
        let client = try await connecte()
        registry.add("GET", soignantsChemin, respond: .json(406, #"{"code":"PGRST116","details":"The result contains 0 rows","hint":null,"message":"no rows"}"#))
        do {
            _ = try await SupabaseStripeConnectGateway(client: client).exercice(context: TestClient.context)
            XCTFail("profil indisponible attendu : jamais un mode d'exercice déduit (web l.93)")
        } catch is JoleneError {}
        XCTAssertTrue(registry.requests(to: statutChemin).isEmpty && registry.requests(to: onboardChemin).isEmpty)
    }

    // MARK: - stripe-connect-status

    func testStatutForceEnvoieForceTrueEtLitLeCorps() async throws {
        let client = try await connecte()
        registry.add("POST", statutChemin, respond: .json(200, """
        {"statut":"COMPLET","onboarding_complete":true,"charges_enabled":true,"payouts_enabled":true,"iban_last4":"0189","requirements":[],"disabled_reason":null,"cached":false}
        """))
        let gateway = SupabaseStripeConnectGateway(client: client)
        let complet = try await gateway.statut(force: true, context: TestClient.context)
        XCTAssertEqual(complet.statut, .complet)
        XCTAssertEqual(complet.ibanLast4, "0189")
        _ = try await gateway.statut(force: false, context: TestClient.context)
        let requetes = registry.requests(to: statutChemin)
        XCTAssertEqual(requetes.map(\.method), ["POST", "POST"], "POST seulement (l.30 : sinon 405)")
        XCTAssertEqual(requetes.map { $0.query("force") }, ["true", nil], "force=true seulement quand demandé")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testStatutCompletSansDrapeauxOuInconnuEstUneErreur() async throws {
        for corps in [#"{"statut":"COMPLET","onboarding_complete":true,"charges_enabled":true,"payouts_enabled":false}"#,
                      #"{"statut":"INCONNU","onboarding_complete":false,"charges_enabled":false,"payouts_enabled":false}"#] {
            registry.reset()
            let client = try await connecte()
            registry.add("POST", statutChemin, respond: .json(200, corps))
            do {
                _ = try await SupabaseStripeConnectGateway(client: client).statut(force: false, context: TestClient.context)
                XCTFail("statut indisponible attendu : \(corps)")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.kind, .contract, corps)
            }
        }
    }
}
