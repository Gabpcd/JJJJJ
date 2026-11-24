import Foundation
import Combine

// Récupération du mot de passe (reste de L1-T10 ; `docs/mobile-swift/LOT1_PLAN.md` §2.5, §3 T10, décision 7, option B).
// Port de la demande de lien de `src/pages/PageConnexion.tsx` (l.40-65, l.230-258, l.339-400) et de la page
// `src/pages/PageResetPassword.tsx` (l.13-227). Aucun texte juridique ; aucune règle de mot de passe propre à l'app :
// la seule règle locale est celle du web (8 unités UTF-16 au moins, confirmation identique, l.86), le serveur
// tranche le reste (refus GoTrue traduits par `MotDePasse.messageRefus`, comme `extraireMessageErreur`).

/// Textes repris mot pour mot du web.
public enum ReinitialisationTextes {
    // source: src/pages/PageConnexion.tsx:345
    public static let motDePasseOublie = "Mot de passe oublié ?"
    // source: src/pages/PageConnexion.tsx:350
    public static let emailDuCompte = "Email de votre compte"
    // source: src/pages/PageConnexion.tsx:359
    public static let emailPlaceholder = "votre@email.com"
    // source: src/pages/PageConnexion.tsx:234
    public static let emailInvalide = "Saisissez une adresse email valide."
    // source: src/pages/PageConnexion.tsx:251
    public static let demandeEnvoyee = "Demande envoyée. Vérifiez votre boîte mail et les courriers indésirables."
    // source: src/pages/PageConnexion.tsx:367-368 (même texte que le compte existe ou non)
    public static func lienEnvoye(a email: String) -> String {
        "Si un compte existe pour \(email), le lien vient d’être envoyé. Vérifiez aussi les courriers indésirables."
    }
    // source: src/pages/PageConnexion.tsx:380
    public static let envoi = "Envoi…"
    // source: src/pages/PageConnexion.tsx:382
    public static func renvoyerDans(_ secondes: Int) -> String { "Renvoyer dans \(secondes) s" }
    // source: src/pages/PageConnexion.tsx:384
    public static let renvoyerLeLien = "Renvoyer le lien"
    // source: src/pages/PageConnexion.tsx:385
    public static let envoyerLeLien = "Envoyer le lien"
    // source: src/pages/PageConnexion.tsx:397 et src/pages/PageResetPassword.tsx:146
    public static let retourConnexion = "Retour à la connexion"

    // source: src/pages/PageResetPassword.tsx:126
    public static let titre = "Réinitialiser le mot de passe"
    // source: src/pages/PageResetPassword.tsx:132
    public static let verification = "Vérification du lien…"
    // source: src/pages/PageResetPassword.tsx:141
    public static let lienInvalide = "Lien invalide ou expiré"
    // source: src/pages/PageResetPassword.tsx:143
    public static let lienInvalideDetail =
        "Le lien de réinitialisation n'est plus valable. Demandez un nouveau lien depuis la page de connexion."
    // source: src/pages/PageResetPassword.tsx:164
    public static let consigne = "Choisissez un nouveau mot de passe (minimum 8 caractères)."
    // source: src/pages/PageResetPassword.tsx:168
    public static let nouveau = "Nouveau mot de passe *"
    // source: src/pages/PageResetPassword.tsx:176
    public static let nouveauPlaceholder = "Minimum 8 caractères"
    // source: src/pages/PageResetPassword.tsx:193
    public static let confirmation = "Confirmer le mot de passe *"
    // source: src/pages/PageResetPassword.tsx:207
    public static let nonCorrespondance = "Les mots de passe ne correspondent pas"
    // source: src/pages/PageResetPassword.tsx:218
    public static let miseAJour = "Mise à jour…"
    // source: src/pages/PageResetPassword.tsx:218
    public static let soumettre = "Modifier mon mot de passe"
    // source: src/pages/PageResetPassword.tsx:156
    public static let modifie = "Mot de passe modifié"
    // source: src/pages/PageResetPassword.tsx:108
    public static let modifieAvecSucces = "Mot de passe modifié avec succès."
    // source: src/pages/PageResetPassword.tsx:103
    public static let sessionNonFermee =
        "Le mot de passe est modifié, mais la session n’a pas pu être fermée. Fermez l’application puis reconnectez-vous."
}

