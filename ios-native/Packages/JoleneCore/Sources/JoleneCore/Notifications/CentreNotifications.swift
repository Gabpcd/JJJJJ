import Foundation
import Combine

// Centre de notifications (lot 3, T5 ; blueprint `docs/mobile-swift/LOT3_PLAN.md` §1.1, D23), port de
// `NotificationsContent` (`src/pages/PageNotifications.tsx` l.37-171) : 200 dernières notifications du
// destinataire, marquer lue au tap (relue, jamais supposée), puis ouverture du lien. Ni suppression (« Supprimer
// les lues » ne supprime rien en base, correction 9 du blueprint) ni Realtime (lot 4).

// MARK: - Décodage (ligne `notifications` sous RLS)

/// Ligne PostgREST de `notifications` (`public.sql` l.70798), colonnes lues : `id, titre, corps, type, lien, lue,
/// lue_le, cree_le`. `lue` est nullable en base (`DEFAULT false`) : null vaut « non lue », comme `!n.lue` du web.
extension NotificationJolene: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, type, titre, corps, lien, lue
        case lueLe = "lue_le"
        case creeLe = "cree_le"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  type: try c.decode(String.self, forKey: .type),
                  titre: try c.decode(String.self, forKey: .titre),
                  corps: try c.decode(String.self, forKey: .corps),
                  lien: try c.decodeIfPresent(String.self, forKey: .lien),
                  lue: try c.decodeIfPresent(Bool.self, forKey: .lue) ?? false,
                  lueLe: try c.decodeIfPresent(String.self, forKey: .lueLe),
                  creeLe: try c.decodeIfPresent(String.self, forKey: .creeLe))
    }
}

// MARK: - Textes (verbatim web, HARD STOP n°4)

public enum CentreNotificationsTextes {
    // source: src/pages/PageNotifications.tsx:124
    public static let titre = "Notifications"
    // source: src/pages/PageNotifications.tsx:140
    public static let erreurChargement = "Impossible de charger vos notifications."
    // source: src/pages/PageNotifications.tsx:142
    public static let reessayer = "Réessayer"
    // source: src/pages/PageNotifications.tsx:146
    public static let videTitre = "Tout est lu !"
    // source: src/pages/PageNotifications.tsx:146
    public static let videDescription = "Vous n'avez aucune notification."
    // source: src/pages/PageNotifications.tsx:93
    public static let marquerLueImpossible = "Impossible de marquer cette notification comme lue."
    // source: src/pages/PageNotifications.tsx:101
    public static let lienInvalide = "Le lien de cette notification n’est pas valide."
    // source: src/pages/PageNotifications.tsx:165
    public static let voir = "Voir"
    // source: src/components/PanneauNotifications.tsx:160 (texte réservé aux lecteurs d'écran)
    public static let nonLue = "Non lue"
}

// MARK: - Cible d'une destination dans l'espace prêt

/// Ce que l'espace prêt fait d'une destination de lien (ligne du centre, tap push), en attendant le
/// coordinateur de liens de L1-T10 (point de fusion consigné dans `DECISIONS_LOT3.md`) : les onglets, le détail
/// d'une mission, le centre de notifications ; un renvoi web passe par le présentateur `.safari`
/// (`PresentateurRenvoiWeb`, injecté par L1-T10) ; une route sans présentation dans l'espace n'ouvre rien.
///
/// Construite depuis une `DestinationLien` seulement (jamais la route brute : `.revenus(section: .factures)`
/// ouvrirait l'onglet natif au lieu du renvoi web assumé, D4). Une tranche qui passe sa ligne de
/// `DestinationLien.ecranNatifLivre` à `true` ajoute ici sa cible (T6 préférences, T9 profil, T14a Stripe…).
public enum CibleNotification: Equatable, Sendable {
    /// Onglet de l'espace (les cinq onglets de `MainTabView`, `EcranNatif`).
    case onglet(EcranNatif)
    /// Détail d'une mission, empilé sur l'onglet Accueil.
    case mission(id: String)
    /// Centre de notifications (`/soignant/notifications`).
    case centre
    /// Renvoi web (`.safari` ou `.etablissement`), présenté par le présentateur de renvoi web s'il est injecté.
    case web(JoleneRoute)
    /// Route sans présentation depuis un espace prêt (connexion, liens de rappel, écrans pas encore câblés).
    case aucune

