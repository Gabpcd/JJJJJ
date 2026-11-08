import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Edge `delete-account` (lot 1, T8 ; Apple 5.1.1) — une réponse = un test, d'après la fiche
/// « Edge `delete-account` » de `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md` (elle-même confrontée à
/// `supabase/functions/delete-account/index.ts` et `verifyUserOrServiceRole` par la garde node).
/// Règle app : seul HTTP 200 `{success:true}` est un succès ; tout autre statut, ou un 200 sans
/// `success === true`, est un refus affiché verbatim (`.refused(code: error_code, message: error)`),
/// sans aucune nouvelle tentative automatique. Appel `POST`, corps `{}`, Bearer de la session courante.
final class SupabaseAccountGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let chemin = "/functions/v1/delete-account"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    /// Client connecté (session GoTrue simulée) : la suppression exige la session de l'utilisateur.
    private func connecte(storage: InMemoryAuthStorage = InMemoryAuthStorage()) async throws -> SupabaseClient {
        let client = TestClient.make(storage: storage)
        registry.add("POST", "/auth/v1/token", respond: .json(200, TestClient.sessionJSON()))
        _ = try await SupabaseAuthGateway(client: client).signIn(email: TestClient.email, password: "motdepasse-test")
        return client
    }

    private func appelsSuppression() -> [RecordedRequest] { registry.requests(to: chemin) }

    /// Une réponse simulée de l'edge → l'issue du port, avec un seul appel et aucune requête non prévue.
    private func issue(_ status: Int, _ corps: String, headers: [String: String] = [:],
                       file: StaticString = #filePath, line: UInt = #line) async throws -> DeleteAccountOutcome {
        registry.reset()
        let client = try await connecte()
        registry.add("POST", chemin, respond: .json(status, corps, headers: headers))
        let resultat = try await SupabaseAccountGateway(client: client).deleteAccount(context: TestClient.context)
        XCTAssertEqual(appelsSuppression().count, 1, "un seul appel, aucun renvoi automatique", file: file, line: line)
        XCTAssertTrue(registry.unmatched.isEmpty, "aucune requête hors contrat", file: file, line: line)
        return resultat
    }

    // MARK: - 200

    func test200SuccesEstLaSeulePreuveDeSuppression() async throws {
        let client = try await connecte()
        let jeton = try XCTUnwrap(client.auth.currentSession?.accessToken)
        registry.add("POST", chemin, respond: .json(200, """
        {"success":true,"auth_deleted":true,"anonymisation":{"success":true,"deja_anonymise":false}}
        """))

        let resultat = try await SupabaseAccountGateway(client: client).deleteAccount(context: TestClient.context)

        XCTAssertEqual(resultat, .deleted)
        let requete = try XCTUnwrap(appelsSuppression().first)
        XCTAssertEqual(appelsSuppression().count, 1)
        XCTAssertEqual(requete.method, "POST")
        XCTAssertEqual(requete.header("Authorization"), "Bearer \(jeton)", "Bearer de la session courante, jamais la clé publishable")
        XCTAssertEqual(requete.header("Content-Type"), "application/json")
        XCTAssertEqual(requete.header("X-Client-Info"), "jolene-ios/2.0.0")
        let corps = try XCTUnwrap(requete.bodyJSON as? [String: Any], "corps JSON attendu")
        XCTAssertTrue(corps.isEmpty, "corps `{}` comme le web (`body: {}`)")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func test200SansSuccesTrueEstUnRefus() async throws {
        let sansDrapeau = try await issue(200, #"{"auth_deleted":true}"#)
        XCTAssertEqual(sansDrapeau, .refused(code: nil, message: "Suppression impossible."), "SectionConfidentialite.tsx l.88-89")
        let faux = try await issue(200, #"{"success":false,"error":"Anonymisation non confirmée"}"#)
        XCTAssertEqual(faux, .refused(code: nil, message: "Anonymisation non confirmée"))
        let erreur = try await issue(200, #"{"success":true,"error":"Erreur interne"}"#)
        XCTAssertEqual(erreur, .refused(code: nil, message: "Erreur interne"), "`data?.error` prime, comme le web")
        let chaine = try await issue(200, #"{"success":"true"}"#)
        XCTAssertEqual(chaine, .refused(code: nil, message: "Suppression impossible."), "seul le booléen true vaut succès")
    }

    // MARK: - 401 / 403 / 405

    func test401JetonAbsentOuInvalideEstUnRefusVerbatim() async throws {
        for message in ["Authorization Bearer manquant", "Token invalide ou expiré"] {
            let resultat = try await issue(401, #"{"error":"\#(message)"}"#)
            XCTAssertEqual(resultat, .refused(code: nil, message: message))
        }
    }

    func test403CompteDesactiveServiceRoleOuAdministrateur() async throws {
        for message in ["Compte desactive", "Suppression self-service uniquement",
                        "Un compte administrateur doit etre retire par un autre administrateur"] {
            let resultat = try await issue(403, #"{"error":"\#(message)"}"#)
            XCTAssertEqual(resultat, .refused(code: nil, message: message))
        }
    }

    func test405MethodeNonAutorisee() async throws {
        let resultat = try await issue(405, #"{"error":"Methode non autorisee"}"#)
        XCTAssertEqual(resultat, .refused(code: nil, message: "Methode non autorisee"))
    }

    // MARK: - 409

    func test409ConflitsDeProfilEtDeResponsabilitesAvecLeurCode() async throws {
        let cas = [
            ("ACCOUNT_PROFILE_CONFLICT", "Votre compte nécessite une vérification manuelle avant suppression."),
            ("DERNIER_PROPRIETAIRE", "Transferez d'abord le role de proprietaire a un autre membre."),
            ("DERNIER_PROPRIETAIRE_GROUPE", "Transferez d'abord la propriete du groupe de sante."),
        ]
        for (code, message) in cas {
            let corps = try String(data: JSONSerialization.data(withJSONObject: ["error": message, "error_code": code]), encoding: .utf8) ?? ""
            let resultat = try await issue(409, corps)
            XCTAssertEqual(resultat, .refused(code: code, message: message))
        }
    }

    func test409ReponsesDeLAnonymisationRelayeesSansCode() async throws {
        let limite = try await issue(409, #"{"error":"Demande de suppression déjà en cours.","success":false}"#)
        XCTAssertEqual(limite, .refused(code: nil, message: "Demande de suppression déjà en cours."))
        let nonConfirmee = try await issue(409, #"{"success":false,"error":"Anonymisation non confirmée"}"#)
        XCTAssertEqual(nonConfirmee, .refused(code: nil, message: "Anonymisation non confirmée"))
        let postgrest = try await issue(409, #"{"error":"canceling statement due to statement timeout"}"#)
        XCTAssertEqual(postgrest, .refused(code: nil, message: "canceling statement due to statement timeout"),
                       "message PostgREST relayé par l'edge (l.137), verbatim")
    }

    // MARK: - 429 / 500 / 503

    func test429DemandeDejaEnCours() async throws {
        let resultat = try await issue(429, #"{"error":"Demande deja en cours"}"#)
        XCTAssertEqual(resultat, .refused(code: nil, message: "Demande deja en cours"))
    }

    func test500ErreursServeur() async throws {
        for message in ["Configuration serveur incomplète (SUPABASE_URL/ANON_KEY)", "Configuration serveur incomplete",
                        "Retrait des equipes impossible", "Retrait des groupes impossible", "Erreur interne"] {
            let resultat = try await issue(500, #"{"error":"\#(message)"}"#)
            XCTAssertEqual(resultat, .refused(code: nil, message: message))
        }
    }

    func test503VerificationsImpossiblesSansCode() async throws {
        for message in ["Verification du compte impossible", "Verification des responsabilites impossible",
                        "Verification des responsabilites groupe impossible"] {
            let resultat = try await issue(503, #"{"error":"\#(message)"}"#)
            XCTAssertEqual(resultat, .refused(code: nil, message: message))
            XCTAssertFalse(CompteSuppression.forceDeconnexion(code: nil), "rien n'a été modifié : la session reste")
        }
    }

    func test503CompteBanniOuAnonymiseAvecCodeDeDeconnexionForcee() async throws {
        let anonymisation = try await issue(503, """
        {"success":false,"auth_deleted":false,"error":"Anonymisation du profil non confirmée ; suppression Auth non effectuée.",
         "error_code":"ANONYMISATION_NON_CONFIRMEE"}
        """)
        XCTAssertEqual(anonymisation, .refused(code: "ANONYMISATION_NON_CONFIRMEE",
                                               message: "Anonymisation du profil non confirmée ; suppression Auth non effectuée."))
        let enAttente = try await issue(503, """
        {"error":"Compte bloque et anonymise; suppression Auth en cours de finalisation","error_code":"AUTH_DELETE_PENDING"}
        """)
        XCTAssertEqual(enAttente, .refused(code: "AUTH_DELETE_PENDING",
                                           message: "Compte bloque et anonymise; suppression Auth en cours de finalisation"))
        for case let .refused(code, _) in [anonymisation, enAttente] {
            XCTAssertTrue(CompteSuppression.forceDeconnexion(code: code), "compte banni ou anonymisé : déconnexion locale")
        }
    }

    // MARK: - Hors fonction

    func testCorpsNonJSONOuPasserelleEstUnRefusGenerique() async throws {
        let passerelle = try await issue(502, "<html>Bad Gateway</html>")
        XCTAssertEqual(passerelle, .refused(code: nil, message: "Suppression impossible."))
        let vide = try await issue(504, "")
        XCTAssertEqual(vide, .refused(code: nil, message: "Suppression impossible."))
        let relais = try await issue(200, #"{"success":true}"#, headers: ["x-relay-error": "true"])
        XCTAssertEqual(relais, .refused(code: nil, message: "Suppression impossible."),
                       "erreur de relais Supabase : jamais un succès, même avec un corps 200")
    }

    func testReseauIndisponibleEstUneErreurReseauSansRenvoi() async throws {
        let client = try await connecte()
        registry.add("POST", chemin, respond: .networkFailure())
        do {
            _ = try await SupabaseAccountGateway(client: client).deleteAccount(context: TestClient.context)
            XCTFail("attendu : erreur réseau")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .network)
        }
        XCTAssertEqual(appelsSuppression().count, 1)
    }

    // MARK: - Session

    func testSansSessionAucunAppelALEdge() async throws {
        let client = TestClient.make()
        do {
            _ = try await SupabaseAccountGateway(client: client).deleteAccount(context: TestClient.context)
            XCTFail("attendu : session absente")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .unauthorized)
        }
        XCTAssertTrue(appelsSuppression().isEmpty, "jamais d'appel sans Bearer utilisateur")
    }

    func testSessionDUnAutreUtilisateurQueLEcranAucunAppel() async throws {
        let client = try await connecte()
        let autreId = "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d"
        let autre = MissionReadContext(userId: autreId, email: "autre@example.test",
                                       profile: SoignantProfile(id: autreId, profession: "IDE"))
        do {
            _ = try await SupabaseAccountGateway(client: client).deleteAccount(context: autre)
            XCTFail("attendu : refus, la session ne correspond pas au compte affiché")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .unauthorized)
        }
        XCTAssertTrue(appelsSuppression().isEmpty, "jamais la suppression d'un autre compte que celui affiché")
    }

    func testContexteIncoherentRefuseAvantToutReseau() async throws {
        var incoherent = TestClient.context
        incoherent.profile.id = "autre"
        do {
            _ = try await SupabaseAccountGateway(client: TestClient.make()).deleteAccount(context: incoherent)
            XCTFail("profil désynchronisé")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .unauthorized)
        }
        XCTAssertTrue(registry.requests.isEmpty)
    }

    // MARK: - Purge locale (AuthPort.signOutLocally)

    func testSignOutLocallyRetireLaSessionAvecLePerimetreLocalEtTolereLeRefusServeur() async throws {
        let storage = InMemoryAuthStorage()
        let client = try await connecte(storage: storage)
        registry.add("POST", "/auth/v1/logout", respond: .json(403, #"{"code":403,"error_code":"session_not_found","msg":"x"}"#))
        let auth: AuthPort = SupabaseAuthGateway(client: client)

        await auth.signOutLocally()

        XCTAssertNil(client.auth.currentSession)
        XCTAssertTrue(storage.keys.isEmpty, "session retirée du stockage (Keychain en production)")
        let logout = try XCTUnwrap(registry.requests(to: "/auth/v1/logout").first)
        XCTAssertEqual(logout.query("scope"), "local", "jamais de révocation globale : l'edge a déjà révoqué les sessions")
    }

    func testSignOutLocallyTolereUnReseauCoupe() async throws {
        let storage = InMemoryAuthStorage()
        let client = try await connecte(storage: storage)
        registry.add("POST", "/auth/v1/logout", respond: .networkFailure())
        await SupabaseAuthGateway(client: client).signOutLocally()
        XCTAssertNil(client.auth.currentSession)
        XCTAssertTrue(storage.keys.isEmpty)
    }
}
