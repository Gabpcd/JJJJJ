import Foundation
import JoleneCore
import Supabase

/// Récupération du mot de passe sur GoTrue (reste de L1-T10 ; `LOT1_PLAN.md` §2.5, §3 T10 et décision 7, option B),
/// port de `PageConnexion.tsx` l.230-258 (demande) et de `PageResetPassword.tsx` l.27-113 (lien, nouveau mot de passe).
///
/// **Quarantaine par isolement** (écart consigné au plan, qui prévoyait d'ignorer les événements du client principal
/// pendant le flux) : tout le flux passe par un `AuthClient` **isolé**, créé par `fabrique` pour chaque lien, avec un
/// stockage en mémoire et sans rafraîchissement automatique. La session de récupération n'est donc jamais écrite dans
/// le Keychain de l'app, n'émet aucun événement vers `SupabaseAuthGateway` ni vers `SessionController`, n'est jamais
/// relue par `restoreSession` et disparaît avec le processus : elle n'ouvre aucun écran de l'app. La session ouverte
/// dans l'app (s'il y en a une) n'est jamais touchée par cette gateway.
///
/// - `requestReset` : `resetPasswordForEmail(email, redirectTo: https://jolene.app/reset-password)` sur un client
///   isolé en flux implicit : aucun verifier PKCE n'est écrit (le slot unique du client principal, qui sert la
///   confirmation d'inscription `?code=`, n'est pas écrasé), et le lien reçu est `token_hash` (modèle d'e-mail du §6.6)
///   ou implicit, les deux formats acceptés par l'app ; réponse identique que le compte existe ou non (GoTrue rend 200
///   dans les deux cas) ; refus GoTrue traduits comme `extraireMessageErreur` (`MotDePasse.messageRefus`) ;
/// - `openRecoverySession` : `token_hash` → `verifyOTP(tokenHash:type: .recovery)` (preuve serveur : un hash d'un autre
///   type est refusé par GoTrue) ; implicit (`type=recovery` exigé par `AuthCallbackCredentials.recovery`) →
///   `setSession`, comme le site (revue B8 sécurité de la vague D, m5 : marqueur déclaratif, parité assumée,
///   `DECISIONS_LOT3.md`) ; `?code=` (PKCE) refusé sans appel réseau (option B) ; tout échec → texte web « Lien invalide ou
///   expiré » (`PageResetPassword.tsx` l.65-67, l.141-143), jamais un état à moitié ouvert : le client isolé est jeté ;
/// - `updatePassword` : `update(user: UserAttributes(password:))` sur la seule session isolée (aucune session isolée →
///   refus sans requête) ; la réponse 200 porte l'utilisateur relu par le serveur, preuve de l'enregistrement, et son
///   identifiant doit être celui de la session de récupération ; refus GoTrue → texte web ; 401/403 → lien expiré ;
///   5xx/408 → issue inconnue (le serveur a pu enregistrer) ;
/// - `signOutAfterRecovery` : après un mot de passe enregistré, `signOut()` de portée globale comme le web (l.98) ; sur
///   abandon ou échec, `signOut(scope: .local)` (la session de récupération seule est révoquée). Le client isolé est
///   jeté dans tous les cas, avant l'appel réseau.
///
/// Aucun jeton, code, lien ni mot de passe dans un message ou un journal (`AuthCallbackCredentials.description` masquée).
public struct SupabaseRecoveryGateway: RecoveryPort {
    /// Fabrique d'un client d'authentification isolé (une instance par lien reçu).
    public typealias Fabrique = @Sendable () -> AuthClient

    /// `urlCallbackPublique('/reset-password')` en coquille native (`src/lib/nativeLinks.ts` l.35-44).
    public static let redirection = URL(string: "https://jolene.app/reset-password")!

    private let fabrique: Fabrique?
    private let coffre: Coffre

    /// `fabrique` nil : verrou explicite (assemblage sans URL ni clé, `SupabaseGateways.make(client:)` des tests).
    public init(fabrique: Fabrique?) {
        self.fabrique = fabrique
        self.coffre = Coffre()
    }

    /// Fabrique de production : même projet et même clé publishable que le client principal, flux implicit, stockage
    /// en mémoire, aucun rafraîchissement automatique, en-tête `X-Client-Info` Jolene, transport injectable.
    public static func fabrique(url: URL, publishableKey: String, session: URLSession = .shared) -> Fabrique {
        let authURL = url.appendingPathComponent("auth/v1")
        return {
            AuthClient(url: authURL,
                       headers: ["apikey": publishableKey, "X-Client-Info": JoleneSupabase.clientInfo],
                       flowType: .implicit,
                       localStorage: StockageMemoire(),
                       fetch: { try await session.data(for: $0) },
                       autoRefreshToken: false)
        }
    }

