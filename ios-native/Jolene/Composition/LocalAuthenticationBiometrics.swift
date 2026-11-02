import Foundation
import LocalAuthentication
import JoleneCore

/// `BiometricPort` sur LocalAuthentication (lot 1, T9, décision 1) : verrou applicatif, jamais une
/// protection de l'item Keychain (aucun `SecAccessControl`). Un `LAContext` neuf par appel, jamais
/// partagé entre tâches (type non `Sendable`) : la valeur ne quitte pas la fonction qui la crée.
///
/// - disponibilité : `canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` — biométrie
///   enrôlée, y compris verrouillée après trop d'essais (`biometryLockout`) ; sinon `.unavailable`
///   (le verrou s'efface, « Non disponible sur cet appareil ») ;
/// - évaluation : `.deviceOwnerAuthentication` (le code de l'appareil prend le relais après les
///   essais biométriques) ; annulation → `.cancelled`, échec → `.failed`, biométrie retirée →
///   `.unavailable`.
///
/// Libellé de l'invite système : `NSFaceIDUsageDescription` (Info.plist) et la raison passée.
/// Prouvé sur appareil seulement (`RECETTE_DEVICE_LOT1.md` §3) : la démo injecte un port `.unavailable`.
struct LocalAuthenticationBiometrics: BiometricPort {
    func availability() async -> BiometricAvailability {
        let context = LAContext()
        var erreur: NSError?
        let evaluable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &erreur)
        // Biométrie verrouillée après trop d'essais (`biometryLockout`) : toujours enrôlée, le verrou
        // reste dû — l'évaluation `.deviceOwnerAuthentication` demande alors le code de l'appareil.
        // La traiter comme indisponible permettrait de contourner le verrou en échouant exprès.
        let verrouillee = erreur.map { LAError.Code(rawValue: $0.code) == .biometryLockout } ?? false
        guard evaluable || verrouillee else { return .unavailable }
        switch context.biometryType {
        case .faceID: return .available(.faceID)
        case .touchID: return .available(.touchID)
        case .none: return verrouillee ? .available(.autre) : .unavailable
        default:
            if #available(iOS 17.0, *), context.biometryType == .opticID { return .available(.opticID) }
            return .available(.autre)
        }
    }

    func authenticate(reason: String) async -> BiometricResult {
        let context = LAContext()
        context.localizedCancelTitle = "Annuler"
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) ? .success : .failed
        } catch let erreur as LAError {
            return Self.issue(erreur.code)
        } catch {
            return .failed
        }
    }

    static func issue(_ code: LAError.Code) -> BiometricResult {
        switch code {
        case .userCancel, .appCancel, .systemCancel, .userFallback, .notInteractive:
            return .cancelled
        case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet:
            return .unavailable
        default:
            return .failed
        }
    }
}
