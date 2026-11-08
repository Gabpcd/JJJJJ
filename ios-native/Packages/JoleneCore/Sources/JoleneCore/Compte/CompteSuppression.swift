import Foundation
import Combine

/// Règles et textes de la suppression de compte (lot 1, T8 ; exigence Apple 5.1.1), port de
/// `src/components/profil-soignant/SectionConfidentialite.tsx` l.81-105 et l.151-200, et de la règle
/// app de la fiche « Edge `delete-account` » (`docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md`).
///
/// Aucun barème, aucune interprétation : un succès est la seule réponse HTTP 200 `{success:true}` de
/// l'edge (aucune relecture possible, le JWT est révoqué), tout le reste est un refus affiché avec le
/// message serveur verbatim, sans nouvelle tentative automatique.
public enum CompteSuppression {
    /// Phrase à saisir à l'identique (`deleteConfirmText !== 'SUPPRIMER'`, l.192 : ni casse ni espaces tolérés).
    public static let motConfirmation = "SUPPRIMER"

    /// Refus sans message serveur lisible (`data?.error || 'Suppression impossible.'`, l.89).
    public static let refusParDefautMessage = "Suppression impossible."

    /// Délai dépassé, réseau coupé ou appel interrompu : le serveur a pu agir (mutation au résultat
    /// inconnu, PRINCIPES §3-§4). Rien n'est annoncé ni renvoyé ; une nouvelle tentative reste
    /// manuelle (l'edge répond alors `Compte desactive` si la suppression a eu lieu).
    public static let confirmationIndisponibleMessage =
        "La suppression de votre compte n'a pas pu être confirmée. Vérifiez votre connexion puis réessayez."

    /// `error_code` des 503 de l'edge qui laissent un compte banni ou anonymisé (`index.ts` l.166-171 et
    /// l.247-250) : la session locale est retirée comme après un succès (blueprint lot 1 §3 T8).
    public static let codesDeconnexionForcee: Set<String> = ["AUTH_DELETE_PENDING", "ANONYMISATION_NON_CONFIRMEE"]

    public static func forceDeconnexion(code: String?) -> Bool {
        guard let code else { return false }
        return codesDeconnexionForcee.contains(code)
    }

    /// Préférences locales du compte supprimé (`LOT1_PLAN.md` l.252 : journal calendrier de T5,
    /// préférence biométrie de T9, une clé `UserDefaults` par `userId`) : toute clé dont un segment est
    /// l'identifiant (séparateurs : tout caractère autre que lettre, chiffre ou « - », casse ignorée) est
    /// retirée. Convention imposée aux clés par compte : l'identifiant y figure comme segment entier
    /// (`jolene.biometrie.activee.<userId>`). Rend les clés retirées, triées.
    @discardableResult
    public static func purgerPreferencesLocales(userId: String, defaults: UserDefaults) -> [String] {
        let identifiant = userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !identifiant.isEmpty else { return [] }
        let cles = defaults.dictionaryRepresentation().keys.filter { cle in
            cle.lowercased().split { !($0.isLetter || $0.isNumber || $0 == "-") }.contains { $0 == identifiant }
        }.sorted()
        cles.forEach(defaults.removeObject(forKey:))
        return cles
    }

    /// Fin de session demandée par une issue du port ; `nil` = refus affiché, la session reste ouverte.
    public static func fin(pour issue: DeleteAccountOutcome) -> FinDeCompte? {
        switch issue {
        case .deleted:
            return .supprime
        case let .refused(code, message):
            return forceDeconnexion(code: code) ? .deconnecte(message: message) : nil
        }
    }

    /// Textes de l'écran. Ceux du web sont repris **mot pour mot, en tutoiement** (HARD STOP n°4 :
    /// wording RGPD non revalidé par Gabrielle) ; leur égalité avec la source web est gardée par
    /// `CompteSuppressionVerbatimTests`. Seuls les textes de l'écran de fin, propres au natif, sont vouvoyés.
    public enum Textes {
        /// En-tête de la section (l.153).
        public static let sectionTitre = "Suppression de compte"
        /// Avertissement de la section (l.155-156).
        public static let sectionAvertissement =
            "La suppression de ton compte est irréversible. Tes données seront anonymisées conformément au RGPD."
        /// Lien d'ouverture (l.162).
        public static let boutonOuvrir = "Supprimer mon compte"
        /// Titre de la confirmation (l.170, sans le pictogramme décoratif « 🗑️ »).
        public static let confirmationTitre = "Supprimer mon compte"
        /// Avertissement de la confirmation (l.171-172, première partie du paragraphe).
        public static let confirmationAvertissement =
            "Cette action est irréversible. Tes données seront anonymisées conformément au RGPD."
        /// Consigne de saisie (l.172, fin du même paragraphe ; `<strong>` sans équivalent dans un libellé).
        public static let confirmationConsigne = "Tape SUPPRIMER pour confirmer."
        /// Exemple de saisie (placeholder, l.178).
        public static let confirmationExemple = "Tape SUPPRIMER"
        public static let boutonAnnuler = "Annuler"
        public static let boutonConfirmer = "Supprimer définitivement"

        /// Écran de fin (natif, vouvoiement ; le web affiche le toast « Compte supprimé. Redirection... »).
        public static let finSupprimeTitre = "Compte supprimé"
        public static let finSupprimeMessage = "Vous avez été déconnecté de l'application."
        public static let finDeconnecteTitre = "Vous avez été déconnecté"
        public static let finContinuer = "Continuer"
    }
}

/// Fin de session consécutive à une suppression de compte, affichée par la racine de l'app : l'onglet
/// Profil n'existe plus quand la session est retirée.
public enum FinDeCompte: Equatable, Sendable {
    /// HTTP 200 `{success:true}` de l'edge.
    case supprime
    /// Refus 503 qui laisse un compte banni ou anonymisé : message serveur verbatim.
    case deconnecte(message: String)

    public var titre: String {
        switch self {
        case .supprime: return CompteSuppression.Textes.finSupprimeTitre
        case .deconnecte: return CompteSuppression.Textes.finDeconnecteTitre
        }
    }

    public var message: String {
        switch self {
        case .supprime: return CompteSuppression.Textes.finSupprimeMessage
        case let .deconnecte(message): return message
        }
    }
}

/// Avis de fin de compte partagé entre l'écran de suppression et la racine de l'app. Signalé
/// **avant** que la session ne soit retirée : quand l'état passe à `.signedOut`, la racine affiche
/// l'écran « Compte supprimé » au lieu de la connexion, jamais « Votre session a expiré ».
@MainActor
public final class AvisFinDeCompte: ObservableObject {
    @Published public private(set) var issue: FinDeCompte?

    public init() {}

    public func signaler(_ issue: FinDeCompte) { self.issue = issue }

    /// L'utilisateur a pris connaissance de l'écran de fin : la connexion s'affiche.
    public func acquitter() { issue = nil }
}
