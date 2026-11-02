import SwiftUI
import JoleneCore

/// Point d'extension « Ajouter au calendrier » (décision 18 : bouton dans Mes missions › À venir
/// ET sur l'Accueil). La tranche T5 le câble avec `CalendarWriter` (EventKit, un événement par
/// créneau PREVISIONNEL, journal local de dédoublonnage) en injectant son implémentation dans
/// l'environnement (`.environment(\.ajoutCalendrierMission, …)`) au-dessus des onglets.
///
/// Tant qu'aucune implémentation n'est injectée, l'Accueil n'affiche aucun bouton calendrier :
/// jamais un bouton sans effet ni un succès fabriqué. EventKit n'est pas `Sendable` : son
/// enveloppe vit sur le main actor, seul le protocole est partagé.
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
    /// Implémentation de l'ajout au calendrier, `nil` tant que T5 ne l'a pas câblée.
    var ajoutCalendrierMission: (any AjoutCalendrierMission)? {
        get { self[AjoutCalendrierMissionKey.self] }
        set { self[AjoutCalendrierMissionKey.self] = newValue }
    }
}
