import SwiftUI
import JoleneCore

/// « Renvoi web » : présentation d'une route `.safari` (`JoleneRoute`, contrat du lot 0 : « servi par
/// Safari (SFSafariViewController) »). Implémenté par le coordinateur des liens (`DeepLinkCoordinator`,
/// lot 3 T3b, reliquat L1-T10), injecté à la racine de la fenêtre (`PointDEntreeLiens`, `JoleneApp`) :
/// `SFSafariViewController` en staging et production, double démo sans réseau (`renvoi-web-demo`).
///
/// Pourquoi pas `openURL` : les chemins `/soignant/*` sont couverts par l'AASA de
/// `GDU5AA28M9.app.jolene` (`applinks:jolene.app`, `Jolene.entitlements`) ; ouverts par `openURL`,
/// ils reviendraient dans l'app par lien universel, qui les renverrait vers Safari (boucle). Un
/// `SFSafariViewController` ne déclenche pas le lien universel, et l'aiguillage ignore le même lien
/// revenu tant que le renvoi est affiché (`AiguillageLiens`, `DeepLinkIntentTests`).
///
/// Consommateurs : l'Accueil (« Vérifier mes présences sur jolene.app », `accueil-oubli-pointage-action`,
/// affiché avec le compteur d'oubli de pointage), le centre de notifications et les taps push
/// (`CibleNotification.web`), l'édition du profil (type d'exercice, `profil-exercice-web-action`). Un écran
/// sans présentateur (aperçus, tests isolés) n'affiche aucun bouton de renvoi : jamais un bouton sans
/// effet (CLAUDE.md, « un gap connu reste verrouillé »).
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
    /// Présentateur des renvois web, injecté à la racine par le coordinateur des liens (`nil` hors de la fenêtre).
    var presentateurRenvoiWeb: (any PresentateurRenvoiWeb)? {
        get { self[PresentateurRenvoiWebKey.self] }
        set { self[PresentateurRenvoiWebKey.self] = newValue }
    }
}

/// Contenu d'une page web présentée par une **feuille locale** (`PageWebLocale`), quand l'écran est lui-même
/// présenté en feuille et que la racine ne peut pas présenter par-dessus (une seule feuille par niveau, limite connue
/// de T3b) : même choix que le renvoi web du coordinateur — `SFSafariViewController` en staging et production, double
/// démo sans réseau en démo (L3-TJ, décision TJ3 de `DECISIONS_LOT3.md`). Injecté à la racine par `PointDEntreeLiens`
/// depuis `DeepLinkCoordinator.estDemo` ; défaut `.safari` hors de la fenêtre.
enum PresentationPageWeb: Sendable {
    case safari
    case doubleDemo
}

private struct PresentationPageWebKey: EnvironmentKey {
    static let defaultValue: PresentationPageWeb = .safari
}

extension EnvironmentValues {
    /// Présentation des pages web des feuilles locales (`PageWebLocale`), posée à la racine par le coordinateur des liens.
    var presentationPageWeb: PresentationPageWeb {
        get { self[PresentationPageWebKey.self] }
        set { self[PresentationPageWebKey.self] = newValue }
    }
}