    public init(_ lien: DestinationLien) {
        switch lien.destination {
        case .accueil: self = .onglet(.accueil)
        case .explorer: self = .onglet(.explorer)
        case .missions: self = .onglet(.missions)
        case .revenus: self = .onglet(.revenus)        // section choisie par l'écran Revenus (T12, T13)
        case .monCompte: self = .onglet(.profil)
        case .missionDetail(let id): self = .mission(id: id)
        case .notifications: self = .centre
        case .safari, .etablissement: self = .web(lien.destination)
        case .connexion, .resetPassword, .confirmerInscription, .inscription, .serieDetail, .profil,
             .parametresNotifications, .stripeConnect:
            // Liens de rappel et connexion : coordinateur de L1-T10. Écrans du lot 3 : leur tranche ajoute leur
            // cible en passant sa ligne de `ecranNatifLivre` (sinon `destination` est déjà un `.safari`).
            self = .aucune
        }
    }

    /// Présentable dans l'espace : un renvoi web exige le présentateur `.safari` (absent avant L1-T10, jamais
    /// `openURL` : les chemins `/soignant/*` reviendraient dans l'app par lien universel, sans effet).
    public func estPresentable(renvoiWebDisponible: Bool) -> Bool {
        switch self {
        case .onglet, .mission, .centre: return true
        case .web: return renvoiWebDisponible
        case .aucune: return false
        }
    }
}

// MARK: - Modèle

