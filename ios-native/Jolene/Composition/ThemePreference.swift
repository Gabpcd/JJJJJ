import SwiftUI
import UIKit
import JoleneCore

/// Thème de l'app (lot 3, T11, D16) appliqué à la racine (`JoleneApp`, une ligne) : `preferredColorScheme`
/// (nil = thème de l'appareil) et, en plus, `overrideUserInterfaceStyle` des fenêtres de la scène. Le second
/// couvre deux limites connues de `preferredColorScheme` sous iOS 16 : le retour à « Système » (nil) n'est pas
/// toujours propagé à une fenêtre déjà forcée, et les contrôleurs UIKit présentés (feuille de partage de
/// l'export) ne suivent que le style de la fenêtre. Choix lu dans `PreferenceThemeModel` (par appareil).
struct ThemeRacine: ViewModifier {
    @ObservedObject var theme: PreferenceThemeModel

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(theme.choix.schemaCouleurs)
            .onAppear { Self.appliquerAuxFenetres(theme.choix) }
            .onChange(of: theme.choix) { Self.appliquerAuxFenetres($0) }
    }

    @MainActor
    private static func appliquerAuxFenetres(_ choix: ChoixTheme) {
        for scene in UIApplication.shared.connectedScenes {
            guard let fenetres = (scene as? UIWindowScene)?.windows else { continue }
            for fenetre in fenetres { fenetre.overrideUserInterfaceStyle = choix.styleInterface }
        }
    }
}

extension ChoixTheme {
    /// Schéma imposé à SwiftUI ; nil = celui de l'appareil.
    var schemaCouleurs: ColorScheme? {
        switch self {
        case .systeme: return nil
        case .clair: return .light
        case .sombre: return .dark
        }
    }

    var styleInterface: UIUserInterfaceStyle {
        switch self {
        case .systeme: return .unspecified
        case .clair: return .light
        case .sombre: return .dark
        }
    }
}
