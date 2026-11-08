import SwiftUI
import UIKit
import JoleneCore
import JoleneDesign

/// Carte « Autorisation du téléphone » (lot 3, T4 ; reprise par les préférences de T6) : état système
/// des notifications de l'appareil et de son enregistrement, comme le bloc `native-push-permission-status`
/// du web (`PageParametresNotifications.tsx` l.140-160 et l.326-354) — textes verbatim
/// (`EtatNotificationsAppareil`, HARD STOP n°4).
///
/// À l'affichage et à chaque retour au premier plan (retour de Réglages compris) : autorisation relue ;
/// si elle permet l'enregistrement, `PushCoordinator.surActive` (idempotent : rejoint un enregistrement
/// en vol, n'écrit rien si le token est déjà enregistré pour cet epoch) puis confirmation lue, comme le
/// web l.147-150. La carte ne demande **jamais** l'autorisation (D1) : « Ouvrir les réglages » ouvre la
/// page Notifications de l'app dans Réglages (`UIApplication.openNotificationSettingsURLString`, iOS 16).
///
/// Identifiants (PRINCIPES §6, `PermissionCard`) : `push-etat-appareil` (+ `-title`, `-message`),
/// bouton `push-ouvrir-reglages`.
struct EtatNotificationsAppareilRow: View {
    /// Libellé du bouton nommé par le blueprint (§1.1 « Ouvrir les réglages », §3 T4) ; action native
    /// sans équivalent web (le web n'ouvre pas les réglages système), non juridique.
    static let ouvrirReglages = "Ouvrir les réglages"

    let push: PushCoordinator
    let permission: PushPermissionPort
    let snapshot: SessionSnapshot
    /// Canal push de Jolene, connu des préférences (T6) ; nil dans le hub Profil.
    var canalPush: Bool?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var autorisation: AutorisationPush?
    @State private var enregistrementConfirme = false

    var body: some View {
        PermissionCard(contenu, onPrimary: ouvrirLesReglages)
            .task { await verifier() }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                Task { await verifier() }
            }
    }

    private var contenu: PermissionCard.Content {
        let positif = EtatNotificationsAppareil.estPositif(autorisation: autorisation,
                                                           enregistrementConfirme: enregistrementConfirme)
        return PermissionCard.Content(
            title: EtatNotificationsAppareil.titre,
            message: EtatNotificationsAppareil.message(autorisation: autorisation,
                                                       enregistrementConfirme: enregistrementConfirme,
                                                       canalPush: canalPush),
            primaryTitle: Self.ouvrirReglages,
            systemImage: positif ? "checkmark.circle" : "exclamationmark.triangle",
            identifier: "push-etat-appareil",
            primaryIdentifier: "push-ouvrir-reglages")
    }

    private func verifier() async {
        let etat = await permission.etat()
        if etat.permetEnregistrement {
            await push.surActive(snapshot)
        }
        let confirme = await push.enregistrementConfirme(epoch: snapshot.epoch)
        autorisation = etat
        enregistrementConfirme = confirme
    }

    private func ouvrirLesReglages() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        openURL(url)
    }
}
