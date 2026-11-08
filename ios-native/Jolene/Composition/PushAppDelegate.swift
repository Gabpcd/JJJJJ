import UIKit
import UserNotifications

/// Délégué d'application (lot 3, T4) monté par `@UIApplicationDelegateAdaptor` dans `JoleneApp` : il remet la
/// réponse d'APNs à `PushRegistrar`. Lot 3, T5 : il pose aussi le délégué `UNUserNotificationCenter` (taps,
/// premier plan) au lancement, avant que le système ne remette le tap qui a lancé l'app ; poser le délégué ne
/// demande aucune autorisation (D1).
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistrar.shared.recu(token: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushRegistrar.shared.echec(error)
    }
}
