import SwiftUI
import UIKit

/// Bouton « OK » au-dessus des pavés sans touche Entrée (numérique, décimal, téléphonique) : il ferme le clavier sans
/// défilement. Sans lui, seul un glissement de la page (`.scrollDismissesKeyboard`) ou un toucher hors du champ fermait le
/// pavé ; au run 43889328109 (iPhone 17, iOS 26.2), la fermeture du pavé pendant un glissement a gelé le serveur de rendu
/// du simulateur (DECISIONS_LOT2, « Gel iPhone CI — 16/11/2026 »). « OK » est un libellé d'interface standard, pas un
/// texte du web ni un texte juridique. Une seule source pour SwiftUI (`boutonOKClavier(_:actif:)`) et UIKit
/// (`barreUIKit(cible:action:)`, champ OTP) : même libellé, même identifiant `clavier-ok` (PRINCIPES §6).
public enum BoutonClavierOK {
    nonisolated public static let libelle = "OK"
    nonisolated public static let identifiant = "clavier-ok"

    /// Claviers sans touche Entrée : le bouton leur est ajouté. Les autres claviers gardent leur touche Entrée
    /// (`submitLabel`) et n'en reçoivent pas.
    nonisolated public static func requis(pour clavier: UIKeyboardType) -> Bool {
        switch clavier {
        case .numberPad, .decimalPad, .phonePad, .asciiCapableNumberPad: return true
        default: return false
        }
    }

    /// Barre d'accessoire d'un `UITextField` (champ OTP de la signature) : espace flexible, puis « OK ».
    @MainActor
    public static func barreUIKit(cible: AnyObject, action: Selector) -> UIToolbar {
        // Largeur non nulle dès la création : une barre de largeur nulle produit des conflits de contraintes.
        let barre = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let ok = UIBarButtonItem(title: libelle, style: .done, target: cible, action: action)
        ok.accessibilityIdentifier = identifiant
        barre.items = [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), ok]
        barre.sizeToFit()
        return barre
    }
}

public extension View {
    /// Ajoute « OK » au-dessus du clavier tant que le champ a le focus ; un toucher rend le focus (le pavé se ferme sans
    /// défilement). Barre conditionnée au focus du champ : deux champs numériques d'un même écran (pointage des missions
    /// a et b) n'empilent jamais deux boutons.
    func boutonOKClavier(_ focus: FocusState<Bool>.Binding, actif: Bool = true) -> some View {
        modifier(BoutonOKClavierModifier(focus: focus, actif: actif))
    }
}

private struct BoutonOKClavierModifier: ViewModifier {
    @FocusState.Binding var focus: Bool
    let actif: Bool

    init(focus: FocusState<Bool>.Binding, actif: Bool) {
        self._focus = focus
        self.actif = actif
    }

    func body(content: Content) -> some View {
        content.toolbar {
            if actif && focus {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(BoutonClavierOK.libelle) { focus = false }
                        .accessibilityIdentifier(BoutonClavierOK.identifiant)
                }
            }
        }
    }
}
