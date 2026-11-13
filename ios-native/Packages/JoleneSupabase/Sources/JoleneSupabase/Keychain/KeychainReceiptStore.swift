import Foundation
import JoleneCore
import Security

/// Magasin Keychain des reçus durables (PRINCIPES §4 ; blueprint `docs/mobile-swift/LOT2_PLAN.md` §2.2 et §2.6 ;
/// décision 23 de `docs/mobile-swift/DECISIONS_LOT2.md` : livré par T1 du lot 2 faute de T7 du lot 1, qui le
/// consomme sans changer son API). Lu et écrit par `ReceiptJournal` (JoleneCore), qui sérialise les opérations,
/// relit après écriture et rend tout échec illisible, sans réparation.
///
/// - Service `app.jolene.receipts`, distinct de la session (`app.jolene.session`) et de l'identifiant terminal
///   (`app.jolene.terminal`) : la déconnexion, qui purge la session, conserve les reçus (un reçu n'est relu que par
///   le même utilisateur, blueprint §2.6). Compte = `CleRecu.compte` (`<domaine>.<userId>`).
/// - `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, jamais synchronisé iCloud ni sauvegardé vers un autre
///   appareil. Plutôt que `WhenUnlocked` (pilote `attemptJournal.ts` l.5) : une réponse reçue pendant que l'écran
///   se verrouille doit encore pouvoir être journalisée ; un reçu ne contient aucun secret (ni code, ni coordonnée).
/// - Toute erreur du trousseau est levée (`KeychainStorageError`, sans la valeur stockée) : jamais « aucun reçu ».
public struct KeychainReceiptStore: ReceiptStorePort {
    public static let service = "app.jolene.receipts"

    private let store: any KeychainItemStore

    public init(store: any KeychainItemStore = SecurityKeychainStore()) {
        self.store = store
    }

    public func lire(_ cle: CleRecu) throws -> Data? {
        let (statut, donnees) = store.copy(Self.requeteLecture(cle))
        switch statut {
        case errSecSuccess:
            guard let donnees else { throw KeychainStorageError(operation: "copy", status: errSecDecode) }
            return donnees
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStorageError(operation: "copy", status: statut)
        }
    }

    public func ecrire(_ donnees: Data, pour cle: CleRecu) throws {
        let ajout = store.add(Self.base(cle).merging(Self.attributsValeur(donnees)) { _, nouveau in nouveau })
        if ajout == errSecSuccess { return }
        guard ajout == errSecDuplicateItem else { throw KeychainStorageError(operation: "add", status: ajout) }
        let miseAJour = store.update(Self.base(cle), attributes: Self.attributsValeur(donnees))
        guard miseAJour == errSecSuccess else { throw KeychainStorageError(operation: "update", status: miseAJour) }
    }

    public func effacer(_ cle: CleRecu) throws {
        let statut = store.delete(Self.base(cle))
        guard statut == errSecSuccess || statut == errSecItemNotFound else {
            throw KeychainStorageError(operation: "delete", status: statut)
        }
    }

    // MARK: - Requêtes

    static func base(_ cle: CleRecu) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: cle.compte,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    static func attributsValeur(_ donnees: Data) -> [String: Any] {
        [
            kSecValueData as String: donnees,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
    }

    static func requeteLecture(_ cle: CleRecu) -> [String: Any] {
        base(cle).merging([
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]) { _, nouveau in nouveau }
    }
}
