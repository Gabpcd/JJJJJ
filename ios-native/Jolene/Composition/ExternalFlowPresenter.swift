import AuthenticationServices
import Combine
import JoleneCore
import UIKit

/// `ExternalFlowPort` réel (lot 3, T14a ; D7, correction 6) : onboarding Stripe Connect hébergé.
///
/// - iOS ≥ 17.4 : `ASWebAuthenticationSession` éphémère avec rappel `.https(host:path:)` sur la `return_url` /
///   `refresh_url` de `stripe-connect-onboard` (`https://jolene.app/soignant/stripe-connect?success|refresh=true`) :
///   le retour revient dans l'app (`.retour(url)`) ; fermeture par l'utilisateur → `.ferme`.
/// - En dessous : le renvoi web du coordinateur des liens (`SFSafariViewController`, présenté par
///   `DeepLinkCoordinator.presenter` et non à part, pour que la fin d'identité le ferme) ; la `return_url` se charge dans
///   la feuille (lien universel non garanti) ; la fermeture de la feuille (`PresentationsRacine.fermetures`) → `.ferme`.
///
/// Dans tous les cas l'issue n'est jamais un succès : l'écran relit le statut avec `force=true`. Un flux à la fois (un
/// nouveau ferme le précédent) ; une navigation par lien ou par tap le ferme (`fermer`, appelé par le coordinateur) ;
/// l'annulation de l'appelant le ferme aussi.
@MainActor
final class ExternalFlowPresenter: NSObject, ExternalFlowPort, ASWebAuthenticationPresentationContextProviding {
    private weak var coordinateur: DeepLinkCoordinator?
    private var session: ASWebAuthenticationSession?
    private var abonnement: AnyCancellable?
    private var attente: CheckedContinuation<IssueFlux, Never>?
    /// Numéro du flux courant : un rappel d'un flux précédent n'achève jamais le suivant.
    private var numero = 0

    init(coordinateur: DeepLinkCoordinator) {
        self.coordinateur = coordinateur
        super.init()
    }

    func ouvrir(url: URL, retour: RetourAttendu) async -> IssueFlux {
        fermer()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<IssueFlux, Never>) in
                attente = continuation
                demarrer(url: url, retour: retour)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.fermer() }
        }
    }

    /// Ferme le flux affiché (navigation par lien ou tap, nouveau flux) : l'attente rend `.ferme`.
    func fermer() {
        session?.cancel()
        terminer(.ferme)
    }

    private func demarrer(url: URL, retour: RetourAttendu) {
        numero += 1
        let courant = numero
        if #available(iOS 17.4, *) {
            let session = ASWebAuthenticationSession(url: url, callback: .https(host: retour.hote, path: retour.chemin)) {
                [weak self] rappel, _ in
                // Rappel d'une session annulée remis après le démarrage d'un nouveau flux : ignoré (numéro périmé).
                Task { @MainActor in
                    guard let self, self.numero == courant else { return }
                    self.terminer(rappel.map(IssueFlux.retour) ?? .ferme)
                }
            }
            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = self
            self.session = session
            if !session.start() { terminer(.ferme) }
        } else {
            guard let coordinateur else {
                terminer(.ferme)
                return
            }
            let depart = coordinateur.presentations.fermetures
            abonnement = coordinateur.$presentations
                .map(\.fermetures)
                .first { $0 > depart }
                .sink { [weak self] _ in self?.terminer(.ferme) }
            coordinateur.presenter(.safari(url))
        }
    }

    private func terminer(_ issue: IssueFlux) {
        session = nil
        abonnement = nil
        guard let attente else { return }
        self.attente = nil
        attente.resume(returning: issue)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let fenetre = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return fenetre }
            if let scene = scenes.first { return ASPresentationAnchor(windowScene: scene) }
            return ASPresentationAnchor()
        }
    }
}
