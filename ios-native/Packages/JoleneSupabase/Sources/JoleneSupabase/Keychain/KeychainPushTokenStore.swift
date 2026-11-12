import Foundation
import JoleneCore
import Security

/// Mémoire du token APNs de l'appareil (lot 3, T4 ; blueprint `LOT3_PLAN.md` §2.6) dans le trousseau
/// local : service `app.jolene.push` (distinct de la session), un seul élément, accessibilité
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (lisible au retour au premier plan après le
/// premier déverrouillage), jamais synchronisé iCloud. Valeur : `{token, userId}` en JSON, rien d'autre.
///
/// Best-effort comme le web (`src/lib/pushDeviceToken.ts` l.6-29) : aucune erreur n'est levée ; une
/// lecture impossible ou illisible rend nil (la déconnexion saute alors la RPC de désactivation, la
/// désinscription locale a lieu quand même). Les statuts du trousseau ne sont jamais journalisés avec la valeur.
public struct KeychainPushTokenStore: PushTokenStorePort {
    public static let service = "app.jolene.push"
    public static let compte = "apns-device-token"

    private let store: any KeychainItemStore

    public init(store: any KeychainItemStore = SecurityKeychainStore()) {
        self.store = store
    }

    public func memoriser(_ token: TokenPushMemorise) {
        guard let valeur = try? JSONEncoder().encode(token) else { return }
        let ajout = store.add(Self.base.merging(Self.attributs(valeur)) { _, nouveau in nouveau })
        guard ajout == errSecDuplicateItem else { return }
        _ = store.update(Self.base, attributes: Self.attributs(valeur))
    }

    public func lire() -> TokenPushMemorise? {
        let requete = Self.base.merging([
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]) { _, nouveau in nouveau }
        let (statut, donnees) = store.copy(requete)
        guard statut == errSecSuccess, let donnees,
              let memorise = try? JSONDecoder().decode(TokenPushMemorise.self, from: donnees) else { return nil }
        // Web `lireTokenMemorise` : `trim() || null`.
        let token = memorise.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        return TokenPushMemorise(token: token, userId: memorise.userId)
    }

    public func oublier() {
        _ = store.delete(Self.base)
    }

    // MARK: - Requêtes

    static var base: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: compte,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    static func attributs(_ valeur: Data) -> [String: Any] {
        [
            kSecValueData as String: valeur,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
    }
}
