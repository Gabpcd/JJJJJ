import EventKit
import SwiftUI
import JoleneCore

/// Ajout au calendrier (lot 1, T5, décision 18) : câblage du point d'extension posé par T3
/// (`AjoutCalendrierMission`). Les règles (un événement par créneau PREVISIONNEL d'un planning
/// complet, journal de dédoublonnage, accord refusé, échecs partiels) sont celles d'`AjoutCalendrier`
/// (JoleneCore, testées par `AjoutCalendrierTests` avec un double d'`EKEventStore`) ; ce fichier ne
/// fournit que l'appareil EventKit et l'injection au-dessus des onglets (Accueil et Mes missions).
///
/// Démonstration : `CalendrierAppareilDemo` (aucune demande système, aucune écriture réelle) et un
/// journal en mémoire ; `refusDemo` (surcharge DEBUG `JOLENE_FORCE_CALENDRIER_REFUS=1`, lue par
/// `AppContainer` avec les autres surcharges, `AppContainer.calendrierRefusDemo`) simule un accès
/// refusé (`DemoMesMissionsTests.testCalendrierAccesRefuse`). Staging et production : EventKit et le
/// journal du compte (`jolene.calendrier.journal.<userId>`, purgé à la suppression du compte, T8).
/// L'écriture réelle est prouvée sur appareil (`RECETTE_DEVICE_LOT1.md` §4), jamais par la CI.
@MainActor
enum CalendarWriter {
    static func ajoutCalendrier(modeDemo: Bool, refusDemo: Bool, userId: String) -> AjoutCalendrier {
        if modeDemo {
            return AjoutCalendrier(appareil: CalendrierAppareilDemo(refuse: refusDemo), journal: JournalCalendrierMemoire())
        }
        return AjoutCalendrier(appareil: CalendrierEventKit(), journal: JournalCalendrierPreferences(userId: userId))
    }
}

extension AjoutCalendrier: AjoutCalendrierMission {
    func ajouterAuCalendrier(_ mission: Mission) async -> AjoutCalendrierIssue {
        let issue = await ajouter(mission)
        return AjoutCalendrierIssue(message: issue.message, succes: issue.succes)
    }
}

/// `EKEventStore` sur le main actor (type non `Sendable`) : accès en écriture seule sous iOS 17+
/// (`requestWriteOnlyAccessToEvents`), accès complet sous iOS 16 (`requestAccess(to:)`) ; aucun
/// événement n'est relu (même mécanisme sur les deux versions : journal local).
@MainActor
final class CalendrierEventKit: CalendrierAppareil {
    /// Aucun calendrier par défaut pour les nouveaux événements (réglage de l'appareil).
    struct CalendrierIndisponible: Error {}

    private lazy var store = EKEventStore()

    func acces() -> AccesCalendrier {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .nonDetermine
        case .denied, .restricted: return .refuse
        // Accès complet (iOS 16 `authorized`, iOS 17+ `fullAccess`) ou écriture seule (iOS 17+).
        default: return .accorde
        }
    }

    func demanderAcces() async -> Bool {
        await withCheckedContinuation { (suite: CheckedContinuation<Bool, Never>) in
            let reponse: @Sendable (Bool, (any Error)?) -> Void = { accorde, _ in suite.resume(returning: accorde) }
            if #available(iOS 17.0, *) {
                store.requestWriteOnlyAccessToEvents(completion: reponse)
            } else {
                store.requestAccess(to: .event, completion: reponse)
            }
        }
    }

    func enregistrer(_ evenement: EvenementCalendrier) throws {
        guard let calendrier = store.defaultCalendarForNewEvents else { throw CalendrierIndisponible() }
        let event = EKEvent(eventStore: store)
        event.calendar = calendrier
        event.title = evenement.titre
        event.startDate = evenement.debut
        event.endDate = evenement.fin
        event.location = evenement.lieu
        event.notes = evenement.notes
        event.url = evenement.url
        event.alarms = evenement.alarmesMinutes.map { EKAlarm(relativeOffset: TimeInterval($0) * 60) }
        try store.save(event, span: .thisEvent, commit: true)
    }
}

/// Boîte de l'instance d'ajout, pour une construction **paresseuse** : `StateObject(wrappedValue:)`
/// n'évalue son argument (`@autoclosure`) qu'une fois par identité de vue, alors qu'un
/// `State(initialValue:)` construisait un `AjoutCalendrier` (appareil + journal) à chaque évaluation
/// du corps de `MainTabView`, aussitôt jeté (revue B8 de T5).
@MainActor
private final class BoiteAjoutCalendrier: ObservableObject {
    let ajout: AjoutCalendrier
    init(_ ajout: AjoutCalendrier) { self.ajout = ajout }
}

/// Injection de l'ajout au calendrier pour une session prête : une instance par epoch (la vue
/// racine des onglets est recréée à chaque changement d'identité), partagée par l'Accueil et Mes
/// missions, si bien qu'un créneau ajouté depuis l'un est « déjà ajouté » depuis l'autre.
@MainActor
private struct InjectionAjoutCalendrier: ViewModifier {
    @StateObject private var boite: BoiteAjoutCalendrier

    init(modeDemo: Bool, refusDemo: Bool, userId: String) {
        _boite = StateObject(wrappedValue: BoiteAjoutCalendrier(
            CalendarWriter.ajoutCalendrier(modeDemo: modeDemo, refusDemo: refusDemo, userId: userId)))
    }

    func body(content: Content) -> some View {
        content.environment(\.ajoutCalendrierMission, boite.ajout)
    }
}

extension View {
    /// `container` fournit le mode et la surcharge DEBUG du refus (`AppContainer.calendrierRefusDemo`).
    func ajoutCalendrier(container: AppContainer, userId: String) -> some View {
        modifier(InjectionAjoutCalendrier(modeDemo: container.isDemo, refusDemo: container.calendrierRefusDemo, userId: userId))
    }
}
