import SwiftUI
import JoleneCore

/// Pool urgence (`/soignant/pool-urgence`) — **stub de L4-T1c**, remplacé par T11 (fichier propre à la tranche, `LOT4_PLAN.md` §4), qui passe
/// aussi sa ligne de `DestinationLien.ecranNatifLivre` à `true`. Jamais atteint avant : la destination reste le renvoi
/// web canonique. Construit par `SecondaryRouter` seulement (coupe-circuit lu avant).
struct PoolUrgenceScreen: View {
    let contexte: ContexteSecondaire

    var body: some View {
        RenvoiWebScreen(ecran: .poolUrgence)
    }
}
