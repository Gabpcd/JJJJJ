import SwiftUI
import JoleneCore

/// Évaluations reçues (`/soignant/evaluations`) — **stub de L4-T1c**, remplacé par T9 (fichier propre à la tranche, `LOT4_PLAN.md` §4), qui passe
/// aussi sa ligne de `DestinationLien.ecranNatifLivre` à `true`. Jamais atteint avant : la destination reste le renvoi
/// web canonique. Construit par `SecondaryRouter` seulement (coupe-circuit lu avant).
struct EvaluationsScreen: View {
    let contexte: ContexteSecondaire

    var body: some View {
        RenvoiWebScreen(ecran: .evaluations)
    }
}
