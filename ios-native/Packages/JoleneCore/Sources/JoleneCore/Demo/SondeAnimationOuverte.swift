#if DEBUG
import Foundation

/// Argument de lancement DEBUG de la recette de la garde de repos XCUITest (`JoleneUITests/GardeRepos.swift`,
/// `DemoGardeReposTests`) : `-JOLENE_UITEST_ANIMATION_OUVERTE 1` pose, en mode démo seulement, une animation UIKit qui ne
/// se termine jamais sur une vue de 1 pt invisible et hors de l'accessibilité (`SondeAnimationOuverteUITest`, cible de
/// l'app, compilée en DEBUG seulement). Elle reproduit à coup sûr l'état relevé sur iPad : XCTest attend les animations
/// de l'app sans jamais recevoir leur fin (« App animations complete notification not received »). Toute autre valeur,
/// ou l'absence de l'argument, ne pose rien. Jamais lu en Release.
public enum SondeAnimationOuverte {
    public static let argument = "-JOLENE_UITEST_ANIMATION_OUVERTE"

    public static func active(arguments: [String], demo: Bool) -> Bool {
        demo && ArgumentsDemo.valeur(argument, dans: arguments) == "1"
    }
}
#endif
