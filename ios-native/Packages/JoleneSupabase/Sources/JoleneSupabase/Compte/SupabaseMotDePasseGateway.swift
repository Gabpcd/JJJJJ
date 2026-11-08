import Foundation
import JoleneCore
import Supabase

/// `MotDePassePort` sur GoTrue (lot 3, T11, D13), comme `ChangementMotDePasse.tsx` l.49-76 :
/// 1. la session courante doit être celle de l'écran (`context.userId`), sinon aucune requête ;
/// 2. l'ancien mot de passe est vérifié par `signIn(email:password:)` sur l'email de cette session
///    (`invalid_credentials` → `.ancienIncorrect`, aucune mise à jour) ; un utilisateur renvoyé différent est un
///    refus, jamais une modification (le contrôleur de session traite le changement d'identité qu'émet le SDK) ;
///    la vérification ouvre une nouvelle session du MÊME utilisateur : `.signedIn` → `.session(même id)`,
///    ignoré par `SessionController` (aucun epoch avancé) ;
/// 3. `update(user: UserAttributes(password:))` (PUT `/auth/v1/user`), une seule fois ; la réponse 200 porte
///    l'utilisateur relu, preuve de la modification (un mot de passe ne se relit pas).
/// Refus GoTrue : réauthentification exigée (`reauthentication_needed`, `reauthentication_not_valid`, « secure
/// password change ») → `.reauthentificationRequise` (refus verrouillé, aucun flux OTP) ; JWT refusé (401/403) ou
/// session absente → session expirée ; autres refus → `.refuse` avec le texte web d'`extraireMessageErreur`
/// (`MotDePasse.messageRefus`). Transport : `SupabaseErrorMapping`. Aucun renvoi, aucun mot de passe dans un
/// message ni un journal.
public struct SupabaseMotDePasseGateway: MotDePassePort {
    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func changer(ancien: String, nouveau: String, context: MissionReadContext) async throws -> ResultatMotDePasse {
        try MissionQuery.validate(context: context)
        let attendu = context.userId.lowercased()
        guard let courant = client.auth.currentSession?.user, courant.id.uuidString.lowercased() == attendu else {
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        }
        guard let email = courant.email, !email.isEmpty else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }

        // 1. Vérification de l'ancien mot de passe (l.50-63).
        do {
            let session = try await client.auth.signIn(email: email, password: ancien)
            guard session.user.id.uuidString.lowercased() == attendu else {
                return .refuse(message: MotDePasse.Textes.erreurGenerique)
            }
        } catch let erreur as AuthError {
            if case .api(_, let code, _, _) = erreur, code == .invalidCredentials { return .ancienIncorrect }
            return try Self.issue(erreur)
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: MotDePasse.Textes.erreurGenerique)
        }

        // 2. Mise à jour (l.65-76).
        do {
            let utilisateur = try await client.auth.update(user: UserAttributes(password: nouveau))
            guard utilisateur.id.uuidString.lowercased() == attendu else {
                throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
            }
            return .modifie
        } catch let erreur as AuthError {
            return try Self.issue(erreur)
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: MotDePasse.Textes.erreurGenerique)
        }
    }

    /// Refus GoTrue → issue du port (ou erreur levée pour la session et le transport).
    static func issue(_ erreur: AuthError) throws -> ResultatMotDePasse {
        switch erreur {
        case .sessionMissing, .refreshDiscarded:
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        case .weakPassword(let message, _):
            return .refuse(message: MotDePasse.messageRefus(code: ErrorCode.weakPassword.rawValue, message: message))
        case .api(let message, let code, _, let reponse):
            if code == .reauthenticationNeeded || code == .reauthenticationNotValid { return .reauthentificationRequise }
            if SupabaseErrorMapping.unauthorizedStatuses.contains(reponse.statusCode) {
                throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
            }
            return .refuse(message: MotDePasse.messageRefus(code: code.rawValue, message: message))
        default:
            throw SupabaseErrorMapping.map(erreur, fallback: MotDePasse.Textes.erreurGenerique)
        }
    }
}
