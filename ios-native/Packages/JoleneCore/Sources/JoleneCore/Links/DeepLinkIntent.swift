import Foundation

// Liens entrants (lot 1 T10, reliquat lot 3 T3b ; `docs/mobile-swift/LOT1_PLAN.md` §2.5 et §3 T10,
// `docs/mobile-swift/LOT3_PLAN.md` §2.5 et §3 T3, `DECISIONS_LOT3.md`, section T3b) : point d'entrée unique des
// Universal Links (`onOpenURL`, `onContinueUserActivity`), de l'argument DEBUG `-JOLENE_OPEN_URL` et des taps push.
//
// Chaîne : URL → `DestinationLien` (route de `LinkRouter`, destination effective selon `ecranNatifLivre`) →
// `DeepLinkIntent` (où et quand la présenter) → `AiguillageLiens` (mémorisation avant `.ready`, rejeu, epoch) →
// action exécutée par le coordinateur de l'app (`Jolene/Composition/DeepLinkCoordinator.swift`). Jamais
// `supabase.auth.handle(url)` ni échange de code : un lien de rappel n'ouvre aucune session dans l'app.

/// Intention d'un lien Jolene reçu : ce que l'app en fait, indépendamment de l'état de la session.
///
/// Classement (sur `DestinationLien.destination`, jamais sur la route brute, sauf pour l'option B) :
/// - `.reinitialisationRefusee` : `/reset-password?code=…` (PKCE). Option B (décision 7 du lot 1) : le verifier
///   n'existe que dans le navigateur qui a demandé le lien ; l'app refuse sans rien échanger ni ouvrir ;
/// - `.renvoiWeb` : destination externe (`.safari`, `.etablissement`) — écran non livré (URL canonique, query et
///   fragment conservés), section de Revenus non portée (`?tab=`), chemin servi par Safari, espace établissement.
///   Présentée **aussitôt**, session ouverte ou non : un renvoi n'a pas besoin de l'espace soignant (inscription,
///   établissement, compte bloqué) ;
/// - `.horsEspace` : route native livrée **sans** cible dans l'espace. Liste nommée et fermée, gardée par
///   `DeepLinkIntentTests.testToutLienHorsEspaceAppartientALaListeNommee` : `/connexion` (l'écran de connexion
///   s'affiche déjà sans session, et l'espace prêt y reste : aucune action) ; depuis l'intégration de T7, la
///   confirmation d’inscription et les pages `/inscription/soignant`, `/inscription/reprendre` et (T8) `/inscription/completer` (action
///   `AiguillageLiens.Action.inscription`, déposée par le coordinateur dans `BoiteLiensInscription`, présentée par
///   `RootView`) ;
/// - `.espace` : destination de l'espace soignant prêt (onglet, section, détail, écran empilé) ; mémorisée tant
///   qu'aucun espace n'est ouvert, rejouée une fois prêt (`AiguillageLiens`).
///
/// Journalisation (PRINCIPES §7) : seule la description masquée (`DestinationLien.description`) est montrée,
/// `dump` compris (`CustomReflectable`) ; jamais l'URL canonique ni un identifiant.
public enum DeepLinkIntent: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case espace(DestinationLien)
    case renvoiWeb(DestinationLien)
    case horsEspace(DestinationLien)
    case reinitialisationRefusee

    public init(_ lien: DestinationLien) {
        // Option B : décidée sur la route, quelle que soit la ligne de `ecranNatifLivre` du reset.
        if case .resetPassword(credentials: .some(.pkce)) = lien.route {
            self = .reinitialisationRefusee
            return
        }
        let destination = lien.destination
        if destination.externalURL != nil {
            self = .renvoiWeb(lien)
            return
        }
        switch destination {
        case .connexion, .resetPassword, .confirmerInscription, .inscription:
            self = .horsEspace(lien)
        case .accueil, .explorer, .missions, .missionDetail, .serieDetail, .revenus, .monCompte, .profil,
             .notifications, .parametresNotifications, .stripeConnect, .safari, .etablissement:
            self = .espace(lien)
        }
    }

    /// Universal Link entrant : `nil` hors des hôtes, schéma et port de l'AASA (`DestinationLien(url:)`).
    public init?(url: URL) {
        guard let lien = DestinationLien(url: url) else { return nil }
        self.init(lien)
    }

    // MARK: Textes

    public enum Textes {
        /// Refus d'un lien de réinitialisation PKCE. source: docs/mobile-swift/LOT1_PLAN.md:403 (décision 7 du lot 1,
        /// option B ; texte natif décidé, non juridique, sans équivalent web : le web échange le code).
        public static let reinitialisationRefusee = "Ce lien ne permet pas de réinitialiser le mot de passe depuis l'application."
        /// Action de fermeture (refus, double démo du renvoi web). source: ios-native/Jolene/Screens/Explorer/FiltresSheet.swift:64
        public static let fermer = "Fermer"
    }

    // MARK: Argument DEBUG

    /// `-JOLENE_OPEN_URL <url>` : lien universel simulé au lancement (à froid), honoré par `AppContainer` en build
    /// DEBUG seulement, en démo comme en STAGING (preuve niveau 3 de l'inscription, correction 14 du blueprint du
    /// lot 3 : lien `token_hash` relu en SQL puis injecté). Mêmes refus qu'un lien universel réel.
    public static let argumentOuverture = "-JOLENE_OPEN_URL"

    public static func ouvertureSimulee(arguments: [String]) -> URL? {
        valeur(de: argumentOuverture, dans: arguments)
    }

    /// `-JOLENE_OPEN_URL_SUIVANT <url>` (revue B8 de T3b, m1) : lien universel remis **pendant** un renvoi affiché, par
    /// le bouton `renvoi-web-lien-suivant` du double démo du présentateur `.safari` (DEBUG et démo seulement, honoré par
    /// `AppContainer`). Preuve XCUITest d'un lien reçu pendant un renvoi (refus `?code=` présenté après la fermeture de
    /// la feuille), sans attente par délai ; mêmes refus qu'un lien universel réel.
    public static let argumentLienSuivant = "-JOLENE_OPEN_URL_SUIVANT"

    public static func lienSuivantSimule(arguments: [String]) -> URL? {
        valeur(de: argumentLienSuivant, dans: arguments)
    }

    private static func valeur(de argument: String, dans arguments: [String]) -> URL? {
        guard let position = arguments.firstIndex(of: argument), arguments.indices.contains(position + 1),
              !arguments[position + 1].isEmpty else { return nil }
        return URL(string: arguments[position + 1])
    }

    // MARK: Description masquée

    public var description: String {
        switch self {
        case .espace(let lien): return "DeepLinkIntent.espace(\(lien))"
        case .renvoiWeb(let lien): return "DeepLinkIntent.renvoiWeb(\(lien))"
        case .horsEspace(let lien): return "DeepLinkIntent.horsEspace(\(lien))"
        case .reinitialisationRefusee: return "DeepLinkIntent.reinitialisationRefusee"
        }
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: ["description": description]) }
}

