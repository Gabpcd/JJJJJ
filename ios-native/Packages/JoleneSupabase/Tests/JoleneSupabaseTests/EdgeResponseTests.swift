import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Décodeur commun des edge functions du lot 3 (blueprint `docs/mobile-swift/LOT3_PLAN.md` §2.4,
/// tranche T1). Formes réelles, d'après les fiches « Edge `register-soignant` », « Edge
/// `stripe-connect-status` » et « Edge `stripe-connect-onboard` » de `CONTRATS_RPC_SOIGNANT.md` :
/// `{ok:false, code, message, error, details?}` (`_shared/errors.ts`), `{error:'texte'}`
/// (`_shared/admin-auth.ts`), `{error:'CODE'}` et `{error:'CODE', message:'texte'}` (Stripe).
/// Règles : le corps de `FunctionsError.httpError` est lu avant tout mapping ; 401 → session
/// expirée quel que soit le corps (passerelle comprise) ; sinon refus structuré, texte serveur
/// verbatim ; corps illisible → `fallback` ; une seule requête, aucun renvoi.
final class EdgeResponseTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let fallback = "Impossible de traiter votre demande. Réessayez."
    private let fonction = "register-soignant"
    private var chemin: String { "/functions/v1/\(fonction)" }

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func invoquer(_ status: Int, _ corps: String, headers: [String: String] = [:],
                          file: StaticString = #filePath, line: UInt = #line) async throws -> EdgeResponse {
        registry.reset()
        registry.add("POST", chemin, respond: StubResponse(status: status, headers: headers.isEmpty ? ["Content-Type": "application/json"] : headers,
                                                           body: Data(corps.utf8), failure: nil))
        let reponse = try await EdgeResponse.invoquer(TestClient.make(), fonction,
                                                      options: FunctionInvokeOptions(method: .post, body: [String: String]()),
                                                      fallback: fallback)
        XCTAssertEqual(registry.requests(to: chemin).count, 1, "une seule requête, aucun renvoi", file: file, line: line)
        XCTAssertTrue(registry.unmatched.isEmpty, file: file, line: line)
        return reponse
    }

    private func refus(_ reponse: EdgeResponse, file: StaticString = #filePath, line: UInt = #line) throws -> RefusEdge {
        try XCTUnwrap(try reponse.refus(fallback: fallback), "attendu : refus", file: file, line: line)
    }

    // MARK: - 2xx

    func testSucces200() async throws {
        let r = try await invoquer(200, #"{"ok":true,"success":true,"soignant_id":"s-1"}"#)
        XCTAssertEqual(r.statut, 200)
        XCTAssertTrue(r.estSucces)
        XCTAssertFalse(r.estRefus)
        XCTAssertNil(try r.refus(fallback: fallback))
        XCTAssertEqual(r.string("soignant_id"), "s-1")
        XCTAssertEqual(r.ok, true)
        XCTAssertEqual(r.success, true)
    }

    func testSucces200SansDrapeauStripeConnectStatus() async throws {
        // `stripe-connect-status` répond sans `ok`/`success` : le statut HTTP et l'absence d'`error` suffisent,
        // la gateway exigeant ensuite ses propres clés (T14a).
        let r = try await invoquer(200, #"{"statut":"NON_DEMANDE","onboarding_complete":false,"charges_enabled":false,"payouts_enabled":false,"cached":false}"#)
        XCTAssertTrue(r.estSucces)
        XCTAssertEqual(r.string("statut"), "NON_DEMANDE")
        XCTAssertEqual(r.bool("onboarding_complete"), false)
    }

    func testRefusDansUn200() async throws {
        let drapeau = try await invoquer(200, #"{"success":false,"error":"Anonymisation non confirmée"}"#)
        XCTAssertEqual(try refus(drapeau), RefusEdge(statut: 200, code: nil, message: "Anonymisation non confirmée"))
        // Parité web `data?.error` : un `error` sans drapeau vrai est un refus, jamais un succès.
        let seul = try await invoquer(200, #"{"error":"Demande deja en cours"}"#)
        XCTAssertFalse(seul.estSucces)
        XCTAssertEqual(try refus(seul).message, "Demande deja en cours")
        let ok = try await invoquer(200, #"{"ok":false,"code":"RATE_LIMITED"}"#)
        XCTAssertEqual(try refus(ok), RefusEdge(statut: 200, code: "RATE_LIMITED", message: fallback))
    }

    // MARK: - `FunctionsError.httpError` : corps lu avant tout mapping

    func testHTTP400AvecCodeEtDetails() async throws {
        let message = "Champs obligatoires manquants (prénom, nom, profession)."
        let r = try await invoquer(400, """
        {"ok":false,"code":"MISSING_REQUIRED_FIELDS","message":"\(message)","error":"\(message)","details":{"champs_manquants":["prenom"]}}
        """)
        XCTAssertEqual(r.statut, 400)
        XCTAssertTrue(r.estRefus)
        XCTAssertEqual(try refus(r), RefusEdge(statut: 400, code: "MISSING_REQUIRED_FIELDS", message: message))
        XCTAssertEqual(r.details?["champs_manquants"]?.arrayValue?.compactMap(\.stringValue), ["prenom"])
    }

    func testHTTP400Mineur() async throws {
        let message = "Vous devez avoir au moins 18 ans pour vous inscrire."
        let r = try await invoquer(400, #"{"ok":false,"code":"UNDERAGE","message":"\#(message)","error":"\#(message)"}"#)
        XCTAssertEqual(try refus(r), RefusEdge(statut: 400, code: "UNDERAGE", message: message))
    }

    func testHTTP401EstUneSessionExpireeQuelQueSoitLeCorps() async throws {
        for corps in [#"{"ok":false,"code":"INVALID_TOKEN","message":"Session invalide. Reconnectez-vous et réessayez.","error":"Session invalide. Reconnectez-vous et réessayez."}"#,
                      #"{"error":"Non autorisé"}"#,
                      #"{"msg":"Invalid JWT"}"#,
                      "<html>401 Unauthorized</html>",
                      ""] {
            let r = try await invoquer(401, corps)
            XCTAssertTrue(r.estNonAutorise)
            XCTAssertThrowsError(try r.refus(fallback: fallback), corps) { error in
                XCTAssertEqual(error as? JoleneError, JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage), corps)
            }
        }
    }

    func testHTTP403CodeSeulDansErrorEtTexteSeul() async throws {
        let code = try await invoquer(403, #"{"error":"TEST_ACCOUNT_PAYMENT_DISABLED"}"#)
        XCTAssertEqual(try refus(code), RefusEdge(statut: 403, code: "TEST_ACCOUNT_PAYMENT_DISABLED", message: fallback),
                       "un code machine n'est jamais affiché tel quel")
        let origine = try await invoquer(403, #"{"error":"ORIGINE_NON_AUTORISEE"}"#)
        XCTAssertEqual(try refus(origine).code, "ORIGINE_NON_AUTORISEE")
        let texte = "Stripe Connect est réservé aux soignants en exercice libéral ou mixte"
        let r = try await invoquer(403, #"{"error":"\#(texte)"}"#)
        XCTAssertEqual(try refus(r), RefusEdge(statut: 403, code: nil, message: texte))
        let desactive = try await invoquer(403, #"{"error":"Compte desactive"}"#)
        XCTAssertEqual(try refus(desactive), RefusEdge(statut: 403, code: nil, message: "Compte desactive"))
    }

    func testHTTP409CodeEtMessageVerbatim() async throws {
        let message = "Ce numéro RPPS est déjà associé à un compte Jolene. Connectez-vous à ce compte, ou contactez le support si ce n'est pas vous."
        let r = try await invoquer(409, #"{"ok":false,"code":"RPPS_ALREADY_REGISTERED","message":"\#(message)","error":"\#(message)"}"#)
        XCTAssertEqual(try refus(r), RefusEdge(statut: 409, code: "RPPS_ALREADY_REGISTERED", message: message))
        // `delete-account` : `error` + `error_code` (lot 1, T8).
        let compte = try await invoquer(409, #"{"error":"Votre compte nécessite une vérification manuelle avant suppression.","error_code":"ACCOUNT_PROFILE_CONFLICT"}"#)
        XCTAssertEqual(try refus(compte), RefusEdge(statut: 409, code: "ACCOUNT_PROFILE_CONFLICT",
                                                    message: "Votre compte nécessite une vérification manuelle avant suppression."))
        XCTAssertEqual(compte.codeErreur, "ACCOUNT_PROFILE_CONFLICT")
        XCTAssertEqual(compte.erreur, "Votre compte nécessite une vérification manuelle avant suppression.")
    }

    func testHTTP429() async throws {
        let message = "Trop de tentatives. Réessayez dans quelques minutes."
        let r = try await invoquer(429, #"{"ok":false,"code":"RATE_LIMITED","message":"\#(message)","error":"\#(message)"}"#)
        XCTAssertEqual(try refus(r), RefusEdge(statut: 429, code: "RATE_LIMITED", message: message))
        let sansCode = try await invoquer(429, #"{"error":"Demande deja en cours"}"#)
        XCTAssertEqual(try refus(sansCode), RefusEdge(statut: 429, code: nil, message: "Demande deja en cours"))
    }

    func testHTTP503CodeDansErrorEtTexteDansMessage() async throws {
        let stripe = try await invoquer(503, #"{"error":"STRIPE_STATUS_UNAVAILABLE","message":"Statut de paiement temporairement indisponible."}"#)
        XCTAssertEqual(try refus(stripe), RefusEdge(statut: 503, code: "STRIPE_STATUS_UNAVAILABLE",
                                                   message: "Statut de paiement temporairement indisponible."))
        let message = "Votre profil est enregistré. Reconnectez-vous pour reprendre votre espace."
        let attente = try await invoquer(503, #"{"ok":false,"code":"ACCOUNT_FINALIZATION_PENDING","message":"\#(message)","error":"\#(message)"}"#)
        XCTAssertEqual(try refus(attente), RefusEdge(statut: 503, code: "ACCOUNT_FINALIZATION_PENDING", message: message))
        let configuration = try await invoquer(503, #"{"error":"Configuration serveur incomplete"}"#)
        XCTAssertEqual(try refus(configuration), RefusEdge(statut: 503, code: nil, message: "Configuration serveur incomplete"))
    }

    func testErreurStripeMappeeCodeMinusculeEtMessage() async throws {
        // `mapStripeError` : `code` Stripe brut (souvent en minuscules) dans `error`, texte dans `message`.
        let r = try await invoquer(400, #"{"error":"parameter_missing","message":"Requête Stripe invalide. Vérifiez les données envoyées."}"#)
        XCTAssertEqual(try refus(r), RefusEdge(statut: 400, code: "parameter_missing",
                                              message: "Requête Stripe invalide. Vérifiez les données envoyées."))
    }

    func testCorpsNonJSONOuVideRendLeFallback() async throws {
        for (status, corps) in [(502, "<html><body>Bad Gateway</body></html>"), (500, ""), (504, "upstream timeout"), (400, "[1,2]")] {
            let r = try await invoquer(status, corps, headers: ["Content-Type": "text/html"])
            XCTAssertEqual(try refus(r), RefusEdge(statut: status, code: nil, message: fallback), "\(status) \(corps)")
            XCTAssertNil(r.erreur)
        }
    }

    // MARK: - Transport

    func testOptionsTransmisesSansModification() async throws {
        registry.add("POST", "/functions/v1/stripe-connect-status", respond: .json(200, #"{"statut":"EN_COURS"}"#))
        let options = FunctionInvokeOptions(method: .post, query: [URLQueryItem(name: "force", value: "true")],
                                            headers: ["Origin": "https://jolene.app"])
        _ = try await EdgeResponse.invoquer(TestClient.make(), "stripe-connect-status", options: options, fallback: fallback)
        let requete = try XCTUnwrap(registry.requests(to: "/functions/v1/stripe-connect-status").first)
        XCTAssertEqual(requete.method, "POST")
        XCTAssertEqual(requete.query("force"), "true")
        XCTAssertEqual(requete.header("Origin"), "https://jolene.app")
    }

    func testRelaiSupabaseEnEchecEstUneErreurInconnueSansRenvoi() async throws {
        registry.add("POST", chemin, respond: .json(200, #"{"success":true}"#, headers: ["x-relay-error": "true"]))
        do {
            _ = try await EdgeResponse.invoquer(TestClient.make(), fonction, options: FunctionInvokeOptions(), fallback: fallback)
            XCTFail("attendu : erreur")
        } catch let error as JoleneError {
            XCTAssertEqual(error, JoleneError(.unknown, fallback), "un 200 relayé en erreur n'est jamais un succès")
        }
        XCTAssertEqual(registry.requests(to: chemin).count, 1)
    }

    func testReseauIndisponible() async throws {
        registry.add("POST", chemin, respond: .networkFailure())
        do {
            _ = try await EdgeResponse.invoquer(TestClient.make(), fonction, options: FunctionInvokeOptions(), fallback: fallback)
            XCTFail("attendu : erreur réseau")
        } catch let error as JoleneError {
            XCTAssertEqual(error.kind, .network)
        }
        XCTAssertEqual(registry.requests(to: chemin).count, 1)
    }

    // MARK: - Lecture tolérante

    func testLectureToleranteEtCodeMachine() {
        XCTAssertEqual(EdgeResponse.lire(Data("{\"a\":1}".utf8)), .object(["a": .integer(1)]))
        XCTAssertEqual(EdgeResponse.lire(Data()), .null)
        XCTAssertEqual(EdgeResponse.lire(Data("pas du json".utf8)), .null)
        for code in ["TEST_ACCOUNT_PAYMENT_DISABLED", "ORIGINE_NON_AUTORISEE", "STRIPE_NOT_CONFIGURED"] {
            XCTAssertTrue(EdgeResponse.estCodeMachine(code), code)
        }
        for texte in ["Non autorisé", "Compte desactive", "OK", "Soignant introuvable", "Erreur interne", ""] {
            XCTAssertFalse(EdgeResponse.estCodeMachine(texte), texte)
        }
        let vide = EdgeResponse(statut: 200, raw: .object(["error": .string("  "), "message": .string("")]))
        XCTAssertNil(vide.erreur)
        XCTAssertNil(vide.message)
        XCTAssertTrue(vide.estSucces, "un `error` vide n'est pas un refus")
    }
}
