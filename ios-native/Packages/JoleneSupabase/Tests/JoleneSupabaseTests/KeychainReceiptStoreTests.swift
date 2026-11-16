import Foundation
import JoleneCore
import Security
import XCTest
@testable import JoleneSupabase

/// Magasin Keychain des reçus durables (décision 23 du lot 2 : livré par T1 faute de T7 ; blueprint `LOT2_PLAN.md`
/// §2.2 et §2.6 ; PRINCIPES §4) : service `app.jolene.receipts`, un compte par (domaine, utilisateur),
/// `AfterFirstUnlockThisDeviceOnly`, jamais synchronisé, conservé à la déconnexion. Les erreurs du trousseau
/// remontent (jamais un reçu absent supposé) ; le journal les traduit en `RecuErreur.illisible`.
final class KeychainReceiptStoreTests: XCTestCase {
    private let userId = "0b4d2b8e-4a9f-4b1c-9e0a-7f3c1d2e5a66"
    private let essai = "6f1c2c1e-4c1a-4f55-9a0e-2b7b1d9e8a01"

    private func cle(_ domaine: String = "scan") throws -> CleRecu {
        try XCTUnwrap(CleRecu(domaine: domaine, userId: userId))
    }

    private func recu() throws -> RecuScan {
        try RecuScan.preparer(userId: userId, epoch: 1, missionId: "m-1", terminalId: "TERM_IOS_ABCDEFGHIJKLMNOPQRST",
                              typeAttendu: .ouverture, nbScansAvant: 0, preuvesAvant: [], gps: .nonDemande, attemptId: essai)
    }

    func testAttributsKeychain() throws {
        let trousseau = TrousseauEnMemoire()
        try KeychainReceiptStore(store: trousseau).ecrire(Data("{}".utf8), pour: try cle())
        XCTAssertEqual(KeychainReceiptStore.service, "app.jolene.receipts")
        XCTAssertNotEqual(KeychainReceiptStore.service, KeychainQueryBuilder.service, "distinct de la session")
        XCTAssertNotEqual(KeychainReceiptStore.service, KeychainTerminalIdentity.service, "distinct de l'identifiant terminal")
        let attributs = try XCTUnwrap(trousseau.attributs(service: KeychainReceiptStore.service, compte: "scan.\(userId)"))
        XCTAssertEqual(attributs[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(attributs[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
                       "ThisDeviceOnly ; lisible après le premier déverrouillage (réponse reçue écran verrouillé)")
        XCTAssertEqual(attributs[kSecAttrSynchronizable as String] as? Bool, false, "jamais synchronisé iCloud")
        XCTAssertNil(attributs[kSecAttrAccessGroup as String])
    }

    func testLectureEcritureRemplacementEffacement() throws {
        let trousseau = TrousseauEnMemoire()
        let magasin = KeychainReceiptStore(store: trousseau)
        XCTAssertNil(try magasin.lire(try cle()), "errSecItemNotFound : aucun reçu")
        try magasin.ecrire(Data("a".utf8), pour: try cle())
        XCTAssertEqual(try magasin.lire(try cle()), Data("a".utf8))
        try magasin.ecrire(Data("b".utf8), pour: try cle())
        XCTAssertEqual(try magasin.lire(try cle()), Data("b".utf8), "errSecDuplicateItem → mise à jour")
        XCTAssertEqual(trousseau.appels.filter { $0 == "update" }.count, 1)
        try magasin.ecrire(Data("d".utf8), pour: try cle("document"))
        XCTAssertEqual(trousseau.nombre, 2, "une clé par domaine")
        try magasin.effacer(try cle())
        XCTAssertNil(try magasin.lire(try cle()))
        XCTAssertNoThrow(try magasin.effacer(try cle()), "effacer un reçu absent n'est pas une erreur")
        XCTAssertEqual(try magasin.lire(try cle("document")), Data("d".utf8))
    }

    func testErreursDuTrousseauRemontent() throws {
        for statut in [errSecInteractionNotAllowed, errSecMissingEntitlement, errSecAuthFailed] {
            let lecture = TrousseauEnMemoire()
            lecture.statutCopieForce = statut
            XCTAssertThrowsError(try KeychainReceiptStore(store: lecture).lire(try cle()), "lecture, statut \(statut)")
            let ecriture = TrousseauEnMemoire()
            ecriture.statutAjoutForce = statut
            XCTAssertThrowsError(try KeychainReceiptStore(store: ecriture).ecrire(Data("x".utf8), pour: try cle()),
                                 "écriture, statut \(statut)")
        }
    }

    func testJournalSurKeychainRelitApresEcritureEtEchoueFermement() async throws {
        let trousseau = TrousseauEnMemoire()
        let journal = ReceiptJournal<RecuScan>(store: KeychainReceiptStore(store: trousseau))
        let prepare = try recu()
        try await journal.ecrire(prepare)
        let relu = try await journal.lire(userId: userId)
        XCTAssertEqual(relu, prepare)
        XCTAssertGreaterThanOrEqual(trousseau.appels.filter { $0 == "copy" }.count, 2, "relecture après écriture")

        trousseau.statutCopieForce = errSecInteractionNotAllowed
        do {
            _ = try await journal.lire(userId: userId)
            XCTFail("trousseau inaccessible : jamais « aucun reçu »")
        } catch let erreur as RecuErreur {
            XCTAssertEqual(erreur, .illisible)
        }
    }

    func testSurvitALaDeconnexion() async throws {
        // La déconnexion purge la session du SDK (`app.jolene.session`) ; le reçu, sous un autre service, reste lisible
        // par le même utilisateur à sa reconnexion (blueprint §2.6, comme le pilote).
        let trousseau = TrousseauEnMemoire()
        let session = KeychainSessionStorage(store: trousseau)
        try session.store(key: "sb-mejpriaetwgtcstbgfid-auth-token", value: Data("session".utf8))
        let journal = ReceiptJournal<RecuScan>(store: KeychainReceiptStore(store: trousseau))
        let demarre = try recu().demarrer(le: Date(timeIntervalSince1970: 1_793_577_600))
        try await journal.ecrire(try recu())
        try await journal.ecrire(demarre)
        try session.remove(key: "sb-mejpriaetwgtcstbgfid-auth-token")
        XCTAssertNil(try session.retrieve(key: "sb-mejpriaetwgtcstbgfid-auth-token"))
        let relu = try await journal.lire(userId: userId)
        XCTAssertEqual(relu, demarre)
    }
}
