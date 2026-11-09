import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Gateway d'inscription (lot 3, T7 ; fiche `fn_demarrer_inscription` de `CONTRATS_RPC_SOIGNANT.md`, définition du
/// dump `public.sql` l.30148-30189) : `signUp` sans captcha avec l'intention en métadonnées, compte existant détecté
/// comme le web, refus GoTrue traduits, confirmation en trois formats, contexte relu, parcours sous RLS, exceptions
/// métier de `fn_demarrer_inscription` restituées avant `SupabaseErrorMapping`. Une seule requête par appel, aucun
/// renvoi.
final class SupabaseInscriptionGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let signup = "/auth/v1/signup"
    private let verify = "/auth/v1/verify"
    private let token = "/auth/v1/token"
    private let user = "/auth/v1/user"
    private let parcoursTable = "/rest/v1/parcours_inscription"
    private let demarrage = "/rest/v1/rpc/fn_demarrer_inscription"
    private let intention = InscriptionRules.intention(profession: "IDE", cgu: true)
    /// Mot de passe de test assemblé (aucun secret).
    private let motDePasse = ["mot", "de", "passe", "8"].joined(separator: "-")

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway(_ client: SupabaseClient = TestClient.make()) -> SupabaseInscriptionGateway {
        SupabaseInscriptionGateway(client: client)
    }

    /// Utilisateur GoTrue (`/user`, `signUp` sans session) ; `identities` absent par défaut.
    private func userJSON(email: String = "nouveau@example.invalid", identities: String? = nil, metadata: String = "{}",
                          confirme: Bool = true) -> String {
        let identitiesField = identities.map { #","identities":\#($0)"# } ?? ""
        let confirmed = confirme ? #""email_confirmed_at":"2026-11-02T10:00:00Z","# : ""
        return """
        {"id":"\(TestClient.userId)","aud":"authenticated","role":"authenticated","email":"\(email)",\(confirmed)
         "app_metadata":{"provider":"email","providers":["email"]},"user_metadata":\(metadata),
         "created_at":"2026-11-02T09:00:00Z","updated_at":"2026-11-02T10:00:00Z","is_anonymous":false\(identitiesField)}
        """
    }

    /// Ligne `parcours_inscription` (`to_jsonb`), colonnes de la table l.71014-71023.
    private func ligneParcours(userId: String = TestClient.userId) -> String {
        """
        {"user_id":"\(userId)","type_compte":"SOIGNANT","donnees":{"profession":"IDE"},
         "consentement_cgu_le":"2026-11-02T10:00:00+00:00","consentement_cgv_le":null,
         "cree_le":"2026-11-02T10:00:00+00:00","modifie_le":"2026-11-02T10:00:00+00:00"}
        """
    }

    private func connecte() async throws -> SupabaseClient {
        let client = TestClient.make()
        registry.add("POST", token, where: { $0.query("grant_type") == "password" }, respond: .json(200, TestClient.sessionJSON(role: nil)))
        _ = try await client.auth.signIn(email: TestClient.email, password: motDePasse)
        return client
    }

    /// Format d'erreur GoTrue de l'API `2024-01-01` (en-tête envoyé par le SDK) : `{code, message}` et en-tête de version.
    private static let versionAPI = ["X-Supabase-Api-Version": "2024-01-01"]

    private func goTrue(_ statut: Int, _ code: String, _ message: String) -> StubResponse {
        .json(statut, #"{"code":"\#(code)","message":"\#(message)"}"#, headers: Self.versionAPI)
    }

    private func corps(_ path: String) throws -> NSDictionary {
        let requete = try XCTUnwrap(registry.requests(to: path).first, "aucun appel à \(path)")
        return try XCTUnwrap(requete.bodyJSON as? NSDictionary)
    }

    func testNomsDuContrat() {
        XCTAssertEqual(SupabaseInscriptionGateway.demarrageRPC, "fn_demarrer_inscription")
        XCTAssertEqual(SupabaseInscriptionGateway.tableParcours, "parcours_inscription")
        XCTAssertEqual(SupabaseInscriptionGateway.exceptionsDemarrage, ["22023", "23505"])
    }

    // MARK: - Création du compte (`signUp`)

    func testSignUpSansSessionEnvoieLIntentionEtLaRedirectionPuisAnnonceLaConfirmation() async throws {
        registry.add("POST", signup, respond: .json(200, userJSON(confirme: false)))
        let resultat = try await gateway().creerCompte(email: " Nouveau@Example.Invalid ", motDePasse: motDePasse, intention: intention)
        XCTAssertEqual(resultat, .confirmationEnvoyee)
        let requete = try XCTUnwrap(registry.requests(to: signup).first)
        XCTAssertEqual(requete.query("redirect_to"), "https://jolene.app/inscription/confirmer")
        let corps = try self.corps(signup)
        XCTAssertEqual(corps["email"] as? String, "nouveau@example.invalid", "adresse normalisée comme le web")
        XCTAssertEqual(corps["password"] as? String, motDePasse)
        let data = try XCTUnwrap(corps["data"] as? NSDictionary)
        XCTAssertEqual(data["inscription_progressive"] as? NSDictionary,
                       ["type": "SOIGNANT", "profession": "IDE", "nom": "", "cgu": true, "cgv": false] as NSDictionary)
        XCTAssertNil(corps["gotrue_meta_security"], "aucun jeton captcha (TURNSTILE_REQUIRED faux en natif)")
        XCTAssertEqual(registry.requests.count, 1)
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testSignUpAvecSessionOuvreLaSession() async throws {
        registry.add("POST", signup, respond: .json(200, TestClient.sessionJSON(role: nil)))
        let client = TestClient.make()
        let resultat = try await gateway(client).creerCompte(email: TestClient.email, motDePasse: motDePasse, intention: intention)
        XCTAssertEqual(resultat, .sessionOuverte)
        XCTAssertNotNil(client.auth.currentSession, "session posée par le SDK")
    }

    func testCompteExistantDetecteParIdentitesVidesOuMessageGoTrue() async throws {
        registry.add("POST", signup, respond: .json(200, userJSON(identities: "[]", confirme: false)))
        let masque = try await gateway().creerCompte(email: "a@b.c", motDePasse: motDePasse, intention: intention)
        XCTAssertEqual(masque, .connexionRequise)
        registry.reset()
        registry.add("POST", signup, respond: goTrue(422, "user_already_exists", "User already registered"))
        let existant = try await gateway().creerCompte(email: "a@b.c", motDePasse: motDePasse, intention: intention)
        XCTAssertEqual(existant, .connexionRequise)
        XCTAssertEqual(registry.requests(to: signup).count, 1)
    }

    func testSessionDejaOuvertePourLaMemeAdresseSansSecondSignUp() async throws {
        let client = try await connecte()
        let resultat = try await gateway(client).creerCompte(email: TestClient.email.uppercased(), motDePasse: motDePasse,
                                                             intention: intention)
        XCTAssertEqual(resultat, .sessionOuverte)
        XCTAssertTrue(registry.requests(to: signup).isEmpty, "creerCompteRapide l.56-62")
    }

    func testRefusCaptchaEtMotDePasseFaibleTraduitsSansRenvoi() async {
        let cas: [(Int, String, String?, String)] = [
            (400, #"{"code":"captcha_failed","message":"captcha protection: request disallowed (invalid-input-response)"}"#,
             RefusInscription.codeCaptcha, InscriptionTextes.erreurInattendue),
            (422, #"{"code":"weak_password","message":"Password should contain at least one character of each","weak_password":{"reasons":["characters"]}}"#,
             "WEAK_PASSWORD", InscriptionTextes.motDePasseDivulgue),
            (429, #"{"code":"over_email_send_rate_limit","message":"email rate limit exceeded"}"#,
             "EMAIL_RATE_LIMIT", InscriptionTextes.tropDeTentatives),
        ]
        for (statut, corps, code, message) in cas {
            registry.reset()
            registry.add("POST", signup, respond: .json(statut, corps, headers: Self.versionAPI))
            do {
                _ = try await gateway().creerCompte(email: "a@b.c", motDePasse: motDePasse, intention: intention)
                XCTFail("refus attendu (\(statut))")
            } catch let refus as RefusInscription {
                XCTAssertEqual(refus.code, code, corps)
                XCTAssertEqual(refus.message, message, corps)
            } catch {
                XCTFail("erreur non traduite : \(error)")
            }
            XCTAssertEqual(registry.requests(to: signup).count, 1, "une seule requête, aucun renvoi")
        }
    }

    func testCoupureReseauEstUneErreurReseau() async {
        registry.add("POST", signup, respond: .networkFailure())
        do {
            _ = try await gateway().creerCompte(email: "a@b.c", motDePasse: motDePasse, intention: intention)
            XCTFail("erreur réseau attendue")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .network)
        } catch {
            XCTFail("erreur non traduite : \(error)")
        }
    }

    // MARK: - Confirmation (D10)

    func testTokenHashVerifieAvecSonTypePuisSessionOuverte() async throws {
        for (type, attendu) in [("signup", "signup"), ("email", "email")] {
            registry.reset()
            registry.add("POST", verify, respond: .json(200, TestClient.sessionJSON(role: nil)))
            let client = TestClient.make()
            let resultat = try await gateway(client).confirmer(.tokenHash(tokenHash: "hash-test", otpType: type))
            XCTAssertEqual(resultat, .sessionOuverte)
            let corps = try self.corps(verify)
            XCTAssertEqual(corps["token_hash"] as? String, "hash-test")
            XCTAssertEqual(corps["type"] as? String, attendu)
            XCTAssertNotNil(client.auth.currentSession)
        }
    }

    func testTypeRecoveryRefuseSansAppelReseau() async throws {
        let resultat = try await gateway().confirmer(.tokenHash(tokenHash: "hash-test", otpType: "recovery"))
        XCTAssertEqual(resultat, .lienRefuse(message: InscriptionTextes.lienNonValide))
        XCTAssertTrue(registry.requests.isEmpty, "un lien de reset n'est jamais consommé par l'inscription")
    }

    func testLienExpireRendLeTexteWeb() async throws {
        registry.add("POST", verify, respond: goTrue(403, "otp_expired", "Email link is invalid or has expired"))
        let resultat = try await gateway().confirmer(.tokenHash(tokenHash: "hash-test", otpType: "signup"))
        XCTAssertEqual(resultat, .lienRefuse(message: InscriptionTextes.lienNonValide))
        XCTAssertEqual(registry.requests(to: verify).count, 1)
    }

    func testCodePKCEEchangeUneFois() async throws {
        registry.add("POST", token, where: { $0.query("grant_type") == "pkce" }, respond: .json(200, TestClient.sessionJSON(role: nil)))
        let resultat = try await gateway().confirmer(.pkce(code: "code-test"))
        XCTAssertEqual(resultat, .sessionOuverte)
        let corps = try self.corps(token)
        XCTAssertEqual(corps["auth_code"] as? String, "code-test")
        XCTAssertEqual(registry.requests(to: token).count, 1)
    }

    func testCodePKCERefuseRendLeTexteWeb() async throws {
        registry.add("POST", token, respond: goTrue(400, "flow_state_not_found", "invalid flow state, no valid flow state found"))
        let resultat = try await gateway().confirmer(.pkce(code: "code-test"))
        XCTAssertEqual(resultat, .lienRefuse(message: InscriptionTextes.lienNonValide))
    }

    func testImplicitPoseLaSessionApresRelectureDeLUtilisateur() async throws {
        registry.add("GET", user, respond: .json(200, userJSON()))
        let client = TestClient.make()
        let jeton = TestClient.accessToken(expiresAt: Date().timeIntervalSince1970 + 3600)
        let resultat = try await gateway(client).confirmer(.implicit(accessToken: jeton, refreshToken: "refresh-test"))
        XCTAssertEqual(resultat, .sessionOuverte)
        XCTAssertEqual(registry.requests(to: user).first?.header("Authorization"), "Bearer \(jeton)")
        XCTAssertNotNil(client.auth.currentSession)
    }

    // MARK: - Contexte et parcours

    func testContexteSansSessionNAppelleRien() async throws {
        let contexte = try await gateway().contexte()
        XCTAssertNil(contexte)
        XCTAssertTrue(registry.requests.isEmpty)
    }

    func testContexteRelitLUtilisateurEtSonIntention() async throws {
        let client = try await connecte()
        registry.add("GET", user, respond: .json(200, userJSON(metadata:
            #"{"inscription_progressive":{"type":"SOIGNANT","profession":"AS","nom":"","cgu":true,"cgv":false}}"#)))
        let contexteLu = try await gateway(client).contexte()
        let contexte = try XCTUnwrap(contexteLu)
        XCTAssertEqual(contexte.userId, TestClient.userId)
        XCTAssertEqual(contexte.email, "nouveau@example.invalid")
        XCTAssertTrue(contexte.emailConfirme)
        XCTAssertEqual(contexte.intention, InscriptionRules.intention(profession: "AS", cgu: true))
    }

    func testContexteSansIntentionValide() async throws {
        let client = try await connecte()
        registry.add("GET", user, respond: .json(200, userJSON(metadata:
            #"{"inscription_progressive":{"type":"SOIGNANT","profession":"AS","cgu":false}}"#)))
        let contexteLu = try await gateway(client).contexte()
        let contexte = try XCTUnwrap(contexteLu)
        XCTAssertNil(contexte.intention, "intention sans cgu:true ignorée")
    }

    func testParcoursLuSousRLSAvecLesColonnesDuContrat() async throws {
        let client = try await connecte()
        registry.add("GET", parcoursTable, respond: .json(200, "[\(ligneParcours())]"))
        let parcoursLu = try await gateway(client).parcours(userId: TestClient.userId)
        let parcours = try XCTUnwrap(parcoursLu)
        XCTAssertEqual(parcours.typeCompte, "SOIGNANT")
        XCTAssertEqual(parcours.brouillon.profession, "IDE")
        let requete = try XCTUnwrap(registry.requests(to: parcoursTable).first)
        XCTAssertEqual(requete.query("select"), "user_id,type_compte,donnees,consentement_cgu_le,modifie_le")
        XCTAssertEqual(requete.query("user_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(requete.query("limit"), "1")
    }

    func testParcoursAbsentOuDUnAutreUtilisateur() async throws {
        let client = try await connecte()
        registry.add("GET", parcoursTable, respond: .json(200, "[]"))
        let absent = try await gateway(client).parcours(userId: TestClient.userId)
        XCTAssertNil(absent)
        registry.reset()
        registry.add("GET", parcoursTable, respond: .json(200, "[\(ligneParcours(userId: "autre"))]"))
        do {
            _ = try await gateway(client).parcours(userId: TestClient.userId)
            XCTFail("ligne d'un autre utilisateur : erreur attendue")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .contract)
        }
    }

    // MARK: - `fn_demarrer_inscription`

    func testDemarrageEnvoieLIntentionEtRelitLaLigne() async throws {
        let client = try await connecte()
        registry.add("POST", demarrage, respond: .json(200, ligneParcours()))
        let parcours = try await gateway(client).demarrer(intention: intention)
        XCTAssertEqual(parcours.userId, TestClient.userId)
        XCTAssertEqual(parcours.consentementCguLe, "2026-11-02T10:00:00+00:00")
        let corps = try self.corps(demarrage)
        XCTAssertEqual(corps["p_type_compte"] as? String, "SOIGNANT")
        XCTAssertEqual(corps["p_profession"] as? String, "IDE")
        XCTAssertTrue(corps["p_nom"] is NSNull, "`input.nom || null`")
        XCTAssertEqual(corps["p_cgu"] as? Bool, true)
        XCTAssertEqual(corps["p_cgv"] as? Bool, false)
        XCTAssertEqual(registry.requests(to: demarrage).count, 1)
    }

    func testExceptionsMetierDuDemarrageRestitueesAvantLeMapping() async throws {
        let client = try await connecte()
        // Statuts PostgREST : 22xxx → 400, 23505 → 409.
        let cas: [(Int, String, String, String)] = [
            (400, #"{"code":"22023","message":"Choisissez votre profession.","details":null,"hint":null}"#,
             "SQLSTATE_22023", "Choisissez votre profession."),
            (409, #"{"code":"23505","message":"ACCOUNT_ALREADY_REGISTERED","details":null,"hint":null}"#,
             "SQLSTATE_23505", InscriptionTextes.compteDejaEspace),
            (409, #"{"code":"23505","message":"ACCOUNT_REGISTRATION_IN_PROGRESS","details":null,"hint":null}"#,
             "SQLSTATE_23505", InscriptionTextes.erreurInattendue),
        ]
        for (statut, corps, code, message) in cas {
            registry.reset()
            registry.add("POST", demarrage, respond: .json(statut, corps))
            do {
                _ = try await gateway(client).demarrer(intention: intention)
                XCTFail("refus attendu")
            } catch let refus as RefusInscription {
                XCTAssertEqual(refus, RefusInscription(code: code, message: message), corps)
            } catch {
                XCTFail("erreur non restituée : \(error)")
            }
            XCTAssertEqual(registry.requests(to: demarrage).count, 1)
        }
    }

    func testSessionInvalideEtFonctionIntrouvableGardentLeMappingDuLot1() async throws {
        let client = try await connecte()
        registry.add("POST", demarrage, respond: .json(403, #"{"code":"42501","message":"Session invalide.","details":null,"hint":null}"#))
        do {
            _ = try await gateway(client).demarrer(intention: intention)
            XCTFail("session expirée attendue")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        }
        registry.reset()
        registry.add("POST", demarrage, respond: .json(404, #"{"code":"PGRST202","message":"Could not find the function","details":null,"hint":null}"#))
        do {
            _ = try await gateway(client).demarrer(intention: intention)
            XCTFail("contrat attendu")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .contract)
        }
    }

    func testDemarrageSansSessionRefuseSansAppel() async {
        do {
            _ = try await gateway().demarrer(intention: intention)
            XCTFail("session absente : refus attendu")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        } catch {
            XCTFail("erreur inattendue : \(error)")
        }
        XCTAssertTrue(registry.requests.isEmpty)
    }

    // MARK: - Complétion (T8)

    func testCompletionRefuseeJusquATrancheT8() async {
        let attendu = UnwiredPorts.erreur(port: "complétion de l'inscription", tranche: "T8", lot: 3)
        let g = gateway()
        // Intégration du lot 3 (T7 × T9) : complétion déclarée non livrée (édition du profil sans « Réessayer la
        // vérification » des modes) ; T8 passe ce drapeau à `true` avec ses appels.
        XCTAssertFalse(g.completionLivree)
        let operations: [() async throws -> Void] = [
            { _ = try await g.enregistrerBrouillon(FormulaireInscription(prenom: "Léa")) },
            { _ = try await g.typesExercice(profession: "IDE") },
            { _ = try await g.finaliser(FormulaireInscription(prenom: "Léa")) },
        ]
        for operation in operations {
            do {
                try await operation()
                XCTFail("refus T8 attendu")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur, attendu)
            } catch {
                XCTFail("erreur inattendue : \(error)")
            }
        }
        XCTAssertTrue(registry.requests.isEmpty)
    }
}
