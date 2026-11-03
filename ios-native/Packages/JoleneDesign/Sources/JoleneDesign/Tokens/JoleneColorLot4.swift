import SwiftUI

/// Jetons ajoutés au lot 4 (T1b), sources `src/index.css` (`:root` puis `.dark`), relus par la garde de dérive
/// de `JoleneDesignLot4Tests`. Fichier distinct de `JoleneColor.swift` : ajouts seuls, aucune réécriture des
/// jetons des lots 0 et 1.
public extension JoleneColor {
    /// `--jolene-rose-200` : bordure décorative du bouton « Passer » du swipe (`BoutonsActionSwipe.tsx`,
    /// `border-jolene-rose-200`). Jamais une encre de texte.
    static let rose200HSL = JoleneDynamicHSL(light: JoleneHSL(326, 100, 86), dark: JoleneHSL(326, 60, 24))
    /// `--jolene-butter-400` : remplissage des étoiles (`StarRow`, bouton « Sauvegarder » : `fill-jolene-butter-400`)
    /// et bordure du bouton favori. Jamais seul porteur d'information : le contour `butter800` atteint 3:1.
    static let butter400HSL = JoleneDynamicHSL(light: JoleneHSL(50, 100, 75), dark: JoleneHSL(50, 80, 52))

    static let rose200 = Color(rose200HSL)
    static let butter400 = Color(butter400HSL)

    /// Arrêts de `.bg-gradient-celebrate` (src/index.css : `conic-gradient` rose → mauve → cyan → butter → rose,
    /// `color: #2b183d`), fond des pastilles `premium` (`ScoreBadge`). Encre : `onGradient`, ≥ 4,5:1 sur chaque arrêt.
    static let celebrateGradientStops = [roseHSL, mauveHSL, cyanHSL, butterHSL, roseHSL]
    static let celebrateGradient = AngularGradient(
        gradient: Gradient(colors: celebrateGradientStops.map { Color($0) }), center: .center)
}
