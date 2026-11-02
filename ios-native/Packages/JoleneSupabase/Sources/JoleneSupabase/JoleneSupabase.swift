import JoleneCore
import Supabase

/// Implémentations des ports de JoleneCore via supabase-swift.
///
/// Point d'entrée : `SupabaseGateways.make(environment:)`. Les gateways ne contiennent
/// aucune règle métier : filtrage serveur (PostgREST), relecture après mutation, et
/// mapping des erreurs du SDK vers `JoleneError` sans jamais inclure une valeur saisie.
public enum JoleneSupabase {
    public static let sdk = "supabase-swift 2.55.5"

    /// Valeur de l'en-tête `X-Client-Info` envoyé sur toutes les requêtes (Auth, PostgREST,
    /// Functions, Storage). Remplace l'en-tête par défaut du SDK (`supabase-swift/…`).
    public static let clientInfo = "jolene-ios/\(JoleneCore.version)"
}
