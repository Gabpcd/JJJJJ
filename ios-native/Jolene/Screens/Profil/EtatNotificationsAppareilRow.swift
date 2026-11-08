import SwiftUI
import UIKit
import JoleneCore
import JoleneDesign

/// Carte « Autorisation du téléphone » (lot 3, T4 ; hôte définitif : préférences de T6, une seule surface —
/// `REVUES_LOT3.md`, section L3-T4) : état système des notifications de l'appareil et de son
/// enregistrement, comme le bloc `native-push-permission-status` du web (`PageParametresNotifications.tsx`
/// l.140-160 et l.326-354) — textes verbatim (`EtatNotificationsAppareil`, HARD STOP n°4).
///
/// Vue sans état : l'hôte possède `EtatNotificationsAppareilModel`, appelle `verifier()` à l'affichage et
/// au retour au premier plan, et n'affiche la carte que si `model.message` existe. La carte ne demande
/// **jamais** l'autorisation (D1) : « Ouvrir les réglages » (seulement si refusé, ou autorisé sans
/// enregistrement confirmé) ouvre la page Notifications de l'app dans Réglages
/// (`UIApplication.openNotificationSettingsURLString`, iOS 16).
///
/// Identifiants (PRINCIPES §6, `PermissionCard`) : `push-etat-appareil` (+ `-title`, `-message`),
/// bouton `push-ouvrir-reglages`.
struct EtatNotificationsAppareilRow: View {
    @ObservedObject var model: EtatNotificationsAppareilModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let message = model.message {
            PermissionCard(contenu(message), onPrimary: actionReglages)
        }
    }

    private func contenu(_ message: String) -> PermissionCard.Content {
        PermissionCard.Content(
            title: EtatNotificationsAppareil.titre,
            message: message,
            primaryTitle: EtatNotificationsAppareil.ouvrirReglages,
            systemImage: model.estPositif ? "checkmark.circle" : "exclamationmark.triangle",
            identifier: "push-etat-appareil",
            primaryIdentifier: "push-ouvrir-reglages")
    }

    /// nil (aucun bouton) quand aucun réglage système n'est utile.
    private var actionReglages: (() -> Void)? {
        guard model.proposeReglages,
              let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return nil }
        let openURL = self.openURL
        return { openURL(url) }
    }
}
