import SwiftUI
import JoleneCore

/// Point d'extension « renvoi web » : présentation d'une route `.safari` (`JoleneRoute`, contrat du
/// lot 0 : « servi par Safari (SFSafariViewController) »). La tranche T10 le câble avec le
/// présentateur `.safari` du `DeepLinkCoordinator` en injectant son implémentation dans
/// l'environnement (`.environment(\.presentateurRenvoiWeb, …)`) au-dessus des onglets.
///
/// Pourquoi pas `openURL` : les chemins `/soignant/*` sont couverts par l'AASA de
/// `GDU5AA28M9.app.jolene` (`applinks:jolene.app`, `Jolene.entitlements`) ; ouverts par
/// `openURL`, ils reviendraient dans l'app par lien universel, que rien ne traite avant T10
/// (aucun `onOpenURL` ni `onContinueUserActivity`) : le bouton ne ferait rien, en silence. Un
/// `SFSafariViewController` ne déclenche pas le lien universel.
///
/// Tant qu'aucune implémentation n'est injectée, l'Accueil garde son compteur d'oubli de pointage
/// mais n'affiche aucun bouton de renvoi : jamais un bouton sans effet (CLAUDE.md, « un gap connu
/// reste verrouillé »). Verrou du gap : `DemoAccueilTests` affirme aujourd'hui l'absence de
/// `accueil-oubli-pointage-action` ; T10 remplace cette assertion par la présence du bouton et la
/// présentation du renvoi, et la clôture T12 vérifie l'injection (`LOT1_PLAN.md` §3 T10 et T12,
/// verrou n°2). Lot 3, T5 : le compteur des notifications non lues ouvre le centre natif
/// (`accueil-notifications-action`) ; dans le centre et pour les taps push, une destination web n'est
/// présentée que par ce présentateur (`CibleNotification.web`), sinon rien n'est ouvert.
@MainActor
protocol PresentateurRenvoiWeb: AnyObject, Sendable {
    /// Présente `route` (`.safari` ou `.etablissement`) hors du lien universel ; sans effet pour
    /// une route native.
    func presenter(_ route: JoleneRoute)
}

private struct PresentateurRenvoiWebKey: EnvironmentKey {
    static let defaultValue: (any PresentateurRenvoiWeb)? = nil
}

extension EnvironmentValues {
    /// Présentateur des renvois web, `nil` tant que T10 ne l'a pas câblé.
    var presentateurRenvoiWeb: (any PresentateurRenvoiWeb)? {
        get { self[PresentateurRenvoiWebKey.self] }
        set { self[PresentateurRenvoiWebKey.self] = newValue }
    }
}
