import SwiftUI
import JoleneCore

/// Route empilée d'un écran secondaire du lot 4 (L4-T1c, `docs/mobile-swift/LOT4_PLAN.md` §2.1, §3 T1c), par valeur
/// comme `MonEspaceRoute` : entrées du hub (`ActiviteSoignantSection`, route nue) et cibles des liens, des taps push et
/// du centre (`CibleNotification.secondaire`, route jetonnée par `MainTabView.presenter`).
struct SecondaireRoute: Hashable {
    let ecran: EcranSecondaire
}

/// Contexte de construction d'un écran secondaire : chaque tranche y lit ce dont son écran a besoin, sans modifier
/// `MainTabView`.
struct ContexteSecondaire {
    let container: AppContainer
    let session: SessionStore
    let snapshot: SessionSnapshot
    /// Présente une cible de l'espace (`MainTabView.presenter`) : lien d'un écran vers un autre écran, renvoi web.
    let ouvrir: (CibleNotification) -> Void
}

private struct ContexteSecondaireKey: EnvironmentKey {
    static let defaultValue: ContexteSecondaire? = nil
}

extension EnvironmentValues {
    /// Contexte des écrans secondaires, injecté au-dessus des onglets par `MainTabView` (nil hors de l'espace prêt) : les
    /// emplacements posés par T1c dans des écrans partagés (détail de mission, Explorer, barre de navigation) y
    /// construisent leurs écrans et y ouvrent leurs cibles, sans que leur tranche modifie ces écrans.
    var contexteSecondaire: ContexteSecondaire? {
        get { self[ContexteSecondaireKey.self] }
        set { self[ContexteSecondaireKey.self] = newValue }
    }
}

extension View {
    /// Enregistre les écrans secondaires sur la pile qui porte cette vue (racine du Profil) : route nue et route jetonnée
    /// (identité de l'écran liée au jeton, comme `destinationsMonEspace`).
    func destinationsSecondaires(_ contexte: ContexteSecondaire) -> some View {
        navigationDestination(for: SecondaireRoute.self) { route in
            SecondaryRouter(ecran: route.ecran, contexte: contexte)
        }
        .navigationDestination(for: PresentationJetonnee<SecondaireRoute>.self) { presentation in
            SecondaryRouter(ecran: presentation.route.ecran, contexte: contexte)
                .id(presentation.jeton)
        }
    }
}

/// Aiguillage `EcranSecondaire` → écran (switch exhaustif, une ligne par écran). Seul point de construction des écrans
/// du lot 4 : il lit le coupe-circuit `ios_natif_<ecran>_actif` (B0-bis, D18 ; fail-open, décision 15 du lot 1) et sert
/// `RenvoiWebScreen` quand il est coupé. Chaque écran est un stub (`<Ecran>Screen.swift`, un fichier par écran sous
/// `Screens/Secondaires/`) remplacé par sa tranche, qui passe aussi sa ligne de `DestinationLien.ecranNatifLivre` : un
/// écran non livré n'est jamais atteint (sa destination reste le renvoi web canonique) et ce fichier n'est plus
/// modifié après T1c.
struct SecondaryRouter: View {
    let ecran: EcranSecondaire
    let contexte: ContexteSecondaire
    /// Coupe-circuit de l'écran, fail-open tant qu'il n'est pas lu.
    @State private var ecranActif = true

    var body: some View {
        Group {
            if ecranActif { ecranNatif } else { RenvoiWebScreen(ecran: ecran) }
        }
        .task(id: ecran) { ecranActif = await drapeau() }
    }

    @ViewBuilder
    private var ecranNatif: some View {
        switch ecran {
        case .swipe:
            // Vue Swipe de l'onglet Explorer (T3b, `SwipeModeView`), jamais un écran empilé : `MainTabView.presenter`
            // ouvre Explorer ; une entrée empilée par erreur reçoit le renvoi web.
            RenvoiWebScreen(ecran: ecran)
        case .recherches: RecherchesScreen(contexte: contexte)                                   // T4
        case .disponibilites: DisponibilitesScreen(contexte: contexte)                           // T5
        case .parrainage: ParrainageScreen(contexte: contexte)                                   // T6
        case let .litiges(onglet, litigeId): LitigesScreen(onglet: onglet, litigeId: litigeId, contexte: contexte) // T8
        case .messagerie(let conversationId): MessagerieScreen(conversationId: conversationId, contexte: contexte) // T7b
        case .bulletins(let copieId): BulletinsScreen(copieId: copieId, contexte: contexte)      // T10
        case .evaluations: EvaluationsScreen(contexte: contexte)                                 // T9
        case .score: ScoreScreen(contexte: contexte)                                             // T9
        case .poolUrgence: PoolUrgenceScreen(contexte: contexte)                                 // T11
        case .exclusions: ExclusionsScreen(contexte: contexte)                                   // T11
        case .serie(let id): SerieDetailScreen(serieId: id, contexte: contexte)                  // T12
        }
    }

    private func drapeau() async -> Bool {
        guard let gateways = await contexte.session.controller.gateways(for: contexte.snapshot.epoch) else { return true }
        return await gateways.flags.ecranActif(ecran)
    }
}
