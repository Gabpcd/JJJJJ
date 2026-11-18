import SwiftUI
import JoleneCore

/// Mon score (`/soignant/score`, alias `fiabilite`, `fiabilite-legacy`) — **stub de L4-T1c**, remplacé par T9 (fichier propre à la tranche, `LOT4_PLAN.md` §4), qui passe
/// aussi sa ligne de `DestinationLien.ecranNatifLivre` à `true`. Jamais atteint avant : la destination reste le renvoi
/// web canonique. Construit par `SecondaryRouter` seulement (coupe-circuit lu avant).
struct ScoreScreen: View {
    let contexte: ContexteSecondaire

    var body: some View {
        RenvoiWebScreen(ecran: .score)
    }
}
