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
/// journal en mémoire ; DEBUG seulement, `JOLENE_FORCE_CALENDRIER_REFUS=1` simule un accès refusé
/// (`DemoMesMissionsTests.testCalendrierAccesRefuse`). Staging et production : EventKit et le journal
/// du compte (`jolene.calendrier.journal.<userId>`, purgé à la suppression du compte, T8). L'écriture
/// réelle est prouvée sur appareil (`RECETTE_DEVICE_LOT1.md` §4), jamais par la CI.
@MainActor
enum CalendarWriter {
    static func ajoutCalendrier(modeDemo: Bool, userId: String) -> AjoutCalendrier {
        if modeDemo {
            #if DEBUG
            let refus = ProcessInfo.processInfo.environment["JOLENE_FORCE_CALENDRIER_REFUS"] == "1"
            #else
            let refus = false
            #endif
            return AjoutCalendrier(appareil: CalendrierAppareilDemo(refuse: refus), journal: JournalCalendrierMemoire())
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

/// Injection de l'ajout au calendrier pour une session prête : une instance par epoch (la vue
/// racine des onglets est recréée à chaque changement d'identité), partagée par l'Accueil et Mes
/// missions, si bien qu'un créneau ajouté depuis l'un est « déjà présent » depuis l'autre.
@MainActor
private struct InjectionAjoutCalendrier: ViewModifier {
    @State private var ajout: AjoutCalendrier

    init(modeDemo: Bool, userId: String) {
        _ajout = State(initialValue: CalendarWriter.ajoutCalendrier(modeDemo: modeDemo, userId: userId))
    }

    func body(content: Content) -> some View {
        content.environment(\.ajoutCalendrierMission, ajout)
    }
}

extension View {
    func ajoutCalendrier(modeDemo: Bool, userId: String) -> some View {
        modifier(InjectionAjoutCalendrier(modeDemo: modeDemo, userId: userId))
    }
}
