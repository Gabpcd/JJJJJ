import SwiftUI
import JoleneCore
import JoleneDesign

/// Bandeau hors ligne de la page Présences (lot 2, T4b ; décision 2) : texte du bandeau global du web
/// (`BandeauHorsLigne.tsx` l.71, `LibellesWeb.Pointage.horsLigne`). Tant qu'il est affiché, les boutons de pointage sont
/// désactivés : aucun scan n'est envoyé ni mis en file (le code rotatif est horodaté par le serveur). Identifiant
/// `hors-ligne-bandeau`.
struct HorsLigneBandeau: View {
    var body: some View {
        InlineNotice(LibellesWeb.Pointage.horsLigne, tone: .warning, identifier: "hors-ligne-bandeau", announcesOnAppear: true)
    }
}
