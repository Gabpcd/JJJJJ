import UIKit

/// Délégué d'application (lot 3, T4) monté par `@UIApplicationDelegateAdaptor` dans `JoleneApp` : il ne
/// fait que remettre la réponse d'APNs à `PushRegistrar`. Le délégué `UNUserNotificationCenter` (taps,
/// premier plan) est posé par la tranche T5.
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistrar.shared.recu(token: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushRegistrar.shared.echec(error)
    }
}