/// Aiguillage unique des liens entrants et des taps push (reliquat L1-T10, lot 3 T3b). Logique pure, sans UI :
/// le coordinateur de l'app (`DeepLinkCoordinator`) exécute les actions rendues (navigation dans l'espace,
/// présentateur `.safari`, refus).
///
/// Règles :
/// - un lien de l'espace reçu sans espace ouvert (lancement à froid, écran de connexion, restauration) est
///   **mémorisé** (le dernier gagne), puis rejoué **une seule fois** par le premier espace prêt
///   (`ouvrirEspace(_:)`) ; reçu dans un espace ouvert, il est présenté aussitôt, pour l'epoch de cet espace ;
/// - les taps push restent dans `BoiteTapsPush` (règle d'epoch de L3-T5 inchangée : un tap reçu pendant l'espace
///   d'un epoch est écarté par un autre) et passent par le même aiguillage : `tapRecu()` dans un espace ouvert,
///   `ouvrirEspace(_:)` sinon, rôle lu dans le snapshot (`PushTapIntent.destination(role:)`) ;
/// - entre un lien et un tap en attente à l'ouverture de l'espace, le plus récent l'emporte (le web navigue vers
///   la dernière demande) ; s'il ne mène nulle part, l'autre sert de repli ; les deux sont consommés ;
/// - renvoi web : présenté aussitôt, jamais mémorisé. Tant qu'un renvoi est affiché, le **même** lien revenu par
///   lien universel est ignoré : un `.safari` issu de l'app n'est jamais rejoué comme lien universel
///   (`LOT1_PLAN.md` §3 T10) ;
/// - une destination de l'espace dont la cible n'est pas présentable (section de Revenus avant sa tranche,
///   repli de `CibleNotification` vers le web) retombe sur son renvoi web canonique : jamais un lien sans effet
///   (revue L3-T5, m3) ;
/// - `.horsEspace` : connexion, aucune action ; confirmation et pages `soignant` / `reprendre` (T7) et `completer` (T8) d’inscription,
///   action `.inscription` rendue aussitôt, avec ou sans espace, jamais mémorisée ni rejouée (la vue de session
///   décide : une identité ouverte n'a pas d'inscription à faire, la confirmation est présentée au-dessus de tout
///   état) ; `.reinitialisationRefusee` : refus, jamais mémorisé.
///
/// Écart consigné (comme les taps, revue L3-T5 m12) : un lien reçu sur l'écran de connexion après une déconnexion
/// est rejoué pour l'identité qui se connecte ensuite, comme le web ; la destination est relue sous sa RLS.
@MainActor
public final class AiguillageLiens {
    /// Ce que l'app présente.
    public enum Action: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        /// Navigation dans l'espace prêt de cet epoch vers une cible présentable (`CibleNotification`) ; `route` est la
        /// destination effective (libellé DEBUG `deeplink-route`).
        case naviguer(CibleNotification, route: JoleneRoute, epoch: Int)
        /// Renvoi web (`.safari` ou `.etablissement`) par le présentateur `.safari`, jamais `openURL`.
        case renvoiWeb(JoleneRoute)
        /// Lien de réinitialisation PKCE refusé (option B) : `DeepLinkIntent.Textes.reinitialisationRefusee`.
        case refusReinitialisation
        /// Lien d'inscription consommé hors de l'espace (intégration de T7) : confirmation (`/inscription/confirmer`) ou
        /// page `soignant` / `reprendre` / `completer` (T8), déposée par le coordinateur dans `BoiteLiensInscription` (lue par `RootView`).
        case inscription(DestinationLien)

