import Foundation

/// Récupération du mot de passe en démonstration (reste de L1-T10 ; `LOT1_PLAN.md` §4, ligne « Reset mot de passe ») :
/// aucune requête réseau, aucun e-mail. Seul le lien `token_hash=demo&type=recovery` ouvre une session de récupération
/// (fictive, tenue ici et jamais vue par l'authentification démo : quarantaine) ; tout autre lien est refusé avec le
/// texte web. `?code=` est refusé avant d'arriver ici (option B, `DeepLinkIntent`), et ici aussi.
/// `nouveauRefuse` : mot de passe que le « serveur » démo refuse (preuve du refus affiché verbatim, sans réseau).
public actor DemoRecoveryGateway: RecoveryPort {
    public static let tokenHashDemo = "demo"
    /// Refusé par la démo comme GoTrue refuse un mot de passe trop faible (`weak_password`).
    public static let nouveauRefuse = "motdepasse"

    private(set) var sessionOuverte = false
    private(set) var motDePasseEnregistre = false
    private(set) var demandes: [String] = []

    public init() {}

    public func requestReset(email: String) async throws {
        demandes.append(ReinitialisationRules.emailNormalise(email))
    }

    public func openRecoverySession(_ credentials: AuthCallbackCredentials) async throws -> RecoveryOutcome {
        sessionOuverte = false
        motDePasseEnregistre = false
        guard case let .tokenHash(tokenHash, otpType) = credentials, tokenHash == Self.tokenHashDemo, otpType == "recovery" else {
            return .lienRefuse(message: ReinitialisationTextes.lienInvalideDetail)
        }
        sessionOuverte = true
        return .sessionOuverte
    }

    public func updatePassword(_ password: String) async throws {
        guard sessionOuverte else { throw JoleneError(.unauthorized, ReinitialisationTextes.lienInvalideDetail) }
        guard password != Self.nouveauRefuse else {
            throw JoleneError(.invalidCredentials, MotDePasse.messageRefus(code: "weak_password", message: "Password is known to be weak"))
        }
        motDePasseEnregistre = true
    }

    public func signOutAfterRecovery() async throws {
        sessionOuverte = false
    }
}
