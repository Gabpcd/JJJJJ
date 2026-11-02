import Foundation
import JoleneCore
import Supabase

/// `AccountPort` sur l'edge function `delete-account` (lot 1, T8 ; Apple 5.1.1), comme le web
/// `SectionConfidentialite.tsx` l.86 (`supabase.functions.invoke('delete-account', { body: {} })`).
///
/// Transport (fiche « Edge `delete-account` », `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md`) : `POST`,
/// corps `{}`, `Authorization: Bearer <access_token>` de la session courante — jamais la clé publishable
/// ni une clé de service. supabase-swift 2.55.5 : `client.functions` passe par `fetchWithAuth`, qui pose
/// lui aussi le Bearer de `auth.session` (SupabaseClient l.430-458) ; l'en-tête explicite garantit que la
/// session vérifiée ici est celle envoyée. La session doit appartenir au compte affiché
/// (`context.userId`) : sinon refus avant tout appel, jamais la suppression d'un autre compte.
///
/// Réponses : seul HTTP 200 avec `success === true` (sans `error`) est un succès (`.deleted`) ; aucune
/// relecture n'est possible (refresh tokens révoqués, utilisateur Auth supprimé). Tout autre statut
/// (`FunctionsError.httpError`), un 200 sans `success === true` ou une erreur de relais Supabase est un
/// refus `.refused(code: error_code, message: error)` verbatim, repli `CompteSuppression.refusParDefautMessage`
/// sans `error` lisible. Un seul appel, aucune nouvelle tentative automatique ; erreur de transport →
/// `JoleneError` (`SupabaseErrorMapping`), résultat inconnu côté serveur.
public struct SupabaseAccountGateway: AccountPort {
    /// Nom de l'edge function (`supabase/functions/delete-account/index.ts`).
    public static let fonction = "delete-account"

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func deleteAccount(context: MissionReadContext) async throws -> DeleteAccountOutcome {
        try MissionQuery.validate(context: context)
        let session: Session
        do {
            session = try await client.auth.session
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: SupabaseErrorMapping.unauthorizedMessage)
        }
        guard session.user.id.uuidString.lowercased() == context.userId.lowercased() else {
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        }
        let options = FunctionInvokeOptions(method: .post, headers: ["Authorization": "Bearer \(session.accessToken)"],
                                            body: [String: String]())
        do {
            return try await client.functions.invoke(Self.fonction, options: options) { corps, _ in
                Self.issue(corps: corps)
            }
        } catch FunctionsError.httpError(_, let corps) {
            return Self.refus(RPCResponse(Self.lire(corps)))
        } catch FunctionsError.relayError {
            return .refused(code: nil, message: CompteSuppression.refusParDefautMessage)
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: CompteSuppression.refusParDefautMessage)
        }
    }

    // MARK: - Interprétation

    /// Corps d'une réponse 2xx : `{success:true}` sans `error` → supprimé ; sinon refus (web l.88-89 :
    /// `data?.error || data?.success !== true`).
    static func issue(corps: Data) -> DeleteAccountOutcome {
        let reponse = RPCResponse(lire(corps))
        guard reponse.success == true, reponse.erreur == nil else { return refus(reponse) }
        return .deleted
    }

    /// Refus verbatim : `error` du serveur et son `error_code` (seule clé de code posée par l'edge).
    static func refus(_ reponse: RPCResponse) -> DeleteAccountOutcome {
        .refused(code: reponse.codeErreur, message: reponse.erreur ?? CompteSuppression.refusParDefautMessage)
    }

    /// Corps JSON tolérant : vide, non JSON (page de passerelle) ou scalaire → `null`.
    static func lire(_ corps: Data) -> AnyJSON {
        (try? JSONDecoder().decode(AnyJSON.self, from: corps)) ?? .null
    }
}
