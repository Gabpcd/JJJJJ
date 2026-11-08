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
/// 3. garde d'identité (revue B8, m2) : si l'identité de l'écran est partie pendant la vérification (`.signedOut`
///    d'une révocation ou d'un refresh refusé, alors que le `signIn` recrée une session dans le SDK et que l'app
///    affiche la connexion), aucune mise à jour ne part, la session recréée est retirée (`signOut(scope: .local)`,
///    seulement si le SDK tient encore le jeton de la vérification : une connexion arrivée après n'est jamais
///    retirée) et l'appel lève `.cancelled` ;
/// 4. `update(user: UserAttributes(password:))` (PUT `/auth/v1/user`), une seule fois ; la réponse 200 porte
///    l'utilisateur relu, preuve de la modification (un mot de passe ne se relit pas).
/// Issues de la mise à jour sans équivalent web (revue B8, m1 ; le SDK rejoue une fois un PUT sur une coupure ou
/// un 408/5xx, `RetryRequestInterceptor`) :
/// - `same_password` avec un nouveau distinct de l'ancien vérifié (octets UTF-8, 72 premiers pour bcrypt) : le mot
///   de passe vaut déjà le nouveau (rejeu d'un PUT abouti) → `.modifie` ; nouveau égal à l'ancien → refus web ;
/// - 5xx ou 408 (après le rejeu) : le serveur a pu enregistrer le changement → issue inconnue (`.unknown`,
///   `confirmationIndisponible`), jamais un refus.
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

    public func changer(ancien: String, nouveau: String, context: MissionReadContext,
                        identiteCourante: @escaping @Sendable () async -> Bool) async throws -> ResultatMotDePasse {
        try MissionQuery.validate(context: context)
        let attendu = context.userId.lowercased()
        guard let courant = client.auth.currentSession?.user, courant.id.uuidString.lowercased() == attendu else {
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        }
        guard let email = courant.email, !email.isEmpty else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }

        // 1. Vérification de l'ancien mot de passe (l.50-63).
        let verification: Session
        do {
            verification = try await client.auth.signIn(email: email, password: ancien)
            guard verification.user.id.uuidString.lowercased() == attendu else {
                return .refuse(message: MotDePasse.Textes.erreurGenerique)
            }
        } catch let erreur as AuthError {
            if case .api(_, let code, _, _) = erreur, code == .invalidCredentials { return .ancienIncorrect }
            return try Self.issue(erreur)
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: MotDePasse.Textes.erreurGenerique)
        }

        // 2. Garde d'identité entre la vérification et la mise à jour (revue B8, m2).
        guard await identiteCourante() else {
            if client.auth.currentSession?.accessToken == verification.accessToken {
                try? await client.auth.signOut(scope: .local)
            }
            throw MotDePasse.identitePartie
        }

        // 3. Mise à jour (l.65-76).
        do {
            let utilisateur = try await client.auth.update(user: UserAttributes(password: nouveau))
            guard utilisateur.id.uuidString.lowercased() == attendu else {
                throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
            }
            return .modifie
        } catch let erreur as AuthError {
            return try Self.issueMiseAJour(erreur, ancien: ancien, nouveau: nouveau)
        } catch let erreur as JoleneError {
            throw erreur
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: MotDePasse.Textes.erreurGenerique)
        }
    }

    /// Statuts d'une mise à jour dont l'issue est inconnue : délai (408) et erreurs serveur (5xx).
    static func issueInconnue(_ statut: Int) -> Bool { statut == 408 || (500...599).contains(statut) }

    /// Refus GoTrue de la mise à jour → issue du port : `same_password` et 5xx/408 d'abord (revue B8, m1), puis la
    /// traduction commune.
    static func issueMiseAJour(_ erreur: AuthError, ancien: String, nouveau: String) throws -> ResultatMotDePasse {
        if case .api(_, let code, _, let reponse) = erreur {
            if code == .samePassword, MotDePasse.memeMotDePasseProuveLaModification(ancien: ancien, nouveau: nouveau) {
                return .modifie
            }
            if issueInconnue(reponse.statusCode) {
                throw JoleneError(.unknown, MotDePasse.Textes.confirmationIndisponible)
            }
        }
        return try issue(erreur)
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
