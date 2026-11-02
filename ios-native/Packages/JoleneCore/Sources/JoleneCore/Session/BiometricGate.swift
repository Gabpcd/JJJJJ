import Foundation

/// Verrou biométrique applicatif (lot 1, T9, décision 1 ; blueprint §2.5) : avant chaque
/// `restoreSession` (lancement à froid, reprise après 30 minutes, « Réessayer sans mot de passe »),
/// si le compte dont la session est conservée a activé le déverrouillage ET que la biométrie est
/// disponible, `LAContext` est évalué. Refus ou annulation : `.signedOut(message: nil)` sans toucher
/// au Keychain (`SessionController.lockForBiometrics()`). Biométrie absente ou retirée : aucun verrou
/// (« désactivé si non enrôlé »). Démo : port `.unavailable`, préférences en mémoire.
///
/// Ce n'est pas une protection cryptographique de la session : l'item Keychain reste accessible
/// appareil déverrouillé (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), comme au lot 0.
public struct BiometricGate: Sendable {
    public enum Issue: Equatable, Sendable {
        /// Aucune préférence active, ou biométrie indisponible : la restauration suit.
        case aucunVerrou
        /// Biométrie réussie : la restauration suit.
        case deverrouille
        /// Échec ou annulation : l'espace reste fermé, la session persistée intacte.
        case refuse
    }

    /// Raison affichée par l'invite système au déverrouillage.
    public static let raisonDeverrouillage = "Déverrouillez votre espace Jolene."

    public let port: BiometricPort
    public let preferences: BiometricPreferenceStore

    public init(port: BiometricPort, preferences: BiometricPreferenceStore) {
        self.port = port
        self.preferences = preferences
    }

    /// Aucun verrou : biométrie indisponible, préférences en mémoire (démo, doubles de test).
    public static var inactif: BiometricGate {
        BiometricGate(port: UnavailableBiometricPort(), preferences: InMemoryBiometricPreferences())
    }

    /// Vrai si le compte dont la session est conservée a activé le déverrouillage. Synchrone, sans
    /// `LAContext` : un compte sans préférence n'interroge jamais la biométrie.
    public var verrouAttendu: Bool {
        guard let identite = preferences.sessionIdentity else { return false }
        return preferences.isEnabled(userId: identite)
    }

    /// Évalue le verrou. Ne lève jamais.
    public func verifier() async -> Issue {
        guard verrouAttendu else { return .aucunVerrou }
        guard case .available = await port.availability() else { return .aucunVerrou }
        switch await port.authenticate(reason: Self.raisonDeverrouillage) {
        case .success: return .deverrouille
        case .unavailable: return .aucunVerrou
        case .failed, .cancelled: return .refuse
        }
    }

    /// Identité dont la session vient d'être ouverte ou restaurée (`.ready`).
    public func memoriser(identite userId: String) {
        preferences.setSessionIdentity(userId)
    }

    /// Plus aucune session à protéger (déconnexion volontaire, session effacée par le SDK). La
    /// préférence du compte, elle, est conservée pour sa prochaine connexion.
    public func oublierIdentite() {
        preferences.setSessionIdentity(nil)
    }
}
