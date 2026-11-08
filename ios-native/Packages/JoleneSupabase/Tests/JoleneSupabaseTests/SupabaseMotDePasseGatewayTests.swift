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

    private func changer(_ client: SupabaseClient, ancien: String = SupabaseMotDePasseGatewayTests.ancien,
                         nouveau: String = SupabaseMotDePasseGatewayTests.nouveau,
                         garde: @escaping @Sendable () async -> Bool) async throws -> ResultatMotDePasse {
        try await SupabaseMotDePasseGateway(client: client).changer(ancien: ancien, nouveau: nouveau, context: TestClient.context,
                                                                    identiteCourante: garde)
    }

    /// Rang de la requête en cours sur un chemin, partagé par les prédicats du transport (évalués dans l'ordre
    /// d'enregistrement, sous le verrou du registre).
    private final class Rang: @unchecked Sendable {
        private let verrou = NSLock()
        private var compte = 0
        private var courant = 0
        /// Nouvelle requête : son rang (1, 2…).
        func nouvelleRequete() -> Int { verrou.lock(); defer { verrou.unlock() }; compte += 1; courant = compte; return courant }
        var actuel: Int { verrou.lock(); defer { verrou.unlock() }; return courant }
    }

    /// Réponses successives d'un même chemin : la n-ième requête reçoit `reponses[n - 1]` (au-delà, aucune : la
    /// requête est hors contrat). Le premier prédicat, consulté le premier pour chaque requête, fixe son rang.
    private func enSequence(_ methode: String, _ chemin: String, _ reponses: [StubResponse]) {
        let rang = Rang()
        for (index, reponse) in reponses.enumerated() {
            registry.add(methode, chemin, where: { _ in
                (index == 0 ? rang.nouvelleRequete() : rang.actuel) == index + 1
            }, respond: reponse)
        }
    }

    private static let logout = "/auth/v1/logout"
    private static let deconnexionAcceptee = StubResponse(status: 204, headers: [:], body: Data(), failure: nil)

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
        // `same_password` n'est plus dans cette table (revue B8, m1) : avec un ancien vérifié et un nouveau distinct,
        // il prouve que le mot de passe vaut déjà le nouveau (tests « Rejeu » ci-dessous) ; avec un nouveau égal à
        // l'ancien, il reste le refus générique du web (`testSamePasswordAvecUnNouveauEgalALAncienResteUnRefus`).
        let cas: [(StubResponse, String)] = [
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
        // La gateway n'appelle `update(user:)` qu'une fois ; le transport du client d'authentification de supabase-swift
        // 2.55.5 (`RetryRequestInterceptor`, `Auth/Internal/APIClient.swift` l.11-16 : PUT et POST, `retryLimit` 2) rejoue
        // UNE fois la même requête sur une erreur réseau transitoire ou un 408/5xx. Le rejeu porte le même corps (aucune
        // nouvelle mutation), puis l'issue reste inconnue : jamais un succès.
        let envois = registry.requests(to: user)
        XCTAssertEqual(envois.count, 2, "un appel de la gateway, rejoué une fois par le SDK")
        XCTAssertEqual(Set(envois.compactMap { $0.body }).count, 1, "rejeu à l'identique, aucune autre valeur envoyée")
    }

    // MARK: - Rejeu du SDK et issue inconnue (revue B8, m1)

    private static let refusMemeMotDePasse = "New password should be different from the old password."

    func testRejeuDUnPUTAboutiSamePasswordAvecUnNouveauDistinctEstUnSucces() async throws {
        // Premier PUT parvenu au serveur, réponse perdue (coupure) ; le rejeu du SDK reçoit `same_password`. L'ancien
        // vient d'être vérifié et le nouveau en diffère : le mot de passe vaut donc déjà le nouveau.
        let client = try await connecte()
        registry.add("POST", token, respond: .json(200, TestClient.sessionJSON()))
        enSequence("PUT", user, [.networkFailure(.networkConnectionLost),
                                 refus(422, code: "same_password", message: Self.refusMemeMotDePasse)])
        let issue = try await changer(client)
        XCTAssertEqual(issue, .modifie, "rejeu d'un PUT abouti : jamais « Une erreur est survenue »")
        let envois = registry.requests(to: user)
        XCTAssertEqual(envois.count, 2, "un appel de la gateway, rejoué une fois par le SDK")
        XCTAssertEqual(Set(envois.compactMap { $0.body }).count, 1, "rejeu à l'identique")
        XCTAssertTrue(registry.unmatched.isEmpty, "requêtes hors contrat : \(registry.unmatched.map(\.path))")
    }

    func testSamePasswordAvecUnNouveauDistinctSansRejeuEstUnSucces() async throws {
        // Même preuve sans rejeu (le mot de passe a été changé entre la vérification et la mise à jour) : le
        // mot de passe vaut le nouveau.
        let client = try await connecte()
        registry.add("POST", token, respond: .json(200, TestClient.sessionJSON()))
        registry.add("PUT", user, respond: refus(422, code: "same_password", message: Self.refusMemeMotDePasse))
        XCTAssertEqual(try await changer(client), .modifie)
        XCTAssertEqual(registry.requests(to: user).count, 1)
    }

    func testSamePasswordAvecUnNouveauEgalALAncienResteUnRefus() async throws {
        // Nouveau égal à l'ancien, octet pour octet : vrai refus, texte web d'`extraireMessageErreur` (l.532).
        let client = try await connecte()
        registry.add("POST", token, respond: .json(200, TestClient.sessionJSON()))
        registry.add("PUT", user, respond: refus(422, code: "same_password", message: Self.refusMemeMotDePasse))
        let issue = try await changer(client, ancien: Self.nouveau, nouveau: Self.nouveau, garde: { true })
        XCTAssertEqual(issue, .refuse(message: "Une erreur est survenue. Veuillez réessayer."))
    }

    func testSamePasswordAvecLesMemes72PremiersOctetsResteUnRefus() async throws {
        // bcrypt (GoTrue) ne lit que les 72 premiers octets : deux mots de passe qui les partagent ne prouvent rien.
        let prefixe = String(repeating: "é", count: 36) // 72 octets UTF-8
        XCTAssertEqual(prefixe.utf8.count, 72)
        let client = try await connecte()
        registry.add("POST", token, respond: .json(200, TestClient.sessionJSON()))
        registry.add("PUT", user, respond: refus(422, code: "same_password", message: Self.refusMemeMotDePasse))
        let issue = try await changer(client, ancien: prefixe + "A1!", nouveau: prefixe + "B2?", garde: { true })
        XCTAssertEqual(issue, .refuse(message: "Une erreur est survenue. Veuillez réessayer."))
    }

    func testSamePasswordFormesNFCEtNFDDistinctesEstUnSucces() async throws {
        // « é » NFC et NFD : égales pour `String`, distinctes pour GoTrue (octets) ; la comparaison est octet par octet.
        let client = try await connecte()
        registry.add("POST", token, respond: .json(200, TestClient.sessionJSON()))
        registry.add("PUT", user, respond: refus(422, code: "same_password", message: Self.refusMemeMotDePasse))
        let issue = try await changer(client, ancien: "Mdp-2026-\u{E9}", nouveau: "Mdp-2026-e\u{301}", garde: { true })
        XCTAssertEqual(issue, .modifie)
    }

    func testErreurServeurOuDelaiALaMiseAJourEstUneIssueInconnue() async throws {
        // 5xx ou 408 sur le PUT (après le rejeu du SDK) : le serveur a pu enregistrer le changement, jamais un refus.
        let cas: [StubResponse] = [
            refus(500, code: "unexpected_failure", message: "Internal Server Error"),
            refus(503, code: "unexpected_failure", message: "Service Unavailable"),
            refus(408, code: "request_timeout", message: "Processing this request timed out, please retry after a moment."),
        ]
        for reponse in cas {
            registry.reset()
            let client = try await connecte()
            registry.add("POST", token, respond: .json(200, TestClient.sessionJSON()))
            registry.add("PUT", user, respond: reponse)
            do {
                let issue = try await changer(client)
                XCTFail("\(reponse.status) : issue inconnue attendue, obtenu \(issue)")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.kind, .unknown, "\(reponse.status)")
                XCTAssertEqual(erreur.message, MotDePasse.Textes.confirmationIndisponible, "\(reponse.status)")
            }
            XCTAssertEqual(registry.requests(to: user).count, 2, "\(reponse.status) : rejoué une fois par le SDK")
        }
    }

    func testErreurServeurALaVerificationResteUnRefusSansMiseAJour() async throws {
        // Avant toute mise à jour, rien n'a changé : le refus générique du web reste juste.
        let client = try await connecte()
        registry.add("POST", token, respond: refus(500, code: "unexpected_failure", message: "Internal Server Error"))
        XCTAssertEqual(try await changer(client), .refuse(message: "Une erreur est survenue. Veuillez réessayer."))
        XCTAssertTrue(registry.requests(to: user).isEmpty)
    }

    // MARK: - Garde d'identité entre la vérification et la mise à jour (revue B8, m2)

    /// Relevés pris par une garde (nombre de vérifications et de mises à jour déjà parties).
    private final class Releves: @unchecked Sendable {
        private let verrou = NSLock()
        private var valeurs: [[Int]] = []
        func noter(_ valeur: [Int]) { verrou.lock(); defer { verrou.unlock() }; valeurs.append(valeur) }
        var tous: [[Int]] { verrou.lock(); defer { verrou.unlock() }; return valeurs }
    }

    func testGardeConsulteeApresLaVerificationEtAvantLaMiseAJour() async throws {
        let client = try await connecte()
        registry.add("POST", token, respond: .json(200, TestClient.sessionJSON()))
        registry.add("PUT", user, respond: .json(200, Self.utilisateurJSON))
        let registre = registry
        let (chemins, releves) = ((token, user), Releves())
        let issue = try await changer(client, garde: {
            releves.noter([registre.requests(to: chemins.0).count, registre.requests(to: chemins.1).count])
            return true
        })
        XCTAssertEqual(issue, .modifie)
        XCTAssertEqual(releves.tous, [[1, 0]], "une consultation, après la vérification et avant la mise à jour")
    }

    func testGardeNonConsulteeSansAncienVerifie() async throws {
        let client = try await connecte()
        registry.add("POST", token, respond: refus(400, code: "invalid_credentials", message: "Invalid login credentials"))
        let releves = Releves()
        let issue = try await changer(client, garde: { releves.noter([0]); return true })
        XCTAssertEqual(issue, .ancienIncorrect)
        XCTAssertTrue(releves.tous.isEmpty)
    }

    func testIdentitePartieApresLaVerificationAucuneMiseAJourSessionRecreeeRetiree() async throws {
        // `.signedOut` (révocation, refresh refusé) arrivé pendant le `signIn` de vérification : l'app affiche la
        // connexion, mais le `signIn` a recréé une session dans le SDK. Aucune mise à jour ; cette session est retirée.
        let client = try await connecte()
        let expiration = Date().timeIntervalSince1970 + 7200
        registry.add("POST", token, respond: .json(200, TestClient.sessionJSON(expiresAt: expiration)))
        registry.add("POST", Self.logout, respond: Self.deconnexionAcceptee)
        registry.add("PUT", user, respond: .json(200, Self.utilisateurJSON))
        do {
            let issue = try await changer(client, garde: { false })
            XCTFail("identité partie : aucune issue attendue, obtenu \(issue)")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .cancelled)
        }
        XCTAssertTrue(registry.requests(to: user).isEmpty, "aucune mise à jour pour une identité partie")
        let deconnexions = registry.requests(to: Self.logout)
        XCTAssertEqual(deconnexions.count, 1)
        XCTAssertEqual(deconnexions.first?.query("scope"), "local", "seule la session recréée est retirée, jamais une déconnexion globale")
        XCTAssertEqual(deconnexions.first?.header("Authorization"), "Bearer \(TestClient.accessToken(expiresAt: expiration))",
                       "le jeton retiré est celui de la vérification")
        XCTAssertNil(client.auth.currentSession, "aucune session laissée au SDK pendant que l'app affiche la connexion")
        XCTAssertTrue(registry.unmatched.isEmpty, "requêtes hors contrat : \(registry.unmatched.map(\.path))")
    }

    func testIdentiteRemplaceeApresLaVerificationLaSessionSuivanteEstConservee() async throws {
        // Une connexion arrivée après la vérification (autre jeton) n'est jamais retirée par la gateway.
        let client = try await connecte()
        let maintenant = Date().timeIntervalSince1970
        let (expirationVerification, expirationSuivante) = (maintenant + 7200, maintenant + 10_800)
        let suivante = ["sui", "vante"].joined()
        registry.add("POST", token, where: { ($0.bodyJSON as? [String: Any])?["password"] as? String == suivante },
                     respond: .json(200, TestClient.sessionJSON(expiresAt: expirationSuivante)))
        registry.add("POST", token, respond: .json(200, TestClient.sessionJSON(expiresAt: expirationVerification)))
        registry.add("POST", Self.logout, respond: Self.deconnexionAcceptee)
        do {
            _ = try await changer(client, garde: {
                _ = try? await SupabaseAuthGateway(client: client).signIn(email: TestClient.email, password: suivante)
                return false
            })
            XCTFail("identité remplacée : aucune issue attendue")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .cancelled)
        }
        XCTAssertTrue(registry.requests(to: user).isEmpty)
        XCTAssertTrue(registry.requests(to: Self.logout).isEmpty, "la session de la connexion suivante n'est pas retirée")
        XCTAssertEqual(client.auth.currentSession?.accessToken, TestClient.accessToken(expiresAt: expirationSuivante))
    }
}
