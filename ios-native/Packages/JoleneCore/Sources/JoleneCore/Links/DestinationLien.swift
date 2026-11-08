import Foundation

/// Destination effective d'un lien Jolene (Universal Link, `lien` d'une notification push, lien
/// interne) — lot 3, T3a.
///
/// `LinkRouter` donne la route du chemin (table de `src/App.tsx`) ; `DestinationLien` décide ce que
/// l'app présente : la route elle-même si son écran natif est livré, sinon un renvoi `.safari` sur
/// l'URL canonique du lien (`https://jolene.app` + chemin, query et fragment conservés). Ainsi un
/// lien vers un écran du lot 3 pas encore mergé ouvre la page web au lieu d'un écran vide.
///
/// Livraison partielle (`DECISIONS_LOT3.md`, « T3 livrée en deux temps ») : le coordinateur de liens
/// du lot 1 (L1-T10 : `JoleneApp.onOpenURL` / `onContinueUserActivity`, `DeepLinkCoordinator`,
/// intention mémorisée avant `.ready`, argument DEBUG `-JOLENE_OPEN_URL`) n'est sur aucune branche ;
/// à l'exécution, seul `AccueilPresentation.renvoiWeb` consomme ce type. Le nom `DeepLinkIntent`
/// reste à L1-T10 (intention différée, epoch) : son intention portera une `DestinationLien` et
/// présentera `destination` une fois rejouée. Le câblage du coordinateur et `DemoLiensLot3Tests`
/// forment le reliquat T3b.
///
/// Ligne par tranche : la tranche d'écran du lot 3 passe sa ligne de `ecranNatifLivre` à `true` et
/// ajuste `DestinationLienTests` (table des écrans, famille du vecteur push, totaux) ; elle ajoute
/// aussi sa cible dans l'espace (`CibleNotification`, `MainTabView.presenter`), exigée par la garde
/// `CentreNotificationsTests.testToutEcranNatifLivreAUneCibleNativePresentable` (revue L3-T5, M1).
///
/// Journalisation (PRINCIPES §7) : ne journaliser que `description` — celle de `DestinationLien`,
/// de `JoleneRoute` ou d'`EtapeInscription`, toutes masquées (`LienMasque`) —, jamais `canonique`,
/// `externalURL`, `EtapeInscription.query` ni un identifiant extrait. Le chemin porte des jetons
/// (`/etab/invitation/:token`) et des identifiants (`/contrat/:id`, `/soignant/missions/:id`) ; la
/// query et le fragment d'un lien de rappel portent `token_hash`, `code`, `access_token`,
/// `refresh_token`.
public struct DestinationLien: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    /// Route rendue par `LinkRouter`, indépendante de la disponibilité des écrans.
    public let route: JoleneRoute
    /// URL web canonique du lien reçu, servie par Safari si l'écran n'est pas livré. Jamais
    /// journalisée : `LienMasque.gabarit(_:)` en donne une forme montrable.
    public let canonique: URL

    /// Universal Link entrant : mêmes refus que `LinkRouter.route(url:)` (hôte, schéma, port).
    public init?(url: URL) {
        guard let routage = LinkRouter.routage(url: url) else { return nil }
        self.init(route: routage.route, canonique: routage.canonique)
    }

    /// Lien interne (chemin relatif ou hôte web de confiance) : mêmes refus que
    /// `LinkRouter.resolve(link:)`.
    public init?(link: String) {
        guard let routage = LinkRouter.routage(link: link) else { return nil }
        self.init(route: routage.route, canonique: routage.canonique)
    }

    init(route: JoleneRoute, canonique: URL) {
        self.route = route
        self.canonique = canonique
    }

    /// Cas de route et gabarit du chemin, segments dynamiques, query et fragment masqués.
    public var description: String {
        "DestinationLien(route: \(route), chemin: \(LienMasque.gabarit(canonique)), "
            + "destination: \(destination.isNative ? "natif" : "web"))"
    }
    public var debugDescription: String { description }

    /// Ce que l'app présente : la route si son écran natif est livré, une route externe telle
    /// quelle, sinon `.safari(canonique)`.
    public var destination: JoleneRoute {
        guard route.isNative, !Self.ecranNatifLivre(route) else { return route }
        return .safari(canonique)
    }

    /// Destination dans l'app pour une route native (`false` pour une route externe), **vraie à
    /// l'arrivée du coordinateur de liens L1-T10**, seul consommateur prévu avec
    /// `AccueilPresentation.renvoiWeb` : `true` veut dire « la route a sa destination dans l'app »,
    /// écran provisoire d'onglet (`PlaceholderScreen`) compris. Une ligne par tranche d'écran : la
    /// tranche qui livre l'écran passe sa ligne à `true`.
    public static func ecranNatifLivre(_ route: JoleneRoute) -> Bool {
        switch route {
        case .connexion, .accueil, .explorer, .missionDetail:
            return true                                  // lots 0 et 1 : écrans présents sur la base
        case .resetPassword, .confirmerInscription:
            return true                                  // vrai à l'arrivée de L1-T10 (écrans livrés par T10)
        case .missions:
            return true                                  // onglet Mes missions : placeholder jusqu'à L1-T5
        case .serieDetail:
            return false                                 // renvoi web assumé (décision 11 du lot 1) ; natif au lot 4
        case .revenus(section: .apercu):
            return true                                  // onglet Revenus : placeholder jusqu'à L3-T12
        case .monCompte:
            return true                                  // hub `ProfileScreen` (lot 1 T8 ; complété par L3-T11)
        case .notifications:
            return true                                  // T5 — centre de notifications (`NotificationsScreen`)
        case .parametresNotifications:
            return false                                 // T6 — préférences de notifications
        case .inscription(let etape):
            switch etape.page {
            case .soignant, .reprendre: return false     // T7 — compte rapide, aiguillage onboarding
            case .completer: return false                // T8 — complétion du profil
            }
        case .profil:
            return false                                 // T9 — édition du profil
        case .revenus(section: .paiementsAConfirmer):
            return false                                 // T13 — paiements à confirmer
        case .stripeConnect:
            return false                                 // T14a — Stripe Connect
        case .revenus(section: .factures), .revenus(section: .bulletins), .revenus(section: .avances):
            return false                                 // renvoi web assumé jusqu'au lot 4 (D4)
        case .safari, .etablissement:
            return false
        }
    }
}
