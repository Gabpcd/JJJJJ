import UIKit
import UserNotifications
import JoleneCore

/// Délégué `UNUserNotificationCenter` (lot 3, T5 ; blueprint §2.5), posé par `PushAppDelegate` au lancement
/// (`didFinishLaunching`, avant la remise d'un tap à froid) :
/// - premier plan (`willPresent`) : bannière, son et centre de notifications du système (`[.banner, .sound,
///   .list]`, aucune pastille : le serveur n'en envoie pas, §1.2), puis `BoiteTapsPush.signalerPremierPlan()`
///   (le centre de notifications visible se relit) ;
/// - tap (`didReceive`, action par défaut seulement) : paires textuelles du payload (`PushTapIntent`) remises
///   à la boîte, que l'espace prêt relit (`MainTabView`) ; l'action « effacer » n'ouvre rien.
///
/// Les gestionnaires de fin sont appelés tout de suite (rien n'est attendu du réseau) ; la boîte est mise à jour
/// sur le main actor. Aucune donnée du payload n'est journalisée (PRINCIPES §7).
@MainActor
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Instance unique : le délégué système et `AppContainer` partagent la même boîte.
    static let shared = NotificationCenterDelegate()

    let boite = BoiteTapsPush()

    private override init() { super.init() }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
        Task { @MainActor in self.boite.signalerPremierPlan() }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let estUnTap = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        let tap = PushTapIntent(userInfo: response.notification.request.content.userInfo)
        completionHandler()
        guard estUnTap else { return }
        Task { @MainActor in self.boite.recevoir(tap) }
    }
}
