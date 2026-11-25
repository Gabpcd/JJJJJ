import Foundation
import Supabase

#if DEBUG
/// Diagnostic DEBUG du transport d'une lecture de session refusée en « non autorisé » (troisième parcours STAGING du
/// lot 5, 25/11/2026) : ce que supabase-swift a pu envoyer, sans jamais recopier le jeton ni l'adresse.
///   - code brut (`postgrest=<code>` ou `http=<statut>`, posé par `RPCResponse.codeBrut` ; `http=200` pour un refus
///     porté par le corps) ;
///   - `jwt=oui|non` : une session est relue du stockage et son jeton a la forme d'un JWT. Sans session relue, le SDK
///     garde la clé publishable en `Authorization` (rôle `anon`) : `jwt=non` ;
///   - `exp=<secondes>` restantes avant l'expiration du jeton (négatif s'il est périmé), `-` sans jeton ;
///   - `hote=oui|non` : l'hôte émetteur du jeton (`iss`) est l'hôte REST du client, `-` sans jeton ou sans `iss`.
/// Absent en Release.
enum DiagnosticTransport {
    /// L'hôte REST est lu sur le client de stockage : supabase-swift construit `/rest/v1` et `/storage/v1` depuis la même
    /// `supabaseURL` (le client REST lui-même n'est pas public).
    static func decrire(client: SupabaseClient, code: String?, maintenant: Date = Date()) -> String {
        decrire(code: code, jeton: client.auth.currentSession?.accessToken,
                hoteREST: client.storage.configuration.url.host, maintenant: maintenant)
    }

    static func decrire(code: String?, jeton: String?, hoteREST: String?, maintenant: Date) -> String {
        var parties = [code ?? "http=200"]
        guard let jeton, let charge = charge(jeton) else {
            return (parties + ["jwt=non", "exp=-", "hote=-"]).joined(separator: ";")
        }
        parties.append("jwt=oui")
        if let exp = (charge["exp"] as? NSNumber)?.doubleValue {
            parties.append("exp=\(Int((exp - maintenant.timeIntervalSince1970).rounded(.down)))")
        } else {
            parties.append("exp=-")
        }
        if let iss = charge["iss"] as? String, let emetteur = URL(string: iss)?.host, let hoteREST {
            parties.append("hote=\(emetteur.lowercased() == hoteREST.lowercased() ? "oui" : "non")")
        } else {
            parties.append("hote=-")
        }
        return parties.joined(separator: ";")
    }

    /// Charge utile d'un jeton en forme de JWT (trois segments base64url, en-tête et charge en JSON objet), nil sinon.
    static func charge(_ jeton: String) -> [String: Any]? {
        let segments = jeton.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3, objet(String(segments[0])) != nil else { return nil }
        return objet(String(segments[1]))
    }

    private static func objet(_ segment: String) -> [String: Any]? {
        var base64 = segment.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let donnees = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: donnees)) as? [String: Any]
    }
}
#endif
