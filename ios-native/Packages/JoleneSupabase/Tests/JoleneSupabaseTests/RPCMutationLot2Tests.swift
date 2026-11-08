import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Classement local au lot 2 d'un échec de mutation non idempotente (blueprint `LOT2_PLAN.md` correction 10 et
/// §2.4 ; revue fraîche de T1) : `RPCResponse.appelerMutation` délègue à l'extension partagée avec le lot 3
/// (`RPCResponse+ExceptionsMetier.swift`, inchangée), puis distingue, sur l'erreur brute du SDK :
/// - rollback prouvé : PostgREST a répondu avec un `code` (SQLSTATE ou `PGRST…`) → `.refusDefinitif` ;
/// - incertain : réseau, annulation, passerelle (corps HTML → `HTTPError`, corps `{"message"}` sans `code` →
///   `PostgrestError(code: nil)`) → `.incertain`, à réconcilier par relecture.
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

    func testClassementSurLErreurBrute() {
        XCTAssertTrue(RPCResponse.rollbackProuve(PostgrestError(code: "23514", message: "x")))
        XCTAssertFalse(RPCResponse.rollbackProuve(PostgrestError(code: nil, message: "x")), "corps de passerelle")
        XCTAssertFalse(RPCResponse.rollbackProuve(PostgrestError(code: "", message: "x")))
        XCTAssertFalse(RPCResponse.rollbackProuve(URLError(.networkConnectionLost)))
        XCTAssertFalse(RPCResponse.rollbackProuve(CancellationError()), "annulation après envoi : incertain")
        XCTAssertFalse(RPCResponse.rollbackProuve(nil))
    }
}
