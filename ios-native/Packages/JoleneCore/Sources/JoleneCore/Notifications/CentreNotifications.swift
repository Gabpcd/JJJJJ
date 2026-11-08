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

    /// Indication vocale de « Voir » sur le compteur de l'Accueil (`accueil-notifications-action`). **Sans source
    /// web** (le web n'a pas d'indication) et non juridique : en attente de relecture par Gabrielle
    /// (`DECISIONS_LOT3.md`, section T5), épinglée par `CentreNotificationsTests`.
    public static let indicationOuvrirCentre = "Ouvre le centre de notifications"
}

// MARK: - Cible d'une destination dans l'espace prêt

/// Ce que l'espace prêt fait d'une destination de lien (ligne du centre, tap push, lien universel : aiguillage
/// unique `AiguillageLiens` de L3-T3b) : un onglet (Revenus avec sa section), le détail d'une mission, le centre de
/// notifications, les préférences de notifications (T6) et l'édition du profil (T9), empilées sur l'onglet Profil
/// (intégration du lot 3) ; un renvoi web passe par le présentateur `.safari` (`PresentateurRenvoiWeb`, injecté à la
/// racine par le coordinateur des liens) ; la connexion n'a pas de présentation dans l'espace (`.aucune`).
///
/// Construite depuis une `DestinationLien` seulement (jamais la route brute : `.revenus(section: .factures)`
/// ouvrirait l'onglet natif au lieu du renvoi web assumé, D4).
///
/// Verrou (revue L3-T5, M1 ; `CLAUDE.md`, « un gap connu reste verrouillé ») : une tranche qui passe sa ligne de
/// `DestinationLien.ecranNatifLivre` à `true` (T6 préférences et T9 profil — faits à l'intégration du lot 3 —,
/// T7/T8 inscription, T13 paiements, T14a Stripe) ajoute ici sa cible, sa présentation (`estPresentable`) et son cas dans `MainTabView.presenter`. Tant
/// qu'elle ne l'a pas fait, son écran retombe sur son renvoi web canonique (jamais un tap qui n'ouvre rien) et la
/// garde `CentreNotificationsTests.testToutEcranNatifLivreAUneCibleNativePresentable` est rouge.
public enum CibleNotification: Equatable, Sendable {
    /// Onglet Accueil, à sa racine.
    case accueil
    /// Onglet Explorer (`/soignant/recherche-missions`).
    case explorer
    /// Onglet Mes missions (`/soignant/missions`).
    case missions
    /// Onglet Revenus et sa section (`?tab=`) : seule la racine (`.apercu`) est présentable avant les tranches de
    /// ses sections (T13 « Paiements à confirmer ») ; une section n'est jamais réduite en silence à l'onglet.
    case revenus(section: SectionRevenus)
    /// Onglet Profil, hub du compte (`/soignant/mon-compte`).
    case monCompte
    /// Détail d'une mission, empilé sur l'onglet Accueil.
    case mission(id: String)
    /// Centre de notifications (`/soignant/notifications`).
    case centre
    /// Préférences de notifications (`/soignant/parametres/notifications`, T6), empilées sur l'onglet Profil comme
    /// l'entrée « Réglages › Notifications » du hub.
    case preferences
    /// Édition du profil (`/soignant/profil`, tout `?tab=`, alias `/soignant/reputation`, T9), empilée sur l'onglet
    /// Profil comme l'entrée « Mon profil » du hub.
    case profil
    /// Renvoi web (`.safari` ou `.etablissement`), présenté par le présentateur de renvoi web s'il est injecté.
    case web(JoleneRoute)
    /// Route sans présentation depuis un espace prêt : connexion et liens de rappel d'authentification (coordinateur
    /// de L1-T10, hors de l'espace).
    case aucune

