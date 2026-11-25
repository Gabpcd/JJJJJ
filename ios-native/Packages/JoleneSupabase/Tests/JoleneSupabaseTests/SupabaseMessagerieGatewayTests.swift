import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Messagerie du lot 4 (T7a) : une forme de réponse des fiches de `CONTRATS_RPC_SOIGNANT.md` = un test. Curseur keyset
/// et arrêt sur curseur inchangé ; 28000 → session expirée ; 42501 au message métier connu → refus restitué, jamais
/// « session expirée » ; chaque code de l'edge `messagerie-validate` ; 200 sans `message_id` → non confirmé ;
/// `fn_messages_non_lus` relu après `marquerLus`. Codes et messages repris de `supabase/schema/public.sql` et de
/// `supabase/functions/messagerie-validate/index.ts`. Une seule requête par appel, aucun renvoi.
final class SupabaseMessagerieGatewayTests: XCTestCase {
    private let registry = StubRegistry.shared
    private let conversation = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
    private let message = "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"
    private let cible = "9d8c7b6a-5f4e-4d3c-8b2a-1f0e9d8c7b6a"
    private let mission = "2b3c4d5e-6f70-4812-9a3b-4c5d6e7f8091"
    private let etablissement = "3c4d5e6f-7081-4923-ab4c-5d6e7f809102"
    private let edge = "/functions/v1/messagerie-validate"
    private let table = "/rest/v1/messages_chat"

    private func rpc(_ fonction: String) -> String { "/rest/v1/rpc/\(fonction)" }

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func gateway() -> SupabaseMessagerieGateway { SupabaseMessagerieGateway(client: TestClient.make()) }

