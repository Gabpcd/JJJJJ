import Foundation

// Biométrie (lot 1, T9, décision 1) : verrou applicatif `LAContext` devant `restoreSession`.
// L'item Keychain de la session reste inchangé (aucun `SecAccessControl biometryCurrentSet`,
// qui invaliderait la session à tout changement d'empreinte). Le port est implémenté par l'app
// (`Jolene/Composition/LocalAuthenticationBiometrics.swift`, LocalAuthentication) ; le cœur n'en
// connaît que les issues. Démo et appareil sans biométrie enrôlée : `.unavailable`, aucun verrou.

/// Biométrie de l'appareil, pour le libellé affiché.
public enum BiometryKind: String, Equatable, Sendable {
    case faceID, touchID, opticID, autre

    public var libelle: String {
        switch self {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .autre: return "la biométrie"
        }
    }
}

public enum BiometricAvailability: Equatable, Sendable {
    /// Biométrie enrôlée (`canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`).
    case available(BiometryKind)
    /// Non enrôlée, absente, sans code d'appareil, ou mode démo.
    case unavailable
}

public enum BiometricResult: Equatable, Sendable {
    case success
    /// Visage ou empreinte non reconnus (au-delà des essais du système).
    case failed
    /// Annulation par l'utilisateur, l'app ou le système (appel entrant, passage en arrière-plan).
    case cancelled
    /// La biométrie a disparu entre la vérification et l'évaluation (désenrôlement, code retiré).
    case unavailable
}

/// Évaluation `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` (code de l'appareil en repli).
public protocol BiometricPort: Sendable {
    func availability() async -> BiometricAvailability
    func authenticate(reason: String) async -> BiometricResult
}

/// Port sans biométrie : monde démo (`LOT1_PLAN.md` §2.7) et défaut de `SessionStore`.
public struct UnavailableBiometricPort: BiometricPort {
    public init() {}
    public func availability() async -> BiometricAvailability { .unavailable }
    public func authenticate(reason: String) async -> BiometricResult { .unavailable }
}

// MARK: - Préférences

/// Préférence « déverrouiller avec Face ID », propre à chaque compte, et identité dont la session est
/// conservée sur l'appareil (le verrou s'applique AVANT `restoreSession`, qui seul connaît l'identité).
/// Synchrone : lue au lancement avant tout appel réseau.
public protocol BiometricPreferenceStore: Sendable {
    func isEnabled(userId: String) -> Bool
    func setEnabled(_ enabled: Bool, userId: String)
    /// Dernière identité arrivée à `.ready`, effacée à la déconnexion volontaire ou quand le SDK a effacé
    /// la session ; nil = aucune session à protéger.
    var sessionIdentity: String? { get }
    func setSessionIdentity(_ userId: String?)
}

enum BiometricPreferenceKeys {
    /// Identifiant normalisé (uuid texte de PostgREST en minuscules) ; nil si vide.
    static func normaliser(_ userId: String) -> String? {
        let valeur = userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return valeur.isEmpty ? nil : valeur
    }
}

/// Préférences en `UserDefaults` (blueprint T9 : `jolene.biometrie.activee`, par userId). La clé
/// d'activation porte l'identifiant comme segment (`jolene.biometrie.activee.<userId>`) : la purge des
/// préférences locales après une suppression de compte (`CompteSuppression.purgerPreferencesLocales`,
/// T8) l'efface sans liste à tenir. Aucune donnée secrète : un drapeau et un identifiant de compte.
public final class UserDefaultsBiometricPreferences: BiometricPreferenceStore, @unchecked Sendable {
    // `@unchecked` : seul état, une référence `UserDefaults` immuable, documentée sûre entre threads.
    public static let enabledKeyPrefix = "jolene.biometrie.activee."
    public static let identityKey = "jolene.biometrie.identite-session"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isEnabled(userId: String) -> Bool {
        guard let id = BiometricPreferenceKeys.normaliser(userId) else { return false }
        return defaults.bool(forKey: Self.enabledKeyPrefix + id)
    }

    public func setEnabled(_ enabled: Bool, userId: String) {
        guard let id = BiometricPreferenceKeys.normaliser(userId) else { return }
        if enabled {
            defaults.set(true, forKey: Self.enabledKeyPrefix + id)
        } else {
            defaults.removeObject(forKey: Self.enabledKeyPrefix + id)
        }
    }

    public var sessionIdentity: String? {
        defaults.string(forKey: Self.identityKey).flatMap(BiometricPreferenceKeys.normaliser)
    }

    public func setSessionIdentity(_ userId: String?) {
        if let userId, let id = BiometricPreferenceKeys.normaliser(userId) {
            defaults.set(id, forKey: Self.identityKey)
        } else {
            defaults.removeObject(forKey: Self.identityKey)
        }
    }
}

/// Préférences en mémoire : monde démo (rien n'est persisté entre deux lancements) et tests.
public final class InMemoryBiometricPreferences: BiometricPreferenceStore, @unchecked Sendable {
    // `@unchecked` : état protégé par `lock`, jamais lu ni écrit hors verrou.
    private let lock = NSLock()
    private var enabled: Set<String> = []
    private var identity: String?

    public init() {}

    public func isEnabled(userId: String) -> Bool {
        guard let id = BiometricPreferenceKeys.normaliser(userId) else { return false }
        lock.lock(); defer { lock.unlock() }
        return enabled.contains(id)
    }

    public func setEnabled(_ value: Bool, userId: String) {
        guard let id = BiometricPreferenceKeys.normaliser(userId) else { return }
        lock.lock(); defer { lock.unlock() }
        if value { enabled.insert(id) } else { enabled.remove(id) }
    }

    public var sessionIdentity: String? {
        lock.lock(); defer { lock.unlock() }
        return identity
    }

    public func setSessionIdentity(_ userId: String?) {
        let id = userId.flatMap(BiometricPreferenceKeys.normaliser)
        lock.lock(); defer { lock.unlock() }
        identity = id
    }
}