    public init(_ lien: DestinationLien) {
        let destination = lien.destination
        switch destination {
        case .accueil: self = .accueil
        case .explorer: self = .explorer
        case .missions: self = .missions
        case .revenus(let section): self = .revenus(section: section)
        case .monCompte: self = .monCompte
        case .missionDetail(let id): self = .mission(id: id)
        case .notifications: self = .centre
        case .parametresNotifications: self = .preferences
        case .profil: self = .profil
        case .safari, .etablissement: self = .web(destination)
        case .connexion, .resetPassword, .confirmerInscription:
            self = .aucune
        case .inscription, .serieDetail, .stripeConnect:
            // Atteint seulement quand la ligne de `ecranNatifLivre` de l'écran est passée à `true` sans que sa
            // tranche ait ajouté sa cible (sinon `destination` est déjà un `.safari`) : repli sur le renvoi web
            // canonique, jamais un tap sans effet ; la garde de `CentreNotificationsTests` le signale.
            self = .web(.safari(lien.canonique))
        }
    }

    /// Onglet porteur de la cible (sélection de la barre), nil pour un renvoi web ou une route sans présentation.
    public var onglet: OngletEspace? {
        switch self {
        case .accueil, .mission, .centre: return .accueil
        case .explorer: return .explorer
        case .missions: return .missions
        case .revenus: return .revenus
        case .monCompte, .preferences, .profil: return .profil
        case .web, .aucune: return nil
        }
    }

    /// Présentable dans l'espace : un renvoi web exige le présentateur `.safari` (absent avant L1-T10, jamais
    /// `openURL` : les chemins `/soignant/*` reviendraient dans l'app par lien universel, sans effet) ; une section
    /// de Revenus attend sa tranche ; depuis le centre (`depuisCentre`), le centre lui-même n'a rien à ouvrir.
    public func estPresentable(renvoiWebDisponible: Bool, depuisCentre: Bool = false) -> Bool {
        switch self {
        case .accueil, .explorer, .missions, .monCompte, .mission, .preferences, .profil: return true
        case .revenus(let section): return section == .apercu
        case .centre: return !depuisCentre
        case .web: return renvoiWebDisponible
        case .aucune: return false
        }
    }
}

// MARK: - Modèle

