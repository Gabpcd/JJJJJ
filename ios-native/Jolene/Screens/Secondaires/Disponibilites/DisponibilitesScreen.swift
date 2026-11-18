import SwiftUI
import JoleneCore

/// Disponibilités (`/soignant/disponibilites`) — **stub de L4-T1c**, remplacé par T5 (fichier propre à la tranche, `LOT4_PLAN.md` §4), qui passe
/// aussi sa ligne de `DestinationLien.ecranNatifLivre` à `true`. Jamais atteint avant : la destination reste le renvoi
/// web canonique. Construit par `SecondaryRouter` seulement, une fois son coupe-circuit lu à vrai, absent ou
/// illisible (`PorteEcranNatif`, fail-open) : aucun `.task` de l'écran ne démarre avant la réponse du drapeau.
struct DisponibilitesScreen: View {
    let contexte: ContexteSecondaire

    var body: some View {
        RenvoiWebScreen(ecran: .disponibilites)
    }
}