/// Règles locales du web, sans ajout.
public enum ReinitialisationRules {
    /// `EMAIL_REGEX` de `PageConnexion.tsx` l.410 (drapeau `i`).
    private static let motifEmail = #"^[^\s@]{1,64}@[^\s@]{1,255}\.[a-z]{2,}$"#
    /// Délai avant un nouvel envoi (`setResetDisponibleDans(60)`, l.248).
    public static let delaiRenvoi = 60
    /// `minLength={8}` et `motDePasse.length >= 8` (l.86, l.179) : unités UTF-16, comme JavaScript.
    public static let longueurMinimale = 8

    /// `email.trim().toLowerCase()` (l.231).
    public static func emailNormalise(_ email: String) -> String { InscriptionRules.emailNormalise(email) }

    /// `EMAIL_REGEX.test(emailNormalise)` (l.233).
    public static func emailValide(_ email: String) -> Bool {
        emailNormalise(email).range(of: motifEmail, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// `motDePasse.length >= 8 && motDePasse === confirmMdp` (l.86).
    public static func valide(nouveau: String, confirmation: String) -> Bool {
        nouveau.utf16.count >= longueurMinimale && nouveau.utf16.elementsEqual(confirmation.utf16)
    }

    /// `confirmMdp && confirmMdp !== motDePasse` (l.206) : message de non-correspondance affiché.
    public static func afficherNonCorrespondance(nouveau: String, confirmation: String) -> Bool {
        !confirmation.utf16.isEmpty && !nouveau.utf16.elementsEqual(confirmation.utf16)
    }
}

/// Fournisseur du port de récupération (relu une seule fois par modèle).
public typealias FournisseurRecovery = @Sendable () async -> RecoveryPort?

// MARK: - Demande de lien (« Mot de passe oublié ? »)

/// Demande d'un lien de réinitialisation depuis l'écran de connexion (`demanderReinitialisation`, l.230-258).
/// Non-révélation : le port ne rend rien de plus qu'un succès ; l'écran affiche le même texte que le compte existe ou
/// non (`lienEnvoye(a:)`). Délai de 60 s entre deux envois (`seconde()` appelée chaque seconde par la vue).
@MainActor
public final class DemandeReinitialisationModel: ObservableObject {
    /// Saisie ; toute modification efface la confirmation affichée (l.355-357).
    @Published public var email: String {
        didSet { if email != oldValue { envoyeA = nil } }
    }
    @Published public private(set) var envoyeA: String?
    @Published public private(set) var disponibleDans = 0
    @Published public private(set) var envoiEnCours = false
    @Published public private(set) var erreur: String?
    @Published public private(set) var annonce: String?

    private let port: FournisseurRecovery

    public init(email: String, port: @escaping FournisseurRecovery) {
        self.email = email
        self.port = port
    }

    /// `disabled={resetSubmitting || !email.trim() || resetDisponibleDans > 0}` (l.374).
    public var peutEnvoyer: Bool {
        !envoiEnCours && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && disponibleDans <= 0
    }

    /// Libellé du bouton (l.379-385).
    public var libelleBouton: String {
        if envoiEnCours { return ReinitialisationTextes.envoi }
        if disponibleDans > 0 { return ReinitialisationTextes.renvoyerDans(disponibleDans) }
        return envoyeA == nil ? ReinitialisationTextes.envoyerLeLien : ReinitialisationTextes.renvoyerLeLien
    }

    public var messageEnvoye: String? { envoyeA.map(ReinitialisationTextes.lienEnvoye(a:)) }

    public func envoyer() async {
        guard peutEnvoyer else { return }
        erreur = nil
        annonce = nil
        let normalise = ReinitialisationRules.emailNormalise(email)
        guard ReinitialisationRules.emailValide(normalise) else {
            erreur = ReinitialisationTextes.emailInvalide
            return
        }
        envoiEnCours = true
        defer { envoiEnCours = false }
        guard let recovery = await port() else {
            erreur = MotDePasse.Textes.erreurGenerique
            return
        }
        do {
            try await recovery.requestReset(email: normalise)
            email = normalise
            envoyeA = normalise
            disponibleDans = ReinitialisationRules.delaiRenvoi
            annonce = ReinitialisationTextes.demandeEnvoyee
        } catch {
            if error is CancellationError || (error as? JoleneError)?.kind == .cancelled { return }
            erreur = (error as? JoleneError)?.message ?? MotDePasse.Textes.erreurGenerique
        }
    }

    /// Une seconde écoulée (minuteur de la vue, l.58-65).
    public func seconde() {
        if disponibleDans > 0 { disponibleDans -= 1 }
    }
}

// MARK: - Lien `/reset-password` et nouveau mot de passe

/// Écran du lien de réinitialisation (`PageResetPassword.tsx`). **Quarantaine** : la session de récupération ouverte
/// par le port ne donne accès à aucun écran ; ce modèle ne connaît que le port de récupération, jamais
/// `SessionController`. Elle est fermée (`signOutAfterRecovery`) sur abandon, sur refus de session et après
/// l'enregistrement du mot de passe ; seul l'état `.succes` (mot de passe enregistré, relu par le serveur, session
/// fermée) mène à la connexion. Sans identifiants (lien sans preuve recovery), aucun appel : refus (l.73-76).
@MainActor
public final class ReinitialisationModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case verification
        case lienInvalide
        case formulaire
        case enregistrement
        /// Mot de passe enregistré et session de récupération fermée.
        case succes
        /// Mot de passe enregistré, fermeture de la session non confirmée par le serveur (l.99-105).
        case succesSessionNonFermee
    }

