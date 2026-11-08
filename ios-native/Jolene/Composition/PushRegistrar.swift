import UIKit
import UserNotifications
import JoleneCore

/// `PushRegistrarPort` réel (lot 3, T4 ; blueprint §2.1) : `UIApplication.registerForRemoteNotifications()`,
/// réponse remise par `PushAppDelegate` (`didRegisterForRemoteNotificationsWithDeviceToken`,
/// `didFailToRegisterForRemoteNotificationsWithError`).
///
/// Une continuation par appel, reprise **une seule fois** : par le token, par l'échec, par la
/// désinscription ou par l'annulation de l'appelant. Le délai de 15 s du web (`pushNative.ts` l.178-191)
/// est posé par `PushCoordinator` (`delaiToken`, via `bounded`), dont l'annulation reprend ici la
/// continuation en attente : aucune attente ne survit au délai. Instance unique (`shared`) : le délégué
/// d'application et `AppContainer` partagent la même file d'attente.
@MainActor
final class PushRegistrar: PushRegistrarPort {
    static let shared = PushRegistrar()

    private var attentes: [UUID: CheckedContinuation<Data, Error>] = [:]

    private init() {}

    func enregistrer() async throws -> Data {
        let identifiant = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                attentes[identifiant] = continuation
                UIApplication.shared.registerForRemoteNotifications()
            }
        } onCancel: {
            Task { @MainActor in PushRegistrar.shared.abandonner(identifiant) }
        }
    }

    /// `unregisterForRemoteNotifications()` (web `PushNotifications.unregister()`, `pushDeviceToken.ts`
    /// l.111-114) ; toute attente encore ouverte est close.
    func desinscrire() async {
        UIApplication.shared.unregisterForRemoteNotifications()
        terminer(.failure(CancellationError()))
    }

    /// Token APNs remis par le délégué d'application.
    func recu(token: Data) {
        terminer(.success(token))
    }

    /// Échec d'enregistrement remis par le délégué (entitlement `aps-environment` absent, simulateur…).
    func echec(_ erreur: Error) {
        terminer(.failure(erreur))
    }

    private func abandonner(_ identifiant: UUID) {
        attentes.removeValue(forKey: identifiant)?.resume(throwing: CancellationError())
    }

    private func terminer(_ resultat: Result<Data, Error>) {
        let enAttente = attentes
        attentes = [:]
        for continuation in enAttente.values {
            continuation.resume(with: resultat)
        }
    }
}

/// `PushPermissionPort` réel (lot 3, T4) : `UNUserNotificationCenter`. `etat()` ne demande rien ;
/// `demander()` n'est appelé qu'au tap de l'utilisateur (pré-prompt T5, préférences T6 ; D1), avec les
/// options du plugin Capacitor du web (alerte, son, pastille).
struct SystemePushPermission: PushPermissionPort {
    func etat() async -> AutorisationPush {
        let reglages = await UNUserNotificationCenter.current().notificationSettings()
        return Self.autorisation(reglages.authorizationStatus)
    }

    func demander() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// `provisional` (et `ephemeral`, App Clips) autorisent la remise : enregistrement permis.
    static func autorisation(_ statut: UNAuthorizationStatus) -> AutorisationPush {
        switch statut {
        case .notDetermined: return .nonDemandee
        case .denied: return .refusee
        case .authorized: return .accordee
        case .provisional, .ephemeral: return .provisoire
        @unknown default: return .nonDemandee
        }
    }
}
