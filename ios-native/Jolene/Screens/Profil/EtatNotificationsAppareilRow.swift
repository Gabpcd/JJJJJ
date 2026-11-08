import SwiftUI
import UIKit
import JoleneCore
import JoleneDesign

/// Carte « Autorisation du téléphone » (lot 3, T4 ; hôte définitif depuis T6 : `PreferencesScreen`, une seule
/// surface — `REVUES_LOT3.md`, section L3-T4) : état système des notifications de l'appareil et de son
/// enregistrement, comme le bloc `native-push-permission-status` du web (`PageParametresNotifications.tsx`
/// l.140-186 et l.326-368) — textes verbatim (`EtatNotificationsAppareil`, HARD STOP n°4).
///
/// Vue sans état : l'hôte possède `EtatNotificationsAppareilModel` (canal push lu de son brouillon), appelle
/// `verifier()` à l'affichage et au retour au premier plan, et n'affiche la carte que si `model.message` existe.
/// Action (`model.action`) :
/// - « Activer sur cet appareil » (l.365) : `model.activer()`, au tap seulement (D1) ; bouton en attente et
///   second tap ignoré pendant la demande ;
/// - « Ouvrir les réglages » (refusé seulement) : page Notifications de l'app dans Réglages
///   (`UIApplication.openNotificationSettingsURLString`, iOS 16) ;
/// - aucune : aucun bouton.
///
/// Identifiants (PRINCIPES §6, `PermissionCard`) : `push-etat-appareil` (+ `-title`, `-message`), boutons
/// `push-activer-appareil` et `push-ouvrir-reglages`.
struct EtatNotificationsAppareilRow: View {
    @ObservedObject var model: EtatNotificationsAppareilModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let message = model.message {
            PermissionCard(contenu(message), isLoading: model.activationEnCours, onPrimary: actionPrincipale)
        }
    }

    private func contenu(_ message: String) -> PermissionCard.Content {
        let activation = model.action == .activer
        return PermissionCard.Content(
            title: EtatNotificationsAppareil.titre,
            message: message,
            primaryTitle: activation ? EtatNotificationsAppareil.activerSurAppareil : EtatNotificationsAppareil.ouvrirReglages,
            systemImage: model.estPositif ? "checkmark.circle" : "exclamationmark.triangle",
            identifier: "push-etat-appareil",
            primaryIdentifier: activation ? "push-activer-appareil" : "push-ouvrir-reglages")
    }

    /// nil (aucun bouton) quand aucune action n'est utile.
    private var actionPrincipale: (() -> Void)? {
        switch model.action {
        case .activer?:
            let model = self.model
            return { Task { await model.activer() } }
        case .ouvrirReglages?:
            guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return nil }
            let openURL = self.openURL
            return { openURL(url) }
        case nil:
            return nil
        }
    }
}