        public var description: String {
            switch self {
            case .naviguer(_, let route, let epoch): return "Action.naviguer(\(route), epoch: \(epoch))"
            case .renvoiWeb(let route): return "Action.renvoiWeb(\(route))"
            case .refusReinitialisation: return "Action.refusReinitialisation"
            case .inscription(let lien): return "Action.inscription(\(lien))"
            }
        }

        public var debugDescription: String { description }

        public var customMirror: Mirror { Mirror(self, children: ["description": description]) }
    }

    private let taps: BoiteTapsPush
    /// Espace prêt ouvert (epoch et rôle) ; nil sans espace.
    private var espace: SessionSnapshot?
    /// Dernier lien de l'espace reçu sans espace ouvert.
    private var lienEnAttente: DestinationLien?
    /// `taps.tapsRecus` à la mémorisation du lien : un tap en attente reçu après lui l'emporte.
    private var tapsAuLien = 0
    /// URL du renvoi web affiché (anti-boucle).
    private var renvoiAffiche: URL?

    public init(taps: BoiteTapsPush) {
        self.taps = taps
    }

    /// Vrai si un lien attend l'ouverture d'un espace (preuve des tests).
    public var aUnLienEnAttente: Bool { lienEnAttente != nil }

    /// Universal Link, `-JOLENE_OPEN_URL` : nil pour un lien non Jolene ou sans action immédiate.
    public func recevoir(url: URL) -> Action? {
        guard let intention = DeepLinkIntent(url: url) else { return nil }
        return recevoir(intention)
    }

    public func recevoir(_ intention: DeepLinkIntent) -> Action? {
        switch intention {
        case .reinitialisationRefusee:
            return .refusReinitialisation
        case .horsEspace(let lien):
            switch lien.destination {
            case .confirmerInscription, .inscription: return .inscription(lien)
            default: return nil
            }
        case .renvoiWeb(let lien):
            if let affiche = renvoiAffiche, affiche == lien.destination.externalURL { return nil }
            return .renvoiWeb(lien.destination)
        case .espace(let lien):
            if let espace { return action(pour: lien, dans: espace) }
            lienEnAttente = lien
            tapsAuLien = taps.tapsRecus
            return nil
        }
    }

    /// Ouverture de l'espace prêt (apparition de `MainTabView`) : ouvre aussi la boîte des taps pour cet epoch, puis
    /// rend l'action de l'intention en attente la plus récente (lien ou tap), une seule fois.
    public func ouvrirEspace(_ snapshot: SessionSnapshot) -> Action? {
        espace = snapshot
        let tapPlusRecent = taps.aUnTapEnAttente && (lienEnAttente == nil || taps.tapsRecus > tapsAuLien)
        let tap = taps.prendre(pour: snapshot)
        let lien = lienEnAttente
        lienEnAttente = nil
        for candidat in (tapPlusRecent ? [tap, lien] : [lien, tap]).compactMap({ $0 }) {
            if let action = action(pour: candidat, dans: snapshot) { return action }
        }
        return nil
    }

    /// Tap reçu (la boîte a avancé) : présenté dans l'espace ouvert ; sans espace, il attend dans la boîte.
    public func tapRecu() -> Action? {
        guard let espace, let lien = taps.prendre(pour: espace) else { return nil }
        return action(pour: lien, dans: espace)
    }

    /// Disparition de l'espace de cet epoch ; sans effet si un autre espace s'est déjà ouvert.
    public func fermerEspace(epoch: Int) {
        if espace?.epoch == epoch { espace = nil }
        taps.fermerEspace(epoch: epoch)
    }

    /// Renvoi web **effectivement affiché** par le présentateur `.safari` (lien entrant, centre, Accueil, profil) :
    /// appelé à l'apparition du contenu de la feuille (`PresentationsRacine.apparition`), jamais à la demande — une
    /// feuille que la racine n'a pas pu présenter ne fait pas ignorer le même lien (revue B8 de T3b, m1).
    public func renvoiWebPresente(_ route: JoleneRoute) {
        renvoiAffiche = route.externalURL
    }

    /// Fin de l'affichage du renvoi web (disparition du contenu de la feuille, `PresentationsRacine.disparition`).
    public func renvoiWebFerme() {
        renvoiAffiche = nil
    }

    /// Action d'une destination tirée dans un espace ouvert (lien reçu ou mémorisé, tap).
    private func action(pour lien: DestinationLien, dans espace: SessionSnapshot) -> Action? {
        switch DeepLinkIntent(lien) {
        case .reinitialisationRefusee:
            return .refusReinitialisation
        case .horsEspace:
            return nil
        case .renvoiWeb(let lien):
            return .renvoiWeb(lien.destination)
        case .espace(let lien):
            let cible = CibleNotification(lien)
            if case .web(let route) = cible { return .renvoiWeb(route) }
            guard cible.estPresentable(renvoiWebDisponible: true) else { return .renvoiWeb(.safari(lien.canonique)) }
            return .naviguer(cible, route: lien.destination, epoch: espace.epoch)
        }
    }
}