    /// Texte du refus de configuration (gap verrouillé, jamais atteint par l'app : `make(environment:)` fournit la
    /// fabrique).
    static let nonConfiguree = JoleneError(.environment, "Configuration Supabase incomplète.")

    private func client() throws -> AuthClient {
        guard let fabrique else { throw Self.nonConfiguree }
        return fabrique()
    }

    // MARK: - Demande de lien

    public func requestReset(email: String) async throws {
        let client = try client()
        do {
            try await client.resetPasswordForEmail(InscriptionRules.emailNormalise(email), redirectTo: Self.redirection)
        } catch let erreur as AuthError {
            throw Self.refus(erreur)
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: MotDePasse.Textes.erreurGenerique)
        }
    }

    // MARK: - Lien de récupération

    public func openRecoverySession(_ credentials: AuthCallbackCredentials) async throws -> RecoveryOutcome {
        // Un lien précédent encore ouvert est fermé d'abord (révoqué) : une seule session de récupération à la fois.
        // La tentative reçoit un jeton du coffre ; une fermeture ou un lien plus récent l'invalide (revue B8 sécurité de
        // la vague D, m4), si bien qu'une vérification qui aboutit après un délai dépassé ou après un second lien
        // n'ouvre rien : sa session est révoquée aussitôt.
        let (tentative, precedent) = await coffre.nouvelleTentative()
        if let (ancien, enregistre) = precedent { try? await ancien.signOut(scope: enregistre ? .global : .local) }
        let refus = RecoveryOutcome.lienRefuse(message: ReinitialisationTextes.lienInvalideDetail)
        let client: AuthClient
        switch credentials {
        case .pkce:
            return refus // option B (décision 7 du lot 1) : aucun échange, aucun appel
        case .tokenHash(_, let otpType) where otpType != "recovery":
            return refus
        case .tokenHash, .implicit:
            // Implicit : `type=recovery` exigé par `AuthCallbackCredentials.recovery`, parité avec le site
            // (`PageResetPassword.tsx`, `setSession` seul ; revue B8 sécurité de la vague D, m5, `DECISIONS_LOT3.md`).
            client = try self.client()
        }
        do {
            let session: Session
            switch credentials {
            case let .tokenHash(tokenHash, _):
                guard case let .session(ouverte) = try await client.verifyOTP(tokenHash: tokenHash, type: .recovery) else {
                    return refus
                }
                session = ouverte
            case let .implicit(accessToken, refreshToken):
                session = try await client.setSession(accessToken: accessToken, refreshToken: refreshToken)
            case .pkce:
                return refus
            }
            guard await coffre.ouvrir(client, userId: session.user.id, tentative: tentative) else {
                // Tentative abandonnée (délai dépassé, abandon, lien plus récent) : rien ne reste ouvert.
                try? await client.signOut(scope: .local)
                throw JoleneError(.cancelled, SupabaseErrorMapping.cancelledMessage)
            }
            return .sessionOuverte
        } catch let erreur as JoleneError where erreur.kind == .cancelled {
            throw erreur
        } catch {
            try? await client.signOut(scope: .local)
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw JoleneError(.cancelled, SupabaseErrorMapping.cancelledMessage)
            }
            return refus
        }
    }

    // MARK: - Nouveau mot de passe

    public func updatePassword(_ password: String) async throws {
        guard let (client, userId) = await coffre.courant() else {
            throw JoleneError(.unauthorized, ReinitialisationTextes.lienInvalideDetail)
        }
        do {
            let relu = try await client.update(user: UserAttributes(password: password))
            guard relu.id == userId else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
            await coffre.marquerEnregistre()
        } catch let erreur as JoleneError {
            throw erreur
        } catch let erreur as AuthError {
            throw Self.refusMiseAJour(erreur)
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: MotDePasse.Textes.erreurGenerique)
        }
    }

    public func signOutAfterRecovery() async throws {
        guard let (client, enregistre) = await coffre.fermer() else { return }
        // Le client est déjà retiré du coffre : même en cas d'échec réseau, aucune session de récupération ne reste.
        try await client.signOut(scope: enregistre ? .global : .local)
    }

    // MARK: - Traductions

    /// Refus GoTrue d'une demande de lien : texte web d'`extraireMessageErreur`, jamais le message anglais.
    static func refus(_ erreur: AuthError) -> JoleneError {
        switch erreur {
        case let .api(message, code, _, reponse):
            if SupabaseMotDePasseGateway.issueInconnue(reponse.statusCode) {
                return SupabaseErrorMapping.map(erreur, fallback: MotDePasse.Textes.erreurGenerique)
            }
            return JoleneError(.invalidCredentials, MotDePasse.messageRefus(code: code.rawValue, message: message))
        case let .weakPassword(message, _):
            return JoleneError(.invalidCredentials, MotDePasse.messageRefus(code: ErrorCode.weakPassword.rawValue, message: message))
        default:
            return SupabaseErrorMapping.map(erreur, fallback: MotDePasse.Textes.erreurGenerique)
        }
    }

    /// Refus GoTrue de la mise à jour : session de récupération refusée (401/403, absente) → lien expiré ; 5xx/408 →
    /// issue inconnue ; sinon texte web.
    static func refusMiseAJour(_ erreur: AuthError) -> JoleneError {
        switch erreur {
        case .sessionMissing, .refreshDiscarded:
            return JoleneError(.unauthorized, ReinitialisationTextes.lienInvalideDetail)
        case let .api(_, _, _, reponse):
            if SupabaseErrorMapping.unauthorizedStatuses.contains(reponse.statusCode) {
                return JoleneError(.unauthorized, ReinitialisationTextes.lienInvalideDetail)
            }
            if SupabaseMotDePasseGateway.issueInconnue(reponse.statusCode) {
                return JoleneError(.unknown, MotDePasse.Textes.confirmationIndisponible)
            }
            return refus(erreur)
        default:
            return refus(erreur)
        }
    }

    // MARK: - Coffre de la session isolée

    /// Client isolé du flux en cours (au plus un), issue de l'enregistrement du mot de passe et jeton de la tentative
    /// en cours. Chaque lien reçu ouvre une tentative ; une fermeture ou une tentative plus récente invalide les
    /// précédentes, qui ne peuvent plus rien ouvrir.
    actor Coffre {
        private var client: AuthClient?
        private var userId: UUID?
        private var enregistre = false
        private var tentative: UInt64 = 0

        /// Nouvelle tentative : le client ouvert (s'il y en a un) est retiré et rendu pour être révoqué, et toute
        /// tentative en vol est invalidée.
        func nouvelleTentative() -> (UInt64, (AuthClient, Bool)?) {
            let precedent = fermer()
            return (tentative, precedent)
        }

        /// Ouvre la session de la tentative `jeton` ; `false` si elle a été abandonnée entre-temps (le client n'est
        /// pas retenu, à révoquer par l'appelant). Un client encore présent n'est jamais écrasé sans être révoqué :
        /// il ne peut l'être que par une tentative plus récente, qui l'a déjà retiré.
        func ouvrir(_ client: AuthClient, userId: UUID, tentative jeton: UInt64) -> Bool {
            guard jeton == tentative, self.client == nil else { return false }
            self.client = client
            self.userId = userId
            enregistre = false
            return true
        }

        func courant() -> (AuthClient, UUID)? {
            guard let client, let userId else { return nil }
            return (client, userId)
        }

        func marquerEnregistre() { enregistre = true }

        /// Retire le client isolé (nil s'il n'y en a pas) et rend s'il a enregistré un mot de passe ; invalide aussi la
        /// tentative en vol (une vérification qui aboutirait ensuite n'ouvre rien).
        func fermer() -> (AuthClient, Bool)? {
            tentative &+= 1
            defer { client = nil; userId = nil; enregistre = false }
            guard let client else { return nil }
            return (client, enregistre)
        }

        var estOuvert: Bool { client != nil }
    }

    /// Vrai si une session de récupération isolée est ouverte (tests).
    var sessionIsoleeOuverte: Bool {
        get async { await coffre.estOuvert }
    }
}

/// Stockage de session en mémoire du client isolé : jamais le Keychain, rien ne survit au processus.
final class StockageMemoire: AuthLocalStorage, @unchecked Sendable {
    private let verrou = NSLock()
    private var valeurs: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        verrou.lock(); defer { verrou.unlock() }
        valeurs[key] = value
    }

    func retrieve(key: String) throws -> Data? {
        verrou.lock(); defer { verrou.unlock() }
        return valeurs[key]
    }

    func remove(key: String) throws {
        verrou.lock(); defer { verrou.unlock() }
        valeurs[key] = nil
    }
}
