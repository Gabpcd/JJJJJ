import Foundation
import JoleneCore
import Supabase
import XCTest
@testable import JoleneSupabase

/// Exceptions PostgREST du lot 4 (blueprint `docs/mobile-swift/LOT4_PLAN.md` §2.4, corrections 14 et 15, tranche T1) :
/// couple « SQLSTATE et message connu » lu AVANT `SupabaseErrorMapping` (inchangé). `28000` → session expirée ; un
/// `42501` au message métier connu → refus restitué mot pour mot, jamais « Votre session a expiré » ; un `42501` au
/// message inconnu garde le comportement du lot 0 ; un GRANT manquant reste `.contract`. Une seule requête par appel.
final class RPCResponseExceptionsLot4Tests: XCTestCase {
    private let registry = StubRegistry.shared
    private let fallback = "Impossible de charger la messagerie. Réessayez."
    private let lus = "/rest/v1/rpc/fn_marquer_messages_lus"

    override func setUp() {
        super.setUp()
        registry.reset()
    }

    private func exception(_ sqlstate: String, _ message: String) -> String {
        let corps: [String: Any] = ["code": sqlstate, "message": message, "details": NSNull(), "hint": NSNull()]
        return String(decoding: try! JSONSerialization.data(withJSONObject: corps), as: UTF8.self)
    }

    private func appeler(_ fonction: String, _ exceptions: ExceptionsLot4, statut: Int, sqlstate: String,
                         message: String) async throws -> RPCResponse {
        registry.reset()
        registry.add("POST", "/rest/v1/rpc/\(fonction)", respond: .json(statut, exception(sqlstate, message)))
        return try await RPCResponse.appeler(TestClient.make(), fonction, params: ["p_conversation_id": .string("c1")],
                                             fallback: fallback, exceptions: exceptions)
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

    func testRefus42501ConnusRestituesMotPourMot() async throws {
        let cas: [(String, ExceptionsLot4, String)] = [
            ("fn_marquer_messages_lus", ExceptionsMetierLot4.marquerMessagesLus, "Accès refusé"),
            ("fn_obtenir_conversation", ExceptionsMetierLot4.obtenirConversation, "Conversation non autorisée"),
            ("fn_user_id_pour_etablissement", ExceptionsMetierLot4.userIdPourEtablissement, "Non autorisé"),
            ("fn_typing_start", ExceptionsMetierLot4.typingStart, "NON_AUTORISE"),
            ("fn_interlocuteurs_conversations", ExceptionsMetierLot4.interlocuteurs, "Compte inactif"),
            ("fn_lister_copies_bulletins", ExceptionsMetierLot4.listerCopiesBulletins, "COPIE_ACCES_REFUSE"),
            ("fn_signaler_copie_bulletin", ExceptionsMetierLot4.signalerCopieBulletin, "COPIE_ACCES_REFUSE"),
        ]
        for (fonction, exceptions, message) in cas {
            let r = try await appeler(fonction, exceptions, statut: 403, sqlstate: "42501", message: message)
            XCTAssertTrue(r.estRefus, message)
            XCTAssertEqual(r.sqlstate, "42501", message)
            XCTAssertEqual(r.erreur, message, "verbatim, jamais « session expirée »")
            XCTAssertEqual(registry.requests(to: "/rest/v1/rpc/\(fonction)").count, 1, "\(fonction) : une seule requête")
        }
    }

    func testSessionAbsente28000QuelQueSoitLeMessage() async {
        for message in ["Non authentifié", "NON_AUTHENTIFIE", "autre"] {
            let e = await erreur {
                _ = try await self.appeler("fn_marquer_messages_lus", ExceptionsMetierLot4.marquerMessagesLus,
                                           statut: 403, sqlstate: "28000", message: message)
            }
            XCTAssertEqual(e?.kind, .unauthorized, message)
            XCTAssertEqual(e?.message, SupabaseErrorMapping.unauthorizedMessage, message)
        }
    }

    func test42501InconnuGardeLeComportementDuLot0() async {
        let e = await erreur {
            _ = try await self.appeler("fn_marquer_messages_lus", ExceptionsMetierLot4.marquerMessagesLus,
                                       statut: 403, sqlstate: "42501", message: "Conversation non autorisée")
        }
        XCTAssertEqual(e?.kind, .unauthorized, "message connu d'une AUTRE RPC : non restitué ici")
    }

    func testPrivilegeManquantResteUneErreurDeContrat() async {
        let e = await erreur {
            _ = try await self.appeler("fn_marquer_messages_lus", ExceptionsMetierLot4.marquerMessagesLus,
                                       statut: 403, sqlstate: "42501", message: "permission denied for function fn_marquer_messages_lus")
        }
        XCTAssertEqual(e?.kind, .contract)
    }

    func testDefautsDuClientEnErreurDeContrat() async {
        let cas: [(String, ExceptionsLot4, String)] = [
            ("fn_obtenir_conversation", ExceptionsMetierLot4.obtenirConversation, "Interlocuteur invalide"),
            ("fn_lister_conversations_messagerie", ExceptionsMetierLot4.listerConversations, "Curseur incomplet"),
            ("fn_signaler_copie_bulletin", ExceptionsMetierLot4.signalerCopieBulletin, "COPIE_MOTIF_INVALIDE"),
        ]
        for (fonction, exceptions, message) in cas {
            let e = await erreur {
                _ = try await self.appeler(fonction, exceptions, statut: 400, sqlstate: "22023", message: message)
            }
            XCTAssertEqual(e?.kind, .contract, message)
        }
    }

    func testRefusP0001DeLaNotationEtCategorie23514() async throws {
        let notation = "Le signalement n’a pas pu être enregistré. Veuillez réessayer."
        let r = try await appeler("fn_signaler_notation", ExceptionsMetierLot4.signalerNotation, statut: 400,
                                  sqlstate: "P0001", message: notation)
        XCTAssertEqual(r.erreur, notation)
        let categorie = try await appeler("fn_soumettre_reclamation", ExceptionsMetierLot4.soumettreReclamation, statut: 400,
                                          sqlstate: "23514", message: "new row violates check constraint \"reclamations_categorie_check\"")
        XCTAssertEqual(categorie.sqlstate, "23514", "refus structuré : la gateway T8 affiche le libellé générique")
    }

    func testSucces200NonIntercepteEtFormeSansSuccess() async throws {
        registry.add("POST", "/rest/v1/rpc/fn_soumettre_reclamation", respond: .json(200, #"{"id":"r1","statut":"EN_ATTENTE"}"#))
        let r = try await RPCResponse.appeler(TestClient.make(), "fn_soumettre_reclamation", fallback: fallback,
                                              exceptions: ExceptionsMetierLot4.soumettreReclamation)
        XCTAssertFalse(r.estRefus)
        XCTAssertFalse(r.estSucces, "{id, statut} sans success : la gateway exige `id` puis relit (§2.4)")
        XCTAssertEqual(try r.requiredString("id"), "r1")
    }
}
