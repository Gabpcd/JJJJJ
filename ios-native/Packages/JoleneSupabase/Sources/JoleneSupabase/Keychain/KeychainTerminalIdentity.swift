import Foundation
import JoleneCore
import Security

/// Identifiant terminal persistant (décision 7 du lot 2, blueprint `LOT2_PLAN.md` §2.2) envoyé dans
/// `p_metadata.id_terminal` : `TERM_IOS_` + 20 caractères base32 aléatoires (`IdentifiantTerminal`),
/// générés une fois, en Keychain `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, jamais synchronisé,
/// sous un service distinct de la session : la déconnexion (purge de `app.jolene.session`) le conserve.
/// Jamais `identifierForVendor` ni empreinte d'appareil.
///
/// Fail-closed : toute issue autre qu'une valeur valide ou absente lève `JoleneError(.environment)` SANS générer
/// ni écrire un second identifiant ; un écrivain concurrent (`errSecDuplicateItem`) gagne : sa valeur est relue.
/// Trois cas, trois messages (revue fraîche de T1) :
/// - trousseau verrouillé (`errSecInteractionNotAllowed`, avant le premier déverrouillage) : transitoire, aucun
///   échec mémorisé, l'appel suivant relit ;
/// - autre échec du trousseau (entitlement absent, erreur interne) : réessayer ;
/// - valeur stockée hors format : permanente (jamais réécrite, décision 7 ; l'élément survit à la réinstallation),
///   donc recours web : le pointage se fait sur jolene.app, qui n'utilise pas cet identifiant
///   (`src/lib/terminal.ts`). Voie de récupération consignée dans `docs/mobile-swift/DECISIONS_LOT2.md`.
/// Textes non juridiques, sans source web (inventaire « Textes opérationnels hors web » du même mémo) ; ils ne
/// citent jamais la valeur stockée.
public struct KeychainTerminalIdentity: TerminalIdentityPort {
    public static let service = "app.jolene.terminal"
    public static let compte = "id_terminal"
    public static let messageVerrouille = "Le trousseau de cet appareil est verrouillé. Déverrouillez l'appareil puis réessayez."
    public static let messageIndisponible = "L'identifiant de cet appareil n'a pas pu être lu. Le pointage est momentanément indisponible : réessayez."
    public static let messageIllisible = "L'identifiant de cet appareil est illisible. Le pointage n'est pas disponible dans l'application sur cet appareil : pointez depuis jolene.app."

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
            guard let relu = try lire() else { throw Self.erreur(statut: errSecItemNotFound) }
            return relu
        default:
            throw Self.erreur(statut: statut)
        }
    }

    /// Valeur stockée et valide, nil si absente ; toute autre issue lève.
    private func lire() throws -> String? {
        let (statut, data) = store.copy(Self.requeteLecture())
        switch statut {
        case errSecSuccess:
            guard let data, let valeur = String(data: data, encoding: .utf8), IdentifiantTerminal.estValide(valeur) else {
                throw JoleneError(.environment, Self.messageIllisible)
            }
            return valeur
        case errSecItemNotFound:
            return nil
        default:
            throw Self.erreur(statut: statut)
        }
    }

    /// Échec du trousseau : verrouillé (transitoire) ou autre.
    private static func erreur(statut: OSStatus) -> JoleneError {
        JoleneError(.environment, statut == errSecInteractionNotAllowed ? messageVerrouille : messageIndisponible)
    }

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