/// Modèle du centre de notifications, lu pour l'epoch de la session (`controller.gateways(for:)`), borné à
/// `SessionController.resolutionTimeout`. Règles :
/// - premier chargement et « Réessayer » : chargement puis liste ou erreur (texte web, jamais le détail technique) ;
/// - relecture silencieuse (notification reçue au premier plan, réconciliation) : la liste affichée reste en place
///   en cas d'échec, sans message ; tirer pour rafraîchir (`rafraichir`) : idem, mais un échec est signalé par
///   `erreurRafraichissement` (texte web `erreurChargement`, revue L3-T5 m3) ;
/// - une réponse d'un epoch périmé ou d'un chargement dépassé est abandonnée ; une annulation n'est jamais une erreur ;
/// - ouvrir : une notification non lue est d'abord marquée lue et **relue** (ligne rendue par le port) ; un échec
///   affiche le texte web et n'ouvre rien (l.89-97), puis la liste est relue sans être retirée (un délai dépassé
///   ne prouve pas que le serveur n'a pas agi, PRINCIPES §5, revue L3-T5 m2) ; puis le lien est résolu
///   (`DestinationLien`), un lien non Jolene affiche le texte web (l.98-102). Une ouverture annulée (centre quitté,
///   revue L3-T5 m4) ne rend aucune cible et n'affiche rien.
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
    /// Échec du dernier tirer-pour-rafraîchir, liste gardée : texte web `erreurChargement` ; nil sinon.
    @Published public private(set) var erreurRafraichissement: String?
    /// Notifications marquées lues (relues) par ce centre : chaque lecture périme le compteur des non lues de
    /// l'Accueil (`AccueilModel.loadIfStale(peremption:)`, revue L3-T5 m1).
    @Published public private(set) var lectures = 0
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

    /// `silencieux` : la liste affichée reste en place (pas d'indicateur, pas d'erreur plein écran, pas de message).
    public func charger(silencieux: Bool = false) async {
        _ = await lire(garderListe: silencieux)
    }

    /// Tirer pour rafraîchir : relecture qui garde la liste affichée ; son échec est signalé par
    /// `erreurRafraichissement` (encart au texte web), jamais avalé. Sans liste affichée, l'erreur reste plein écran.
    public func rafraichir() async {
        erreurRafraichissement = nil
        if await lire(garderListe: true) == .echecListeGardee {
            erreurRafraichissement = CentreNotificationsTextes.erreurChargement
        }
    }

    private enum IssueLecture: Equatable { case publiee, echecListeGardee, echecPublie, abandonnee }

    private func lire(garderListe silencieux: Bool) async -> IssueLecture {
        generation += 1
        let courant = generation
        let garderListe: Bool
        if case .charge = etat { garderListe = silencieux } else { garderListe = false }
        if !garderListe { etat = .chargement }

        guard let gateways = await controller.gateways(for: snapshot.epoch), generation == courant else { return .abandonnee }
        horloge = gateways.clock
        let port = gateways.notifications
        let context = snapshot.context
        do {
            let liste = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.liste(context: context)
            }
            guard await controller.epoch == snapshot.epoch, generation == courant else { return .abandonnee }
            etat = .charge(liste)
            erreurRafraichissement = nil
            return .publiee
        } catch {
            guard await controller.epoch == snapshot.epoch, generation == courant, !Task.isCancelled else { return .abandonnee }
            if error is CancellationError { return .abandonnee }
            if let jolene = error as? JoleneError, jolene.kind == .cancelled { return .abandonnee }
            if garderListe { return .echecListeGardee }
            etat = .echec
            return .echecPublie
        }
    }

    /// Destination du lien d'une notification, nil sans lien, lien vide ou lien non Jolene.
    public static func destination(_ notification: NotificationJolene) -> DestinationLien? {
        guard let lien = notification.lien, !lien.isEmpty else { return nil }
        return DestinationLien(link: lien)
    }

    /// « Voir » affiché : lien Jolene dont la cible est présentable depuis le centre (jamais le centre lui-même).
    public static func afficheVoir(_ notification: NotificationJolene, renvoiWebDisponible: Bool) -> Bool {
        guard let lien = destination(notification) else { return false }
        return CibleNotification(lien).estPresentable(renvoiWebDisponible: renvoiWebDisponible, depuisCentre: true)
    }

    /// La ligne est un bouton s'il y a quelque chose à faire : la marquer lue, ouvrir sa cible depuis le centre, ou
    /// signaler un lien invalide (comme le web) ; jamais un bouton sans effet.
    public static func estActionnable(_ notification: NotificationJolene, renvoiWebDisponible: Bool) -> Bool {
        if !notification.lue { return true }
        guard let lien = notification.lien, !lien.isEmpty else { return false }
        guard let destination = DestinationLien(link: lien) else { return true }
        return CibleNotification(destination).estPresentable(renvoiWebDisponible: renvoiWebDisponible, depuisCentre: true)
    }

    /// Tap sur une ligne (`handleClick`, l.89-103) : rend la cible à présenter depuis le centre, nil s'il n'y a rien
    /// à ouvrir (échec du marquage, ouverture annulée, lien absent, invalide ou sans présentation depuis le centre).
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
                lectures += 1
            } catch {
                guard await controller.epoch == snapshot.epoch else { return nil }
                // Centre quitté pendant l'appel : ni message ni relecture pour un écran parti (revue L3-T5, m4).
                if Self.estAnnulation(error) { return nil }
                signaler(CentreNotificationsTextes.marquerLueImpossible)
                // Le PATCH a pu aboutir (délai dépassé, relecture en échec) : réconciliation silencieuse, message
                // gardé (PRINCIPES §5, revue L3-T5 m2).
                await charger(silencieux: true)
                return nil
            }
            if Task.isCancelled { return nil }
        }
        guard let lien = notification.lien, !lien.isEmpty else { return nil }
        guard let destination = DestinationLien(link: lien) else {
            signaler(CentreNotificationsTextes.lienInvalide)
            return nil
        }
        let cible = CibleNotification(destination)
        return cible.estPresentable(renvoiWebDisponible: renvoiWebDisponible, depuisCentre: true) ? cible : nil
    }

    private static func estAnnulation(_ error: Error) -> Bool {
        if Task.isCancelled || error is CancellationError { return true }
        if let jolene = error as? JoleneError, jolene.kind == .cancelled { return true }
        return false
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
