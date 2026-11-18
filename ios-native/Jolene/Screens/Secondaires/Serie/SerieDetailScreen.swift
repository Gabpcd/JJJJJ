import SwiftUI
import JoleneCore

/// Détail de série (`/soignant/missions/serie/:id`, décision 11 du lot 1) — **stub de L4-T1c**, remplacé par T12 (fichier propre à la tranche, `LOT4_PLAN.md` §4), qui passe
/// aussi sa ligne de `DestinationLien.ecranNatifLivre` à `true`. Jamais atteint avant : la destination reste le renvoi
/// web canonique. Construit par `SecondaryRouter` seulement (coupe-circuit lu avant).
struct SerieDetailScreen: View {
    let serieId: String
    let contexte: ContexteSecondaire

    var body: some View {
        RenvoiWebScreen(ecran: .serie(id: serieId))
    }
}
