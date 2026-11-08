import Foundation
import JoleneCore
import Security
import XCTest
@testable import JoleneSupabase

/// Trousseau en mémoire indexé par (service, compte), comme le vrai : permet de prouver qu'une purge de
/// session (`app.jolene.session`) ne touche pas l'identifiant terminal. Statuts forcés optionnels.
final class TrousseauEnMemoire: KeychainItemStore, @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [String: (data: Data, attributs: [String: Any])] = [:]
    private(set) var appels: [String] = []
    var statutCopieForce: OSStatus?
    var statutAjoutForce: OSStatus?
    /// Simule un second écrivain : l'élément apparaît juste avant notre `add`, qui rend alors `errSecDuplicateItem`.
    var ecrivainConcurrent: Data?

    private func cle(_ requete: [String: Any]) -> String {
        "\(requete[kSecAttrService as String] ?? "")|\(requete[kSecAttrAccount as String] ?? "")"
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        appels.append("add")
        if let statutAjoutForce { return statutAjoutForce }
        if let ecrivainConcurrent {
            elements[cle(attributes)] = (ecrivainConcurrent, attributes)
            self.ecrivainConcurrent = nil
            return errSecDuplicateItem
        }
        guard elements[cle(attributes)] == nil else { return errSecDuplicateItem }
        elements[cle(attributes)] = (attributes[kSecValueData as String] as? Data ?? Data(), attributes)
        return errSecSuccess
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        appels.append("update")
        guard var element = elements[cle(query)] else { return errSecItemNotFound }
        if let data = attributes[kSecValueData as String] as? Data { element.data = data }
        elements[cle(query)] = element
        return errSecSuccess
    }

    func copy(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        lock.lock(); defer { lock.unlock() }
        appels.append("copy")
        if let statutCopieForce { return (statutCopieForce, nil) }
        guard let element = elements[cle(query)] else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, element.data)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        appels.append("delete")
        return elements.removeValue(forKey: cle(query)) == nil ? errSecItemNotFound : errSecSuccess
    }

    func attributs(service: String, compte: String) -> [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        return elements["\(service)|\(compte)"]?.attributs
    }

    func poser(_ valeur: String, service: String, compte: String) {
        lock.lock(); defer { lock.unlock() }
        elements["\(service)|\(compte)"] = (Data(valeur.utf8), [:])
    }

    var nombre: Int {
        lock.lock(); defer { lock.unlock() }
        return elements.count
    }
}

/// Identifiant terminal (décision 7, blueprint §2.2) : `TERM_IOS_` + 20 caractères base32 aléatoires,
/// générés une fois, Keychain `AfterFirstUnlockThisDeviceOnly`, non synchronisé, conservé à la
/// déconnexion ; une erreur Keychain n'engendre jamais un second identifiant.
final class KeychainTerminalIdentityTests: XCTestCase {
    private let service = KeychainTerminalIdentity.service
    private let compte = KeychainTerminalIdentity.compte

    private func erreur(_ operation: () throws -> Void) -> JoleneError? {
        do {
            try operation()
            return nil
        } catch let error as JoleneError {
            return error
        } catch {
            XCTFail("type d'erreur inattendu : \(error)")
            return nil
        }
    }

    func testFormatEtStabiliteSurDeuxLectures() throws {
        let trousseau = TrousseauEnMemoire()
        let terminal = KeychainTerminalIdentity(store: trousseau)
        let premier = try terminal.identifiant()
        XCTAssertNotNil(premier.range(of: "^TERM_IOS_[A-Z2-7]{20}$", options: .regularExpression), premier)
        let second = try terminal.identifiant()
        XCTAssertEqual(premier, second)
        XCTAssertEqual(try KeychainTerminalIdentity(store: trousseau).identifiant(), premier, "nouvelle instance : même identifiant")
        XCTAssertEqual(trousseau.appels.filter { $0 == "add" }.count, 1, "généré une seule fois")
        XCTAssertFalse(trousseau.appels.contains("update"), "jamais réécrit")
        XCTAssertFalse(trousseau.appels.contains("delete"))
    }