/// Modèle du centre de notifications, lu pour l'epoch de la session (`controller.gateways(for:)`), borné à
/// `SessionController.resolutionTimeout`. Règles :
/// - premier chargement et « Réessayer » : chargement puis liste ou erreur (texte web, jamais le détail technique) ;
/// - relecture silencieuse (tirer pour rafraîchir, notification reçue au premier plan) : la liste affichée reste
///   en place en cas d'échec ;
/// - une réponse d'un epoch périmé ou d'un chargement dépassé est abandonnée ; une annulation n'est jamais une erreur ;
/// - ouvrir : une notification non lue est d'abord marquée lue et **relue** (ligne rendue par le port) ; un échec
///   affiche le texte web et n'ouvre rien (l.89-97) ; puis le lien est résolu (`DestinationLien`), un lien non
///   Jolene affiche le texte web (l.98-102).
@MainActor
public final class CentreNotificationsModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case chargement
        case charge([NotificationJolene])
        case echec
    }

    /// 200 dernières (`.limit(200)`, l.58) ; lue aussi par les gateways (hors main actor).
    nonisolated public static let limite = 200

    @Published public private(set) var etat: Etat = .chargement
    /// Texte web d'une action refusée (marquer lue, lien invalide) ; nil sinon.
    @Published public private(set) var messageAction: String?
    /// Jeton de l'annonce de `messageAction` (une même erreur répétée est réannoncée).
    @Published public private(set) var numeroMessage = 0
    /// Notification en cours d'ouverture : un second tap est ignoré.
    @Published public private(set) var ouvertureEnCours: String?
    /// Horloge des gateways de la session (démo : horloge fixée), pour les dates relatives.
    public private(set) var horloge: any ClockPort = SystemClock()

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private var generation = 0

    public init(controller: SessionController, snapshot: SessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
    }

    public var notifications: [NotificationJolene] {
        if case let .charge(liste) = etat { return liste }
        return []
    }

    /// `silencieux` : la liste affichée reste en place (pas d'indicateur, pas d'erreur plein écran).
    public func charger(silencieux: Bool = false) async {
        generation += 1
        let courant = generation
        let garderListe: Bool
        if case .charge = etat { garderListe = silencieux } else { garderListe = false }
        if !garderListe { etat = .chargement }

        guard let gateways = await controller.gateways(for: snapshot.epoch), generation == courant else { return }
        horloge = gateways.clock
        let port = gateways.notifications
        let context = snapshot.context
        do {
            let liste = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.liste(context: context)
            }
            guard await controller.epoch == snapshot.epoch, generation == courant else { return }
            etat = .charge(liste)
        } catch {
            guard await controller.epoch == snapshot.epoch, generation == courant, !Task.isCancelled else { return }
            if error is CancellationError { return }
            if let jolene = error as? JoleneError, jolene.kind == .cancelled { return }
            if !garderListe { etat = .echec }
        }
    }

    /// Destination du lien d'une notification, nil sans lien, lien vide ou lien non Jolene.
    public static func destination(_ notification: NotificationJolene) -> DestinationLien? {
        guard let lien = notification.lien, !lien.isEmpty else { return nil }
        return DestinationLien(link: lien)
    }

    /// « Voir » affiché : lien Jolene dont la cible est présentable dans l'espace.
    public static func afficheVoir(_ notification: NotificationJolene, renvoiWebDisponible: Bool) -> Bool {
        guard let lien = destination(notification) else { return false }
        return CibleNotification(lien).estPresentable(renvoiWebDisponible: renvoiWebDisponible)
    }

    /// La ligne est un bouton s'il y a quelque chose à faire : la marquer lue, ouvrir sa cible, ou signaler un
    /// lien invalide (comme le web) ; jamais un bouton sans effet.
    public static func estActionnable(_ notification: NotificationJolene, renvoiWebDisponible: Bool) -> Bool {
        if !notification.lue { return true }
        guard let lien = notification.lien, !lien.isEmpty else { return false }
        guard let destination = DestinationLien(link: lien) else { return true }
        return CibleNotification(destination).estPresentable(renvoiWebDisponible: renvoiWebDisponible)
    }

    /// Tap sur une ligne (`handleClick`, l.89-103) : rend la cible à présenter, nil s'il n'y a rien à ouvrir
    /// (échec du marquage, lien absent, invalide ou sans présentation dans l'espace).
    public func ouvrir(_ notification: NotificationJolene, renvoiWebDisponible: Bool) async -> CibleNotification? {
        guard ouvertureEnCours == nil else { return nil }
        ouvertureEnCours = notification.id
        defer { ouvertureEnCours = nil }
        messageAction = nil

        if !notification.lue {
            guard let gateways = await controller.gateways(for: snapshot.epoch) else { return nil }
            let port = gateways.notifications
            let context = snapshot.context
            let id = notification.id
            do {
                let relue = try await bounded(timeout: controller.resolutionTimeout) {
                    try await port.marquerLue(id: id, context: context)
                }
                guard await controller.epoch == snapshot.epoch else { return nil }
                guard relue.id == id, relue.lue else { throw JoleneError(.unknown, CentreNotificationsTextes.marquerLueImpossible) }
                remplacer(relue)
            } catch {
                guard await controller.epoch == snapshot.epoch else { return nil }
                signaler(CentreNotificationsTextes.marquerLueImpossible)
                return nil
            }
        }
        guard let lien = notification.lien, !lien.isEmpty else { return nil }
        guard let destination = DestinationLien(link: lien) else {
            signaler(CentreNotificationsTextes.lienInvalide)
            return nil
        }
        let cible = CibleNotification(destination)
        return cible.estPresentable(renvoiWebDisponible: renvoiWebDisponible) ? cible : nil
    }

    /// Fin de l'affichage du message d'action.
    public func effacerMessage() {
        messageAction = nil
    }

    private func signaler(_ message: String) {
        messageAction = message
        numeroMessage += 1
    }

    private func remplacer(_ relue: NotificationJolene) {
        guard case var .charge(liste) = etat, let index = liste.firstIndex(where: { $0.id == relue.id }) else { return }
        liste[index] = relue
        etat = .charge(liste)
    }
}
