import SwiftUI
import JoleneCore
import JoleneDesign

/// Ce dont les écrans de la messagerie du lot 4 (`MessagerieScreen`, `ConversationScreen`, `SignalementSheet`) ont
/// besoin, dans l'espace soignant (`ContexteSecondaire`) comme dans l'espace établissement (lot 5, T11) : contrôleur,
/// espace d'appel des modèles (`ContexteMessagerie`), cycle Realtime de l'app et horloge. Aucune règle ici.
@MainActor
struct ContexteEcranMessagerie {
    let controller: SessionController
    let contexte: ContexteMessagerie
    /// Cycle observé par les écrans (génération des suivis, badge).
    let cycle: CycleRealtime
    /// Cycle de l'app transmis aux modèles ; `nil` sans session de l'app (aucun canal partagé).
    let cycleAttache: CycleRealtime?
    let maintenant: () -> Date

    init(_ secondaire: ContexteSecondaire) {
        let cycle = secondaire.container.cycleMessagerie
        self.controller = secondaire.session.controller
        self.contexte = ContexteMessagerie(secondaire.snapshot)
        self.cycle = cycle ?? CycleRealtime(session: secondaire.session)
        self.cycleAttache = cycle
        let clock = secondaire.container.clock
        self.maintenant = { clock.now() }
    }

    /// Lot 5 (T11) : espace établissement ; `moi` est l'utilisateur de la session, jamais l'établissement.
    init(etablissement snapshot: EtablissementSessionSnapshot, session: SessionStore, environnement: MessagerieEtablissementEnvironnement?) {
        self.controller = session.controller
        self.contexte = ContexteMessagerie(snapshot)
        self.cycle = environnement?.cycle ?? CycleRealtime(session: session)
        self.cycleAttache = environnement?.cycle
        let clock: ClockPort = environnement?.clock ?? SystemClock()
        self.maintenant = { clock.now() }
    }
}

/// Cycle et horloge de l'app pour la messagerie de l'espace établissement, injectés une fois par
/// `EtablissementTabView` (les racines et destinations établissement ne reçoivent pas le conteneur).
struct MessagerieEtablissementEnvironnement {
    var cycle: CycleRealtime?
    var clock: ClockPort

    init(cycle: CycleRealtime?, clock: ClockPort) {
        self.cycle = cycle; self.clock = clock
    }
}

private struct MessagerieEtablissementKey: EnvironmentKey {
    static let defaultValue: MessagerieEtablissementEnvironnement? = nil
}

extension EnvironmentValues {
    /// `nil` hors de `EtablissementTabView`.
    var messagerieEtablissement: MessagerieEtablissementEnvironnement? {
        get { self[MessagerieEtablissementKey.self] }
        set { self[MessagerieEtablissementKey.self] = newValue }
    }
}

/// Badge de l'onglet Messages de l'espace établissement : `fn_messages_non_lus()` relu par le cycle (valeur serveur,
/// `9+` au-delà de 9 comme `BarreNavigation.tsx` l.405-408), jamais recalculé.
struct BadgeMessagesEtablissement: ViewModifier {
    @ObservedObject var cycle: CycleRealtime

    func body(content: Content) -> some View {
        content.badge(MessageriePresentation.badge(cycle.nonLus).map { Text($0) })
    }
}

extension View {
    @ViewBuilder func badgeMessagesEtablissement(_ cycle: CycleRealtime?) -> some View {
        if let cycle { modifier(BadgeMessagesEtablissement(cycle: cycle)) } else { self }
    }
}