    /// Client connecté (session GoTrue simulée) : l'edge exige le jeton de l'utilisateur.
    private func connecte() async throws -> SupabaseClient {
        let client = TestClient.make()
        registry.add("POST", "/auth/v1/token", respond: .json(200, TestClient.sessionJSON()))
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

    private func corps(_ path: String, _ index: Int = 0) throws -> [String: Any] {
        let requetes = registry.requests(to: path)
        XCTAssertGreaterThan(requetes.count, index, "aucune requête \(path)")
        return try XCTUnwrap(requetes[index].bodyJSON as? [String: Any], "aucun corps \(path)")
    }

    private let vide = StubResponse(status: 204, headers: [:], body: Data(), failure: nil)

    private func ligne(_ numero: Int) -> String {
        let id = String(format: "00000000-0000-4000-8000-%012d", numero)
        let ordre = String(format: "2026-11-01T%02d:%02d:00.123456+00:00", 23 - numero / 60, 59 - numero % 60)
        return """
        {"id":"\(id)","participant_1_id":"\(TestClient.userId)","participant_2_id":"\(cible)","mission_id":"\(mission)",
         "etablissement_id":"\(etablissement)","soignant_id":"\(TestClient.userId)","dernier_message_le":"\(ordre)",
         "cree_le":"2026-10-01T08:00:00+00:00","archived_at":null,"autre_id":"\(cible)","dernier_contenu":"Aperçu \(numero)",
         "non_lus":\(numero % 3),"mission_intitule":"Mission \(numero)","ordre_le":"\(ordre)"}
        """
    }

    private func page(_ numeros: ClosedRange<Int>) -> String { "[\(numeros.map(ligne).joined(separator: ","))]" }

    // MARK: - Liste : curseur keyset

    func testPremierePageSansCurseurPuisPageSuivanteAuCurseur() async throws {
        let lister = rpc("fn_lister_conversations_messagerie")
        registry.add("POST", lister, respond: .json(200, page(1...100)))
        let premiere = try await gateway().conversations(avant: nil, context: TestClient.context)
        XCTAssertEqual(premiere.conversations.count, 100)
        XCTAssertEqual(premiere.conversations.first?.dernierContenu, "Aperçu 1")
        XCTAssertEqual(premiere.conversations.first?.nonLus, 1)
        XCTAssertEqual(premiere.conversations.first?.autreId, cible)
        let curseur = try XCTUnwrap(premiere.suivant, "page pleine : curseur de la dernière ligne")
        XCTAssertEqual(curseur, premiere.conversations.last?.curseur)
        XCTAssertEqual(curseur.ordreLe, "2026-11-01T22:19:00.123456+00:00", "ordre_le tel que servi, microsecondes comprises")
        let envoye = try corps(lister)
        XCTAssertTrue(envoye["p_avant"] is NSNull, "premier appel : curseur nul des deux côtés, comme le web")
        XCTAssertTrue(envoye["p_avant_id"] is NSNull)
        XCTAssertEqual(envoye["p_limite"] as? Int, 100)

        registry.reset()
        registry.add("POST", lister, respond: .json(200, page(101...103)))
        let seconde = try await gateway().conversations(avant: curseur, context: TestClient.context)
        XCTAssertEqual(seconde.conversations.count, 3)
        XCTAssertNil(seconde.suivant, "page incomplète : fin de la pagination")
        let suite = try corps(lister)
        XCTAssertEqual(suite["p_avant"] as? String, curseur.ordreLe)
        XCTAssertEqual(suite["p_avant_id"] as? String, curseur.id)
        XCTAssertEqual(registry.requests(to: lister).count, 1, "une page = une requête")
    }

    func testArretSurCurseurInchangeOuIncomplet() async throws {
        let lister = rpc("fn_lister_conversations_messagerie")
        registry.add("POST", lister, respond: .json(200, page(1...100)))
        let derniere = CurseurConversations(ordreLe: "2026-11-01T22:19:00.123456+00:00", id: "00000000-0000-4000-8000-000000000100")
        let figee = try await gateway().conversations(avant: derniere, context: TestClient.context)
        XCTAssertEqual(figee.conversations.count, 100)
        XCTAssertNil(figee.suivant, "curseur de la dernière ligne = curseur envoyé : arrêt")

        registry.reset()
        let sansOrdre = (1...100).map { numero in numero == 100 ? #"{"id":"00000000-0000-4000-8000-000000000100"}"# : ligne(numero) }
        registry.add("POST", lister, respond: .json(200, "[\(sansOrdre.joined(separator: ","))]"))
        let incomplete = try await gateway().conversations(avant: nil, context: TestClient.context)
        XCTAssertNil(incomplete.suivant, "dernière ligne sans ordre_le : arrêt, jamais un curseur incomplet")
    }

    func testListeSessionAbsenteCurseurIncompletEtFormeInattendue() async throws {
        let lister = rpc("fn_lister_conversations_messagerie")
        registry.add("POST", lister, respond: .json(403, exception("28000", "Non authentifié")))
        let session = await erreur { _ = try await self.gateway().conversations(avant: nil, context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized, "28000 → session expirée")
        XCTAssertEqual(session?.message, SupabaseErrorMapping.unauthorizedMessage)

        registry.reset()
        registry.add("POST", lister, respond: .json(400, exception("22023", "Curseur incomplet")))
        let curseur = await erreur { _ = try await self.gateway().conversations(avant: nil, context: TestClient.context) }
        XCTAssertEqual(curseur?.kind, .contract, "défaut du client, jamais « session expirée »")

        registry.reset()
        registry.add("POST", lister, respond: .json(200, #"{"conversations":[]}"#))
        let forme = await erreur { _ = try await self.gateway().conversations(avant: nil, context: TestClient.context) }
        XCTAssertEqual(forme?.kind, .contract, "réponse qui n'est pas un tableau : jamais une liste vide plausible")

        registry.reset()
        registry.add("POST", lister, respond: .json(200, #"[\#(ligne(1)),{"autre_id":"sans-id"},\#(ligne(2))]"#))
        let tolerante = try await gateway().conversations(avant: nil, context: TestClient.context)
        XCTAssertEqual(tolerante.conversations.count, 2, "ligne illisible écartée seule")
        XCTAssertEqual(registry.requests(to: lister).count, 1)
    }

    // MARK: - Interlocuteurs

    func testInterlocuteursParLotEtRefus() async throws {
        let noms = rpc("fn_interlocuteurs_conversations")
        registry.add("POST", noms, respond: .json(200, """
        [{"conversation_id":"\(conversation)","participant_id":"\(cible)","prenom":"Clinique fictive","nom":"","avatar_url":null,"est_jolene":false},
         {"participant_id":"sans-conversation"}]
        """))
        let lignes = try await gateway().interlocuteurs(ids: [conversation], context: TestClient.context)
        XCTAssertEqual(lignes, [Interlocuteur(conversationId: conversation, participantId: cible, prenom: "Clinique fictive", nom: nil)])
        XCTAssertEqual(try corps(noms)["p_conversation_ids"] as? [String], [conversation])

        registry.reset()
        let aucun = try await gateway().interlocuteurs(ids: [], context: TestClient.context)
        XCTAssertEqual(aucun, [])
        let trop = await erreur { _ = try await self.gateway().interlocuteurs(ids: (0...100).map { "c-\($0)" }, context: TestClient.context) }
        XCTAssertEqual(trop?.kind, .contract, "plus de cent identifiants : jamais envoyé")
        XCTAssertTrue(registry.requests.isEmpty, "liste vide ou trop longue : aucune requête")

        registry.add("POST", noms, respond: .json(403, exception("42501", "Compte inactif")))
        let inactif = await erreur { _ = try await self.gateway().interlocuteurs(ids: [self.conversation], context: TestClient.context) }
        XCTAssertEqual(inactif, JoleneError(.unknown, "Compte inactif"), "refus métier mot pour mot, jamais « session expirée »")

        registry.reset()
        registry.add("POST", noms, respond: .json(400, exception("22023", "Trop de conversations demandées")))
        let serveur = await erreur { _ = try await self.gateway().interlocuteurs(ids: [self.conversation], context: TestClient.context) }
        XCTAssertEqual(serveur?.kind, .contract)

        registry.reset()
        registry.add("POST", noms, respond: .json(403, exception("28000", "Non authentifié")))
        let session = await erreur { _ = try await self.gateway().interlocuteurs(ids: [self.conversation], context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized)
    }

    // MARK: - Fil (PostgREST messages_chat)

    private func ligneMessage(_ id: String, _ creeLe: String, auteur: String? = nil) -> String {
        #"{"id":"\#(id)","conversation_id":"\#(conversation)","auteur_id":"\#(auteur ?? cible)","contenu":"Bonjour","est_admin":false,"lu":false,"cree_le":"\#(creeLe)"}"#
    }

    func testFilCinqCentsDerniersRendusDansLOrdreCroissant() async throws {
        registry.add("GET", table, respond: .json(200, """
        [\(ligneMessage("m-3", "2026-11-02T10:02:00+00:00")),{"id":"illisible"},\(ligneMessage("m-2", "2026-11-02T10:01:00+00:00")),
         \(ligneMessage("m-1", "2026-11-02T10:00:00+00:00"))]
        """))
        let fil = try await gateway().messages(conversationId: conversation.uppercased(), context: TestClient.context)
        XCTAssertEqual(fil.map(\.id), ["m-1", "m-2", "m-3"], "lus du plus récent au plus ancien, rendus dans l'ordre du fil")
        let requete = try XCTUnwrap(registry.requests(to: table).first)
        XCTAssertEqual(requete.query("select"), "id,conversation_id,auteur_id,contenu,est_admin,lu,cree_le")
        XCTAssertEqual(requete.query("conversation_id"), "eq.\(conversation)", "uuid canonique")
        XCTAssertEqual(requete.query("order"), "cree_le.desc.nullslast", "du plus récent au plus ancien (suffixe du SDK)")
        XCTAssertEqual(requete.query("limit"), "500")
        XCTAssertNil(requete.query("cree_le"))
        XCTAssertEqual(registry.requests.count, 1)
    }

    func testRelectureDepuisUnCreeLeEncodeLeFuseau() async throws {
        let depuis = "2026-11-02T10:01:00.123456+00:00"
        registry.add("GET", table, respond: .json(200, "[\(ligneMessage("m-3", "2026-11-02T10:02:00+00:00"))]"))
        let fil = try await gateway().messages(conversationId: conversation, depuis: depuis, context: TestClient.context)
        XCTAssertEqual(fil.map(\.id), ["m-3"])
        let requete = try XCTUnwrap(registry.requests(to: table).first)
        XCTAssertEqual(requete.query("cree_le"), "gte.\(depuis)", "valeur servie renvoyée telle quelle")
        XCTAssertTrue(requete.url.absoluteString.contains("%2B00"), "« + » du fuseau encodé, jamais lu comme une espace")
        XCTAssertEqual(requete.query("conversation_id"), "eq.\(conversation)")
        XCTAssertEqual(requete.query("limit"), "500")
    }

    func testMessageReluParIdEtAbsent() async throws {
        registry.add("GET", table, respond: .json(200, "[\(ligneMessage(message, "2026-11-02T10:02:00+00:00", auteur: TestClient.userId))]"))
        let relu = try await gateway().message(id: message, conversationId: conversation, context: TestClient.context)
        XCTAssertEqual(relu?.id, message)
        XCTAssertEqual(relu?.auteurId, TestClient.userId)
        let requete = try XCTUnwrap(registry.requests(to: table).first)
        XCTAssertEqual(requete.query("id"), "eq.\(message)")
        XCTAssertEqual(requete.query("conversation_id"), "eq.\(conversation)")
        XCTAssertEqual(requete.query("limit"), "1")

        registry.reset()
        registry.add("GET", table, respond: .json(200, "[]"))
        let absent = try await gateway().message(id: message, conversationId: conversation, context: TestClient.context)
        XCTAssertNil(absent, "ligne non relue : jamais un message fabriqué")
    }

    func testLectureDuFilEnEchec() async throws {
        registry.add("GET", table, respond: .json(401, #"{"code":"PGRST301","message":"JWT expired"}"#))
        let session = await erreur { _ = try await self.gateway().messages(conversationId: self.conversation, context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized)
        registry.reset()
        registry.add("GET", table, respond: .json(200, #"{"pas":"un tableau"}"#))
        let forme = await erreur { _ = try await self.gateway().messages(conversationId: self.conversation, context: TestClient.context) }
        XCTAssertEqual(forme?.kind, .contract)
    }

    // MARK: - Envoi par l'edge

    private func envoyer(_ status: Int, _ corps: String, file: StaticString = #filePath, line: UInt = #line) async throws -> EnvoiOutcome {
        registry.reset()
        let client = try await connecte()
        registry.add("POST", edge, respond: .json(status, corps))
        let issue = try await SupabaseMessagerieGateway(client: client)
            .envoyer(conversationId: conversation, contenu: "Bonjour", context: TestClient.context)
        XCTAssertEqual(registry.requests(to: edge).count, 1, "un seul appel, aucun renvoi automatique", file: file, line: line)
        XCTAssertTrue(registry.unmatched.isEmpty, file: file, line: line)
        return issue
    }

    func testEnvoi200AvecMessageIdEtCorpsDeLaRequete() async throws {
        let client = try await connecte()
        let jeton = try XCTUnwrap(client.auth.currentSession?.accessToken)
        registry.add("POST", edge, respond: .json(200, #"{"success":true,"message_id":"\#(message)"}"#))
        let issue = try await SupabaseMessagerieGateway(client: client)
            .envoyer(conversationId: conversation.uppercased(), contenu: "Bonjour à vous", context: TestClient.context)
        XCTAssertEqual(issue, .envoye(messageId: message))
        let requete = try XCTUnwrap(registry.requests(to: edge).first)
        XCTAssertEqual(requete.method, "POST")
        XCTAssertEqual(requete.header("Authorization"), "Bearer \(jeton)", "jeton de l'utilisateur, jamais la clé publishable")
        let envoye = try XCTUnwrap(requete.bodyJSON as? [String: Any])
        XCTAssertEqual(envoye["conversation_id"] as? String, conversation)
        XCTAssertEqual(envoye["content"] as? String, "Bonjour à vous")
        XCTAssertEqual(Set(envoye.keys), ["conversation_id", "content"])
        XCTAssertTrue(registry.requests(to: table).isEmpty, "la relecture de la ligne est demandée par le modèle, pas supposée")
    }

    func testEnvoi200SansMessageIdNonConfirme() async throws {
        for corps in [#"{"success":true}"#, #"{"success":true,"message_id":""}"#, #"{"success":true,"message_id":42}"#,
                      #"{"message_id":"\#(message)"}"#, #"{"success":false,"message_id":"\#(message)"}"#, "[]", "bonjour"] {
            let issue = try await envoyer(200, corps)
            XCTAssertEqual(issue, .nonConfirme, "200 sans succès ET message_id : REPONSE_ENVOI_INVALIDE du web — \(corps)")
        }
    }

    func testChaqueCodeDeLEdge() async throws {
        let repli = MessagerieRepli.message
        let cas: [(Int, String, EnvoiOutcome)] = [
            (400, #"{"success":false,"error":"ANTI_LEAK_REFUSE","detected_type":"TELEPHONE"}"#, .antiFuite(.telephone)),
            (400, #"{"success":false,"error":"ANTI_LEAK_REFUSE","detected_type":"EMAIL"}"#, .antiFuite(.email)),
            (400, #"{"success":false,"error":"ANTI_LEAK_REFUSE","detected_type":"URL"}"#, .antiFuite(.url)),
            (400, #"{"success":false,"error":"ANTI_LEAK_REFUSE","detected_type":"HANDLE"}"#, .antiFuite(.handle)),
            (400, #"{"success":false,"error":"ANTI_LEAK_REFUSE","detected_type":"KEYWORD"}"#, .antiFuite(.keyword)),
            (400, #"{"success":false,"error":"ANTI_LEAK_REFUSE"}"#, .antiFuite(nil)),
            (400, #"{"success":false,"error":"BAD_REQUEST"}"#, .refuse(code: "BAD_REQUEST", message: repli)),
            (400, #"{"success":false,"error":"CONTENT_EMPTY"}"#, .refuse(code: "CONTENT_EMPTY", message: repli)),
            (403, #"{"success":false,"error":"CONVERSATION_NON_AUTORISEE"}"#, .refuse(code: "CONVERSATION_NON_AUTORISEE", message: repli)),
            (403, #"{"success":false,"error":"ENVOI_REFUSE"}"#, .refuse(code: "ENVOI_REFUSE", message: repli)),
            (403, #"{"success":false,"error":"Vous ne pouvez plus écrire dans cette conversation."}"#,
             .refuse(code: nil, message: "Vous ne pouvez plus écrire dans cette conversation.")),
            (403, #"{"success":false,"error":"REFUS_RELAYE_FUTUR"}"#, .refuse(code: "REFUS_RELAYE_FUTUR", message: repli)),
            (409, #"{"success":false,"error":"CONVERSATION_ARCHIVEE"}"#, .refuse(code: "CONVERSATION_ARCHIVEE", message: repli)),
            (413, #"{"success":false,"error":"CONTENT_TOO_LARGE","max":4000}"#, .refuse(code: "CONTENT_TOO_LARGE", message: repli)),
            (429, #"{"success":false,"error":"RATE_LIMIT"}"#, .refuse(code: "RATE_LIMIT", message: repli)),
            (503, #"{"success":false,"error":"AUTORISATION_INDISPONIBLE"}"#, .refuse(code: "AUTORISATION_INDISPONIBLE", message: repli)),
            // Issue de l'insertion inconnue : non confirmé, fil relu, aucun renvoi.
            (503, #"{"success":false,"error":"ENVOI_INDISPONIBLE"}"#, .nonConfirme),
            (500, #"{"success":false,"error":"INTERNAL_ERROR","message":"TypeError: détail technique"}"#, .nonConfirme),
        ]
        for (status, corps, attendu) in cas {
            let issue = try await envoyer(status, corps)
            XCTAssertEqual(issue, attendu, "\(status) \(corps)")
        }
        XCTAssertEqual(Set(cas.map(\.0)), [400, 403, 409, 413, 429, 500, 503], "statuts de refus de index.ts (401 et 405 à part)")
    }

    func testEnvoi401SessionExpireeEtStatutsInattendusNonConfirmes() async throws {
        registry.reset()
        let client = try await connecte()
        registry.add("POST", edge, respond: .json(401, #"{"success":false,"error":"NON_AUTHENTIFIE"}"#))
        let session = await erreur {
            _ = try await SupabaseMessagerieGateway(client: client).envoyer(conversationId: self.conversation, contenu: "Bonjour", context: TestClient.context)
        }
        XCTAssertEqual(session?.kind, .unauthorized)
        XCTAssertEqual(registry.requests(to: edge).count, 1)

        for (status, corps) in [(405, #"{"success":false,"error":"METHOD_NOT_ALLOWED"}"#), (502, "<html>Bad Gateway</html>"), (504, ""),
                                (400, #"{"success":false,"error":"CODE_INCONNU"}"#), (403, "pas du JSON"), (429, #"{"success":false}"#)] {
            let issue = try await envoyer(status, corps)
            XCTAssertEqual(issue, .nonConfirme, "statut ou corps inattendu : jamais un refus supposé, jamais un succès — \(status) \(corps)")
        }
    }

    func testEnvoiSansSessionIdentifiantInvalideEtCoupure() async throws {
        let sansSession = await erreur {
            _ = try await self.gateway().envoyer(conversationId: self.conversation, contenu: "Bonjour", context: TestClient.context)
        }
        XCTAssertEqual(sansSession?.kind, .unauthorized, "aucune session : rien n'est envoyé")
        XCTAssertTrue(registry.requests(to: edge).isEmpty)

        let invalide = await erreur {
            _ = try await self.gateway().envoyer(conversationId: "pas-un-uuid", contenu: "Bonjour", context: TestClient.context)
        }
        XCTAssertEqual(invalide?.kind, .contract)
        XCTAssertTrue(registry.requests(to: edge).isEmpty)

        registry.reset()
        let client = try await connecte()
        registry.add("POST", edge, respond: .networkFailure(.networkConnectionLost))
        let coupure = await erreur {
            _ = try await SupabaseMessagerieGateway(client: client).envoyer(conversationId: self.conversation, contenu: "Bonjour", context: TestClient.context)
        }
        XCTAssertEqual(coupure?.kind, .network, "coupure : erreur réseau, que le modèle traite en « non confirmé » sans renvoi")
        XCTAssertEqual(registry.requests(to: edge).count, 1)
    }

    // MARK: - Lecture et badge

    func testMarquerLusPuisBadgeRelu() async throws {
        let lus = rpc("fn_marquer_messages_lus")
        let badge = rpc("fn_messages_non_lus")
        registry.add("POST", lus, respond: vide)
        registry.add("POST", badge, respond: .json(200, "4"))
        let passerelle = gateway()
        let issue = try await passerelle.marquerLus(conversationId: conversation, context: TestClient.context)
        XCTAssertEqual(issue, .lus)
        let nonLus = try await passerelle.nonLus(context: TestClient.context)
        XCTAssertEqual(nonLus, 4, "fn_messages_non_lus relu après marquerLus : entier nu du serveur")
        XCTAssertEqual(try corps(lus)["p_conversation_id"] as? String, conversation)
        XCTAssertEqual(registry.requests.map(\.path), [lus, badge])
        XCTAssertTrue(registry.unmatched.isEmpty)
    }

    func testMarquerLusAccesRefuseSessionAbsenteEt42501Inconnu() async throws {
        let lus = rpc("fn_marquer_messages_lus")
        registry.add("POST", lus, respond: .json(403, exception("42501", "Accès refusé")))
        let refuse = try await gateway().marquerLus(conversationId: conversation, context: TestClient.context)
        XCTAssertEqual(refuse, .accesRefuse, "42501 « Accès refusé » : refus métier, jamais une déconnexion")
        XCTAssertEqual(registry.requests(to: lus).count, 1)

        registry.reset()
        registry.add("POST", lus, respond: .json(403, exception("28000", "Non authentifié")))
        let session = await erreur { _ = try await self.gateway().marquerLus(conversationId: self.conversation, context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized)

        registry.reset()
        registry.add("POST", lus, respond: .json(403, exception("42501", "permission denied for function fn_marquer_messages_lus")))
        let grant = await erreur { _ = try await self.gateway().marquerLus(conversationId: self.conversation, context: TestClient.context) }
        XCTAssertEqual(grant?.kind, .contract, "GRANT manquant : défaut de contrat")

        registry.reset()
        registry.add("POST", lus, respond: .json(403, exception("42501", "autre message")))
        let inconnu = await erreur { _ = try await self.gateway().marquerLus(conversationId: self.conversation, context: TestClient.context) }
        XCTAssertEqual(inconnu?.kind, .unauthorized, "42501 au message inconnu : comportement du lot 0")
    }

    func testBadgeEntierNuSinonContrat() async throws {
        let badge = rpc("fn_messages_non_lus")
        registry.add("POST", badge, respond: .json(200, "0"))
        let zero = try await gateway().nonLus(context: TestClient.context)
        XCTAssertEqual(zero, 0)
        let parametres = registry.requests(to: badge).first?.bodyJSON as? [String: Any]
        XCTAssertTrue(parametres?.isEmpty ?? true, "aucun paramètre")
        for corps in [#""4""#, "null", #"{"non_lus":4}"#, "-1", "2.5"] {
            registry.reset()
            registry.add("POST", badge, respond: .json(200, corps))
            let forme = await erreur { _ = try await self.gateway().nonLus(context: TestClient.context) }
            XCTAssertEqual(forme?.kind, .contract, "jamais un badge fabriqué — \(corps)")
        }
    }

    // MARK: - Saisie et présence

    func testSaisieEtPresence() async throws {
        let debut = rpc("fn_typing_start")
        let fin = rpc("fn_typing_stop")
        let presence = rpc("fn_update_presence")
        registry.add("POST", debut, respond: vide)
        registry.add("POST", fin, respond: vide)
        registry.add("POST", presence, respond: vide)
        let passerelle = gateway()
        try await passerelle.saisie(debut: true, conversationId: conversation, context: TestClient.context)
        try await passerelle.saisie(debut: false, conversationId: conversation, context: TestClient.context)
        try await passerelle.presence(context: TestClient.context)
        XCTAssertEqual(registry.requests.map(\.path), [debut, fin, presence])
        XCTAssertEqual(try corps(debut)["p_conversation_id"] as? String, conversation)
        XCTAssertEqual(try corps(fin)["p_conversation_id"] as? String, conversation)

        registry.reset()
        registry.add("POST", debut, respond: .json(403, exception("42501", "NON_AUTORISE")))
        try await gateway().saisie(debut: true, conversationId: conversation, context: TestClient.context) // abandonné sans erreur
        XCTAssertEqual(registry.requests(to: debut).count, 1)

        registry.reset()
        registry.add("POST", debut, respond: .json(403, exception("28000", "NON_AUTHENTIFIE")))
        let saisie = await erreur { try await self.gateway().saisie(debut: true, conversationId: self.conversation, context: TestClient.context) }
        XCTAssertEqual(saisie?.kind, .unauthorized)

        registry.reset()
        registry.add("POST", presence, respond: .json(403, exception("28000", "NON_AUTHENTIFIE")))
        let battement = await erreur { try await self.gateway().presence(context: TestClient.context) }
        XCTAssertEqual(battement?.kind, .unauthorized)
    }

    // MARK: - Blocage et signalement

    func testBlocageReluApresChaqueBascule() async throws {
        let etat = rpc("fn_est_bloque")
        let bloquer = rpc("fn_bloquer_utilisateur")
        let debloquer = rpc("fn_debloquer_utilisateur")
        registry.add("POST", etat, respond: .json(200, "false"))
        let initial = try await gateway().bloque(cibleId: cible, context: TestClient.context)
        XCTAssertFalse(initial)
        XCTAssertEqual(try corps(etat)["p_cible_id"] as? String, cible)

        registry.reset()
        registry.add("POST", bloquer, respond: .json(200, #"{"success":true}"#))
        registry.add("POST", etat, respond: .json(200, "true"))
        let bloque = try await gateway().basculerBlocage(cibleId: cible, bloquer: true, context: TestClient.context)
        XCTAssertTrue(bloque, "état relu par fn_est_bloque")
        XCTAssertEqual(registry.requests.map(\.path), [bloquer, etat])
        XCTAssertEqual(Set(try corps(bloquer).keys), ["p_cible_id"], "aucun motif envoyé, comme le web")

        registry.reset()
        registry.add("POST", debloquer, respond: .json(200, #"{"success":true}"#))
        registry.add("POST", etat, respond: .json(200, "false"))
        let debloque = try await gateway().basculerBlocage(cibleId: cible, bloquer: false, context: TestClient.context)
        XCTAssertFalse(debloque)
        XCTAssertEqual(registry.requests.map(\.path), [debloquer, etat])
    }

    func testBlocageRefusVerbatimEtFormesInattendues() async throws {
        let etat = rpc("fn_est_bloque")
        let bloquer = rpc("fn_bloquer_utilisateur")
        registry.add("POST", bloquer, respond: .json(200, #"{"error":"Cible invalide."}"#))
        let cibleInvalide = await erreur { _ = try await self.gateway().basculerBlocage(cibleId: self.cible, bloquer: true, context: TestClient.context) }
        XCTAssertEqual(cibleInvalide, JoleneError(.unknown, "Cible invalide."), "message serveur mot pour mot")
        XCTAssertTrue(registry.requests(to: etat).isEmpty, "aucune relecture d'un refus")

        registry.reset()
        registry.add("POST", bloquer, respond: .json(200, #"{"error":"Non authentifié"}"#))
        let session = await erreur { _ = try await self.gateway().basculerBlocage(cibleId: self.cible, bloquer: true, context: TestClient.context) }
        XCTAssertEqual(session?.kind, .unauthorized)

        registry.reset()
        registry.add("POST", bloquer, respond: .json(200, #"{"ok":true}"#))
        let sansSucces = await erreur { _ = try await self.gateway().basculerBlocage(cibleId: self.cible, bloquer: true, context: TestClient.context) }
        XCTAssertEqual(sansSucces?.kind, .contract, "ni `success:true` ni refus : jamais un succès supposé")

        for corps in [#""true""#, "null", "1", #"{"bloque":true}"#] {
            registry.reset()
            registry.add("POST", etat, respond: .json(200, corps))
            let forme = await erreur { _ = try await self.gateway().bloque(cibleId: self.cible, context: TestClient.context) }
            XCTAssertEqual(forme?.kind, .contract, "booléen nu exigé, comme le web — \(corps)")
        }
    }

    func testSignalerSuccesRefusVerbatimEtSessionAbsente() async throws {
        let signaler = rpc("fn_signaler_utilisateur")
        registry.add("POST", signaler, respond: .json(200, #"{"success":true,"signalement_id":"\#(message)"}"#))
        let succes = try await gateway().signaler(cibleId: etablissement, type: .etablissement, categorie: "COMPORTEMENT_INAPPROPRIE",
                                                  motif: "  Propos déplacés pendant la mission  ", missionId: mission, context: TestClient.context)
        XCTAssertEqual(succes, .signale)
        let envoye = try corps(signaler)
        XCTAssertEqual(envoye["p_cible_id"] as? String, etablissement)
        XCTAssertEqual(envoye["p_cible_type"] as? String, "ETABLISSEMENT")
        XCTAssertEqual(envoye["p_categorie"] as? String, "COMPORTEMENT_INAPPROPRIE")
        XCTAssertEqual(envoye["p_motif"] as? String, "Propos déplacés pendant la mission", "motif sans espaces de bord, comme le web")
        XCTAssertEqual(envoye["p_mission_id"] as? String, mission)

        registry.reset()
        registry.add("POST", signaler, respond: .json(200, #"{"success":true,"signalement_id":"\#(message)"}"#))
        _ = try await gateway().signaler(cibleId: etablissement, type: .etablissement, categorie: "AUTRE", motif: "Un motif assez long",
                                         missionId: nil, context: TestClient.context)
        XCTAssertTrue(try corps(signaler)["p_mission_id"] is NSNull, "sans mission : null, comme le web")

        for message in ["Cible invalide", "Catégorie invalide", "Motif obligatoire (10 caractères minimum).",
                        "Vous ne pouvez pas vous signaler vous-même.", "Profil signaleur inconnu"] {
            registry.reset()
            registry.add("POST", signaler, respond: .json(200, #"{"success":false,"error":"\#(message)"}"#))
            let refus = try await gateway().signaler(cibleId: etablissement, type: .etablissement, categorie: "AUTRE",
                                                     motif: "Un motif assez long", missionId: nil, context: TestClient.context)
            XCTAssertEqual(refus, .refuse(message: message))
        }

        registry.reset()
        registry.add("POST", signaler, respond: .json(200, #"{"success":false,"error":"Non authentifié"}"#))
        let session = await erreur {
            _ = try await self.gateway().signaler(cibleId: self.etablissement, type: .etablissement, categorie: "AUTRE",
                                                  motif: "Un motif assez long", missionId: nil, context: TestClient.context)
        }
        XCTAssertEqual(session?.kind, .unauthorized)

        registry.reset()
        registry.add("POST", signaler, respond: .json(200, #"{"success":true}"#))
        let sansId = await erreur {
            _ = try await self.gateway().signaler(cibleId: self.etablissement, type: .etablissement, categorie: "AUTRE",
                                                  motif: "Un motif assez long", missionId: nil, context: TestClient.context)
        }
        XCTAssertEqual(sansId?.kind, .contract, "succès = signalement_id présent")
    }

    // MARK: - « Écrire à l'établissement »

    func testConversationPourMissionResoutLInterlocuteurPuisLeFil() async throws {
        let interlocuteur = rpc("fn_user_id_pour_etablissement")
        let obtenir = rpc("fn_obtenir_conversation")
        registry.add("POST", interlocuteur, respond: .json(200, #""\#(cible)""#))
        registry.add("POST", obtenir, respond: .json(200, #""\#(conversation)""#))
        let issue = try await gateway().conversationPourMission(missionId: mission, etablissementId: etablissement, context: TestClient.context)
        XCTAssertEqual(issue, .conversation(id: conversation))
        XCTAssertEqual(registry.requests.map(\.path), [interlocuteur, obtenir])
        XCTAssertEqual(try corps(interlocuteur)["p_etablissement_id"] as? String, etablissement)
        let fil = try corps(obtenir)
        XCTAssertEqual(fil["p_autre_id"] as? String, cible)
        XCTAssertEqual(fil["p_mission_id"] as? String, mission, "jamais sans mission : pas de création libre de conversation (D8)")
    }

    func testConversationIndisponibleJamaisSessionExpiree() async throws {
        let interlocuteur = rpc("fn_user_id_pour_etablissement")
        let obtenir = rpc("fn_obtenir_conversation")
        registry.add("POST", interlocuteur, respond: .json(200, "null"))
        let aucun = try await gateway().conversationPourMission(missionId: mission, etablissementId: etablissement, context: TestClient.context)
        XCTAssertEqual(aucun, .indisponible(message: MessagerieRepli.message), "aucun interlocuteur actif")
        XCTAssertTrue(registry.requests(to: obtenir).isEmpty)

        registry.reset()
        registry.add("POST", interlocuteur, respond: .json(403, exception("42501", "Non autorisé")))
        let nonAutorise = try await gateway().conversationPourMission(missionId: mission, etablissementId: etablissement, context: TestClient.context)
        XCTAssertEqual(nonAutorise, .indisponible(message: "Non autorisé"))
        XCTAssertTrue(registry.requests(to: obtenir).isEmpty)

        registry.reset()
        registry.add("POST", interlocuteur, respond: .json(200, #""\#(cible)""#))
        registry.add("POST", obtenir, respond: .json(403, exception("42501", "Conversation non autorisée")))
        let refusee = try await gateway().conversationPourMission(missionId: mission, etablissementId: etablissement, context: TestClient.context)
        XCTAssertEqual(refusee, .indisponible(message: "Conversation non autorisée"),
                       "fn_obtenir_conversation 42501 → conversation indisponible, jamais « session expirée »")

        registry.reset()
        registry.add("POST", interlocuteur, respond: .json(200, #""\#(cible)""#))
        registry.add("POST", obtenir, respond: .json(200, "null"))
        let sansFil = try await gateway().conversationPourMission(missionId: mission, etablissementId: etablissement, context: TestClient.context)
        XCTAssertEqual(sansFil, .indisponible(message: MessagerieRepli.message))

        registry.reset()
        registry.add("POST", interlocuteur, respond: .json(200, #""\#(cible)""#))
        registry.add("POST", obtenir, respond: .json(400, exception("22023", "Interlocuteur invalide")))
        let invalide = await erreur {
            _ = try await self.gateway().conversationPourMission(missionId: self.mission, etablissementId: self.etablissement, context: TestClient.context)
        }
        XCTAssertEqual(invalide?.kind, .contract)

        registry.reset()
        registry.add("POST", interlocuteur, respond: .json(403, exception("28000", "Non authentifié")))
        let session = await erreur {
            _ = try await self.gateway().conversationPourMission(missionId: self.mission, etablissementId: self.etablissement, context: TestClient.context)
        }
        XCTAssertEqual(session?.kind, .unauthorized)
    }

    func testIdentifiantsInvalidesSansRequete() async throws {
        let passerelle = gateway()
        let operations: [() async throws -> Void] = [
            { _ = try await passerelle.messages(conversationId: "x", context: TestClient.context) },
            { _ = try await passerelle.messages(conversationId: "x", depuis: "2026-11-02T10:00:00+00:00", context: TestClient.context) },
            { _ = try await passerelle.message(id: "x", conversationId: self.conversation, context: TestClient.context) },
            { _ = try await passerelle.marquerLus(conversationId: "x", context: TestClient.context) },
            { try await passerelle.saisie(debut: true, conversationId: "x", context: TestClient.context) },
            { _ = try await passerelle.bloque(cibleId: "x", context: TestClient.context) },
            { _ = try await passerelle.basculerBlocage(cibleId: "x", bloquer: true, context: TestClient.context) },
            { _ = try await passerelle.signaler(cibleId: "x", type: .etablissement, categorie: "AUTRE", motif: "Un motif assez long",
                                               missionId: nil, context: TestClient.context) },
            { _ = try await passerelle.conversationPourMission(missionId: "x", etablissementId: self.etablissement, context: TestClient.context) },
        ]
        for operation in operations {
            let refus = await erreur(operation)
            XCTAssertEqual(refus?.kind, .contract)
        }
        XCTAssertTrue(registry.requests.isEmpty, "identifiant invalide : aucune requête")
    }
}
