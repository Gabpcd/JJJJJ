import Foundation
import JoleneCore
import Security
import XCTest
@testable import JoleneSupabase

/// Mémoire du token APNs (lot 3, T4 ; blueprint §2.6) : trousseau local, service `app.jolene.push`,
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, jamais synchronisé ; valeur = token + identifiant
/// de l'utilisateur, rien d'autre. Best-effort comme le web (`pushDeviceToken.ts` l.6-20) : une erreur
/// du trousseau n'est jamais levée (la RPC de désactivation est alors simplement sautée).
final class KeychainPushTokenStoreTests: XCTestCase {
    private let valeur = TokenPushMemorise(token: String(repeating: "0a", count: 32), userId: TestClient.userId)

    private func string(_ dict: [String: Any], _ key: CFString) -> String? {
        dict[key as String].map { "\($0)" }
    }

    func testMemoriserPoseServiceCompteAccessibiliteEtAucuneSynchronisation() throws {
        let store = RecordingKeychainStore()
        KeychainPushTokenStore(store: store).memoriser(valeur)
        XCTAssertEqual(store.calls, [.add])
        let add = store.lastAdd
        XCTAssertEqual(string(add, kSecClass), kSecClassGenericPassword as String)
        XCTAssertEqual(string(add, kSecAttrService), "app.jolene.push")
        XCTAssertEqual(string(add, kSecAttrAccount), KeychainPushTokenStore.compte)
        XCTAssertEqual(string(add, kSecAttrAccessible), kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertEqual(add[kSecAttrSynchronizable as String] as? Bool, false, "jamais synchronisé iCloud")
        XCTAssertNil(add[kSecAttrAccessGroup as String])
        let donnees = try XCTUnwrap(add[kSecValueData as String] as? Data)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: donnees) as? [String: String])
        XCTAssertEqual(json, ["token": valeur.token, "userId": valeur.userId], "token et utilisateur, rien d'autre")
    }

    func testMemoriserRemplaceUnElementExistant() {
        let store = RecordingKeychainStore()
        store.addStatus = errSecDuplicateItem
        KeychainPushTokenStore(store: store).memoriser(valeur)
        XCTAssertEqual(store.calls, [.add, .update])
        XCTAssertEqual(string(store.lastUpdateQuery, kSecAttrService), "app.jolene.push")
        XCTAssertEqual(store.lastUpdateQuery[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(string(store.lastUpdateAttributes, kSecAttrAccessible),
                       kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertNotNil(store.lastUpdateAttributes[kSecValueData as String] as? Data)
    }

    func testLireRelitLaValeurOuRienSansJamaisLever() throws {
        let store = RecordingKeychainStore()
        let donnees = try JSONSerialization.data(withJSONObject: ["token": valeur.token, "userId": valeur.userId])
        store.copyResult = (errSecSuccess, donnees)
        XCTAssertEqual(KeychainPushTokenStore(store: store).lire(), valeur)
        XCTAssertEqual(string(store.lastQuery, kSecAttrService), "app.jolene.push")
        XCTAssertEqual(string(store.lastQuery, kSecMatchLimit), kSecMatchLimitOne as String)

        store.copyResult = (errSecItemNotFound, nil)
        XCTAssertNil(KeychainPushTokenStore(store: store).lire())
        store.copyResult = (errSecMissingEntitlement, nil)
        XCTAssertNil(KeychainPushTokenStore(store: store).lire(), "trousseau indisponible : aucun token")
        store.copyResult = (errSecSuccess, Data("illisible".utf8))
        XCTAssertNil(KeychainPushTokenStore(store: store).lire(), "valeur illisible : aucun token")
        store.copyResult = (errSecSuccess, try JSONSerialization.data(withJSONObject: ["token": " ", "userId": "u"]))
        XCTAssertNil(KeychainPushTokenStore(store: store).lire(), "token vide : aucun token (web `trim() || null`)")
    }

    func testOublierSupprimeLElementDuService() {
        let store = RecordingKeychainStore()
        KeychainPushTokenStore(store: store).oublier()
        XCTAssertEqual(store.calls, [.delete])
        XCTAssertEqual(string(store.lastQuery, kSecAttrService), "app.jolene.push")
        XCTAssertEqual(string(store.lastQuery, kSecAttrAccount), KeychainPushTokenStore.compte)
        store.deleteStatus = errSecItemNotFound
        KeychainPushTokenStore(store: store).oublier() // aucun élément : rien à lever
    }

    func testEchecsDuTrousseauAvales() {
        let store = RecordingKeychainStore()
        store.addStatus = errSecMissingEntitlement
        KeychainPushTokenStore(store: store).memoriser(valeur) // ne lève pas
        XCTAssertEqual(store.calls, [.add])
        store.deleteStatus = errSecInteractionNotAllowed
        KeychainPushTokenStore(store: store).oublier() // ne lève pas
    }

    func testServiceDistinctDeLaSession() {
        XCTAssertNotEqual(KeychainPushTokenStore.service, KeychainQueryBuilder.service, "le token push ne partage pas l'élément de session")
    }
}
