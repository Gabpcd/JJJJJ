import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Messagerie en contexte établissement (lot 5, T11 ; `LOT5_PLAN.md` §3 T11) : mêmes RPC, même table, même edge que le
/// lot 4, sous le JWT du membre. Prouvé ici : l'auteur d'un envoi est l'utilisateur de la session (jeton, aucun champ
/// d'auteur ni d'établissement dans le corps ; un contexte dont `userId` n'est pas la session est refusé avant tout
/// envoi) ; le badge est l'entier nu de `fn_messages_non_lus()` ; « Contacter le soignant » n'appelle que
/// `fn_obtenir_conversation(p_autre_id := soignant, p_mission_id)` ; un contexte incohérent n'envoie rien.
final class SupabaseMessagerieEtablissementTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let conversation = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
    private let mission = "2b3c4d5e-6f70-4812-9a3b-4c5d6e7f8091"
    private let etablissement = "3c4d5e6f-7081-4923-ab4c-5d6e7f809102"
    private let soignant = "9d8c7b6a-5f4e-4d3c-8b2a-1f0e9d8c7b6a"
    private let edge = "/functions/v1/messagerie-validate"
    private let table = "/rest/v1/messages_chat"

    private func rpc(_ fonction: String) -> String { "/rest/v1/rpc/\(fonction)" }

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    /// Membre RH de l'établissement, utilisateur de la session de test.
    private func etab(userId: String = TestClient.userId, etablissementId: String? = nil) -> EtablissementReadContext {
        EtablissementReadContext(userId: userId, etablissementId: etablissementId ?? etablissement, roleEtab: .rh,
                                 permissions: PermissionsEtab(accordees: [.lecture, .candidatures]), epoch: 1)
    }

    private func gateway() -> SupabaseMessagerieGateway { SupabaseMessagerieGateway(client: TestClient.make()) }

    private func connecte() async throws -> SupabaseClient {
        let client = TestClient.make()
        registry.add("POST", "/auth/v1/token", respond: .json(200, TestClient.sessionJSON(role: "ADMIN_ETABLISSEMENT")))
        _ = try await SupabaseAuthGateway(client: client).signIn(email: TestClient.email, password: "motdepasse-test")
        return client
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

    private func exception(_ sqlstate: String, _ message: String) -> String {
        let corps: [String: Any] = ["code": sqlstate, "message": message, "details": NSNull(), "hint": NSNull()]
        return String(decoding: try! JSONSerialization.data(withJSONObject: corps), as: UTF8.self)
    }

    // MARK: - Identité de l'auteur

    func testEnvoiSousLeJetonDuMembreSansAuteurNiEtablissementDansLeCorps() async throws {
        let client = try await connecte()
        let jeton = try XCTUnwrap(client.auth.currentSession?.accessToken)
        registry.add("POST", edge, respond: .json(200, #"{"success":true,"message_id":"1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"}"#))
        let issue = try await SupabaseMessagerieGateway(client: client)
            .envoyer(conversationId: conversation, contenu: "Bonjour, à quelle heure arrivez-vous ?", etab: etab())
        XCTAssertEqual(issue, .envoye(messageId: "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"))
        let requete = try XCTUnwrap(registry.requests(to: edge).first)
        XCTAssertEqual(requete.header("Authorization"), "Bearer \(jeton)",
                       "auteur = utilisateur de la session (auth.uid() de l'edge), jamais l'établissement")
        let corps = try XCTUnwrap(requete.bodyJSON as? [String: Any])
        XCTAssertEqual(Set(corps.keys), ["conversation_id", "content"], "aucun auteur ni établissement envoyé par l'app")
        XCTAssertFalse(String(describing: corps).contains(etablissement))
    }

    func testContexteDontLUtilisateurNEstPasLaSessionRefuseAvantEnvoi() async throws {
        let client = try await connecte()
        // Un contexte qui prendrait l'établissement pour auteur (userId = etablissement_id) n'est jamais envoyé.
        let refus = await erreur {
            _ = try await SupabaseMessagerieGateway(client: client)
                .envoyer(conversationId: self.conversation, contenu: "Bonjour", etab: self.etab(userId: self.etablissement))
        }
        XCTAssertEqual(refus?.kind, .unauthorized)
        XCTAssertTrue(registry.requests(to: edge).isEmpty, "aucun envoi sous une autre identité que la session")
    }

    func testContexteEtablissementIncoherentAucuneRequete() async throws {
        let incoherent = await erreur { _ = try await self.gateway().conversations(avant: nil, etab: self.etab(etablissementId: " ")) }
        XCTAssertEqual(incoherent?.kind, .unauthorized)
        let sansUtilisateur = await erreur { _ = try await self.gateway().nonLus(etab: self.etab(userId: "")) }
        XCTAssertEqual(sansUtilisateur?.kind, .unauthorized)
        XCTAssertTrue(registry.requests.isEmpty)
    }

    // MARK: - Liste, fil, badge

    func testListeFilEtBadgeMemesLecturesQueLeLot4() async throws {
        let lister = rpc("fn_lister_conversations_messagerie")
        let badge = rpc("fn_messages_non_lus")
        let lus = rpc("fn_marquer_messages_lus")
        registry.add("POST", lister, respond: .json(200, "[]"))
        registry.add("GET", table, respond: .json(200, "[]"))
        registry.add("POST", lus, respond: StubResponse(status: 204, headers: [:], body: Data(), failure: nil))
        registry.add("POST", badge, respond: .json(200, "2"))
        let passerelle = gateway()
        let page = try await passerelle.conversations(avant: nil, etab: etab())
        XCTAssertEqual(page.conversations, [])
        XCTAssertNil(page.suivant)
        _ = try await passerelle.messages(conversationId: conversation, etab: etab())
        let lecture = try await passerelle.marquerLus(conversationId: conversation, etab: etab())
        XCTAssertEqual(lecture, .lus)
        let nonLus = try await passerelle.nonLus(etab: etab())
        XCTAssertEqual(nonLus, 2, "badge = entier nu de fn_messages_non_lus (comptage d'équipe serveur), jamais recalculé")
        let fil = try XCTUnwrap(registry.requests(to: table).first)
        XCTAssertTrue(fil.url.absoluteString.contains("conversation_id=eq.\(conversation)"), "fil filtré par conversation")
        XCTAssertEqual(registry.requests.map(\.path), [lister, table, lus, badge])
    }

    // MARK: - « Contacter le soignant »

    func testContacterLeSoignantObtenirConversationSeule() async throws {
        let obtenir = rpc("fn_obtenir_conversation")
        registry.add("POST", obtenir, respond: .json(200, #""\#(conversation)""#))
        let issue = try await gateway().conversationPourSoignant(missionId: mission, soignantId: soignant.uppercased(), etab: etab())
        XCTAssertEqual(issue, .conversation(id: conversation))
        XCTAssertEqual(registry.requests.map(\.path), [obtenir], "aucune résolution d'établissement côté établissement")
        let corps = try XCTUnwrap(registry.requests(to: obtenir).first?.bodyJSON as? [String: Any])
        XCTAssertEqual(corps["p_autre_id"] as? String, soignant)
        XCTAssertEqual(corps["p_mission_id"] as? String, mission)
    }

    func testContacterLeSoignantRefusesJamaisSessionSaufNonAuthentifie() async throws {
        let obtenir = rpc("fn_obtenir_conversation")
        registry.add("POST", obtenir, respond: .json(403, exception("42501", "Conversation non autorisée")))
        let refusee = try await gateway().conversationPourSoignant(missionId: mission, soignantId: soignant, etab: etab())
        XCTAssertEqual(refusee, .indisponible(message: "Conversation non autorisée"))

        registry.reset()
        registry.add("POST", obtenir, respond: .json(200, "null"))
        let vide = try await gateway().conversationPourSoignant(missionId: mission, soignantId: soignant, etab: etab())
        XCTAssertEqual(vide, .indisponible(message: MessagerieRepli.message))

        registry.reset()
        registry.add("POST", obtenir, respond: .json(401, exception("28000", "Non authentifié")))
        let session = await erreur {
            _ = try await self.gateway().conversationPourSoignant(missionId: self.mission, soignantId: self.soignant, etab: self.etab())
        }
        XCTAssertEqual(session?.kind, .unauthorized)

        registry.reset()
        let invalide = await erreur {
            _ = try await self.gateway().conversationPourSoignant(missionId: "pas-un-uuid", soignantId: self.soignant, etab: self.etab())
        }
        XCTAssertEqual(invalide?.kind, .contract)
        XCTAssertTrue(registry.requests.isEmpty, "identifiant invalide : aucune requête")
    }
}
