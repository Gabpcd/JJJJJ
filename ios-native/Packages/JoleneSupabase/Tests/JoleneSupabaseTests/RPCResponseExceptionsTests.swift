import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Exceptions métier des RPC du lot 3 (blueprint `docs/mobile-swift/LOT3_PLAN.md` §2.4, corrections
/// 12 et 16, tranche T1). `fn_demarrer_inscription`, `fn_enregistrer_parcours_inscription` et
/// `fn_upsert_token_push` signalent leurs refus par `RAISE EXCEPTION` (HTTP 4xx/5xx PostgREST), jamais
/// en jsonb HTTP 200 ; `SupabaseErrorMapping` les réduirait au message générique. L'appelant déclare
/// les SQLSTATE métier de SA RPC (`exceptionsMetier`) : ils sont restitués en refus structuré
/// `{success:false, ok:false, code:"SQLSTATE_<code>", error:<message brut>}` (forme partagée avec le
/// lot 2), dans l'ordre `[CODE DU TRAVAIL]` → exceptions métier → `SupabaseErrorMapping` ; tout le
/// reste garde le comportement du lot 1. Statuts HTTP des stubs = ceux de PostgREST pour chaque
/// SQLSTATE (22023, 23514, P0001 → 400 ; 23505 → 409 ; 42501 → 403 ; autres P0… → 500).
final class RPCResponseExceptionsTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let fallback = "Impossible de traiter votre demande. Réessayez."
    private let demarrer = "/rest/v1/rpc/fn_demarrer_inscription"
    private let brouillon = "/rest/v1/rpc/fn_enregistrer_parcours_inscription"
    private let upsert = "/rest/v1/rpc/fn_upsert_token_push"
    /// RPC du lot 2 qui déclare 42501 comme métier (blueprint du lot 2 §2.4) : forme partagée du helper.
    private let scanner = "/rest/v1/rpc/fn_scanner_code_pointage"
    /// SQLSTATE métier déclarés par les gateways d'inscription (§2.4) : 42501 n'en fait pas partie.
    private let exceptionsInscription: Set<String> = ["22023", "23505", "P0002"]

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func exception(_ sqlstate: String, _ message: String) -> String {
        #"{"code":"\#(sqlstate)","details":null,"hint":null,"message":"\#(message)"}"#
    }

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

    // MARK: - Restitution

    func test22023MessageUtilisateurRestitueVerbatim() async throws {
        // `fn_demarrer_inscription` l.30118.
        registry.add("POST", demarrer, respond: .json(400, exception("22023", "Choisissez votre profession.")))
        let r = try await RPCResponse.appeler(TestClient.make(), "fn_demarrer_inscription",
                                              params: ["p_type_compte": .string("SOIGNANT"), "p_cgu": .bool(true)],
                                              fallback: fallback, exceptionsMetier: exceptionsInscription)
        XCTAssertTrue(r.estRefus)
        XCTAssertFalse(r.estSucces)
        XCTAssertEqual(r.erreur, "Choisissez votre profession.")
        XCTAssertEqual(r.code, "SQLSTATE_22023")
        XCTAssertEqual(r.sqlstate, "22023")
        XCTAssertNoThrow(try r.leverSiErreur(fallback: fallback), "refus structuré : l'appelant le traduit en issue")
        let corps = try XCTUnwrap(registry.requests(to: demarrer).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(corps["p_type_compte"] as? String, "SOIGNANT")
        XCTAssertEqual(registry.requests(to: demarrer).count, 1, "une seule requête, aucun renvoi")
    }

    func test23505CodeDeReservationRestitue() async throws {
        // `fn_demarrer_inscription` l.30127 : le message de l'exception EST le code de réservation.
        registry.add("POST", demarrer, respond: .json(409, exception("23505", "ACCOUNT_ALREADY_REGISTERED")))
        let r = try await RPCResponse.appeler(TestClient.make(), "fn_demarrer_inscription", params: [:],
                                              fallback: fallback, exceptionsMetier: exceptionsInscription)
        XCTAssertEqual(r.sqlstate, "23505")
        XCTAssertEqual(r.erreur, "ACCOUNT_ALREADY_REGISTERED")
        XCTAssertEqual(r.success, false)
        XCTAssertEqual(r.ok, false)
    }

    func testP0002SansParametre() async throws {
        // `fn_enregistrer_parcours_inscription` l.32456 (variante sans paramètre de l'appel).
        registry.add("POST", brouillon, respond: .json(500, exception("P0002", "Inscription introuvable.")))
        let r = try await RPCResponse.appeler(TestClient.make(), "fn_enregistrer_parcours_inscription",
                                              fallback: fallback, exceptionsMetier: exceptionsInscription)
        XCTAssertEqual(r.sqlstate, "P0002")
        XCTAssertEqual(r.erreur, "Inscription introuvable.")
    }

    // MARK: - Comportement du lot 1 conservé

    func test42501NonDeclareResteUneSessionExpiree() async throws {
        // `fn_demarrer_inscription` l.30110 « Session invalide. » : 42501 → `.unauthorized` (mapping inchangé).
        registry.add("POST", demarrer, respond: .json(403, exception("42501", "Session invalide.")))
        let e = await erreur {
            _ = try await RPCResponse.appeler(TestClient.make(), "fn_demarrer_inscription", params: [:],
                                              fallback: fallback, exceptionsMetier: self.exceptionsInscription)
        }
        XCTAssertEqual(e, JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage))
    }

    func test42501DeclareEstRestitue() async throws {
        // Seule une RPC qui déclare 42501 comme métier le restitue (cas du lot 2, `fn_scanner_code_pointage`
        // l.55652 du dump) : refus verbatim, jamais `.unauthorized`.
        let message = "Vous n'êtes pas assigné(e) à cette mission."
        registry.add("POST", scanner, respond: .json(403, exception("42501", message)))
        let r = try await RPCResponse.appeler(TestClient.make(), "fn_scanner_code_pointage", params: [:],
                                              fallback: fallback, exceptionsMetier: ["42501"])
        XCTAssertEqual(r.sqlstate, "42501")
        XCTAssertEqual(r.erreur, message)
        XCTAssertTrue(r.estRefus)
    }

    func test42501PrivilegeManquantDeclareEstUneErreurDeContrat() async throws {
        // GRANT manquant (incident #835, blueprint du lot 2 §2.4) : « permission denied for … » n'est jamais un
        // refus métier restitué, même quand la RPC déclare 42501 — erreur de contrat, une seule requête.
        for message in ["permission denied for function fn_scanner_code_pointage",
                        "permission denied for table signatures_contrats"] {
            registry.reset()
            registry.add("POST", scanner, respond: .json(403, exception("42501", message)))
            let e = await erreur {
                _ = try await RPCResponse.appeler(TestClient.make(), "fn_scanner_code_pointage", params: [:],
                                                  fallback: self.fallback, exceptionsMetier: ["42501", "P0002"])
            }
            XCTAssertEqual(e, JoleneError(.contract, SupabaseErrorMapping.contractMessage), message)
            XCTAssertEqual(registry.requests(to: scanner).count, 1, "aucun renvoi")
        }
    }

    func test42501PrivilegeManquantNonDeclareGardeLeComportementDuLot1() async throws {
        // Sans 42501 déclaré, `SupabaseErrorMapping` reste seul juge (lot 1, inchangé) : session expirée.
        registry.add("POST", demarrer, respond: .json(403, exception("42501", "permission denied for function fn_demarrer_inscription")))
        let e = await erreur {
            _ = try await RPCResponse.appeler(TestClient.make(), "fn_demarrer_inscription", params: [:],
                                              fallback: self.fallback, exceptionsMetier: self.exceptionsInscription)
        }
        XCTAssertEqual(e, JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage))
    }

    func testPGRST202ResteUnRefusDeContratSansRenvoi() async throws {
        registry.add("POST", demarrer, respond: .json(404, """
        {"code":"PGRST202","details":null,"hint":null,"message":"Could not find the function public.fn_demarrer_inscription in the schema cache"}
        """))
        let e = await erreur {
            _ = try await RPCResponse.appeler(TestClient.make(), "fn_demarrer_inscription", params: [:],
                                              fallback: fallback, exceptionsMetier: self.exceptionsInscription)
        }
        XCTAssertEqual(e?.kind, .contract)
        XCTAssertEqual(registry.requests(to: demarrer).count, 1)
    }

    func testExceptionHorsEnsembleResteGenerique() async throws {
        registry.add("POST", demarrer, respond: .json(400, exception("P0001", "Erreur technique interne")))
        let e = await erreur {
            _ = try await RPCResponse.appeler(TestClient.make(), "fn_demarrer_inscription", params: [:],
                                              fallback: fallback, exceptionsMetier: self.exceptionsInscription)
        }
        XCTAssertEqual(e, JoleneError(.unknown, fallback), "jamais le texte technique d'une exception non déclarée")
    }

    func testAppelSansExceptionsMetierGardeLeComportementDuLot1() async throws {
        registry.add("POST", demarrer, respond: .json(400, exception("22023", "Choisissez votre profession.")))
        let e = await erreur {
            _ = try await RPCResponse.appeler(TestClient.make(), "fn_demarrer_inscription", params: [:], fallback: fallback)
        }
        XCTAssertEqual(e, JoleneError(.unknown, fallback))
    }

    func testCodeDuTravailPrimeSurLesExceptionsMetier() async throws {
        let message = "[CODE DU TRAVAIL] Repos insuffisant avant mission : 8.5 heures au lieu de 11h minimum (Art. L3131-1). Assignation bloquée."
        registry.add("POST", "/rest/v1/rpc/fn_confirmer_action_planning_v1", respond: .json(400, exception("23514", message)))
        let r = try await RPCResponse.appeler(TestClient.make(), "fn_confirmer_action_planning_v1", params: [:],
                                              fallback: fallback, exceptionsMetier: ["23514"])
        XCTAssertEqual(r.code, CandidatureOutcome.codeRefusCodeDuTravail, "ordre : [CODE DU TRAVAIL] d'abord")
        XCTAssertEqual(r.erreur, message)
        XCTAssertNil(r.sqlstate)
    }

    func testSucces200InchangeAvecExceptionsMetier() async throws {
        registry.add("POST", demarrer, respond: .json(200, #"{"user_id":"u-1","type_compte":"SOIGNANT","donnees":{"profession":"IDE"}}"#))
        let r = try await RPCResponse.appeler(TestClient.make(), "fn_demarrer_inscription", params: [:],
                                              fallback: fallback, exceptionsMetier: exceptionsInscription)
        XCTAssertFalse(r.estRefus)
        XCTAssertEqual(r.string("type_compte"), "SOIGNANT")
        XCTAssertNil(r.sqlstate)
    }

    // MARK: - RPC `void` (correction 16)

    func testRPCVoid204EtCorpsVideSontDesSucces() async throws {
        for (status, corps) in [(204, ""), (200, "")] {
            registry.reset()
            registry.add("POST", upsert, respond: StubResponse(status: status, headers: [:], body: Data(corps.utf8), failure: nil))
            let issue = try await RPCResponse.appelerSansCorps(TestClient.make(), "fn_upsert_token_push",
                                                                params: ["p_token": .string(String(repeating: "a", count: 64)),
                                                                         "p_plateforme": .string("IOS")],
                                                                fallback: fallback, exceptionsMetier: ["22023"])
            XCTAssertEqual(issue, .succes, "HTTP \(status) sans corps")
            let corpsEnvoye = try XCTUnwrap(registry.requests(to: upsert).first?.bodyJSON as? [String: Any])
            XCTAssertEqual(corpsEnvoye["p_plateforme"] as? String, "IOS")
            XCTAssertEqual(registry.requests(to: upsert).count, 1)
        }
    }

    func testRPCVoidCorpsNullEstUnSucces() async throws {
        registry.add("POST", upsert, respond: .json(200, "null"))
        let issue = try await RPCResponse.appelerSansCorps(TestClient.make(), "fn_upsert_token_push", params: [:], fallback: fallback)
        XCTAssertEqual(issue, .succes)
    }

    func testRPCVoid22023Restitue() async throws {
        // `fn_upsert_token_push` l.64645.
        registry.add("POST", upsert, respond: .json(400, exception("22023", "Token push invalide")))
        let issue = try await RPCResponse.appelerSansCorps(TestClient.make(), "fn_upsert_token_push",
                                                            params: ["p_token": .string("court")],
                                                            fallback: fallback, exceptionsMetier: ["22023"])
        guard case let .refus(reponse) = issue else { return XCTFail("attendu : refus restitué, obtenu \(issue)") }
        XCTAssertEqual(reponse.sqlstate, "22023")
        XCTAssertEqual(reponse.erreur, "Token push invalide")
        XCTAssertEqual(registry.requests(to: upsert).count, 1, "aucun renvoi")
    }

    func testRPCVoid42501EstUneSessionExpiree() async throws {
        // `fn_upsert_token_push` l.64642 « Non authentifie ».
        registry.add("POST", upsert, respond: .json(403, exception("42501", "Non authentifie")))
        let e = await erreur {
            _ = try await RPCResponse.appelerSansCorps(TestClient.make(), "fn_upsert_token_push", params: [:],
                                                        fallback: self.fallback, exceptionsMetier: ["22023"])
        }
        XCTAssertEqual(e?.kind, .unauthorized)
    }

    func testRPCVoidReseauIndisponible() async throws {
        registry.add("POST", upsert, respond: .networkFailure())
        let e = await erreur {
            _ = try await RPCResponse.appelerSansCorps(TestClient.make(), "fn_upsert_token_push", params: [:], fallback: self.fallback)
        }
        XCTAssertEqual(e?.kind, .network)
    }

    func testSQLStateLuSeulementSurUnRefusRestitue() {
        XCTAssertEqual(RPCResponse.refusMetier(sqlstate: "22023", message: "x").sqlstate, "22023")
        XCTAssertNil(RPCResponse(.object(["code": .string("SQLSTATE_22023")])).sqlstate, "sans drapeau de refus : pas un refus restitué")
        XCTAssertNil(RPCResponse(.object(["success": .bool(false), "code": .string("PLANNING_MODIFIE_RECONFIRMER")])).sqlstate)
    }
}
