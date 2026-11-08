import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Centre de notifications (lot 3, T5) sur la table `notifications` : contrat du web repris à l'identique
/// (`src/pages/PageNotifications.tsx` l.53-58, l.91) — select borné à 200, filtré par destinataire, trié par
/// `cree_le` décroissant ; marquer lue = PATCH `{lue, lue_le}` filtré par `id` et destinataire puis relecture de la
/// ligne ; une liste vide (RLS) reste une liste vide ; une mise à jour sans effet n'est jamais un faux succès.
final class SupabaseNotificationsGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let chemin = "/rest/v1/notifications"
    private let horloge = FixedClock(Date(timeIntervalSince1970: 1_793_577_600)) // 2026-11-02T00:00:00Z

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseNotificationsGateway {
        SupabaseNotificationsGateway(client: TestClient.make(), clock: horloge)
    }

    private func ligne(_ id: String, lue: Bool) -> String {
        #"{"id":"\#(id)","titre":"Titre \#(id)","corps":"Corps","type":"RAPPEL_MISSION","lien":"/soignant/missions/m-1","lue":\#(lue),"lue_le":null,"cree_le":"2026-11-01T22:00:00.123456+00:00"}"#
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

    func testConstantesDuContrat() {
        XCTAssertEqual(SupabaseNotificationsGateway.table, "notifications")
        XCTAssertEqual(SupabaseNotificationsGateway.colonnes, "id, titre, corps, type, lien, lue, lue_le, cree_le")
        XCTAssertEqual(SupabaseNotificationsGateway.limite, 200)
    }

    // MARK: - Liste

    func testListeBorneeA200FiltreeParDestinataireTrieeParDate() async throws {
        registry.add("GET", chemin, respond: .json(200, "[\(ligne("n1", lue: false)),\(ligne("n2", lue: true))]"))
        let liste = try await gateway().liste(context: TestClient.context)
        XCTAssertEqual(liste.map(\.id), ["n1", "n2"])
        XCTAssertEqual(liste.map(\.lue), [false, true])
        let requete = try XCTUnwrap(registry.requests(to: chemin).first)
        XCTAssertEqual(requete.query("select")?.replacingOccurrences(of: " ", with: ""), "id,titre,corps,type,lien,lue,lue_le,cree_le")
        XCTAssertEqual(requete.query("destinataire_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(requete.query("order"), "cree_le.desc")
        XCTAssertEqual(requete.query("limit"), "200")
        XCTAssertEqual(requete.method, "GET")
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testListeVideSousRLSEstUneListeVide() async throws {
        registry.add("GET", chemin, respond: .json(200, "[]"))
        let liste = try await gateway().liste(context: TestClient.context)
        XCTAssertEqual(liste, [], "aucune ligne visible : liste vide, jamais une erreur ni des lignes fabriquées")
    }

    func testListeErreursTraduites() async {
        registry.add("GET", chemin, respond: .json(401, #"{"code":"PGRST301","details":null,"hint":null,"message":"JWT expired"}"#))
        let session = await erreur { _ = try await self.gateway().liste(context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized)

        // (Échec réseau d'un GET : le SDK le retente avec attente, 1 + 2 + 4 s ; traduction `.network` déjà couverte
        // par `SupabaseErrorMappingTests`.)
        registry.reset()
        registry.add("GET", chemin, respond: .json(200, #"[{"id":"n1","type":"SYSTEM"}]"#))
        let contrat = await erreur { _ = try await self.gateway().liste(context: TestClient.context) }
        XCTAssertEqual(contrat?.message, "Impossible de charger vos notifications.", "ligne illisible : texte web, pas de détail")
    }

    func testContexteIncoherentRefuseSansAppel() async {
        let incoherent = MissionReadContext(userId: TestClient.userId, email: nil,
                                            profile: SoignantProfile(id: "autre", profession: "IDE"))
        let refus = await erreur { _ = try await self.gateway().liste(context: incoherent) }
        XCTAssertEqual(refus?.kind, .unauthorized)
        XCTAssertTrue(registry.requests.isEmpty)
    }

    // MARK: - Marquer lue

    func testMarquerLuePatchPuisRelecture() async throws {
        registry.add("PATCH", chemin, respond: StubResponse(status: 204, headers: [:], body: Data(), failure: nil))
        registry.add("GET", chemin, respond: .json(200, ligne("n1", lue: true)))
        let relue = try await gateway().marquerLue(id: "n1", context: TestClient.context)
        XCTAssertEqual(relue.id, "n1")
        XCTAssertTrue(relue.lue)

        let patch = try XCTUnwrap(registry.requests.first { $0.method == "PATCH" })
        XCTAssertEqual(patch.path, chemin)
        XCTAssertEqual(patch.query("id"), "eq.n1")
        XCTAssertEqual(patch.query("destinataire_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(patch.bodyJSON as? NSDictionary, ["lue": true, "lue_le": "2026-11-02T00:00:00.000Z"] as NSDictionary,
                       "seuls `lue` et `lue_le` (triggers de protection) ; horloge des gateways")
        XCTAssertEqual(patch.header("Prefer"), "return=minimal")

        let relecture = try XCTUnwrap(registry.requests.first { $0.method == "GET" })
        XCTAssertEqual(relecture.query("id"), "eq.n1")
        XCTAssertEqual(relecture.query("destinataire_id"), "eq.\(TestClient.userId)")
        XCTAssertEqual(relecture.header("Accept"), "application/vnd.pgrst.object+json")
        XCTAssertEqual(registry.requests.map(\.method), ["PATCH", "GET"], "mise à jour puis relecture, dans cet ordre")
    }

    func testMiseAJourSansEffetJamaisUnFauxSucces() async {
        // RLS : le PATCH ne touche aucune ligne (204), la relecture rend la ligne toujours non lue.
        registry.add("PATCH", chemin, respond: StubResponse(status: 204, headers: [:], body: Data(), failure: nil))
        registry.add("GET", chemin, respond: .json(200, ligne("n1", lue: false)))
        let nonLue = await erreur { _ = try await self.gateway().marquerLue(id: "n1", context: TestClient.context) }
        XCTAssertEqual(nonLue?.message, "Impossible de marquer cette notification comme lue.")

        // Ligne invisible (autre destinataire) : relecture sans ligne → refus.
        registry.reset()
        registry.add("PATCH", chemin, respond: StubResponse(status: 204, headers: [:], body: Data(), failure: nil))
        registry.add("GET", chemin, respond: .json(406, #"{"code":"PGRST116","details":"The result contains 0 rows","hint":null,"message":"JSON object requested, multiple (or no) rows returned"}"#))
        let absente = await erreur { _ = try await self.gateway().marquerLue(id: "n1", context: TestClient.context) }
        XCTAssertEqual(absente?.message, "Impossible de marquer cette notification comme lue.")
    }

    func testEchecDuPatchSansRelecture() async {
        registry.add("PATCH", chemin, respond: .json(400, #"{"code":"P0001","details":null,"hint":null,"message":"Seuls les champs lue et lue_le peuvent être modifiés"}"#))
        let refus = await erreur { _ = try await self.gateway().marquerLue(id: "n1", context: TestClient.context) }
        XCTAssertEqual(refus?.message, "Impossible de marquer cette notification comme lue.", "jamais le message technique du serveur")
        XCTAssertEqual(registry.requests.map(\.method), ["PATCH"], "aucune relecture après un échec")
    }

    func testIdentifiantVideRefuseSansAppel() async {
        let refus = await erreur { _ = try await self.gateway().marquerLue(id: "", context: TestClient.context) }
        XCTAssertEqual(refus?.kind, .contract)
        XCTAssertTrue(registry.requests.isEmpty)
    }

    func testMondeSupabaseCableLeCentre() {
        XCTAssertTrue(SupabaseGateways.make(client: TestClient.make()).notifications is SupabaseNotificationsGateway)
    }
}
