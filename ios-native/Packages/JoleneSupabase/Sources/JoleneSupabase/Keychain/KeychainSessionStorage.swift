import Foundation
import Security
import Supabase

/// Accès bas niveau au trousseau. Abstrait les appels `SecItem*` pour que la logique de
/// requête (service, compte, accessibilité, synchronisation) soit testable sans
/// entitlement Keychain, ce qu'un `swift test` macOS n'a pas toujours.
public protocol KeychainItemStore: Sendable {
    func add(_ attributes: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func copy(_ query: [String: Any]) -> (status: OSStatus, data: Data?)
    func delete(_ query: [String: Any]) -> OSStatus
}

/// Implémentation réelle via le framework Security.
public struct SecurityKeychainStore: KeychainItemStore {
    public init() {}

    public func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    public func copy(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    public func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

/// Construction pure des dictionnaires Keychain (plan §4.3) :
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, jamais synchronisé iCloud,
/// service `app.jolene.session`, compte = clé de stockage du SDK.
public enum KeychainQueryBuilder {
    public static let service = "app.jolene.session"

    /// Attributs communs à toutes les opérations : classe, service, compte, non synchronisé.
    public static func base(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    /// Attributs portant la valeur et sa classe d'accessibilité (ajout et mise à jour).
    public static func valueAttributes(_ value: Data) -> [String: Any] {
        [
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
    }

    public static func add(key: String, value: Data) -> [String: Any] {
        base(key: key).merging(valueAttributes(value)) { _, new in new }
    }

    public static func lookup(key: String) -> [String: Any] {
        base(key: key).merging([
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]) { _, new in new }
    }
}

/// Erreur Keychain remontée au SDK (qui la journalise et considère la session absente).
/// Le message ne contient jamais la valeur stockée.
public struct KeychainStorageError: Error, Equatable, Sendable, LocalizedError {
    public let operation: String
    public let status: OSStatus

    public var errorDescription: String? {
        "Keychain \(operation) a échoué (statut \(status))."
    }
}

/// Stockage de session supabase-swift sauvegardé dans le trousseau local de l'appareil.
///
/// Remplace `KeychainLocalStorage` du SDK pour imposer l'accessibilité
/// `WhenUnlockedThisDeviceOnly` et l'absence de synchronisation iCloud (plan §4.3).
public struct KeychainSessionStorage: AuthLocalStorage {
    private let store: any KeychainItemStore

    public init(store: any KeychainItemStore = SecurityKeychainStore()) {
        self.store = store
    }

    public func store(key: String, value: Data) throws {
        let addStatus = store.add(KeychainQueryBuilder.add(key: key, value: value))
        if addStatus == errSecSuccess { return }
        guard addStatus == errSecDuplicateItem else {
            throw KeychainStorageError(operation: "add", status: addStatus)
        }
        let updateStatus = store.update(
            KeychainQueryBuilder.base(key: key),
            attributes: KeychainQueryBuilder.valueAttributes(value)
        )
        guard updateStatus == errSecSuccess else {
            throw KeychainStorageError(operation: "update", status: updateStatus)
        }
    }

    public func retrieve(key: String) throws -> Data? {
        let (status, data) = store.copy(KeychainQueryBuilder.lookup(key: key))
        switch status {
        case errSecSuccess: return data
        case errSecItemNotFound: return nil
        default: throw KeychainStorageError(operation: "copy", status: status)
        }
    }

    public func remove(key: String) throws {
        let status = store.delete(KeychainQueryBuilder.base(key: key))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStorageError(operation: "delete", status: status)
        }
    }

    /// Sonde de disponibilité : écrit puis supprime un élément témoin. Faux quand le processus
    /// n'a pas d'entitlement Keychain (`errSecMissingEntitlement`) ou que le trousseau est
    /// inaccessible. Sert à isoler le test d'intégration réel sur macOS.
    public static func isAvailable(store: any KeychainItemStore = SecurityKeychainStore()) -> Bool {
        let key = "app.jolene.session.probe.\(UUID().uuidString)"
        let storage = KeychainSessionStorage(store: store)
        do {
            try storage.store(key: key, value: Data([0x01]))
            let read = try storage.retrieve(key: key)
            try storage.remove(key: key)
            return read == Data([0x01])
        } catch {
            return false
        }
    }
}
