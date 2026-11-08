import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Exceptions métier des RPC du lot 2 (blueprint `docs/mobile-swift/LOT2_PLAN.md` §2.4, corrections 10
/// et 22, tranche T1), par l'extension partagée avec le lot 3 (`RPCResponse+ExceptionsMetier.swift`).
/// `fn_scanner_code_pointage` et les triggers de `presences` signalent leurs refus par `RAISE EXCEPTION`
/// (HTTP 4xx/5xx PostgREST) : chaque message du dump est restitué mot pour mot, AVANT
/// `SupabaseErrorMapping` (qui ferait de 42501 « Votre session a expiré »). Statuts des stubs = ceux de
/// PostgREST pour chaque SQLSTATE (42501 → 403, 23503 → 409, P0001, 22023, 23514 → 400, autres P0… → 500)
/// pour exercer le décodage réel du SDK. Une seule requête par appel, aucun renvoi (POST).
final class RPCResponseExceptionsMetierTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let fallback = "Impossible d'enregistrer le pointage. Réessayez."
    private let scanner = "/rest/v1/rpc/fn_scanner_code_pointage"
    private let coherence = "/rest/v1/rpc/fn_verifier_coherence_documents"
    private let params: JSONObject = ["p_code": .string("123456"),
                                      "p_metadata": .object(["id_terminal": .string("TERM_IOS_ABCDEFGHIJKLMNOPQRST")])]

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func exception(_ sqlstate: String, _ message: String, details: String? = nil, hint: String? = nil) -> String {
        let corps: [String: Any] = ["code": sqlstate, "message": message, "details": details as Any? ?? NSNull(),
                                    "hint": hint as Any? ?? NSNull()]
        let data = try! JSONSerialization.data(withJSONObject: corps)
        return String(decoding: data, as: UTF8.self)
    }

    private func statut(_ sqlstate: String) -> Int {
        switch sqlstate {
        case "42501": return 403
        case "23503": return 409
        case "P0001", "22023", "23514": return 400
        default: return sqlstate.hasPrefix("P0") ? 500 : 400
        }
    }

    private func scanne(exceptionsMetier: Set<String>? = ExceptionsMetierLot2.scannerCodePointage) async throws -> RPCResponse {
        if let exceptionsMetier {
            return try await RPCResponse.appeler(TestClient.make(), "fn_scanner_code_pointage", params: params,
                                                 fallback: fallback, exceptionsMetier: exceptionsMetier)
        }
        return try await RPCResponse.appeler(TestClient.make(), "fn_scanner_code_pointage", params: params, fallback: fallback)
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

    // MARK: - Ensembles déclarés

    func testSQLStateMetierDeclaresParRPC() {
        XCTAssertEqual(ExceptionsMetierLot2.scannerCodePointage, ["P0001", "P0002", "22023", "23503", "23514", "42501"],
                       "§2.4 : fn_scanner_code_pointage et les triggers de presences")
        XCTAssertEqual(ExceptionsMetierLot2.verifierCoherenceDocuments, ["42501"])
    }

    // MARK: - Restitution verbatim (une requête par exception)

    func testChaqueExceptionDuScanEstRestitueeMotPourMot() async throws {
        // Messages exacts du dump `supabase/schema/public.sql` (paramètres `%` remplis comme PostgreSQL).
        let exceptions: [(String, String)] = [
            ("P0002", "Code de pointage invalide ou expiré."),                                        // l.55649
            ("42501", "Vous n'êtes pas assigné(e) à cette mission."),                                  // l.55652
            ("23514", "Scan déjà pris en compte. Prochain scan possible dans 87 secondes."),          // l.55662-55664
            ("23514", "Le contrat doit être signé avant le pointage."),                               // l.55677
            ("23514", "Pointage trop tôt. Mission commence à 09:00. Possible à partir de 08:45."),    // l.55686-55689
            ("P0002", "Aucun créneau effectif ouvert à fermer."),                                      // l.55775
            ("23514", "La fin réelle doit être postérieure au début réel du créneau."),                // l.55778
            ("22023", "Mission et soignant requis"),                                                   // l.35867
            ("42501", "Le soignant n'est pas affecté à cette mission."),                               // l.35875-35876
            ("23514", "La mission ne peut pas être démarrée dans son état actuel."),                   // l.35879-35880
            ("23503", "Profil soignant introuvable."),                                                 // l.35900
            ("23514", "Le contrat signé par les deux parties est requis avant le pointage."),          // l.35919-35920
            ("23514", "Les justificatifs requis ne sont plus tous vérifiés. Déposez ou faites valider la preuve courante avant de démarrer."), // l.35925-35926
            ("P0001", "Pointage trop tôt. La mission commence à 08:00."),                              // l.1961
        ]
        for (sqlstate, message) in exceptions {
            registry.reset()
            registry.add("POST", scanner, respond: .json(statut(sqlstate), exception(sqlstate, message)))
            let r = try await scanne()
            XCTAssertTrue(r.estRefus, message)
            XCTAssertFalse(r.estSucces, message)
            XCTAssertEqual(r.sqlstate, sqlstate, message)
            XCTAssertEqual(r.code, "SQLSTATE_\(sqlstate)", message)
            XCTAssertEqual(r.erreur, message, "verbatim")
            XCTAssertNoThrow(try r.leverSiErreur(fallback: fallback), "refus structuré : l'appelant le traduit en IssueScan.refuse")
            XCTAssertEqual(registry.requests(to: scanner).count, 1, "\(sqlstate) : une seule requête, aucun renvoi")
        }
    }

    func testCorpsDeLaRequeteDuScanInchange() async throws {
        registry.add("POST", scanner, respond: .json(500, exception("P0002", "Code de pointage invalide ou expiré.")))
        _ = try await scanne()
        let corps = try XCTUnwrap(registry.requests(to: scanner).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(corps["p_code"] as? String, "123456")
        XCTAssertEqual((corps["p_metadata"] as? [String: Any])?["id_terminal"] as? String, "TERM_IOS_ABCDEFGHIJKLMNOPQRST")
    }

    func testDetailsEtHintJamaisRepris() async throws {
        registry.add("POST", scanner, respond: .json(400, exception("23514", "Le contrat doit être signé avant le pointage.",
                                                                     details: "Failing row contains (valeur-interne)",
                                                                     hint: "CHECK presences_x")))
        let r = try await scanne()
        XCTAssertEqual(r.erreur, "Le contrat doit être signé avant le pointage.")
        XCTAssertFalse(String(describing: r.raw).contains("valeur-interne"))
        XCTAssertFalse(String(describing: r.raw).contains("CHECK"))
    }

    // MARK: - 42501 métier, GRANT manquant, contrat

    func test42501MetierNEstJamaisUneSessionExpiree() async throws {
        registry.add("POST", scanner, respond: .json(403, exception("42501", "Vous n'êtes pas assigné(e) à cette mission.")))
        let r = try await scanne()
        XCTAssertEqual(r.sqlstate, "42501")
        XCTAssertEqual(r.erreur, "Vous n'êtes pas assigné(e) à cette mission.")
        // Même exception sans déclaration : comportement du lot 1 (SupabaseErrorMapping), session expirée.
        registry.reset()
        registry.add("POST", scanner, respond: .json(403, exception("42501", "Vous n'êtes pas assigné(e) à cette mission.")))
        let e = await erreur { _ = try await self.scanne(exceptionsMetier: nil) }
        XCTAssertEqual(e, JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage))
    }

    func testPrivilegeManquantEstUneErreurDeContrat() async throws {
        registry.add("POST", scanner, respond: .json(403, exception("42501", "permission denied for function fn_scanner_code_pointage")))
        let e = await erreur { _ = try await self.scanne() }
        XCTAssertEqual(e, JoleneError(.contract, SupabaseErrorMapping.contractMessage))
        XCTAssertEqual(registry.requests(to: scanner).count, 1)
    }

    func testPGRST202EstUnRefusDeContratSansRenvoi() async throws {
        registry.add("POST", scanner, respond: .json(404, """
        {"code":"PGRST202","details":null,"hint":null,"message":"Could not find the function public.fn_scanner_code_pointage in the schema cache"}
        """))
        let e = await erreur { _ = try await self.scanne() }
        XCTAssertEqual(e, JoleneError(.contract, SupabaseErrorMapping.contractMessage))
        XCTAssertEqual(registry.requests(to: scanner).count, 1, "une seule requête comptée")
    }

    func testSQLStateHorsEnsembleResteGenerique() async throws {
        // Correction 10 : PostgrestError décodée = rollback prouvé ; non déclarée → message générique, jamais
        // le texte technique ; distinct d'une erreur réseau (`.network`), seule incertaine avec le délai.
        registry.add("POST", scanner, respond: .json(400, exception("40001", "could not serialize access due to concurrent update")))
        let e = await erreur { _ = try await self.scanne() }
        XCTAssertEqual(e, JoleneError(.unknown, fallback))
        registry.reset()
        registry.add("POST", scanner, respond: .networkFailure(.networkConnectionLost))
        let reseau = await erreur { _ = try await self.scanne() }
        XCTAssertEqual(reseau?.kind, .network)
        XCTAssertEqual(registry.requests(to: scanner).count, 1, "réponse perdue : aucun renvoi, la réconciliation tranche")
    }

    func testCodeDuTravailInchangeAvecExceptionsMetier() async throws {
        let message = "[CODE DU TRAVAIL] Repos insuffisant avant mission : 8.5 heures au lieu de 11h minimum (Art. L3131-1). Assignation bloquée."
        registry.add("POST", scanner, respond: .json(400, exception("23514", message)))
        let r = try await scanne()
        XCTAssertEqual(r.code, CandidatureOutcome.codeRefusCodeDuTravail, "ordre : [CODE DU TRAVAIL] d'abord")
        XCTAssertEqual(r.erreur, message)
        XCTAssertNil(r.sqlstate)
    }

    func testAppelSansExceptionsMetierGardeLeComportementDuLot1() async throws {
        registry.add("POST", scanner, respond: .json(500, exception("P0002", "Code de pointage invalide ou expiré.")))
        let e = await erreur { _ = try await self.scanne(exceptionsMetier: nil) }
        XCTAssertEqual(e, JoleneError(.unknown, fallback))
    }

    func testSuccesInchange() async throws {
        registry.add("POST", scanner, respond: .json(200, """
        {"type_scan_effectue":"OUVERTURE","prochain_type_scan":"FERMETURE","numero_scan":1,"validation_etab_requise":false}
        """))
        let r = try await scanne()
        XCTAssertFalse(r.estRefus)
        XCTAssertNil(r.sqlstate)
        XCTAssertEqual(r.int("numero_scan"), 1)
    }

    // MARK: - Cohérence documentaire (lecture best-effort)

    func testCoherence42501AccesRefuseRestitueSansSessionExpiree() async throws {
        // `fn_verifier_coherence_documents` l.65833, l.65839 : compte inactif ou autre soignant ; le web avale (l.296).
        registry.add("POST", coherence, respond: .json(403, exception("42501", "Accès refusé")))
        let r = try await RPCResponse.appeler(TestClient.make(), "fn_verifier_coherence_documents", fallback: fallback,
                                              exceptionsMetier: ExceptionsMetierLot2.verifierCoherenceDocuments)
        XCTAssertEqual(r.sqlstate, "42501")
        XCTAssertEqual(r.erreur, "Accès refusé")
        XCTAssertNil(registry.requests(to: coherence).first?.bodyJSON, "appel sans p_soignant_id (parité web)")
    }
}
