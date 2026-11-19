import SwiftUI
import JoleneCore

/// Point d'extension « Ajouter au calendrier » (décision 18 : bouton dans Mes missions › À venir
/// ET sur l'Accueil). Câblé par la tranche T5 : `CalendarWriter.swift` injecte `AjoutCalendrier`
/// (JoleneCore : un événement par créneau PREVISIONNEL, journal local de dédoublonnage) dans
/// l'environnement au-dessus des onglets (`MainTabView`, `.ajoutCalendrier(container:userId:)`).
///
/// Sans implémentation injectée (aperçus, futur écran hors onglets), aucun bouton calendrier n'est
/// rendu : jamais un bouton sans effet ni un succès fabriqué. Preuves : `DemoAccueilTests` (bouton
/// `accueil-calendrier-demo-assignee-001` et issue `accueil-calendrier-issue`) et
/// `DemoMesMissionsTests` (`calendrier-{id}`, `missions-calendrier-issue`). EventKit n'est pas
/// `Sendable` : son enveloppe vit sur le main actor, seul le protocole est partagé.
@MainActor
protocol AjoutCalendrierMission: AnyObject, Sendable {
    /// Ajoute les créneaux planifiés de `mission` au calendrier de l'appareil et rend le message
    /// à afficher (accord refusé, créneaux déjà ajoutés, nombre d'événements écrits…).
    func ajouterAuCalendrier(_ mission: Mission) async -> AjoutCalendrierIssue
}

/// Issue présentée sous la liste des prochaines missions (`accueil-calendrier-issue`).
struct AjoutCalendrierIssue: Equatable, Sendable {
    var message: String
    var succes: Bool
}

private struct AjoutCalendrierMissionKey: EnvironmentKey {
    static let defaultValue: (any AjoutCalendrierMission)? = nil
}

extension EnvironmentValues {
    /// Implémentation de l'ajout au calendrier (T5), `nil` hors des onglets d'une session prête.
    var ajoutCalendrierMission: (any AjoutCalendrierMission)? {
        get { self[AjoutCalendrierMissionKey.self] }
        set { self[AjoutCalendrierMissionKey.self] = newValue }
    }
}
