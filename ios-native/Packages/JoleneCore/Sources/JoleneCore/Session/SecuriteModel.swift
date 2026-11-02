import Foundation
import Combine

/// Modèle de l'écran Profil › Sécurité (lot 1, T9) : préférence de déverrouillage biométrique du
/// compte connecté (`BiometricPreferenceStore`, par userId).
///
/// - interrupteur grisé tant que la disponibilité n'est pas connue, et sans biométrie enrôlée (démo
///   comprise) : « Non disponible sur cet appareil » ;
/// - activer exige une biométrie réussie (preuve que l'utilisateur peut déverrouiller ensuite) ;
///   une annulation n'est pas une erreur ; désactiver ne demande rien ;
/// - l'interrupteur n'affiche « activé » que si le verrou s'applique réellement (préférence ET
///   biométrie disponible).
@MainActor
public final class SecuriteModel: ObservableObject {
    public enum Disponibilite: Equatable, Sendable {
        case inconnue
        case disponible(BiometryKind)
        case indisponible
    }

    public static let indisponibleMessage = "Non disponible sur cet appareil"
    public static let activationEchoueeMessage = "Le déverrouillage biométrique n'a pas été activé. Réessayez."

    @Published public private(set) var disponibilite: Disponibilite = .inconnue
    @Published public private(set) var activee: Bool
    @Published public private(set) var enCours = false
    @Published public private(set) var message: String?

    private let gate: BiometricGate
    private let userId: String

    public init(gate: BiometricGate, userId: String) {
        self.gate = gate
        self.userId = userId
        self.activee = gate.preferences.isEnabled(userId: userId)
    }

    public var estIndisponible: Bool { disponibilite == .indisponible }

    /// Valeur affichée par l'interrupteur.
    public var interrupteur: Bool {
        guard case .disponible = disponibilite else { return false }
        return activee
    }

    public var interrupteurModifiable: Bool {
        guard case .disponible = disponibilite else { return false }
        return !enCours
    }

    public var libelleInterrupteur: String {
        guard case let .disponible(type) = disponibilite else { return "Déverrouillage biométrique" }
        return "Déverrouiller avec \(type.libelle)"
    }

    public var explication: String {
        let demande: String
        if case let .disponible(type) = disponibilite, type != .autre {
            demande = "\(type.libelle) vous est demandé"
        } else {
            demande = "la biométrie vous est demandée"
        }
        return "À l'ouverture de l'application et au retour après 30 minutes d'absence, \(demande) avant d'afficher votre espace. Votre session reste enregistrée sur cet appareil."
    }

    public func charger() async {
        switch await gate.port.availability() {
        case let .available(type): disponibilite = .disponible(type)
        case .unavailable: disponibilite = .indisponible
        }
        activee = gate.preferences.isEnabled(userId: userId)
    }

    public func basculer(_ activer: Bool) async {
        guard interrupteurModifiable, activer != interrupteur else { return }
        message = nil
        guard activer else {
            gate.preferences.setEnabled(false, userId: userId)
            activee = false
            return
        }
        guard case let .disponible(type) = disponibilite else { return }
        enCours = true
        let issue = await gate.port.authenticate(reason: "Confirmez pour activer le déverrouillage par \(type.libelle).")
        enCours = false
        switch issue {
        case .success:
            gate.preferences.setEnabled(true, userId: userId)
            gate.memoriser(identite: userId)
            activee = true
        case .cancelled:
            activee = false
        case .failed:
            activee = false
            message = Self.activationEchoueeMessage
        case .unavailable:
            activee = false
            disponibilite = .indisponible
        }
    }
}