    func testAttributsKeychain() throws {
        let trousseau = TrousseauEnMemoire()
        _ = try KeychainTerminalIdentity(store: trousseau).identifiant()
        let attributs = try XCTUnwrap(trousseau.attributs(service: service, compte: compte))
        XCTAssertEqual(service, "app.jolene.terminal", "distinct du service de session")
        XCTAssertNotEqual(service, KeychainQueryBuilder.service)
        XCTAssertEqual(attributs[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(attributs[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertEqual(attributs[kSecAttrSynchronizable as String] as? Bool, false, "jamais synchronisé iCloud")
        XCTAssertNil(attributs[kSecAttrAccessGroup as String])
    }

    func testSurvitALaDeconnexion() throws {
        // La déconnexion retire la session du SDK (`KeychainSessionStorage.remove`, service `app.jolene.session`) ;
        // l'identifiant terminal, sous un autre service, reste le même.
        let trousseau = TrousseauEnMemoire()
        let session = KeychainSessionStorage(store: trousseau)
        try session.store(key: "sb-mejpriaetwgtcstbgfid-auth-token", value: Data("session".utf8))
        let avant = try KeychainTerminalIdentity(store: trousseau).identifiant()
        try session.remove(key: "sb-mejpriaetwgtcstbgfid-auth-token")
        XCTAssertNil(try session.retrieve(key: "sb-mejpriaetwgtcstbgfid-auth-token"))
        XCTAssertEqual(trousseau.nombre, 1)
        XCTAssertEqual(try KeychainTerminalIdentity(store: trousseau).identifiant(), avant)
    }

    func testErreurDeLectureSansSecondIdentifiant() {
        // Revue fraîche de T1 : trousseau verrouillé (transitoire) distinct des autres échecs.
        let attendus: [(OSStatus, String)] = [
            (errSecInteractionNotAllowed, KeychainTerminalIdentity.messageVerrouille),
            (errSecMissingEntitlement, KeychainTerminalIdentity.messageIndisponible),
            (errSecAuthFailed, KeychainTerminalIdentity.messageIndisponible),
        ]
        for (statut, message) in attendus {
            let trousseau = TrousseauEnMemoire()
            trousseau.statutCopieForce = statut
            let e = erreur { _ = try KeychainTerminalIdentity(store: trousseau).identifiant() }
            XCTAssertEqual(e?.kind, .environment, "statut \(statut)")
            XCTAssertEqual(e?.message, message, "statut \(statut)")
            XCTAssertFalse(trousseau.appels.contains("add"), "statut \(statut) : aucune génération")
        }
    }

    func testTrousseauVerrouilleEstTransitoire() throws {
        let trousseau = TrousseauEnMemoire()
        let terminal = KeychainTerminalIdentity(store: trousseau)
        let avant = try terminal.identifiant()
        trousseau.statutCopieForce = errSecInteractionNotAllowed
        XCTAssertEqual(erreur { _ = try terminal.identifiant() }?.message, KeychainTerminalIdentity.messageVerrouille)
        trousseau.statutCopieForce = nil
        XCTAssertEqual(try terminal.identifiant(), avant, "déverrouillé : le même identifiant, aucun échec mémorisé")
    }

    func testEchecDEcritureSansIdentifiantRendu() {
        for (statut, message) in [(errSecMissingEntitlement, KeychainTerminalIdentity.messageIndisponible),
                                  (errSecInteractionNotAllowed, KeychainTerminalIdentity.messageVerrouille)] {
            let trousseau = TrousseauEnMemoire()
            trousseau.statutAjoutForce = statut
            let e = erreur { _ = try KeychainTerminalIdentity(store: trousseau).identifiant() }
            XCTAssertEqual(e?.kind, .environment)
            XCTAssertEqual(e?.message, message)
            XCTAssertEqual(trousseau.appels.filter { $0 == "add" }.count, 1, "aucune nouvelle tentative")
        }
    }

    func testTextesOperationnelsInventories() {
        // Textes non juridiques nouveaux de T1, inventoriés avec leur motif dans `docs/mobile-swift/DECISIONS_LOT2.md`
        // (« Textes opérationnels hors web ») ; le web n'a pas d'équivalent (`src/lib/terminal.ts` : empreinte
        // navigateur recalculée, rien de stocké). Vouvoiement ; jamais « redémarrez l'application » pour une valeur
        // illisible, que rien ne réécrit : le recours est le pointage sur jolene.app.
        XCTAssertEqual(KeychainTerminalIdentity.messageVerrouille,
                       "Le trousseau de cet appareil est verrouillé. Déverrouillez l'appareil puis réessayez.")
        XCTAssertEqual(KeychainTerminalIdentity.messageIndisponible,
                       "L'identifiant de cet appareil n'a pas pu être lu. Le pointage est momentanément indisponible : réessayez.")
        XCTAssertEqual(KeychainTerminalIdentity.messageIllisible,
                       "L'identifiant de cet appareil est illisible. Le pointage n'est pas disponible dans l'application sur cet appareil : pointez depuis jolene.app.")
        for message in [KeychainTerminalIdentity.messageVerrouille, KeychainTerminalIdentity.messageIndisponible,
                        KeychainTerminalIdentity.messageIllisible] {
            XCTAssertFalse(message.lowercased().contains("redémarr"), message)
        }
    }

    func testEcrivainConcurrentLIdentifiantDejaStockeGagne() throws {
        let trousseau = TrousseauEnMemoire()
        trousseau.ecrivainConcurrent = Data("TERM_IOS_ZZZZZZZZZZZZZZZZZZZZ".utf8)
        XCTAssertEqual(try KeychainTerminalIdentity(store: trousseau).identifiant(), "TERM_IOS_ZZZZZZZZZZZZZZZZZZZZ",
                       "errSecDuplicateItem : relecture, jamais d'écrasement")
        XCTAssertFalse(trousseau.appels.contains("update"))
    }

    func testValeurStockeeIllisibleNEstJamaisRemplacee() {
        // Décision 7 (généré une fois) : une valeur hors format n'est ni réécrite ni effacée ; elle survit à la
        // réinstallation (trousseau). Recours documenté : pointer sur jolene.app (`DECISIONS_LOT2.md`, consigne T4b).
        for valeur in ["TERM_WEB_abc", "TERM_IOS_abcdefghijklmnopqrst", ""] {
            let trousseau = TrousseauEnMemoire()
            trousseau.poser(valeur, service: service, compte: compte)
            let e = erreur { _ = try KeychainTerminalIdentity(store: trousseau).identifiant() }
            XCTAssertEqual(e?.kind, .environment, "fail-closed")
            XCTAssertEqual(e?.message, KeychainTerminalIdentity.messageIllisible, valeur)
            if !valeur.isEmpty {
                XCTAssertFalse(e?.message.contains(valeur) ?? true, "le message ne cite jamais la valeur")
            }
            XCTAssertEqual(trousseau.appels, ["copy"], "aucune écriture ni suppression")
        }
    }
}
