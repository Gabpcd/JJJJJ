import Foundation

/// Destination effective d'un lien Jolene (Universal Link, `lien` d'une notification push, lien
/// interne) — lot 3, T3.
///
/// `LinkRouter` donne la route du chemin (table de `src/App.tsx`) ; `DeepLinkIntent` décide ce que
/// l'app présente : la route elle-même si son écran natif est livré, sinon un renvoi `.safari` sur
/// l'URL canonique du lien (`https://jolene.app` + chemin, query et fragment conservés). Ainsi un
/// lien vers un écran du lot 3 pas encore mergé ouvre la page web au lieu d'un écran vide.
///
/// Point d'extension minimal : le coordinateur de liens du lot 1 (T10 : `JoleneApp.onOpenURL` /
/// `onContinueUserActivity`, `DeepLinkCoordinator`, intention mémorisée avant `.ready`, argument
/// DEBUG `-JOLENE_OPEN_URL`) n'est pas sur la base du lot 3 ; il consommera `destination`. En
/// attendant, chaque tranche d'écran du lot 3 change **une ligne** de `ecranNatifLivre` (au lieu
/// de `DeepLinkCoordinator.swift`, prévu par le blueprint du lot 3 §3 T3) et la ligne
/// correspondante de `DeepLinkIntentTests`.
public struct DeepLinkIntent: Equatable, Sendable {
    /// Route rendue par `LinkRouter`, indépendante de la disponibilité des écrans.
    public let route: JoleneRoute
    /// URL web canonique du lien reçu, servie par Safari si l'écran n'est pas livré.
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

    /// Ce que l'app présente : la route si son écran natif est livré, une route externe telle
    /// quelle, sinon `.safari(canonique)`.
    public var destination: JoleneRoute {
        guard route.isNative, !Self.ecranNatifLivre(route) else { return route }
        return .safari(canonique)
    }

    /// Écran natif livré pour une route native (`false` pour une route externe). Une ligne par
    /// tranche d'écran : la tranche qui livre l'écran passe sa ligne à `true`.
    public static func ecranNatifLivre(_ route: JoleneRoute) -> Bool {
        switch route {
        case .connexion, .resetPassword, .confirmerInscription,
             .accueil, .explorer, .missions, .missionDetail, .serieDetail:
            return true                                  // lots 0 et 1
        case .revenus(section: .apercu):
            return true                                  // onglet Revenus (lot 1 ; contenu natif : T12)
        case .monCompte:
            return true                                  // hub `ProfileScreen` (lot 1 T8 ; T11)
        case .notifications:
            return false                                 // T5 — centre de notifications
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
