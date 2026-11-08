import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Changement de mot de passe sur GoTrue (lot 3, T11, D13), comme `ChangementMotDePasse.tsx` l.49-76 :
/// 1. l'ancien mot de passe est vérifié par `signIn` sur l'email de la session courante (un utilisateur
///    différent est un refus, jamais une modification) ;
/// 2. `update(user: UserAttributes(password:))` (PUT `/auth/v1/user`), une seule fois ;
/// refus GoTrue traduits comme `extraireMessageErreur` (textes web verbatim), réauthentification exigée
/// (« secure password change ») → refus verrouillé, session absente ou JWT refusé → session expirée.
/// Aucun mot de passe dans un message ; aucune requête hors contrat, aucun renvoi.
final class SupabaseMotDePasseGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let token = "/auth/v1/token"
    private let user = "/auth/v1/user"
    private static let ancien = ["ancien", "-", "mdp"].joined()
    private static let nouveau = ["Nouveau", "-mdp-", "2026"].joined()
    private static let autreUtilisateur = "7c1e9b2a-3d4f-4a5b-8c6d-9e0f1a2b3c4d"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    /// Client connecté (session GoTrue simulée) puis registre vidé : seules les requêtes du changement restent.
    private func connecte() async throws -> SupabaseClient {
        let client = TestClient.make()
        registry.add("POST", token, respond: .json(200, TestClient.sessionJSON()))
        _ = try await SupabaseAuthGateway(client: client).signIn(email: TestClient.email, password: "motdepasse-test")
        registry.reset()
        return client
    }

    private static var utilisateurJSON: String {
        """
        {"id":"\(TestClient.userId)","aud":"authenticated","role":"authenticated","email":"\(TestClient.email)",
         "email_confirmed_at":"2026-01-15T10:00:00Z","app_metadata":{"provider":"email","providers":["email"]},
         "user_metadata":{},"identities":[],"created_at":"2026-01-10T09:00:00Z","updated_at":"2026-11-08T10:00:00Z",
         "is_anonymous":false}
        """
    }

    private static let versionAPI = ["X-Supabase-Api-Version": "2024-01-01"]

    private func refus(_ status: Int, code: String, message: String, extra: String = "") -> StubResponse {
        .json(status, #"{"code":"\#(code)","error_code":"\#(code)","msg":"\#(message)"\#(extra)}"#, headers: Self.versionAPI)
    }

    private func changer(_ client: SupabaseClient) async throws -> ResultatMotDePasse {
        try await SupabaseMotDePasseGateway(client: client).changer(ancien: Self.ancien, nouveau: Self.nouveau, context: TestClient.context)
    }

    // MARK: - Succès

    func testAncienVerifieSurLEmailDeLaSessionPuisMotDePasseMisAJour() async throws {
        let client = try await connecte()
        registry.add("POST", token, respond: .json(200, TestClient.sessionJSON()))
        registry.add("PUT", user, respond: .json(200, Self.utilisateurJSON))

        let issue = try await changer(client)

        XCTAssertEqual(issue, .modifie)
        let verification = try XCTUnwrap(registry.requests(to: token).first)
        XCTAssertEqual(registry.requests(to: token).count, 1)
        XCTAssertEqual(verification.query("grant_type"), "password")
        let corps = try XCTUnwrap(verification.bodyJSON as? [String: Any])
        XCTAssertEqual(corps["email"] as? String, TestClient.email, "email de la session courante")
        XCTAssertEqual(corps["password"] as? String, Self.ancien)
        let miseAJour = try XCTUnwrap(registry.requests(to: user).first)
        XCTAssertEqual(registry.requests(to: user).count, 1, "une seule mise à jour, aucun renvoi")
        let corpsMiseAJour = try XCTUnwrap(miseAJour.bodyJSON as? [String: Any])
        XCTAssertEqual(corpsMiseAJour["password"] as? String, Self.nouveau)
        XCTAssertNil(corpsMiseAJour["email"], "seul le mot de passe change")
        XCTAssertNil(corpsMiseAJour["nonce"])
        let jeton = try XCTUnwrap(client.auth.currentSession?.accessToken)
        XCTAssertEqual(miseAJour.header("Authorization"), "Bearer \(jeton)")
        XCTAssertTrue(registry.unmatched.isEmpty, "requêtes hors contrat : \(registry.unmatched.map(\.path))")
        XCTAssertEqual(client.auth.currentSession?.user.id.uuidString.lowercased(), TestClient.userId, "même utilisateur")
    }

    // MARK: - Ancien mot de passe

    func testAncienIncorrectSansMiseAJour() async throws {
        let client = try await connecte()
        registry.add("POST", token, respond: refus(400, code: "invalid_credentials", message: "Invalid login credentials"))
        let issue = try await changer(client)
        XCTAssertEqual(issue, .ancienIncorrect, "« Ancien mot de passe incorrect. » (l.57-58)")
        XCTAssertTrue(registry.requests(to: user).isEmpty, "aucune mise à jour sans ancien vérifié")
        XCTAssertNotNil(client.auth.currentSession, "la session courante est conservée")
    }

    func testVerificationRefuseeAutrementTraduiteCommeLeWeb() async throws {
        let client = try await connecte()
        registry.add("POST", token, respond: refus(429, code: "over_request_rate_limit", message: "Request rate limit reached"))
        let issue = try await changer(client)
        XCTAssertEqual(issue, .refuse(message: "Une erreur est survenue. Veuillez réessayer."), "extraireMessageErreur (erreurs.ts l.532)")
        XCTAssertTrue(registry.requests(to: user).isEmpty)
    }

    func testUtilisateurDifferentRefuseSansMiseAJour() async throws {
        let client = try await connecte()
        let autre = TestClient.sessionJSON().replacingOccurrences(of: TestClient.userId, with: Self.autreUtilisateur)
        registry.add("POST", token, respond: .json(200, autre))
        let issue = try await changer(client)
        XCTAssertEqual(issue, .refuse(message: MotDePasse.Textes.erreurGenerique))
        XCTAssertTrue(registry.requests(to: user).isEmpty, "jamais la mise à jour d'un autre compte")
    }

    func testSansSessionAucuneRequete() async throws {
        let client = TestClient.make()
        do {
            _ = try await changer(client)
            XCTFail("session absente : refus attendu")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        }
        XCTAssertTrue(registry.requests.isEmpty)
    }

    func testContexteDUneAutreIdentiteAucuneRequete() async throws {
        let client = try await connecte()
        let contexte = MissionReadContext(userId: Self.autreUtilisateur, email: TestClient.email, profile: TestClient.profile)
        do {
            _ = try await SupabaseMotDePasseGateway(client: client).changer(ancien: Self.ancien, nouveau: Self.nouveau, context: contexte)
            XCTFail("identité changée : refus attendu")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        }
        XCTAssertTrue(registry.requests.isEmpty, "la session courante n'est pas celle de l'écran")
    }

    // MARK: - Mise à jour

    func testReauthentificationExigeeRefusVerrouille() async throws {
        for code in ["reauthentication_needed", "reauthentication_not_valid"] {
            registry.reset()
            let client = try await connecte()
            registry.add("POST", token, respond: .json(200, TestClient.sessionJSON()))
            registry.add("PUT", user, respond: refus(400, code: code, message: "Password update requires reauthentication"))
            let issue = try await changer(client)
            XCTAssertEqual(issue, .reauthentificationRequise, code)
            XCTAssertEqual(registry.requests(to: user).count, 1, "aucun flux OTP ni renvoi (D13)")
        }
    }

    func testRefusDeLaMiseAJourTraduitsCommeExtraireMessageErreur() async throws {
        let cas: [(StubResponse, String)] = [
            (refus(422, code: "same_password", message: "New password should be different from the old password."),
             "Une erreur est survenue. Veuillez réessayer."),
            (refus(422, code: "weak_password", message: "Password is known to be weak and easy to guess, please choose a different one.",
                   extra: #","weak_password":{"reasons":["pwned"]}"#),
             "Mot de passe trop faible. Utilisez au moins 8 caractères avec majuscules, minuscules, chiffres et caractères spéciaux."),
            (refus(422, code: "weak_password", message: "Password should contain at least one character of each: abc.",
                   extra: #","weak_password":{"reasons":["characters"]}"#),
             "Mot de passe trop faible : ajoutez majuscules, minuscules, chiffres et caractères spéciaux (8+ caractères)."),
            (refus(422, code: "weak_password", message: "Password should be at least 6 characters.",
                   extra: #","weak_password":{"reasons":["length"]}"#),
             "Mot de passe trop court : il doit contenir au moins 8 caractères."),
        ]
        for (reponse, attendu) in cas {
            registry.reset()
            let client = try await connecte()
            registry.add("POST", token, respond: .json(200, TestClient.sessionJSON()))
            registry.add("PUT", user, respond: reponse)
            let issue = try await changer(client)
            XCTAssertEqual(issue, .refuse(message: attendu))
            XCTAssertEqual(registry.requests(to: user).count, 1)
            if case .refuse(let message) = issue {
                XCTAssertFalse(message.contains(Self.nouveau) || message.contains(Self.ancien), "aucun mot de passe dans un message")
            }
        }
    }

    func testJetonRefuseALaMiseAJourEstUneSessionExpiree() async throws {
        let client = try await connecte()
        registry.add("POST", token, respond: .json(200, TestClient.sessionJSON()))
        registry.add("PUT", user, respond: refus(403, code: "bad_jwt", message: "invalid JWT"))
        do {
            _ = try await changer(client)
            XCTFail("403 : session expirée attendue")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        }
    }

    func testCoupureReseauALaMiseAJourLeveUneErreurReseau() async throws {
        let client = try await connecte()
        registry.add("POST", token, respond: .json(200, TestClient.sessionJSON()))
        registry.add("PUT", user, respond: .networkFailure())
        do {
            _ = try await changer(client)
            XCTFail("coupure : erreur attendue (issue inconnue, jamais un succès)")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .network)
        }
        XCTAssertEqual(registry.requests(to: user).count, 1, "aucun renvoi automatique")
    }
}
