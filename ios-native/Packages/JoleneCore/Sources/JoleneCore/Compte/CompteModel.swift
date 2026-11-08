import Foundation
import Combine

/// Modèle de l'écran de suppression de compte (lot 1, T8 ; Apple 5.1.1), port de
/// `SectionConfidentialite.tsx` `handleSupprimerCompte` (l.81-105).
///
/// Règles :
/// - un seul appel par action de l'utilisateur, borné à `SessionController.resolutionTimeout`
///   (décision 14), jamais renvoyé automatiquement ; un second appui pendant l'appel est ignoré ;
/// - succès = issue `.deleted` du port (HTTP 200 `{success:true}`) ; aucune relecture n'est possible
///   (JWT révoqué, utilisateur Auth supprimé) ;
/// - après un succès, ou un refus qui laisse le compte banni ou anonymisé
///   (`CompteSuppression.codesDeconnexionForcee`) : l'écran de fin est signalé (`AvisFinDeCompte`),
///   puis l'identité est retirée par `SessionController.signOutLocally()` AVANT la purge locale du SDK,
///   si bien que son événement `.signedOut` est ignoré : jamais « Votre session a expiré » ; après une
///   suppression confirmée seulement, les préférences locales du compte sont purgées (`LOT1_PLAN.md` l.252) ;
/// - tout autre refus : message serveur verbatim, la session reste ouverte, nouvelle tentative manuelle ;
/// - délai dépassé ou réseau coupé : `CompteSuppression.confirmationIndisponibleMessage` (le serveur a pu agir) ;
/// - epoch d'identité : aucun appel pour un epoch périmé ; une autre identité connectée pendant l'appel
///   n'est jamais déconnectée.
@MainActor
public final class CompteModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        /// Saisie possible.
        case pret
        /// Appel en cours : confirmation, saisie et retour désactivés.
        case envoi
        /// Refus ou erreur affiché ; une nouvelle tentative reste possible.
        case refuse(message: String)
        /// Compte supprimé (ou session retirée de force) : la racine de l'app prend le relais.
        case termine(FinDeCompte)
    }

    @Published public private(set) var etat: Etat = .pret
    /// Nombre de refus affichés : jeton d'annonce VoiceOver (`InlineNotice.announcementID`).
    @Published public private(set) var tentatives = 0

    private let session: SessionStore
    private let snapshot: SessionSnapshot
    private let avis: AvisFinDeCompte
    private let preferences: UserDefaults

    /// - Parameter preferences: domaine des préférences locales par compte, purgé après une
    ///   suppression confirmée (`CompteSuppression.purgerPreferencesLocales`).
    public init(session: SessionStore, snapshot: SessionSnapshot, avis: AvisFinDeCompte,
                preferences: UserDefaults = .standard) {
        self.session = session
        self.snapshot = snapshot
        self.avis = avis
        self.preferences = preferences
    }

    /// Vrai pendant l'appel et après la fin : plus aucune action, ni retour, ni nouvelle saisie.
    public var enCours: Bool {
        switch etat {
        case .envoi, .termine: return true
        case .pret, .refuse: return false
        }
    }

    public var messageRefus: String? {
        if case let .refuse(message) = etat { return message }
        return nil
    }

    /// Envoie la demande de suppression. La phrase « SUPPRIMER » est exigée par l'écran
    /// (`ConfirmationSheet.Configuration.requiredPhrase`, égalité stricte) avant cet appel.
    public func supprimer() async {
        guard !enCours else { return }
        etat = .envoi
        let controller = session.controller
        guard let gateways = await controller.gateways(for: snapshot.epoch) else {
            etat = .pret
            return
        }
        let port = gateways.compte
        let context = snapshot.context
        let issue: DeleteAccountOutcome
        do {
            issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.deleteAccount(context: context)
            }
        } catch {
            guard await controller.epoch == snapshot.epoch else {
                etat = .pret
                return
            }
            refuser(Self.message(pour: error))
            return
        }
        if let fin = CompteSuppression.fin(pour: issue) {
            await terminer(fin)
        } else if case let .refused(_, message) = issue {
            guard await controller.epoch == snapshot.epoch else {
                etat = .pret
                return
            }
            refuser(message)
        }
    }

    // MARK: - Interne

    private func refuser(_ message: String) {
        tentatives += 1
        etat = .refuse(message: message)
    }

    /// Fin de session après une suppression : avis d'abord (la racine l'affichera), puis identité
    /// retirée et session locale purgée. Si l'identité a déjà été retirée pendant l'appel (événement
    /// `.signedOut` du SDK, jetons révoqués), l'écran de fin remplace « session expirée » ; si une autre
    /// identité est active, rien n'est touché.
    private func terminer(_ fin: FinDeCompte) async {
        etat = .termine(fin)
        let controller = session.controller
        let memeIdentite = await controller.epoch == snapshot.epoch
        let etatSession = await controller.state
        var sansIdentite = false
        if case .signedOut = etatSession { sansIdentite = true }
        guard memeIdentite || sansIdentite else { return }
        avis.signaler(fin)
        // Préférences du compte : purgées seulement quand la suppression est confirmée (une déconnexion
        // forcée sans suppression Auth confirmée les conserve).
        if fin == .supprime {
            CompteSuppression.purgerPreferencesLocales(userId: snapshot.user.id, defaults: preferences)
        }
        // Lot 3, T4 : `SessionStore.signOutLocally` ajoute la désinscription push locale (sans RPC)
        // avant `controller.signOutLocally()` puis relit l'état, comme ici au lot 1.
        await session.signOutLocally()
    }

    static func message(pour error: Error) -> String {
        if let jolene = error as? JoleneError {
            switch jolene.kind {
            case .network, .cancelled: return CompteSuppression.confirmationIndisponibleMessage
            default: return jolene.message
            }
        }
        return CompteSuppression.confirmationIndisponibleMessage
    }
}
