import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Récupération du mot de passe sur GoTrue (reste de L1-T10) : demande de lien sans révélation ni verifier PKCE,
/// lien `token_hash` / implicit ouvert sur un client **isolé** (quarantaine : le client principal, son stockage et ses
/// événements ne voient jamais la session de récupération), `?code=` refusé sans appel, mise à jour relue, fermeture.
final class SupabaseRecoveryGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let recover = "/auth/v1/recover"
    private let verify = "/auth/v1/verify"
    private let user = "/auth/v1/user"
    private let logout = "/auth/v1/logout"
    private static let nouveau = ["Nouveau", "-mdp-", "2026"].joined()
    private static let hash = "HASHSECRET42"
    private static let versionAPI = ["X-Supabase-Api-Version": "2024-01-01"]

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func gateway() -> SupabaseRecoveryGateway {
        SupabaseRecoveryGateway(fabrique: SupabaseRecoveryGateway.fabrique(
            url: TestClient.url, publishableKey: TestClient.publishableKey, session: Self.session))
    }

    private func refus(_ status: Int, code: String, message: String) -> StubResponse {
        .json(status, #"{"code":"\#(code)","error_code":"\#(code)","msg":"\#(message)"}"#, headers: Self.versionAPI)
    }

    private static func utilisateurJSON(id: String = TestClient.userId) -> String {
        """
        {"id":"\(id)","aud":"authenticated","role":"authenticated","email":"\(TestClient.email)",
         "email_confirmed_at":"2026-01-15T10:00:00Z","app_metadata":{"provider":"email","providers":["email"]},
         "user_metadata":{},"identities":[],"created_at":"2026-01-10T09:00:00Z","updated_at":"2026-11-24T10:00:00Z",
         "is_anonymous":false}
        """
    }

    /// Lien `token_hash` ouvert, registre vidé.
    private func ouvert(_ g: SupabaseRecoveryGateway) async throws {
        registry.add("POST", verify, respond: .json(200, TestClient.sessionJSON()))
        let issue = try await g.openRecoverySession(.tokenHash(tokenHash: Self.hash, otpType: "recovery"))
        XCTAssertEqual(issue, .sessionOuverte)
        registry.reset()
    }

    // MARK: - Demande de lien

    func testDemandeDeLienRedirectionWebSansVerifierEtMemeReponseQueLeCompteExisteOuNon() async throws {
        let principal = InMemoryAuthStorage()
        _ = TestClient.make(storage: principal)
        let g = gateway()
        registry.add("POST", recover, respond: .json(200, "{}"))
        try await g.requestReset(email: "  Inscrite@Example.TEST ")
        try await g.requestReset(email: "inconnue@example.test")
        let requetes = registry.requests(to: recover)
        XCTAssertEqual(requetes.count, 2, "une requête par demande, aucun renvoi")
        for requete in requetes {
            XCTAssertEqual(requete.query("redirect_to"), "https://jolene.app/reset-password")
            let corps = try XCTUnwrap(requete.bodyJSON as? [String: Any])
            XCTAssertNil(corps["code_challenge"], "flux implicit : aucun verifier PKCE n'est posé")
            XCTAssertEqual(requete.header("apikey"), TestClient.publishableKey)
        }
        XCTAssertEqual((requetes[0].bodyJSON as? [String: Any])?["email"] as? String, "inscrite@example.test")
        XCTAssertEqual(principal.keys, [], "le slot PKCE du client principal (confirmation d'inscription) n'est pas écrasé")
        XCTAssertEqual(registry.unmatched.count, 0)
    }

    func testDemandeRefusParLeServeurTraduiteCommeLeWeb() async throws {
        let g = gateway()
        registry.add("POST", recover, respond: refus(429, code: "over_email_send_rate_limit", message: "Email rate limit exceeded"))
        do {
            try await g.requestReset(email: "a@example.test")
            XCTFail("refus attendu")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.message, "Trop de tentatives. Veuillez patienter quelques minutes.")
            XCTAssertFalse(erreur.message.contains("Email rate limit"), "jamais le message anglais")
        }
    }

    // MARK: - Lien de récupération

    func testTokenHashOuvreUneSessionIsoleeQueLeClientPrincipalNeVoitJamais() async throws {
        let principal = InMemoryAuthStorage()
        let client = TestClient.make(storage: principal)
        let g = gateway()
        registry.add("POST", verify, respond: .json(200, TestClient.sessionJSON()))
        let issue = try await g.openRecoverySession(.tokenHash(tokenHash: Self.hash, otpType: "recovery"))
        XCTAssertEqual(issue, .sessionOuverte)
        let corps = try XCTUnwrap(registry.requests(to: verify).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(corps["token_hash"] as? String, Self.hash)
        XCTAssertEqual(corps["type"] as? String, "recovery", "preuve serveur : un hash d'un autre type est refusé")
        let isolee = await g.sessionIsoleeOuverte
        XCTAssertTrue(isolee)
        // Quarantaine : rien dans le client principal (session, stockage), donc rien pour `SessionController`.
        XCTAssertNil(client.auth.currentSession)
        XCTAssertEqual(principal.keys, [])
        let restauree = try await SupabaseAuthGateway(client: client).restoreSession()
        XCTAssertNil(restauree, "la session de récupération n'est jamais restaurée par l'app")
    }

    func testLienExpireOuDejaUtiliseDonneLeRefusDuWebEtNeLaisseRienOuvert() async throws {
        let g = gateway()
        registry.add("POST", verify, respond: refus(403, code: "otp_expired", message: "Email link is invalid or has expired"))
        let issue = try await g.openRecoverySession(.tokenHash(tokenHash: Self.hash, otpType: "recovery"))
        XCTAssertEqual(issue, .lienRefuse(message: ReinitialisationTextes.lienInvalideDetail))
        let isolee = await g.sessionIsoleeOuverte
        XCTAssertFalse(isolee)
        XCTAssertFalse("\(issue)".contains(Self.hash))
        registry.reset()
        do {
            try await g.updatePassword(Self.nouveau)
            XCTFail("aucune mise à jour sans session")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        }
        XCTAssertEqual(registry.requests.count, 0)
    }

    func testCodePKCEEtTypeEtrangerRefusesSansAucunAppel() async throws {
        let g = gateway()
        for lien: AuthCallbackCredentials in [.pkce(code: "c"), .tokenHash(tokenHash: Self.hash, otpType: "signup")] {
            let issue = try await g.openRecoverySession(lien)
            XCTAssertEqual(issue, .lienRefuse(message: ReinitialisationTextes.lienInvalideDetail))
        }
        XCTAssertEqual(registry.requests.count, 0, "option B : ni échange ni vérification")
    }

    /// Revue B8 sécurité de la vague D (m5), parité avec le site : un lien implicite `type=recovery` ouvre la session
    /// sur le client isolé (jeton relu par le serveur), un implicite d'un autre type n'est jamais un lien de récupération.
    func testImplicitRecoveryOuvreLaSessionIsoleeEtAutreTypeRefuse() async throws {
        let principal = InMemoryAuthStorage()
        let client = TestClient.make(storage: principal)
        let g = gateway()
        registry.add("GET", user, respond: .json(200, Self.utilisateurJSON()))
        let jeton = TestClient.accessToken(expiresAt: Date().timeIntervalSince1970 + 3600)
        let lien = try XCTUnwrap(AuthCallbackCredentials.recovery(search: "", fragment: "#access_token=\(jeton)&refresh_token=r&type=recovery"))
        let issue = try await g.openRecoverySession(lien)
        XCTAssertEqual(issue, .sessionOuverte)
        XCTAssertEqual(registry.requests(to: user).count, 1, "jeton relu par le serveur avant tout formulaire")
        let isolee = await g.sessionIsoleeOuverte
        XCTAssertTrue(isolee)
        XCTAssertNil(client.auth.currentSession, "quarantaine : rien dans le client principal")
        XCTAssertEqual(principal.keys, [])
        for type in ["signup", "magiclink", "invite"] {
            XCTAssertNil(AuthCallbackCredentials.recovery(search: "", fragment: "#access_token=a&refresh_token=r&type=\(type)"), type)
        }
        XCTAssertNil(AuthCallbackCredentials.recovery(search: "", fragment: "#access_token=a&refresh_token=r"), "sans type")
    }

    // MARK: - Nouveau mot de passe, relecture, fermeture

    func testMiseAJourReluePuisFermetureGlobaleEtPlusRienDOuvert() async throws {
        let g = gateway()
        try await ouvert(g)
        registry.add("PUT", user, respond: .json(200, Self.utilisateurJSON()))
        registry.add("POST", logout, respond: StubResponse(status: 204, headers: [:], body: Data(), failure: nil))
        try await g.updatePassword(Self.nouveau)
        let corps = try XCTUnwrap(registry.requests(to: user).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(corps["password"] as? String, Self.nouveau)
        XCTAssertTrue(registry.requests(to: user).first?.header("Authorization")?.hasPrefix("Bearer ") == true,
                      "mise à jour portée par la session de récupération isolée")
        try await g.signOutAfterRecovery()
        XCTAssertEqual(registry.requests(to: logout).first?.query("scope"), "global", "comme le web (signOut par défaut)")
        let isolee = await g.sessionIsoleeOuverte
        XCTAssertFalse(isolee)
        registry.reset()
        do {
            try await g.updatePassword(Self.nouveau)
            XCTFail("session fermée : plus aucune mise à jour")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        }
        try await g.signOutAfterRecovery()
        XCTAssertEqual(registry.requests.count, 0, "fermeture idempotente, aucune requête")
    }

    func testAbandonRevoqueLaSeuleSessionDeRecuperation() async throws {
        let g = gateway()
        try await ouvert(g)
        registry.add("POST", logout, respond: StubResponse(status: 204, headers: [:], body: Data(), failure: nil))
        try await g.signOutAfterRecovery()
        XCTAssertEqual(registry.requests(to: logout).first?.query("scope"), "local")
        let isolee = await g.sessionIsoleeOuverte
        XCTAssertFalse(isolee)
    }

    // MARK: - Tentatives (revue B8 sécurité de la vague D, m4)

    private func clientIsole() -> AuthClient {
        SupabaseRecoveryGateway.fabrique(url: TestClient.url, publishableKey: TestClient.publishableKey, session: Self.session)()
    }

    /// Un second lien ferme et révoque d'abord la session de récupération du premier (portée locale) avant de vérifier
    /// le sien : jamais deux sessions, jamais la session du premier compte sous le formulaire du second.
    func testNouveauLienRevoqueDAbordLaSessionEnCours() async throws {
        let g = gateway()
        try await ouvert(g)
        registry.add("POST", logout, respond: StubResponse(status: 204, headers: [:], body: Data(), failure: nil))
        registry.add("POST", verify, respond: .json(200, TestClient.sessionJSON()))
        let issue = try await g.openRecoverySession(.tokenHash(tokenHash: "AUTREHASH", otpType: "recovery"))
        XCTAssertEqual(issue, .sessionOuverte)
        let chemins = registry.requests.map(\.path)
        XCTAssertEqual(chemins.first, logout, "révocation avant la vérification du second lien")
        XCTAssertEqual(registry.requests(to: logout).first?.query("scope"), "local")
        XCTAssertEqual(registry.requests(to: verify).count, 1)
    }

    /// Délai dépassé puis fermeture par le modèle, ou lien plus récent : la vérification qui aboutit ensuite n'ouvre rien.
    func testTentativeAbandonneeNOuvreRien() async {
        let coffre = SupabaseRecoveryGateway.Coffre()
        let (premiere, aucun) = await coffre.nouvelleTentative()
        XCTAssertNil(aucun)
        _ = await coffre.fermer() // délai dépassé : `signOutAfterRecovery` du modèle
        let tardive = await coffre.ouvrir(clientIsole(), userId: UUID(), tentative: premiere)
        XCTAssertFalse(tardive, "vérification aboutie après la fermeture : refusée")
        let ouvertApresFermeture = await coffre.estOuvert
        XCTAssertFalse(ouvertApresFermeture)

        let (a, _) = await coffre.nouvelleTentative()
        let (b, _) = await coffre.nouvelleTentative() // second lien reçu pendant la vérification du premier
        let ouvertA = await coffre.ouvrir(clientIsole(), userId: UUID(), tentative: a)
        XCTAssertFalse(ouvertA, "le premier lien, dépassé par le second, n'ouvre rien")
        let ouvertB = await coffre.ouvrir(clientIsole(), userId: UUID(), tentative: b)
        XCTAssertTrue(ouvertB)
        let (_, precedent) = await coffre.nouvelleTentative()
        XCTAssertNotNil(precedent, "un troisième lien reçoit la session du second, à révoquer")
        let fermeApresTroisieme = await coffre.estOuvert
        XCTAssertFalse(fermeApresTroisieme)
    }

    func testFermetureEchoueeNeLaissePasLaSessionOuverte() async throws {
        let g = gateway()
        try await ouvert(g)
        registry.add("POST", logout, respond: .networkFailure())
        do { try await g.signOutAfterRecovery() } catch {}
        let isolee = await g.sessionIsoleeOuverte
        XCTAssertFalse(isolee, "client isolé jeté avant l'appel réseau")
    }

    func testRefusDeLaMiseAJourTraduitsEtSessionExpiree() async throws {
        let g = gateway()
        try await ouvert(g)
        registry.add("PUT", user, respond: refus(422, code: "weak_password", message: "Password should be at least 8 characters."))
        do {
            try await g.updatePassword("1234567a")
            XCTFail("refus attendu")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .invalidCredentials)
            XCTAssertEqual(erreur.message, "Mot de passe trop court : il doit contenir au moins 8 caractères.")
        }
        let toujours = await g.sessionIsoleeOuverte
        XCTAssertTrue(toujours, "un refus garde la quarantaine : l'utilisateur corrige ou abandonne")
        registry.reset()
        registry.add("PUT", user, respond: refus(401, code: "bad_jwt", message: "invalid JWT"))
        do {
            try await g.updatePassword(Self.nouveau)
            XCTFail("refus attendu")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
            XCTAssertEqual(erreur.message, ReinitialisationTextes.lienInvalideDetail)
        }
    }

    func testUtilisateurReluDifferentEstUneErreurDeContratJamaisUnSucces() async throws {
        let g = gateway()
        try await ouvert(g)
        registry.add("PUT", user, respond: .json(200, Self.utilisateurJSON(id: "7c1e9b2a-3d4f-4a5b-8c6d-9e0f1a2b3c4d")))
        do {
            try await g.updatePassword(Self.nouveau)
            XCTFail("aucun succès fabriqué")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .contract)
        }
    }

    // MARK: - Assemblage

    func testAssemblageSansFabriqueVerrouilleSansAucuneRequete() async throws {
        let gateways = SupabaseGateways.make(client: TestClient.make())
        XCTAssertTrue(gateways.recovery is SupabaseRecoveryGateway)
        XCTAssertFalse(gateways.unwiredPorts.contains("recovery"))
        do {
            try await gateways.recovery.requestReset(email: "a@example.test")
            XCTFail("verrou attendu")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .environment)
        }
        let issue = try? await gateways.recovery.openRecoverySession(.tokenHash(tokenHash: Self.hash, otpType: "recovery"))
        XCTAssertNil(issue)
        XCTAssertEqual(registry.requests.count, 0)
    }
}
