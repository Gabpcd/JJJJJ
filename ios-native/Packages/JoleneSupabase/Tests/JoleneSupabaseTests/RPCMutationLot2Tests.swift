import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Classement local au lot 2 d'un échec de mutation non idempotente (blueprint `LOT2_PLAN.md` correction 10 et
/// §2.4 ; revue fraîche de T1) : `RPCResponse.appelerMutation` délègue à l'extension partagée avec le lot 3
/// (`RPCResponse+ExceptionsMetier.swift`, inchangée), puis distingue, sur l'erreur brute du SDK :
/// - rollback prouvé : `code` SQLSTATE (cinq caractères `[0-9A-Z]`) ou code PostgREST de la liste blanche, émis
///   avant toute transaction ou après son annulation (`PGRST000`, `PGRST002`, `PGRST003`, `PGRST1xx` sauf
///   `PGRST103`/`PGRST111`/`PGRST112`, `PGRST2xx`, `PGRST3xx`) → `.refusDefinitif` ;
/// - incertain : réseau, annulation, passerelle (corps HTML → `HTTPError`, corps `{"message"}` sans `code` →
///   `PostgrestError(code: nil)`), `PGRST001` (connexion à la base cassée en cours de session, COMMIT compris), tout
///   autre code → `.incertain`, à réconcilier par relecture (revue fraîche de T1, seconde passe).
/// Une seule requête dans tous les cas (POST : le SDK ne rejoue jamais un `rpc`).
final class RPCMutationLot2Tests: XCTestCase {
    private let registry = StubRegistry.shared
    private let fallback = "Impossible d'enregistrer le pointage. Réessayez."
    private let scanner = "/rest/v1/rpc/fn_scanner_code_pointage"
    private let params: JSONObject = ["p_code": .string("123456"),
                                      "p_metadata": .object(["id_terminal": .string("TERM_IOS_ABCDEFGHIJKLMNOPQRST")])]

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func exception(_ sqlstate: String, _ message: String) -> StubResponse {
        let corps = #"{"code":"\#(sqlstate)","details":null,"hint":null,"message":"\#(message)"}"#
        return .json(RPCResponseExceptionsMetierTests.statut(sqlstate), corps)
    }

    private func scanne(_ reponse: StubResponse, file: StaticString = #filePath, line: UInt = #line) async -> IssueMutation {
        registry.reset()
        registry.add("POST", scanner, respond: reponse)
        let issue = await RPCResponse.appelerMutation(TestClient.make(), "fn_scanner_code_pointage", params: params,
                                                      fallback: fallback,
                                                      exceptionsMetier: ExceptionsMetierLot2.scannerCodePointage)
        XCTAssertEqual(registry.requests(to: scanner).count, 1, "une seule requête, aucun renvoi", file: file, line: line)
        return issue
    }

    // MARK: - Réponses

