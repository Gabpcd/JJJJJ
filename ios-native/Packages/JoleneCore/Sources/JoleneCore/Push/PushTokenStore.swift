import Foundation

/// Token APNs mémorisé sur l'appareil après un enregistrement réussi (blueprint `LOT3_PLAN.md` §2.6),
/// lu à la déconnexion volontaire pour désactiver **cette installation seulement**
/// (`fn_desactiver_mon_token_push`). Port de `memoriserTokenPushAppareil` / `oublierTokenPushAppareil`
/// (`src/lib/pushDeviceToken.ts` l.4-29). L'identifiant de l'utilisateur accompagne le token ; aucune
/// autre donnée n'est conservée.
public struct TokenPushMemorise: Equatable, Codable, Sendable {
    /// Hexadécimal minuscule, tel qu'envoyé à `fn_upsert_token_push`.
    public var token: String
    public var userId: String

    public init(token: String, userId: String) {
        self.token = token; self.userId = userId
    }
}

/// Mémoire du token de l'appareil. Best-effort comme le web (stockage privé ou indisponible toléré,
/// `pushDeviceToken.ts` l.10-13) : aucune méthode ne lève ; une lecture impossible rend `nil`, et la
/// déconnexion saute alors la RPC (le transport local est désinscrit quand même).
///
/// Implémentations : trousseau local `app.jolene.push` (`KeychainPushTokenStore`, JoleneSupabase),
/// mémoire vive en démo et en test (`MemoirePushTokenStore`).
public protocol PushTokenStorePort: Sendable {
    func memoriser(_ token: TokenPushMemorise)
    func lire() -> TokenPushMemorise?
    func oublier()
}

/// Mémoire vive (monde démo) : rien ne survit au processus.
public final class MemoirePushTokenStore: PushTokenStorePort, @unchecked Sendable {
    private let verrou = NSLock()
    private var valeur: TokenPushMemorise?

    public init(_ initial: TokenPushMemorise? = nil) {
        valeur = initial
    }

    public func memoriser(_ token: TokenPushMemorise) {
        verrou.lock(); defer { verrou.unlock() }
        valeur = token
    }

    public func lire() -> TokenPushMemorise? {
        verrou.lock(); defer { verrou.unlock() }
        return valeur
    }

    public func oublier() {
        verrou.lock(); defer { verrou.unlock() }
        valeur = nil
    }
}
