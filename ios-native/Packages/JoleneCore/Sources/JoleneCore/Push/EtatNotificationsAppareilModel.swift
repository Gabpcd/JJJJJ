import Foundation
import Combine

/// Modèle de la carte « Autorisation du téléphone » (lot 3, T4), port de l'effet de
/// `src/pages/PageParametresNotifications.tsx` l.142-158 : l'autorisation système est lue, puis, si elle
/// permet l'enregistrement, `PushCoordinator.surActive` (idempotent : rejoint un enregistrement en vol,
/// n'écrit rien si le token est déjà enregistré pour cet epoch) et la confirmation est relue. Le modèle ne
/// demande **jamais** l'autorisation (D1). Règles d'affichage : `EtatNotificationsAppareil`.
///
/// L'hôte appelle `verifier()` à l'affichage et à chaque retour au premier plan (retour de Réglages
/// compris) ; l'état déjà connu reste affiché pendant une nouvelle vérification (pas de clignotement).
/// Sans coordinateur ni port d'autorisation (environnement refusé), aucune carte.
@MainActor
public final class EtatNotificationsAppareilModel: ObservableObject {
    /// Autorisation système lue (nil avant la première lecture).
    @Published public private(set) var autorisation: AutorisationPush?
    /// Enregistrement confirmé pour l'epoch de `snapshot` (nil tant qu'il n'est pas vérifié).
    @Published public private(set) var enregistrementConfirme: Bool?
    /// Canal push de Jolene, connu des préférences seulement (T6) ; nil dans le hub.
    @Published public var canalPush: Bool?

    private let push: PushCoordinator?
    private let permission: PushPermissionPort?
    private let snapshot: SessionSnapshot

    public init(push: PushCoordinator?, permission: PushPermissionPort?, snapshot: SessionSnapshot,
                canalPush: Bool? = nil) {
        self.push = push
        self.permission = permission
        self.snapshot = snapshot
        self.canalPush = canalPush
    }

    /// Message à afficher, nil : aucune carte.
    public var message: String? {
        EtatNotificationsAppareil.message(autorisation: autorisation, enregistrementConfirme: enregistrementConfirme,
                                          canalPush: canalPush)
    }

    /// « Ouvrir les réglages » proposé (refusé, ou autorisé sans enregistrement confirmé).
    public var proposeReglages: Bool {
        EtatNotificationsAppareil.proposeReglages(autorisation: autorisation, enregistrementConfirme: enregistrementConfirme)
    }

    /// Ton positif de la carte (autorisé et enregistré).
    public var estPositif: Bool {
        EtatNotificationsAppareil.estPositif(autorisation: autorisation, enregistrementConfirme: enregistrementConfirme)
    }

    /// Lit l'autorisation, puis vérifie l'enregistrement si elle le permet.
    public func verifier() async {
        guard let push, let permission else { return }
        let etat = await permission.etat()
        autorisation = etat
        guard etat.permetEnregistrement else { return }
        await push.surActive(snapshot)
        enregistrementConfirme = await push.enregistrementConfirme(epoch: snapshot.epoch)
    }
}
