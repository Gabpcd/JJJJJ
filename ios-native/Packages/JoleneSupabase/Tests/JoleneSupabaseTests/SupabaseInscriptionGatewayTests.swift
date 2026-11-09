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

    private let brouillonRPC = "/rest/v1/rpc/fn_enregistrer_parcours_inscription"
    private let typesRPC = "/rest/v1/rpc/fn_types_exercice_autorises"
    private let edge = "/functions/v1/register-soignant"

    private static let formulaire = FormulaireInscription(prenom: "Léa", nom: "Martin", telephone: "", dateNaissance: "1990-05-14",
                                                          profession: "IDE", typesContrat: ["CDD", "LIBERAL"], rpps: "", rayon: nil)

    /// Ligne `parcours_inscription` relue après la fusion du brouillon ; `extra` : clés supplémentaires de `donnees`
    /// (déclaration étudiant du web, revue B8 de T8, B1).
    private func ligneBrouillon(userId: String = TestClient.userId, extra: String = "") -> String {
        """
        {"user_id":"\(userId)","type_compte":"SOIGNANT",
         "donnees":{"profession":"IDE","prenom":"Léa","nom":"Martin","telephone":"","dateNaissance":"1990-05-14","typesContrat":["CDD","LIBERAL"],"rpps":""\(extra)},
         "consentement_cgu_le":"2026-11-02T10:00:00+00:00","consentement_cgv_le":null,
         "cree_le":"2026-11-02T10:00:00+00:00","modifie_le":"2026-11-09T10:00:00+00:00"}
        """
    }

    /// Réponse d'erreur partagée des edges (`_shared/errors.ts` l.34-46 : `error` miroir de `message`).
    private func erreurEdge(_ statut: Int, _ code: String, _ message: String) -> StubResponse {
        .json(statut, #"{"ok":false,"code":"\#(code)","message":"\#(message)","error":"\#(message)"}"#)
    }

    private func stubRefresh(_ reponse: StubResponse) {
        registry.add("POST", token, where: { $0.query("grant_type") == "refresh_token" }, respond: reponse)
    }

    private func appelsRefresh() -> [RecordedRequest] {
        registry.requests(to: token).filter { $0.query("grant_type") == "refresh_token" }
    }

    func testNomsDuContratDeLaCompletion() {
        XCTAssertEqual(SupabaseInscriptionGateway.brouillonRPC, "fn_enregistrer_parcours_inscription")
        XCTAssertEqual(SupabaseInscriptionGateway.typesExerciceRPC, "fn_types_exercice_autorises")
        XCTAssertEqual(SupabaseInscriptionGateway.finalisationEdge, "register-soignant")
        XCTAssertEqual(SupabaseInscriptionGateway.exceptionsBrouillon, ["22023", "P0002"])
        // Intégration du lot 3 (T7 × T9) : T8 livre la complétion, « Réessayer la vérification » des modes d'exercice
        // devient effectif dans l'édition du profil.
        XCTAssertTrue(gateway().completionLivree)
    }

    func testBrouillonEnvoieLaListeBlancheEtRelitLaLigne() async throws {
        let client = try await connecte()
        registry.add("POST", brouillonRPC, respond: .json(200, ligneBrouillon()))
        let parcours = try await gateway(client).enregistrerBrouillon(Self.formulaire)
        XCTAssertEqual(parcours.userId, TestClient.userId)
        XCTAssertEqual(parcours.brouillon.prenom, "Léa")
        XCTAssertEqual(parcours.brouillon.typesContrat, ["CDD", "LIBERAL"])
        XCTAssertEqual(parcours.modifieLe, "2026-11-09T10:00:00+00:00")
        let corps = try self.corps(brouillonRPC)
        XCTAssertEqual(corps.allKeys as? [String], ["p_donnees"])
        let donnees = try XCTUnwrap(corps["p_donnees"] as? NSDictionary)
        XCTAssertEqual(Set(donnees.allKeys as? [String] ?? []), ["prenom", "nom", "telephone", "dateNaissance", "typesContrat", "rpps"])
        XCTAssertTrue(Set(donnees.allKeys as? [String] ?? []).isSubset(of: CompletionRules.clesBrouillon))
        XCTAssertNil(donnees["profession"], "profession figée : jamais réécrite")
        XCTAssertNil(donnees["email"])
        XCTAssertEqual(donnees["typesContrat"] as? [String], ["CDD", "LIBERAL"])
        XCTAssertEqual(registry.requests(to: brouillonRPC).count, 1)
    }

    func testExceptionsDuBrouillonRestitueesAvantLeMapping() async throws {
        let client = try await connecte()
        let cas: [(String, String, String)] = [
            (#"{"code":"22023","message":"Champ non autorisé dans le brouillon.","details":null,"hint":null}"#,
             "SQLSTATE_22023", "Champ non autorisé dans le brouillon."),
            (#"{"code":"P0002","message":"Inscription introuvable.","details":null,"hint":null}"#,
             "SQLSTATE_P0002", "Inscription introuvable."),
        ]
        for (corps, code, message) in cas {
            registry.reset()
            registry.add("POST", brouillonRPC, respond: .json(400, corps))
            do {
                _ = try await gateway(client).enregistrerBrouillon(Self.formulaire)
                XCTFail("refus attendu")
            } catch let refus as RefusInscription {
                XCTAssertEqual(refus, RefusInscription(code: code, message: message), "message serveur verbatim")
            } catch {
                XCTFail("exception non restituée : \(error)")
            }
            XCTAssertEqual(registry.requests(to: brouillonRPC).count, 1)
        }
        registry.reset()
        registry.add("POST", brouillonRPC, respond: .json(403, #"{"code":"42501","message":"Session invalide.","details":null,"hint":null}"#))
        do {
            _ = try await gateway(client).enregistrerBrouillon(Self.formulaire)
            XCTFail("session expirée attendue")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .unauthorized)
        }
    }

    func testBrouillonDUnAutreUtilisateurOuSansSessionRefuse() async throws {
        let client = try await connecte()
        registry.add("POST", brouillonRPC, respond: .json(200, ligneBrouillon(userId: "autre")))
        do {
            _ = try await gateway(client).enregistrerBrouillon(Self.formulaire)
            XCTFail("ligne d'un autre utilisateur : contrat attendu")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .contract)
        }
        registry.reset()
        do {
            _ = try await gateway().enregistrerBrouillon(Self.formulaire)
            XCTFail("session absente : refus attendu")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur, JoleneError(.unauthorized, CompletionTextes.sessionAbsente))
        }
        XCTAssertTrue(registry.requests.isEmpty, "aucun appel sans session")
    }

    func testReferentielDesModesTableauDeChainesSinonIndisponible() async throws {
        let client = try await connecte()
        registry.add("POST", typesRPC, respond: .json(200, #"["SALARIE"]"#))
        let types = try await gateway(client).typesExercice(profession: "AS")
        XCTAssertEqual(types, ["SALARIE"])
        let corps = try self.corps(typesRPC)
        XCTAssertEqual(corps, ["p_profession": "AS"] as NSDictionary)
        let requete = try XCTUnwrap(registry.requests(to: typesRPC).first)
        XCTAssertEqual(requete.header("Authorization"), "Bearer \(try XCTUnwrap(client.auth.currentSession?.accessToken))",
                       "appelé avec le JWT de la session d'inscription, jamais en anonyme")
        for illisible in [#"{"error":"x"}"#, #"[1,"LIBERAL"]"#, #""SALARIE""#, "null"] {
            registry.reset()
            registry.add("POST", typesRPC, respond: .json(200, illisible))
            let lu = try await gateway(client).typesExercice(profession: "IDE")
            XCTAssertNil(lu, "\(illisible) : référentiel indisponible, jamais supposé")
        }
        registry.reset()
        registry.add("POST", typesRPC, respond: .networkFailure())
        do {
            _ = try await gateway(client).typesExercice(profession: "IDE")
            XCTFail("erreur de transport attendue")
        } catch let erreur as JoleneError {
            XCTAssertEqual(erreur.kind, .network)
        }
    }

    func testFinalisationBrouillonPuisRegisterSoignantPuisRafraichissement() async throws {
        let client = try await connecte()
        let jeton = try XCTUnwrap(client.auth.currentSession?.accessToken)
        registry.add("POST", brouillonRPC, respond: .json(200, ligneBrouillon()))
        registry.add("POST", edge, respond: .json(200, #"{"ok":true,"success":true,"soignant_id":"\#(TestClient.userId)"}"#))
        stubRefresh(.json(200, TestClient.sessionJSON(role: "SOIGNANT")))
        let resultat = try await gateway(client).finaliser(Self.formulaire)
        XCTAssertEqual(resultat, .finalisee(soignantId: TestClient.userId))
        XCTAssertEqual(registry.requests.map(\.path), [token, brouillonRPC, edge, token],
                       "connexion du test, brouillon, register-soignant, puis refreshSession")
        let appel = try XCTUnwrap(registry.requests(to: edge).first)
        XCTAssertEqual(appel.method, "POST")
        XCTAssertEqual(appel.header("Authorization"), "Bearer \(jeton)", "Bearer de la session, jamais la clé publishable")
        let corps = try XCTUnwrap(appel.bodyJSON as? NSDictionary)
        XCTAssertEqual(Set(corps.allKeys as? [String] ?? []),
                       ["prenom", "nom", "telephone", "dateNaissance", "profession", "typesContrat", "rpps"])
        XCTAssertEqual(corps["profession"] as? String, "IDE")
        XCTAssertTrue(corps["telephone"] is NSNull, "`form.telephone || null`")
        XCTAssertTrue(corps["rpps"] is NSNull, "`form.rpps || null`")
        XCTAssertNil(corps["est_etudiant"], "parcours étudiant en renvoi web (D11)")
        XCTAssertNil(corps["rayon"], "aucun rayon par défaut côté app (serveur : 30 km)")
        XCTAssertEqual(appelsRefresh().count, 1)
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    /// Refus certains : message serveur verbatim, aucune relecture. Les issues inconnues (5xx, 409 d'un profil possible,
    /// corps illisible) ont leur propre test (revue B8 de T8, M1 : ce test les épinglait à tort en refus certains).
    func testChaqueRefusDeRegisterSoignantRendSonMessageVerbatimSansRafraichissement() async throws {
        let client = try await connecte()
        let cas: [(Int, String, String)] = [
            (400, "UNDERAGE", "Vous devez avoir au moins 18 ans pour vous inscrire."),
            (400, "RPPS_FORMAT_INVALID", "Le numéro RPPS est obligatoire pour votre profession (11 chiffres)."),
            (400, "RPPS_TRAITS_MISMATCH", "Les informations saisies (nom, prénom) ne correspondent pas au numéro RPPS."),
            (409, "RPPS_ALREADY_REGISTERED", "Ce numéro RPPS est déjà associé à un compte Jolene. Connectez-vous à ce compte, ou contactez le support si ce n'est pas vous."),
            (409, "ACCOUNT_TYPE_MISMATCH", "Ce compte est déjà associé à un autre espace Jolene. Utilisez une autre adresse ou contactez le support."),
            (429, "RATE_LIMITED", "Trop de tentatives. Réessayez dans quelques minutes."),
        ]
        for (statut, code, message) in cas {
            registry.reset()
            registry.add("POST", brouillonRPC, respond: .json(200, ligneBrouillon()))
            registry.add("POST", edge, respond: erreurEdge(statut, code, message))
            let resultat = try await gateway(client).finaliser(Self.formulaire)
            XCTAssertEqual(resultat, .refusee(code: code, message: message), "\(statut) \(code)")
            XCTAssertEqual(registry.requests(to: edge).count, 1, "aucun renvoi")
            XCTAssertTrue(appelsRefresh().isEmpty, "refus : aucune session rafraîchie")
        }
    }

    /// Revue B8 de T8, M1 : un 5xx (corps de passerelle illisible, délai de l'edge, `INTERNAL_ERROR` du `catch` final qui
    /// peut suivre l'INSERT) et un 409 qui dit le profil créé ou en cours de création ne sont jamais des refus certains :
    /// `.indeterminee` (relecture du rôle par le modèle), message serveur verbatim en repli, sinon le repli du web l.224.
    func testIssuesInconnuesDeRegisterSoignantRendentUneIssueIndeterminee() async throws {
        let client = try await connecte()
        let lisibles: [(Int, String, String)] = [
            (409, "ACCOUNT_ALREADY_REGISTERED", "Ce compte soignant existe déjà. Connectez-vous pour continuer."),
            (409, "ACCOUNT_REGISTRATION_IN_PROGRESS", "Une inscription est déjà en cours pour ce compte. Patientez quelques instants puis réessayez."),
            (409, "USER_ALREADY_REGISTERED", "Un compte existe déjà avec cet email. Connectez-vous ou utilisez une autre adresse."),
            (503, "ACCOUNT_RESERVATION_UNAVAILABLE", "Inscription momentanément indisponible. Réessayez dans quelques minutes."),
            (500, "INTERNAL_ERROR", "Erreur serveur. Notre équipe a été notifiée. Réessayez dans quelques minutes."),
        ]
        for (statut, code, message) in lisibles {
            registry.reset()
            registry.add("POST", brouillonRPC, respond: .json(200, ligneBrouillon()))
            registry.add("POST", edge, respond: erreurEdge(statut, code, message))
            let resultat = try await gateway(client).finaliser(Self.formulaire)
            XCTAssertEqual(resultat, .indeterminee(message: message), "\(statut) \(code)")
            XCTAssertEqual(registry.requests(to: edge).count, 1, "aucun renvoi")
            XCTAssertTrue(appelsRefresh().isEmpty)
        }
        // Corps illisibles (page de passerelle, délai, corps vide) : repli du web l.224, jamais un refus certain.
        for illisible: StubResponse in [.json(502, "<html>Bad gateway</html>"), .json(504, ""), .json(500, "upstream timeout"),
                                        .json(200, "<html>portail captif</html>")] {
            registry.reset()
            registry.add("POST", brouillonRPC, respond: .json(200, ligneBrouillon()))
            registry.add("POST", edge, respond: illisible)
            let resultat = try await gateway(client).finaliser(Self.formulaire)
            XCTAssertEqual(resultat, .indeterminee(message: CompletionTextes.saisieConservee))
            XCTAssertTrue(appelsRefresh().isEmpty)
        }
    }

    /// Revue B8 de T8, B1 : la déclaration étudiant du web (`estEtudiant: true`) relue dans le brouillon fusionné par le
    /// serveur verrouille la finalisation native : `register-soignant` n'est jamais appelée (elle écrirait
    /// `est_etudiant = false`, index.ts l.309). Toute autre valeur (`"true"`, `false`) n'est pas une déclaration.
    func testBrouillonEtudiantNEstJamaisFinaliseEnNatif() async throws {
        let client = try await connecte()
        registry.add("POST", brouillonRPC,
                     respond: .json(200, ligneBrouillon(extra: #","estEtudiant":true,"scolariteFormation":"IFSI","scolariteAnnee":"1""#)))
        let resultat = try await gateway(client).finaliser(Self.formulaire)
        XCTAssertEqual(resultat, .parcoursEtudiant)
        XCTAssertTrue(registry.requests(to: edge).isEmpty, "verrou D11 : register-soignant jamais appelée")
        XCTAssertTrue(appelsRefresh().isEmpty)
        let donnees = try XCTUnwrap(try corps(brouillonRPC)["p_donnees"] as? NSDictionary)
        XCTAssertNil(donnees["estEtudiant"], "la déclaration n'est jamais réécrite par le natif")
        for nonDeclare in [#","estEtudiant":"true""#, #","estEtudiant":false"#] {
            registry.reset()
            registry.add("POST", brouillonRPC, respond: .json(200, ligneBrouillon(extra: nonDeclare)))
            registry.add("POST", edge, respond: .json(200, #"{"ok":true,"success":true,"soignant_id":"\#(TestClient.userId)"}"#))
            stubRefresh(.json(200, TestClient.sessionJSON(role: "SOIGNANT")))
            let fini = try await gateway(client).finaliser(Self.formulaire)
            XCTAssertEqual(fini, .finalisee(soignantId: TestClient.userId), nonDeclare)
        }
    }

    /// Revue B8 de T8, m4 : la réponse « salarié(e) » part dans le brouillon (liste blanche serveur), jamais vers
    /// `register-soignant`.
    func testReponseSalarieDansLeBrouillonJamaisDansRegisterSoignant() async throws {
        let client = try await connecte()
        registry.add("POST", brouillonRPC, respond: .json(200, ligneBrouillon(extra: #","estSalarieEtablissement":true"#)))
        registry.add("POST", edge, respond: .json(200, #"{"ok":true,"success":true,"soignant_id":"\#(TestClient.userId)"}"#))
        stubRefresh(.json(200, TestClient.sessionJSON(role: "SOIGNANT")))
        var formulaire = Self.formulaire
        formulaire.estSalarieEtablissement = true
        _ = try await gateway(client).finaliser(formulaire)
        let donnees = try XCTUnwrap(try corps(brouillonRPC)["p_donnees"] as? NSDictionary)
        XCTAssertEqual(donnees["estSalarieEtablissement"] as? Bool, true)
        let edgeCorps = try corps(edge)
        XCTAssertNil(edgeCorps["estSalarieEtablissement"])
        XCTAssertNil(edgeCorps["est_etudiant"])
    }

    /// Revue B8 de T8, m1 : le Bearer de `register-soignant` est celui d'une session valide (`auth.session`, rafraîchie si
    /// expirée, comme `SupabaseAccountGateway`), jamais un `currentSession` périmé. Le brouillon (PostgREST) rafraîchit
    /// déjà la session juste avant : ce test épingle le Bearer frais, indépendamment de cet effet de bord.
    func testBearerDeRegisterSoignantPrisDUneSessionValide() async throws {
        let client = TestClient.make()
        let expire = TestClient.sessionJSON(expiresAt: Date().timeIntervalSince1970 - 60, role: nil)
        registry.add("POST", token, where: { $0.query("grant_type") == "password" }, respond: .json(200, expire))
        _ = try await client.auth.signIn(email: TestClient.email, password: motDePasse)
        let ancien = try XCTUnwrap(client.auth.currentSession?.accessToken)
        let frais = TestClient.sessionJSON(expiresAt: Date().timeIntervalSince1970 + 3600, role: nil)
        stubRefresh(.json(200, frais))
        registry.add("POST", brouillonRPC, respond: .json(200, ligneBrouillon()))
        registry.add("POST", edge, respond: .json(200, #"{"ok":true,"success":true,"soignant_id":"\#(TestClient.userId)"}"#))
        _ = try await gateway(client).finaliser(Self.formulaire)
        let appel = try XCTUnwrap(registry.requests(to: edge).first)
        XCTAssertNotEqual(appel.header("Authorization"), "Bearer \(ancien)", "jamais le jeton expiré")
        XCTAssertTrue(appel.header("Authorization")?.hasPrefix("Bearer ") == true)
        let rafraichi = try XCTUnwrap(registry.requests(to: brouillonRPC).first?.header("Authorization"))
        XCTAssertEqual(appel.header("Authorization"), rafraichi, "même session valide que le brouillon")
    }

    func testFinalisationEnAttenteDemandeLaDeconnexionLocale() async throws {
        let client = try await connecte()
        registry.add("POST", brouillonRPC, respond: .json(200, ligneBrouillon()))
        registry.add("POST", edge, respond: erreurEdge(503, "ACCOUNT_FINALIZATION_PENDING",
                                                       "Votre profil est enregistré. Reconnectez-vous pour reprendre votre espace."))
        let resultat = try await gateway(client).finaliser(Self.formulaire)
        XCTAssertEqual(resultat, .finalisationEnAttente(message: "Votre profil est enregistré. Reconnectez-vous pour reprendre votre espace."))
        XCTAssertTrue(appelsRefresh().isEmpty)
    }

    func testSessionRefuseeParLEdgeEstUneSessionExpiree() async throws {
        let client = try await connecte()
        for (code, message) in [("INVALID_TOKEN", "Session invalide. Reconnectez-vous et réessayez."),
                                ("ACCOUNT_AUTH_INACTIVE", "Ce compte est déjà associé à un autre espace Jolene. Utilisez une autre adresse ou contactez le support.")] {
            registry.reset()
            registry.add("POST", brouillonRPC, respond: .json(200, ligneBrouillon()))
            registry.add("POST", edge, respond: erreurEdge(401, code, message))
            do {
                _ = try await gateway(client).finaliser(Self.formulaire)
                XCTFail("401 : session expirée attendue")
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.kind, .unauthorized, code)
            }
        }
    }

    func testSucces2xxSansDrapeauOuSansIdentifiantEstUneErreurDeContrat() async throws {
        let client = try await connecte()
        for corps in ["{}", #"{"success":true}"#, #"{"ok":true,"soignant_id":""}"#, "[]"] {
            registry.reset()
            registry.add("POST", brouillonRPC, respond: .json(200, ligneBrouillon()))
            registry.add("POST", edge, respond: .json(200, corps))
            do {
                let resultat = try await gateway(client).finaliser(Self.formulaire)
                if corps == "[]" {
                    // Revue B8 de T8, M1 : un 2xx illisible n'est pas un refus certain (le profil a pu être créé).
                    XCTAssertEqual(resultat, .indeterminee(message: CompletionTextes.saisieConservee),
                                   "corps non objet : issue inconnue, jamais un succès")
                } else {
                    XCTFail("\(corps) : jamais un succès fabriqué (\(resultat))")
                }
            } catch let erreur as JoleneError {
                XCTAssertEqual(erreur.kind, .contract, corps)
            }
            XCTAssertTrue(appelsRefresh().isEmpty, corps)
        }
    }

    func testRafraichissementRefuseApresLeProfilCreeImposeLaReconnexion() async throws {
        let client = try await connecte()
        registry.add("POST", brouillonRPC, respond: .json(200, ligneBrouillon()))
        registry.add("POST", edge, respond: .json(200, #"{"ok":true,"success":true,"soignant_id":"\#(TestClient.userId)"}"#))
        stubRefresh(goTrue(400, "refresh_token_not_found", "Invalid Refresh Token: Refresh Token Not Found"))
        let resultat = try await gateway(client).finaliser(Self.formulaire)
        XCTAssertEqual(resultat, .finalisationEnAttente(message: CompletionTextes.profilEnregistreReconnecter),
                       "« Votre profil est enregistré. Reconnectez-vous pour ouvrir votre espace. » (web l.236)")
        XCTAssertEqual(appelsRefresh().count, 1)
    }

    func testBrouillonRefuseInterromptLaFinalisationSansAppelerLEdge() async throws {
        let client = try await connecte()
        registry.add("POST", brouillonRPC, respond: .json(400, #"{"code":"P0002","message":"Inscription introuvable.","details":null,"hint":null}"#))
        do {
            _ = try await gateway(client).finaliser(Self.formulaire)
            XCTFail("refus du brouillon attendu")
        } catch let refus as RefusInscription {
            XCTAssertEqual(refus.message, "Inscription introuvable.")
        }
        XCTAssertTrue(registry.requests(to: edge).isEmpty, "finaliserProfil : brouillon d'abord, edge jamais appelée après un refus")
    }
}
