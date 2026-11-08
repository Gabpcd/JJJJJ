import Foundation
import JoleneCore
import Security

/// Identifiant terminal persistant (décision 7 du lot 2, blueprint `LOT2_PLAN.md` §2.2) envoyé dans
/// `p_metadata.id_terminal` : `TERM_IOS_` + 20 caractères base32 aléatoires (`IdentifiantTerminal`),
/// générés une fois, en Keychain `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, jamais synchronisé,
/// sous un service distinct de la session : la déconnexion (purge de `app.jolene.session`) le conserve.
/// Jamais `identifierForVendor` ni empreinte d'appareil.
///
/// Fail-closed : une lecture en échec (trousseau verrouillé avant le premier déverrouillage, entitlement
/// absent…) ou une valeur stockée hors format lève `JoleneError(.environment)` SANS générer ni écrire un
/// second identifiant ; un écrivain concurrent (`errSecDuplicateItem`) gagne : sa valeur est relue.
public struct KeychainTerminalIdentity: TerminalIdentityPort {
    public static let service = "app.jolene.terminal"
    public static let compte = "id_terminal"
    /// Message technique (non juridique) ; ne cite jamais la valeur stockée.
    public static let messageIndisponible = "L'identifiant de cet appareil n'a pas pu être lu. Le pointage est indisponible : redémarrez l'application."

    private let store: any KeychainItemStore

    public init(store: any KeychainItemStore = SecurityKeychainStore()) {
        self.store = store
    }

    public func identifiant() throws -> String {
        if let existant = try lire() { return existant }
        var aleatoire = SystemRandomNumberGenerator()
        let nouveau = IdentifiantTerminal.generer(using: &aleatoire)
        let statut = store.add(Self.requeteAjout(Data(nouveau.utf8)))
        switch statut {
        case errSecSuccess, errSecDuplicateItem:
            // Relecture avant de rendre la valeur : celle du trousseau fait foi (écrivain concurrent compris).
            guard let relu = try lire() else { throw Self.erreur }
            return relu
        default:
            throw Self.erreur
        }
    }

    /// Valeur stockée et valide, nil si absente ; toute autre issue lève.
    private func lire() throws -> String? {
        let (statut, data) = store.copy(Self.requeteLecture())
        switch statut {
        case errSecSuccess:
            guard let data, let valeur = String(data: data, encoding: .utf8), IdentifiantTerminal.estValide(valeur) else {
                throw Self.erreur
            }
            return valeur
        case errSecItemNotFound:
            return nil
        default:
            throw Self.erreur
        }
    }

    private static var erreur: JoleneError { JoleneError(.environment, messageIndisponible) }

    static func base() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: compte,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    static func requeteAjout(_ valeur: Data) -> [String: Any] {
        base().merging([
            kSecValueData as String: valeur,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]) { _, nouveau in nouveau }
    }

    static func requeteLecture() -> [String: Any] {
        base().merging([
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]) { _, nouveau in nouveau }
    }
}