    @Published public private(set) var etat: Etat = .verification
    @Published public private(set) var erreur: String?

    private let fournisseur: FournisseurRecovery
    private let credentials: AuthCallbackCredentials?
    private let delai: TimeInterval
    private var port: RecoveryPort?
    private var tente = false
    private var ferme = false

    public init(port: @escaping FournisseurRecovery, credentials: AuthCallbackCredentials?, delai: TimeInterval = 30) {
        self.fournisseur = port
        self.credentials = credentials
        self.delai = delai
    }

    /// Vrai tant qu'aucune issue ne mène à la connexion : la vue ne se ferme que par `abandonner()` ou après succès.
    public var estTermine: Bool { etat == .succes || etat == .succesSessionNonFermee }

    /// Vérifie le lien, une seule fois.
    public func ouvrir() async {
        guard !tente else { return }
        tente = true
        guard let credentials else {
            etat = .lienInvalide
            return
        }
        guard let port = await fournisseur() else {
            etat = .lienInvalide
            return
        }
        self.port = port
        do {
            let issue = try await bounded(timeout: delai) { try await port.openRecoverySession(credentials) }
            switch issue {
            case .sessionOuverte where ferme:
                // Abandon pendant la vérification : la session qui vient de s'ouvrir est fermée aussitôt.
                try? await port.signOutAfterRecovery()
                etat = .lienInvalide
            case .sessionOuverte:
                etat = .formulaire
            case .lienRefuse:
                await fermer()
                etat = .lienInvalide
            }
        } catch {
            // Délai dépassé, annulation ou transport : rien ne doit rester ouvert, même si l'abandon a déjà fermé.
            ferme = true
            try? await port.signOutAfterRecovery()
            etat = .lienInvalide
        }
    }

    public func peutEnregistrer(nouveau: String, confirmation: String) -> Bool {
        etat == .formulaire && ReinitialisationRules.valide(nouveau: nouveau, confirmation: confirmation)
    }

    /// `handleSubmit` (l.88-113) : mot de passe enregistré, puis session de récupération fermée.
    public func enregistrer(nouveau: String, confirmation: String) async {
        guard peutEnregistrer(nouveau: nouveau, confirmation: confirmation), let port, !ferme else { return }
        erreur = nil
        etat = .enregistrement
        do {
            try await port.updatePassword(nouveau)
        } catch {
            let refus = error as? JoleneError
            if refus?.kind == .unauthorized {
                await fermer()
                etat = .lienInvalide
                return
            }
            etat = .formulaire
            if error is CancellationError || refus?.kind == .cancelled { return }
            erreur = refus?.message ?? MotDePasse.Textes.erreurGenerique
            return
        }
        ferme = true
        do {
            try await port.signOutAfterRecovery()
            etat = .succes
        } catch {
            etat = .succesSessionNonFermee
        }
    }

    /// Abandon (fermeture de l'écran, retour à la connexion, disparition) : la session de récupération est fermée.
    public func abandonner() async {
        await fermer()
    }

    private func fermer() async {
        guard !ferme else { return }
        ferme = true
        try? await port?.signOutAfterRecovery()
    }
}
