import Foundation
import JoleneCore
import Security
import XCTest
@testable import JoleneSupabase

/// Magasin Keychain provisoire des reçus d'avatar (lot 3, T10 ; PRINCIPES §4) : conventions du magasin du lot 2 (service
/// `app.jolene.receipts`, compte `avatar.<userId>`, accessibilité après premier déverrouillage, jamais synchronisé),
/// erreurs du trousseau levées, reçu altéré illisible (jamais « aucun reçu »).
final class KeychainRecusAvatarTests: XCTestCase {
    private let recu = RecuAvatar(userId: TestClient.userId, attemptId: "essai-1",
                                  chemin: "\(TestClient.userId)/avatar-1793577600000.jpg")

    private func string(_ dict: [String: Any], _ key: CFString) -> String? {
        dict[key as String].map { "\($0)" }
    }

    func testEcrireServiceCompteAccessibiliteSansSynchronisation() throws {
        let store = RecordingKeychainStore()
        try KeychainRecusAvatar(store: store).ecrire(recu)
        XCTAssertEqual(store.calls, [.add])
        let ajout = store.lastAdd
        XCTAssertEqual(string(ajout, kSecAttrService), "app.jolene.receipts")
        XCTAssertEqual(string(ajout, kSecAttrAccount), "avatar.\(TestClient.userId)")
        XCTAssertEqual(string(ajout, kSecAttrAccessible), kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertEqual(ajout[kSecAttrSynchronizable as String] as? Bool, false)
        let donnees = try XCTUnwrap(ajout[kSecValueData as String] as? Data)
        XCTAssertEqual(try RecuAvatar.decoder(donnees, userId: TestClient.userId), recu)
        XCTAssertFalse(String(decoding: donnees, as: UTF8.self).contains("http"), "aucune URL dans le reçu")
    }

    func testEcrireRemplaceUnElementExistant() throws {
        let store = RecordingKeychainStore()
        store.addStatus = errSecDuplicateItem
        try KeychainRecusAvatar(store: store).ecrire(recu)
        XCTAssertEqual(store.calls, [.add, .update])
        XCTAssertEqual(string(store.lastUpdateQuery, kSecAttrAccount), "avatar.\(TestClient.userId)")
        store.updateStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try KeychainRecusAvatar(store: store).ecrire(recu)) {
            XCTAssertEqual($0 as? KeychainStorageError, KeychainStorageError(operation: "update", status: errSecInteractionNotAllowed))
        }
    }

    func testLireRelitOuLeveSansJamaisRendreAucunRecuSurErreur() throws {
        let store = RecordingKeychainStore()
        store.copyResult = (errSecItemNotFound, nil)
        XCTAssertNil(try KeychainRecusAvatar(store: store).lire(userId: TestClient.userId))
        XCTAssertEqual(string(store.lastQuery, kSecMatchLimit), kSecMatchLimitOne as String)
        store.copyResult = (errSecSuccess, try recu.encoder())
        XCTAssertEqual(try KeychainRecusAvatar(store: store).lire(userId: TestClient.userId), recu)
        store.copyResult = (errSecMissingEntitlement, nil)
        XCTAssertThrowsError(try KeychainRecusAvatar(store: store).lire(userId: TestClient.userId), "trousseau indisponible levé")
        store.copyResult = (errSecSuccess, Data("altéré".utf8))
        XCTAssertThrowsError(try KeychainRecusAvatar(store: store).lire(userId: TestClient.userId)) {
            XCTAssertEqual($0 as? RecuAvatar.Erreur, .illisible)
        }
        store.copyResult = (errSecSuccess, try recu.encoder())
        XCTAssertThrowsError(try KeychainRecusAvatar(store: store).lire(userId: "autre-utilisateur")) {
            XCTAssertEqual($0 as? RecuAvatar.Erreur, .utilisateurDifferent)
        }
    }

    func testEffacer() throws {
        let store = RecordingKeychainStore()
        try KeychainRecusAvatar(store: store).effacer(userId: TestClient.userId)
        store.deleteStatus = errSecItemNotFound
        try KeychainRecusAvatar(store: store).effacer(userId: TestClient.userId)
        store.deleteStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try KeychainRecusAvatar(store: store).effacer(userId: TestClient.userId))
        XCTAssertEqual(string(store.lastQuery, kSecAttrService), "app.jolene.receipts")
    }
}
