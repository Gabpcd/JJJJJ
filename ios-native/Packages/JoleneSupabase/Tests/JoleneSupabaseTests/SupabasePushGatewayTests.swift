import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Gateway push du lot 3 (T4 ; fiches `fn_upsert_token_push` et `fn_desactiver_mon_token_push` de
/// `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md`) : contrat repris à l'identique du web
/// (`src/lib/pushNative.ts` l.32-35, `src/lib/pushDeviceToken.ts` l.90-102) — token APNs hexadécimal,
/// `p_plateforme = 'IOS'`, RPC `void` appelée sans décodage de corps (correction 16), 22023 restitué
/// avant `SupabaseErrorMapping` puis refusé en contrat sans renvoi, désactivation `{success:false}`
/// jamais bloquante.
final class SupabasePushGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let upsert = "/rest/v1/rpc/fn_upsert_token_push"
    private let desactivation = "/rest/v1/rpc/fn_desactiver_mon_token_push"
    /// Token de 32 octets calculé (aucun littéral hexadécimal) : 64 caractères minuscules.
    private let token = Data((0..<32).map { UInt8(0xa0 + $0 % 16) }).map { String(format: "%02x", $0) }.joined()

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabasePushGateway { SupabasePushGateway(client: TestClient.make()) }

    private func corps(_ path: String) throws -> NSDictionary {
        let requete = try XCTUnwrap(registry.requests(to: path).first, "aucun appel à \(path)")
        return try XCTUnwrap(requete.bodyJSON as? NSDictionary)
    }

    private func exception(_ code: String, _ message: String) -> String {
        #"{"code":"\#(code)","details":null,"hint":null,"message":"\#(message)"}"#
    }

    private func erreur(_ operation: @escaping () async throws -> Void) async -> JoleneError? {
        do {
            try await operation()
            return nil
        } catch let jolene as JoleneError {
            return jolene
        } catch {
            XCTFail("erreur non traduite : \(error)")
            return nil
        }
    }

    func testNomsEtPlateforme() {
        XCTAssertEqual(SupabasePushGateway.enregistrementRPC, "fn_upsert_token_push")
        XCTAssertEqual(SupabasePushGateway.desactivationRPC, "fn_desactiver_mon_token_push")
        XCTAssertEqual(SupabasePushGateway.plateforme, PushCoordinator.plateforme)
        XCTAssertEqual(SupabasePushGateway.exceptionsMetier, ["22023"])
    }

    // MARK: - fn_upsert_token_push (void)

    func testEnregistrerEnvoieLeTokenEtIOSEt204EstUnSucces() async throws {
        registry.add("POST", upsert, respond: StubResponse(status: 204, headers: [:], body: Data(), failure: nil))
        try await gateway().enregistrer(token: token, context: TestClient.context)
        XCTAssertEqual(try corps(upsert), ["p_token": token, "p_plateforme": "IOS"] as NSDictionary)
        XCTAssertEqual(registry.requests(to: upsert).count, 1)
        XCTAssertEqual(registry.requests.first?.header("X-Client-Info"), "jolene-ios/2.0.0")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testEnregistrer200ACorpsVideEstUnSuccesSansDecodage() async throws {
        registry.add("POST", upsert, respond: StubResponse(status: 200, headers: [:], body: Data(), failure: nil))
        try await gateway().enregistrer(token: token, context: TestClient.context)
        XCTAssertEqual(registry.requests(to: upsert).count, 1)
    }

    func testEnregistrer42501EstUneSessionExpiree() async {
        // l.64642 « Non authentifie » : `auth.uid()` nul ou compte inactif.
        registry.add("POST", upsert, respond: .json(403, exception("42501", "Non authentifie")))
        let e = await erreur { try await self.gateway().enregistrer(token: self.token, context: TestClient.context) }
        XCTAssertEqual(e?.kind, .unauthorized)
        XCTAssertEqual(registry.requests(to: upsert).count, 1)
    }

    func testEnregistrer22023EstUnRefusDeContratSansRenvoi() async {
        for message in ["Token push invalide", "Plateforme push invalide"] {
            registry.reset()
            registry.add("POST", upsert, respond: .json(400, exception("22023", message)))
            let e = await erreur { try await self.gateway().enregistrer(token: self.token, context: TestClient.context) }
            XCTAssertEqual(e, JoleneError(.contract, SupabaseErrorMapping.contractMessage), message)
            XCTAssertEqual(registry.requests(to: upsert).count, 1, "\(message) : aucun renvoi")
        }
    }

    func testEnregistrerFonctionIntrouvableEtReseau() async {
        registry.add("POST", upsert, respond: .json(404, exception("PGRST202", "Could not find the function")))
        var e = await erreur { try await self.gateway().enregistrer(token: self.token, context: TestClient.context) }
        XCTAssertEqual(e?.kind, .contract)
        registry.reset()
        registry.add("POST", upsert, respond: .networkFailure())
        e = await erreur { try await self.gateway().enregistrer(token: self.token, context: TestClient.context) }
        XCTAssertEqual(e?.kind, .network)
    }

    func testEnregistrerRefuseUnContexteIncoherentAvantToutAppel() async {
        let contexte = MissionReadContext(userId: TestClient.userId, email: nil,
                                          profile: SoignantProfile(id: "autre-profil", profession: "IDE"))
        let e = await erreur { try await self.gateway().enregistrer(token: self.token, context: contexte) }
        XCTAssertEqual(e?.kind, .unauthorized)
        XCTAssertTrue(registry.requests.isEmpty, "aucun appel réseau")
    }

    // MARK: - fn_desactiver_mon_token_push (jsonb)

    func testDesactiverEnvoieLeTokenEtLitLeNombreDeLignes() async throws {
        registry.add("POST", desactivation,
                     respond: .json(200, #"{"success":true,"tokens_desactives":1,"scope":"CURRENT_DEVICE"}"#))
        let issue = try await gateway().desactiver(token: token)
        XCTAssertEqual(issue, .desactive(tokensDesactives: 1))
        XCTAssertEqual(try corps(desactivation), ["p_token": token] as NSDictionary)
        XCTAssertEqual(registry.requests(to: desactivation).count, 1)
    }

    func testDesactiverZeroLigneResteUnSucces() async throws {
        registry.add("POST", desactivation,
                     respond: .json(200, #"{"success":true,"tokens_desactives":0,"scope":"CURRENT_DEVICE"}"#))
        let issue = try await gateway().desactiver(token: token)
        XCTAssertEqual(issue, .desactive(tokensDesactives: 0))
    }

    func testDesactiverSuccessFalseNEstJamaisBloquant() async throws {
        // l.30186-30191 : messages sans accent, comme la source ; jamais « session expirée ».
        for message in ["Non authentifie", "Token push invalide"] {
            registry.reset()
            registry.add("POST", desactivation, respond: .json(200, #"{"success":false,"error":"\#(message)"}"#))
            let issue = try await gateway().desactiver(token: token)
            XCTAssertEqual(issue, .nonDesactive, message)
        }
    }

    func testDesactiverFormeInattendueNestJamaisUnSucces() async {
        registry.add("POST", desactivation, respond: .json(200, "{}"))
        var e = await erreur { _ = try await self.gateway().desactiver(token: self.token) }
        XCTAssertEqual(e?.kind, .contract, "ni drapeau ni erreur : refus de contrat, jamais un succès supposé")
        registry.reset()
        registry.add("POST", desactivation, respond: .json(200, #"{"success":true,"error":"incohérent"}"#))
        e = await erreur { _ = try await self.gateway().desactiver(token: self.token) }
        XCTAssertNotNil(e, "`success:true` accompagné d'une erreur n'est pas un succès")
        registry.reset()
        registry.add("POST", desactivation, respond: .networkFailure())
        e = await erreur { _ = try await self.gateway().desactiver(token: self.token) }
        XCTAssertEqual(e?.kind, .network)
    }
}
