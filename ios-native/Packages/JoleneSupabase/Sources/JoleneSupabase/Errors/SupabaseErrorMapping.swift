import Foundation
import JoleneCore
import Supabase

/// Traduction des erreurs du SDK vers `JoleneError`. Règles (brief lot 0, point 5) :
/// - PostgREST `PGRST200`…`PGRST203` (dont `PGRST202` fonction introuvable) et HTTP 300…303
///   => `.contract`, refus définitif : la version de l'app ne correspond plus au backend,
///   aucun retry n'a de sens.
/// - Erreur réseau (`URLError`) => `.network`.
/// - HTTP 401/403, JWT invalide (`PGRST301`…`PGRST303`), privilège insuffisant (`42501`),
///   session absente => `.unauthorized`.
/// - Annulation => `.cancelled`.
/// Aucun message ne reprend une valeur saisie ni un détail technique du serveur.
public enum SupabaseErrorMapping {
    public static let contractMessage = "Cette version de l'application n'est plus compatible avec le service. Mettez-la à jour."
    public static let networkMessage = "Connexion impossible. Vérifiez votre réseau puis réessayez."
    public static let unauthorizedMessage = "Votre session a expiré. Reconnectez-vous."
    public static let cancelledMessage = "Chargement annulé."

    /// Codes PostgREST signalant un décalage de contrat (relation, embedding ou fonction).
    public static let contractCodes: Set<String> = ["PGRST200", "PGRST201", "PGRST202", "PGRST203"]
    /// Codes PostgREST signalant un JWT refusé ou un privilège manquant.
    public static let unauthorizedCodes: Set<String> = ["PGRST301", "PGRST302", "PGRST303", "42501"]
    public static let contractStatuses: ClosedRange<Int> = 300...303
    public static let unauthorizedStatuses: Set<Int> = [401, 403]

    /// `fallback` est le message métier générique affiché quand l'erreur n'entre dans
    /// aucune catégorie (ex. « Impossible de charger les missions. Réessayez. »).
    public static func map(_ error: any Error, fallback: String) -> JoleneError {
        if let jolene = error as? JoleneError { return jolene }
        if error is CancellationError { return JoleneError(.cancelled, cancelledMessage) }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled
                ? JoleneError(.cancelled, cancelledMessage)
                : JoleneError(.network, networkMessage)
        }
        if let postgrest = error as? PostgrestError {
            return map(postgrestCode: postgrest.code, fallback: fallback)
        }
        if let http = error as? HTTPError {
            return map(status: http.response.statusCode, fallback: fallback)
        }
        if let auth = error as? AuthError {
            return map(auth: auth, fallback: fallback)
        }
        return JoleneError(.unknown, fallback)
    }

    public static func map(postgrestCode code: String?, fallback: String) -> JoleneError {
        guard let code else { return JoleneError(.unknown, fallback) }
        if contractCodes.contains(code) { return JoleneError(.contract, contractMessage) }
        if unauthorizedCodes.contains(code) { return JoleneError(.unauthorized, unauthorizedMessage) }
        return JoleneError(.unknown, fallback)
    }

    public static func map(status: Int, fallback: String) -> JoleneError {
        if contractStatuses.contains(status) { return JoleneError(.contract, contractMessage) }
        if unauthorizedStatuses.contains(status) { return JoleneError(.unauthorized, unauthorizedMessage) }
        return JoleneError(.unknown, fallback)
    }

    static func map(auth: AuthError, fallback: String) -> JoleneError {
        switch auth {
        case .sessionMissing, .refreshDiscarded:
            return JoleneError(.unauthorized, unauthorizedMessage)
        case .api(_, _, _, let response):
            return map(status: response.statusCode, fallback: fallback)
        default:
            return JoleneError(.unknown, fallback)
        }
    }
}
