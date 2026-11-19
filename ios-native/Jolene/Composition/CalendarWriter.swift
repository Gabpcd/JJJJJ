import EventKit
import SwiftUI
import JoleneCore
#if DEBUG
import os
#endif

/// Ajout au calendrier (lot 1, T5, décision 18) : câblage du point d'extension posé par T3
/// (`AjoutCalendrierMission`). Les règles (un événement par créneau PREVISIONNEL d'un planning
/// complet, journal de dédoublonnage, accord refusé, échecs partiels) sont celles d'`AjoutCalendrier`
/// (JoleneCore, testées par `AjoutCalendrierTests` avec un double d'`EKEventStore`) ; ce fichier ne
/// fournit que l'appareil EventKit et l'injection au-dessus des onglets (Accueil et Mes missions).
///
/// Démonstration : `CalendrierAppareilDemo` (aucune demande système, aucune écriture réelle, chaque
/// issue suivie de `IssueAjoutCalendrier.mentionDemo`) et un journal en mémoire ; `refusDemo`
/// (surcharge DEBUG `JOLENE_FORCE_CALENDRIER_REFUS=1`, lue par `AppContainer` avec les autres
/// surcharges, `AppContainer.calendrierRefusDemo`) simule un accès refusé
/// (`DemoMesMissionsTests.testMesMissionsPanneRepriseChargerPlusEtCalendrierRefuse`). Staging et
/// production : EventKit et le journal du compte (`jolene.calendrier.journal.<userId>`, purgé à la
/// suppression du compte, T8).
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
/// événement n'est relu (même mécanisme sur les deux versions : journal local). Une erreur de la
/// demande d'accès est levée (message d'échec générique, `AjoutCalendrier`) et journalisée en DEBUG,
/// jamais présentée comme un refus de l'utilisateur (revue B8 de T5, 2e passe).
@MainActor
final class CalendrierEventKit: CalendrierAppareil {
    /// Aucun calendrier par défaut pour les nouveaux événements (réglage de l'appareil).
    struct CalendrierIndisponible: Error {}
    /// Demande d'accès en erreur (EventKit : `completion(false, error)`), distincte d'un refus.
    struct DemandeAccesEnErreur: Error {}

    private lazy var store = EKEventStore()

    func acces() -> AccesCalendrier {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .nonDetermine
        case .denied, .restricted: return .refuse
        // Accès complet (iOS 16 `authorized`, iOS 17+ `fullAccess`) ou écriture seule (iOS 17+).
        default: return .accorde
        }
    }

    func demanderAcces() async throws -> Bool {
        try await withCheckedThrowingContinuation { (suite: CheckedContinuation<Bool, any Error>) in
            let reponse: @Sendable (Bool, (any Error)?) -> Void = { accorde, erreur in
                // Accordé : succès, quelle que soit l'erreur jointe. Refusé sans erreur : choix de
                // l'utilisateur. Refusé avec erreur : panne EventKit, jamais un refus.
                if !accorde, let erreur {
                    Self.journaliser(erreur)
                    suite.resume(throwing: DemandeAccesEnErreur())
                } else {
                    suite.resume(returning: accorde)
                }
            }
            if #available(iOS 17.0, *) {
                store.requestWriteOnlyAccessToEvents(completion: reponse)
            } else {
                store.requestAccess(to: .event, completion: reponse)
            }
        }
    }

    /// Journal DEBUG de l'erreur EventKit : domaine et code seulement (aucune donnée de mission). Rien
    /// en Release.
    nonisolated private static func journaliser(_ erreur: any Error) {
        #if DEBUG
        let ns = erreur as NSError
        Logger(subsystem: "app.jolene", category: "calendrier")
            .debug("Demande d'accès au calendrier en erreur : \(ns.domain, privacy: .public) \(ns.code, privacy: .public)")
        #endif
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
