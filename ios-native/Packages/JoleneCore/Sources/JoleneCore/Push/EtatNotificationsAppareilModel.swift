import Foundation
import Combine

/// Modèle de la carte « Autorisation du téléphone » (lot 3, T4 ; activation par T6), port des effets de
/// `src/pages/PageParametresNotifications.tsx` l.142-186 : l'autorisation système est lue, puis, si elle
/// permet l'enregistrement, `PushCoordinator.surActive` (idempotent : rejoint un enregistrement en vol,
/// n'écrit rien si le token est déjà enregistré pour cet epoch, retente un enregistrement en échec) et la
/// confirmation est relue. Règles d'affichage et d'action : `EtatNotificationsAppareil`.
///
/// - `verifier()` ne demande **jamais** l'autorisation (D1). L'hôte (écran des préférences de T6) l'appelle à
///   l'affichage et à chaque retour au premier plan (retour de Réglages compris) ; l'état déjà connu reste
///   affiché pendant une nouvelle vérification (pas de clignotement).
/// - `activer()` (T6, « Activer sur cet appareil », web `activerPushSurAppareil` l.167-186) : seulement au tap
///   de l'utilisateur ; demande l'autorisation (feuille système si elle n'a jamais été demandée, réponse
///   immédiate sinon), puis vérifie et enregistre comme `verifier()`. Une demande en échec affiche l'état
///   indisponible (l.180-182) jusqu'à la lecture suivante. Un second tap pendant l'activation est ignoré.
///   Les toasts du web (l.176, l.178, l.182) ne sont pas portés : la carte affiche le même état (l.346, l.350,
///   l.351), relu et non supposé.
/// Sans coordinateur ni port d'autorisation (environnement refusé), aucune carte et aucune demande.
@MainActor
public final class EtatNotificationsAppareilModel: ObservableObject {
    /// Autorisation système lue (nil avant la première lecture).
    @Published public private(set) var autorisation: AutorisationPush?
    /// Enregistrement confirmé pour l'epoch de `snapshot` (nil tant qu'il n'est pas vérifié).
    @Published public private(set) var enregistrementConfirme: Bool?
    /// Canal push de Jolene, connu des préférences (T6 : brouillon `global.canal_push`) ; nil s'il est inconnu.
    @Published public var canalPush: Bool?
    /// Dernière activation en échec (web `unavailable`) ; levé par la lecture système suivante.
    @Published public private(set) var indisponible = false
    /// Activation en cours (bouton en attente, second tap ignoré).
    @Published public private(set) var activationEnCours = false

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
                                          canalPush: canalPush, indisponible: indisponible)
    }

    /// Action proposée sous le message, nil : aucun bouton.
    public var action: EtatNotificationsAppareil.Action? {
        EtatNotificationsAppareil.action(autorisation: autorisation, enregistrementConfirme: enregistrementConfirme,
                                         canalPush: canalPush, indisponible: indisponible)
    }

    /// Ton positif de la carte (autorisé et enregistré).
    public var estPositif: Bool {
        EtatNotificationsAppareil.estPositif(autorisation: autorisation, enregistrementConfirme: enregistrementConfirme,
                                             indisponible: indisponible)
    }

    /// Lit l'autorisation, puis vérifie l'enregistrement si elle le permet.
    public func verifier() async {
        guard let push, let permission else { return }
        let etat = await permission.etat()
        autorisation = etat
        indisponible = false
        guard etat.permetEnregistrement else { return }
        await push.surActive(snapshot)
        enregistrementConfirme = await push.enregistrementConfirme(epoch: snapshot.epoch)
    }

    /// « Activer sur cet appareil » : demande au tap, puis lecture et enregistrement (`verifier`).
    public func activer() async {
        guard !activationEnCours, let permission, push != nil else { return }
        activationEnCours = true
        defer { activationEnCours = false }
        do {
            _ = try await permission.demander()
        } catch {
            indisponible = true
            return
        }
        await verifier()
    }
}
