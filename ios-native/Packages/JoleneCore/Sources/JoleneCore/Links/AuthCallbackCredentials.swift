import Foundation

/// Identifiants extraits d'un callback email Supabase (reset de mot de passe ou
/// confirmation d'inscription), dans les trois formats : implicit (fragment),
/// PKCE (`code`) et `token_hash`. Port de `extraireRecoveryCredentials`
/// (`src/lib/nativeLinks.ts`) et de la lecture de `confirmerInscription`
/// (`src/pages/ConfirmationInscription.tsx`).
///
/// Les valeurs sont des secrets : `description` les masque toujours.
public enum AuthCallbackCredentials: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case implicit(accessToken: String, refreshToken: String)
    case pkce(code: String)
    /// `otpType` est le `type` Supabase à passer à `verifyOTP` : `recovery`, `signup` ou `email`.
    case tokenHash(tokenHash: String, otpType: String)

    public var description: String {
        switch self {
        case .implicit: return "AuthCallbackCredentials(implicit, valeurs masquées)"
        case .pkce: return "AuthCallbackCredentials(pkce, valeur masquée)"
        case .tokenHash(_, let otpType): return "AuthCallbackCredentials(token_hash \(otpType), valeur masquée)"
        }
    }
    public var debugDescription: String { description }

    /// Extrait les identifiants d'un lien de récupération de mot de passe (`/reset-password`).
    /// `search` et `fragment` acceptent ou non leur préfixe « ? » / « # ».
    public static func recovery(search: String, fragment: String) -> AuthCallbackCredentials? {
        let query = FormQuery(search, strippingPrefix: "?")
        let hash = FormQuery(fragment, strippingPrefix: "#")
        let type = hash.get("type") ?? query.get("type")

        // Un flux implicit expose directement une session : le marqueur recovery
        // explicite est obligatoire pour ne jamais accepter un callback OAuth.
        if let accessToken = hash.get("access_token"), let refreshToken = hash.get("refresh_token"),
           !accessToken.isEmpty, !refreshToken.isEmpty {
            return type == "recovery" ? .implicit(accessToken: accessToken, refreshToken: refreshToken) : nil
        }

        // Le lien PKCE Supabase ne contient pas toujours `type=recovery` : sa nature est
        // vérifiée après échange grâce au `redirectType` stocké avec le verifier.
        if let type, type != "recovery" { return nil }
        if let code = query.get("code"), !code.isEmpty { return .pkce(code: code) }

        if let tokenHash = query.get("token_hash"), !tokenHash.isEmpty, type == "recovery" {
            return .tokenHash(tokenHash: tokenHash, otpType: "recovery")
        }
        return nil
    }

    /// Extrait les identifiants d'un lien de confirmation d'inscription (`/inscription/confirmer`).
    /// Même logique que le web : `type` absent ou `signup`/`email` uniquement ; implicit et
    /// `token_hash` exigent un `type`, PKCE non.
    public static func signup(search: String, fragment: String) -> AuthCallbackCredentials? {
        let query = FormQuery(search, strippingPrefix: "?")
        let hash = FormQuery(fragment, strippingPrefix: "#")
        let type = hash.get("type") ?? query.get("type")
        if let type, type != "signup", type != "email" { return nil }

        if let accessToken = hash.get("access_token"), let refreshToken = hash.get("refresh_token"),
           !accessToken.isEmpty, !refreshToken.isEmpty {
            return type != nil ? .implicit(accessToken: accessToken, refreshToken: refreshToken) : nil
        }
        if let code = query.get("code"), !code.isEmpty { return .pkce(code: code) }
        if let tokenHash = query.get("token_hash"), !tokenHash.isEmpty, let type {
            return .tokenHash(tokenHash: tokenHash, otpType: type == "signup" ? "signup" : "email")
        }
        return nil
    }

    /// Variante sur un lien normalisé (`JoleneLink.normalize`) ou une URL complète.
    public static func recovery(link: String) -> AuthCallbackCredentials? {
        let parts = JoleneLink.split(link: link)
        return recovery(search: parts.query ?? "", fragment: parts.fragment ?? "")
    }

    public static func signup(link: String) -> AuthCallbackCredentials? {
        let parts = JoleneLink.split(link: link)
        return signup(search: parts.query ?? "", fragment: parts.fragment ?? "")
    }
}
