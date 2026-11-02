import Foundation
import Security
import XCTest
@testable import JoleneSupabase

/// Magasin enregistreur : rejoue des statuts et capture les dictionnaires transmis.
final class RecordingKeychainStore: KeychainItemStore, @unchecked Sendable {
    enum Call: Equatable { case add, update, copy, delete }
    private let lock = NSLock()
    private(set) var calls: [Call] = []
    private(set) var lastAdd: [String: Any] = [:]
    private(set) var lastUpdateQuery: [String: Any] = [:]
    private(set) var lastUpdateAttributes: [String: Any] = [:]
    private(set) var lastQuery: [String: Any] = [:]
    var addStatus: OSStatus = errSecSuccess
    var updateStatus: OSStatus = errSecSuccess
    var copyResult: (OSStatus, Data?) = (errSecItemNotFound, nil)
    var deleteStatus: OSStatus = errSecSuccess

    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        calls.append(.add); lastAdd = attributes; return addStatus
    }
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        calls.append(.update); lastUpdateQuery = query; lastUpdateAttributes = attributes; return updateStatus
    }
    func copy(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        lock.lock(); defer { lock.unlock() }
        calls.append(.copy); lastQuery = query; return copyResult
    }
    func delete(_ query: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        calls.append(.delete); lastQuery = query; return deleteStatus
    }
}

final class KeychainSessionStorageTests: XCTestCase {
    private let key = "sb-mejpriaetwgtcstbgfid-auth-token"
    private let value = Data("session-bytes".utf8)

    private func string(_ dict: [String: Any], _ key: CFString) -> String? {
        dict[key as String].map { "\($0)" }
    }

    func testAddQueryCarriesServiceAccountAccessibilityAndNoSync() throws {
        let store = RecordingKeychainStore()
        try KeychainSessionStorage(store: store).store(key: key, value: value)

        XCTAssertEqual(store.calls, [.add])
        let add = store.lastAdd
        XCTAssertEqual(string(add, kSecClass), kSecClassGenericPassword as String)
        XCTAssertEqual(string(add, kSecAttrService), "app.jolene.session")
        XCTAssertEqual(string(add, kSecAttrAccount), key)
        XCTAssertEqual(string(add, kSecAttrAccessible), kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertEqual(add[kSecAttrSynchronizable as String] as? Bool, false, "jamais synchronisé iCloud")
        XCTAssertEqual(add[kSecValueData as String] as? Data, value)
        XCTAssertNil(add[kSecAttrAccessGroup as String])
    }

    func testDuplicateItemFallsBackToUpdateWithSameAccessibility() throws {
        let store = RecordingKeychainStore()
        store.addStatus = errSecDuplicateItem
        try KeychainSessionStorage(store: store).store(key: key, value: value)

        XCTAssertEqual(store.calls, [.add, .update])
        XCTAssertEqual(string(store.lastUpdateQuery, kSecAttrService), "app.jolene.session")
        XCTAssertEqual(string(store.lastUpdateQuery, kSecAttrAccount), key)
        XCTAssertEqual(store.lastUpdateQuery[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(store.lastUpdateAttributes[kSecValueData as String] as? Data, value)
        XCTAssertEqual(string(store.lastUpdateAttributes, kSecAttrAccessible), kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }

    func testStoreFailuresSurfaceStatusWithoutValue() {
        let store = RecordingKeychainStore()
        store.addStatus = errSecMissingEntitlement
        XCTAssertThrowsError(try KeychainSessionStorage(store: store).store(key: key, value: value)) { error in
            XCTAssertEqual(error as? KeychainStorageError, KeychainStorageError(operation: "add", status: errSecMissingEntitlement))
            XCTAssertFalse("\(error)".contains("session-bytes"))
        }
        let updating = RecordingKeychainStore()
        updating.addStatus = errSecDuplicateItem
        updating.updateStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try KeychainSessionStorage(store: updating).store(key: key, value: value)) { error in
            XCTAssertEqual(error as? KeychainStorageError, KeychainStorageError(operation: "update", status: errSecInteractionNotAllowed))
        }
    }

    func testRetrieveReturnsDataNilOrThrows() throws {
        let store = RecordingKeychainStore()
        store.copyResult = (errSecSuccess, value)
        XCTAssertEqual(try KeychainSessionStorage(store: store).retrieve(key: key), value)
        XCTAssertEqual(string(store.lastQuery, kSecAttrAccount), key)
        XCTAssertEqual(store.lastQuery[kSecReturnData as String] as? Bool, true)
        XCTAssertEqual(string(store.lastQuery, kSecMatchLimit), kSecMatchLimitOne as String)

        store.copyResult = (errSecItemNotFound, nil)
        XCTAssertNil(try KeychainSessionStorage(store: store).retrieve(key: key))

        store.copyResult = (errSecAuthFailed, nil)
        XCTAssertThrowsError(try KeychainSessionStorage(store: store).retrieve(key: key))
    }

    func testRemoveToleratesMissingItemOnly() throws {
        let store = RecordingKeychainStore()
        XCTAssertNoThrow(try KeychainSessionStorage(store: store).remove(key: key))
        store.deleteStatus = errSecItemNotFound
        XCTAssertNoThrow(try KeychainSessionStorage(store: store).remove(key: key))
        store.deleteStatus = errSecAuthFailed
        XCTAssertThrowsError(try KeychainSessionStorage(store: store).remove(key: key))
        XCTAssertEqual(string(store.lastQuery, kSecAttrService), "app.jolene.session")
    }

    /// Intégration réelle avec le framework Security : exécutée seulement si le processus
    /// de test dispose d'un trousseau accessible (sinon XCTSkip, jamais un faux vert).
    func testRealKeychainRoundTripWhenAvailable() throws {
        try XCTSkipUnless(KeychainSessionStorage.isAvailable(), "Keychain indisponible pour ce processus de test (entitlement)")
        let storage = KeychainSessionStorage()
        let probeKey = "app.jolene.session.test.\(UUID().uuidString)"
        defer { try? storage.remove(key: probeKey) }

        try storage.store(key: probeKey, value: value)
        XCTAssertEqual(try storage.retrieve(key: probeKey), value)
        try storage.store(key: probeKey, value: Data("v2".utf8))
        XCTAssertEqual(try storage.retrieve(key: probeKey), Data("v2".utf8), "mise à jour d'un élément existant")
        try storage.remove(key: probeKey)
        XCTAssertNil(try storage.retrieve(key: probeKey))
    }
}
