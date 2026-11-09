import Foundation
import JoleneCore
import Supabase

/// `AuthPort` sur GoTrue via supabase-swift (plan §4.3) : email + mot de passe, PKCE,
/// session persistée par le stockage injecté dans le client (Keychain en production).
public struct SupabaseAuthGateway: AuthPort {
    public static let invalidCredentialsMessage = "Email ou mot de passe incorrect."
    public static let emailUnconfirmedMessage = "Confirmez votre adresse email avant de continuer."
    public static let tooManyAttemptsMessage = "Trop de tentatives. Réessayez dans quelques minutes."
    public static let signInFallbackMessage = "La connexion a échoué. Réessayez."
    public static let signOutFallbackMessage = "La déconnexion n'a pas pu être confirmée. Réessayez."

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    /// Lit la session persistée sans réseau quand elle est encore valide ; sinon la
    /// rafraîchit. Une session irrécupérable (refus 4xx du serveur) vaut « déconnecté ».
    public func restoreSession() async throws -> AuthenticatedUser? {
        guard let stored = client.auth.currentSession else { return nil }
        if !stored.isExpired { return Self.user(from: stored.user) }
        do {
            let refreshed = try await client.auth.session
            return Self.user(from: refreshed.user)
        } catch let error as AuthError {
            switch error {
            case .sessionMissing:
                return nil
            case .api(_, _, _, let response) where (400..<500).contains(response.statusCode):
                return nil
            default:
                throw SupabaseErrorMapping.map(error, fallback: SupabaseErrorMapping.unauthorizedMessage)
            }
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: SupabaseErrorMapping.unauthorizedMessage)
        }
    }

    /// Les refus GoTrue (400/401/403/422) deviennent `.invalidCredentials` avec un message
    /// générique : ni l'email ni le détail serveur ne sont exposés.
    public func signIn(email: String, password: String) async throws -> AuthenticatedUser {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            throw JoleneError(.invalidCredentials, Self.invalidCredentialsMessage)
        }
        do {
            let session = try await client.auth.signIn(email: trimmedEmail, password: password)
            return Self.user(from: session.user)
        } catch let error as AuthError {
            throw Self.signInError(error)
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.signInFallbackMessage)
        }
    }

    /// Le SDK supprime la session locale avant d'appeler le serveur ; un échec serveur
    /// (réseau, 5xx) est toléré. On relit l'état local après l'opération.
    public func signOut() async throws {
        do {
            try await client.auth.signOut(scope: .global)
        } catch {
            // Échec serveur toléré : la session locale est déjà retirée par le SDK.
        }
        guard client.auth.currentSession == nil else {
            throw JoleneError(.unknown, Self.signOutFallbackMessage)
        }
    }

    /// Événements du SDK (`onAuthStateChange`) traduits en `AuthEvent` : `SIGNED_OUT` → `.signedOut`
    /// (le SDK a effacé la session locale : révocation, déconnexion globale, refresh refusé) ;
    /// tout événement porteur d'une session → `.session(userId)`. Un `INITIAL_SESSION` sans
    /// session n'émet rien (c'est `restoreSession` qui tranche).
    public func authEvents() -> AsyncStream<AuthEvent> {
        let source = client.auth.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                for await (event, session) in source {
                    if let mapped = Self.authEvent(event, session: session) {
                        continuation.yield(mapped)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func authEvent(_ event: AuthChangeEvent, session: Session?) -> AuthEvent? {
        switch event {
        case .signedOut:
            return .signedOut
        case .initialSession, .signedIn, .tokenRefreshed, .userUpdated, .passwordRecovery, .mfaChallengeVerified, .userDeleted:
            guard let session else { return nil }
            return .session(userId: session.user.id.uuidString.lowercased())
        }
    }

    static func signInError(_ error: AuthError) -> JoleneError {
        switch error {
        case .api(_, let code, _, let response):
            if code.rawValue == "email_not_confirmed" {
                return JoleneError(.unauthorized, emailUnconfirmedMessage)
            }
            switch response.statusCode {
            case 400, 401, 403, 422:
                return JoleneError(.invalidCredentials, invalidCredentialsMessage)
            case 429:
                return JoleneError(.unknown, tooManyAttemptsMessage)
            default:
                return SupabaseErrorMapping.map(status: response.statusCode, fallback: signInFallbackMessage)
            }
        case .weakPassword:
            return JoleneError(.invalidCredentials, invalidCredentialsMessage)
        default:
            return SupabaseErrorMapping.map(error, fallback: signInFallbackMessage)
        }
    }

    /// `User` GoTrue -> `AuthenticatedUser`. L'identifiant est normalisé en minuscules pour
    /// correspondre aux uuid texte renvoyés par PostgREST (`soignants.id`).
    static func user(from user: User) -> AuthenticatedUser {
        AuthenticatedUser(
            id: user.id.uuidString.lowercased(),
            email: user.email,
            emailConfirmedAt: user.emailConfirmedAt,
            appMetadataRole: user.appMetadata["role"]?.stringValue,
            appMetadataEtablissementId: user.appMetadata["etablissement_id"]?.stringValue
        )
    }
}

// MARK: - Purge locale (lot 1, T8)

extension SupabaseAuthGateway: LocalSignOutPort {
    /// Purge locale après la suppression du compte : `signOut(scope: .local)`, comme le web
    /// (`SectionConfidentialite.tsx` l.96). supabase-swift 2.55.5 retire la session du stockage
    /// (Keychain) et émet `.signedOut` AVANT l'appel `/logout?scope=local` (AuthClient l.1100-1113) ;
    /// cet appel, sans objet (l'edge a déjà révoqué les sessions), est toléré en échec.
    public func signOutLocally() async {
        do {
            try await client.auth.signOut(scope: .local)
        } catch {
            // Session locale déjà retirée par le SDK : un refus ou une coupure du serveur est sans effet.
        }
    }
}
