import Foundation
import JoleneCore
import Security

/// Magasin Keychain PROVISOIRE des reçus d'avatar (lot 3, T10 ; PRINCIPES §4), à remplacer à la fusion des lots par
/// `ReceiptJournal<RecuAvatar>` sur `KeychainReceiptStore` (lot 2, `feat/ios-lot2`), dont le lot 3 ne dépend pas
/// (point de fusion : `docs/mobile-swift/DECISIONS_LOT3.md`, section T10). Il reprend à dessein les conventions de ce
/// magasin, pour qu'un reçu écrit avant la fusion soit relu après :
/// - service `app.jolene.receipts` (distinct de la session `app.jolene.session` et du push `app.jolene.push` : la
///   déconnexion, qui purge la session, conserve le reçu, relu seulement par le même utilisateur) ; compte
///   `avatar.<userId>` (`<domaine>.<userId>`) ;
/// - `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, jamais synchronisé iCloud ;
/// - toute erreur du trousseau est levée (`KeychainStorageError`, sans la valeur) : jamais « aucun reçu » ; un reçu
///   illisible lève `RecuAvatar.Erreur.illisible`, sans réparation (l'envoi est alors refusé, fail-closed).
public struct KeychainRecusAvatar: RecusAvatarPort {
    public static let service = "app.jolene.receipts"

    private let store: any KeychainItemStore

    public init(store: any KeychainItemStore = SecurityKeychainStore()) {
        self.store = store
    }

    public static func compte(userId: String) -> String { "\(RecuAvatar.domaine).\(userId)" }

    public func lire(userId: String) throws -> RecuAvatar? {
        let (statut, donnees) = store.copy(Self.requeteLecture(userId))
        switch statut {
        case errSecSuccess:
            guard let donnees else { throw KeychainStorageError(operation: "copy", status: errSecDecode) }
            return try RecuAvatar.decoder(donnees, userId: userId)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStorageError(operation: "copy", status: statut)
        }
    }

    public func ecrire(_ recu: RecuAvatar) throws {
        let donnees = try recu.encoder()
        let ajout = store.add(Self.base(recu.userId).merging(Self.attributsValeur(donnees)) { _, nouveau in nouveau })
        if ajout == errSecSuccess { return }
        guard ajout == errSecDuplicateItem else { throw KeychainStorageError(operation: "add", status: ajout) }
        let miseAJour = store.update(Self.base(recu.userId), attributes: Self.attributsValeur(donnees))
        guard miseAJour == errSecSuccess else { throw KeychainStorageError(operation: "update", status: miseAJour) }
    }

    public func effacer(userId: String) throws {
        let statut = store.delete(Self.base(userId))
        guard statut == errSecSuccess || statut == errSecItemNotFound else {
            throw KeychainStorageError(operation: "delete", status: statut)
        }
    }

    // MARK: - Requêtes

    static func base(_ userId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: compte(userId: userId),
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    static func attributsValeur(_ donnees: Data) -> [String: Any] {
        [
            kSecValueData as String: donnees,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
    }

    static func requeteLecture(_ userId: String) -> [String: Any] {
        base(userId).merging([
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]) { _, nouveau in nouveau }
    }
}
