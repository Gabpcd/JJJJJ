import UIKit

/// Feuille de partage du système (lot 2, T9a ; `LOT2_PLAN.md` §3 T9a) pour la copie temporaire de l'original
/// contrôlé d'un contrat (`Contrat-<numéro>.html`, `FichierContratTemporaire`, protection `complete`, exclue de la
/// sauvegarde). Présentée par UIKit au-dessus de la scène active (popover ancré au centre de la fenêtre sur iPad) ;
/// `aLaFermeture` est appelé une seule fois, quand la feuille se ferme (partage fait ou annulé), pour effacer la
/// copie. Jamais d'URL signée : seul le fichier local est partagé.
@MainActor
enum ShareSheet {
    /// Présente la feuille pour `fichier` ; faux (et `aLaFermeture` non appelé) si aucune fenêtre ne peut la porter.
    @discardableResult
    static func presenter(fichier: URL, aLaFermeture: @escaping @MainActor @Sendable () -> Void) -> Bool {
        guard let presentateur = presentateurCourant() else { return false }
        let feuille = UIActivityViewController(activityItems: [fichier], applicationActivities: nil)
        let fermeture = Fermeture()
        feuille.completionWithItemsHandler = { _, _, _, _ in
            MainActor.assumeIsolated {
                guard !fermeture.faite else { return }
                fermeture.faite = true
                aLaFermeture()
            }
        }
        if let popover = feuille.popoverPresentationController {
            popover.sourceView = presentateur.view
            popover.sourceRect = CGRect(x: presentateur.view.bounds.midX, y: presentateur.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        presentateur.present(feuille, animated: true)
        return true
    }

    /// Fermeture déjà signalée (la feuille peut rappeler son gestionnaire).
    @MainActor
    private final class Fermeture {
        var faite = false
    }

    /// Contrôleur le plus haut de la fenêtre clé de la scène au premier plan.
    private static func presentateurCourant() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var courant = scene?.windows.first { $0.isKeyWindow }?.rootViewController ?? scene?.windows.first?.rootViewController
        while let presente = courant?.presentedViewController { courant = presente }
        return courant
    }
}