    func testSuccesEtExceptionDeclareeSontDesReponses() async throws {
        let succes = await scanne(.json(200, #"{"type_scan_effectue":"OUVERTURE","prochain_type_scan":"FERMETURE","numero_scan":1}"#))
        guard case let .reponse(r) = succes else { return XCTFail("succès attendu : \(succes)") }
        XCTAssertFalse(r.estRefus)
        XCTAssertEqual(r.int("numero_scan"), 1)

        let refus = await scanne(exception("P0002", "Code de pointage invalide ou expiré."))
        guard case let .reponse(declaree) = refus else { return XCTFail("refus restitué attendu : \(refus)") }
        XCTAssertEqual(declaree.sqlstate, "P0002")
        XCTAssertEqual(declaree.erreur, "Code de pointage invalide ou expiré.")

        let codeDuTravail = await scanne(exception("23514", "[CODE DU TRAVAIL] Repos insuffisant avant mission."))
        guard case let .reponse(travail) = codeDuTravail else { return XCTFail("refus restitué attendu") }
        XCTAssertEqual(travail.code, CandidatureOutcome.codeRefusCodeDuTravail)
    }

    // MARK: - Rollback prouvé

    func testExceptionNonDeclareeEstUnRefusDefinitif() async {
        // 40001 (sérialisation) et 57014 (statement_timeout) : la transaction est annulée, rien n'est écrit.
        let serialisation = await scanne(exception("40001", "could not serialize access due to concurrent update"))
        XCTAssertEqual(serialisation, .refusDefinitif(code: "40001", erreur: JoleneError(.unknown, fallback)))
        let delai = await scanne(exception("57014", "canceling statement due to statement timeout"))
        XCTAssertEqual(delai, .refusDefinitif(code: "57014", erreur: JoleneError(.unknown, fallback)))
    }

    func testErreursDeContratSontDesRefusDefinitifs() async {
        let privilege = await scanne(exception("42501", "permission denied for function fn_scanner_code_pointage"))
        XCTAssertEqual(privilege, .refusDefinitif(code: "42501", erreur: JoleneError(.contract, SupabaseErrorMapping.contractMessage)))
        let introuvable = await scanne(.json(404, """
        {"code":"PGRST202","details":null,"hint":null,"message":"Could not find the function public.fn_scanner_code_pointage in the schema cache"}
        """))
        XCTAssertEqual(introuvable, .refusDefinitif(code: "PGRST202", erreur: JoleneError(.contract, SupabaseErrorMapping.contractMessage)))
        let base = await scanne(.json(503, #"{"code":"PGRST000","details":null,"hint":null,"message":"Could not connect to the database"}"#))
        XCTAssertEqual(base, .refusDefinitif(code: "PGRST000", erreur: JoleneError(.unknown, fallback)),
                       "PostgREST n'a pas ouvert de transaction")
    }

    // MARK: - Incertain

    func testPasserellesSontIncertaines() async {
        let html = StubResponse(status: 502, headers: ["Content-Type": "text/html"],
                                body: Data("<html><body><h1>502 Bad Gateway</h1></body></html>".utf8), failure: nil)
        let enHTML = await scanne(html)
        XCTAssertEqual(enHTML, .incertain(JoleneError(.unknown, fallback)), "502 HTML → HTTPError")
        let html504 = StubResponse(status: 504, headers: ["Content-Type": "text/html"],
                                   body: Data("<html><body>504 Gateway Time-out</body></html>".utf8), failure: nil)
        let enHTML504 = await scanne(html504)
        XCTAssertEqual(enHTML504, .incertain(JoleneError(.unknown, fallback)))
        let message = await scanne(.json(504, #"{"message":"The upstream server is timing out"}"#))
        XCTAssertEqual(message, .incertain(JoleneError(.unknown, fallback)), "{message} sans code → PostgrestError(code: nil)")
        let message502 = await scanne(.json(502, #"{"message":"An invalid response was received from the upstream server"}"#))
        XCTAssertEqual(message502, .incertain(JoleneError(.unknown, fallback)))
    }

    func testReseauEstIncertain() async {
        let perdue = await scanne(.networkFailure(.networkConnectionLost))
        XCTAssertEqual(perdue, .incertain(JoleneError(.network, SupabaseErrorMapping.networkMessage)))
        let delai = await scanne(.networkFailure(.timedOut))
        XCTAssertEqual(delai, .incertain(JoleneError(.network, SupabaseErrorMapping.networkMessage)))
    }

    func testConnexionCasseeEnCoursDeSessionEstIncertaine() async {
        // PGRST001 (503) : la connexion à la base a cassé pendant la requête, COMMIT compris. Le scan a pu être
        // appliqué : le reçu `started` est gardé et la relecture tranche (correction 10, PRINCIPES §4).
        let coupure = await scanne(.json(503, """
        {"code":"PGRST001","details":null,"hint":null,"message":"Database client error. Retrying the connection."}
        """))
        XCTAssertEqual(coupure, .incertain(JoleneError(.unknown, fallback)))
    }

    func testCodeNiSQLStateNiDeLaListeBlancheEstIncertain() async {
        // Passerelle qui imiterait la forme PostgREST avec un `code` texte ; erreur interne de PostgREST (PGRSTX00) ;
        // statut ou en-têtes posés par la fonction et refusés à la construction de la réponse, après le COMMIT
        // (PGRST111, PGRST112) : aucune preuve de rollback.
        let passerelle = await scanne(.json(504, #"{"code":"upstream_request_timeout","message":"The upstream server is timing out"}"#))
        XCTAssertEqual(passerelle, .incertain(JoleneError(.unknown, fallback)))
        let interne = await scanne(.json(500, #"{"code":"PGRSTX00","details":null,"hint":null,"message":"Internal error"}"#))
        XCTAssertEqual(interne, .incertain(JoleneError(.unknown, fallback)))
        let statut = await scanne(.json(500, #"{"code":"PGRST112","details":null,"hint":null,"message":"Invalid status code"}"#))
        XCTAssertEqual(statut, .incertain(JoleneError(.unknown, fallback)))
    }

    func testClassementSurLErreurBrute() {
        // SQLSTATE : cinq caractères `[0-9A-Z]`, même prédicat que `RecuScan.refuser(sqlstate:)` (le reçu d'un refus
        // définitif à SQLSTATE se journalise toujours en `refused`).
        for code in ["23514", "P0002", "42501", "40001", "57014", "XX000"] {
            XCTAssertTrue(RPCResponse.rollbackProuve(PostgrestError(code: code, message: "x")), code)
            XCTAssertTrue(RecuScan.sqlstateValide(code), code)
        }
        // Codes PostgREST émis avant toute transaction (connexion, cache de schéma, pool, requête, JWT) ou après son
        // annulation (PGRST116, PGRST124).
        for code in ["PGRST000", "PGRST002", "PGRST003", "PGRST100", "PGRST102", "PGRST116", "PGRST124", "PGRST200",
                     "PGRST202", "PGRST205", "PGRST300", "PGRST301", "PGRST303"] {
            XCTAssertTrue(RPCResponse.rollbackProuve(PostgrestError(code: code, message: "x")), code)
        }
        // Aucune preuve : connexion cassée en cours de session, erreur interne, réponse construite après le COMMIT
        // (plage 416, en-têtes et statut posés par la fonction), codes inconnus ou mal formés.
        for code in ["PGRST001", "PGRSTX00", "PGRST103", "PGRST111", "PGRST112", "PGRST004", "PGRST400", "PGRST20",
                     "PGRST2000", "pgrst202", "PGRST2O2", "p0002", "2351", "235140", " 2351", "2351\u{0661}",
                     "upstream_request_timeout", ""] {
            XCTAssertFalse(RPCResponse.rollbackProuve(PostgrestError(code: code, message: "x")), code)
        }
        XCTAssertFalse(RPCResponse.rollbackProuve(PostgrestError(code: nil, message: "x")), "corps de passerelle")
        XCTAssertFalse(RPCResponse.rollbackProuve(URLError(.networkConnectionLost)))
        XCTAssertFalse(RPCResponse.rollbackProuve(CancellationError()), "annulation après envoi : incertain")
        XCTAssertFalse(RPCResponse.rollbackProuve(nil))
    }
}
