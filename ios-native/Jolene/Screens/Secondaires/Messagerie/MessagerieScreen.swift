import SwiftUI
import JoleneCore

/// Messagerie (`/soignant/messagerie?conv=`) — **stub de L4-T1c**, remplacé par T7b (fichier propre à la tranche, `LOT4_PLAN.md` §4), qui passe
/// aussi sa ligne de `DestinationLien.ecranNatifLivre` à `true`. Jamais atteint avant : la destination reste le renvoi
/// web canonique. Construit par `SecondaryRouter` seulement (coupe-circuit lu avant).
struct MessagerieScreen: View {
    let conversationId: String?
    let contexte: ContexteSecondaire

    var body: some View {
        RenvoiWebScreen(ecran: .messagerie(conversationId: conversationId))
    }
}
