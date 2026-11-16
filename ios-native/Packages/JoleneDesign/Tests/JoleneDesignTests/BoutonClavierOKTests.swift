import XCTest
import SwiftUI
import UIKit
@testable import JoleneDesign

/// Bouton « OK » au-dessus des pavés sans touche Entrée (DECISIONS_LOT2, « Gel iPhone CI — 16/11/2026 ») : un pavé
/// numérique, décimal ou téléphonique se ferme sans défilement. Partie calculable vérifiée ici (libellé, identifiant,
/// claviers concernés, barre UIKit du champ OTP) ; le parcours visible (bouton unique, clavier fermé avant tout
/// défilement) est prouvé par les XCUITest du pointage (`DemoPointageTests`, `DemoPointageEtatsTests`) et de la signature
/// (`DemoSignatureContratTests`), via `fermerLePaveNumerique()`.
final class BoutonClavierOKTests: XCTestCase {
    func testLibelleEtIdentifiantStables() {
        XCTAssertEqual(BoutonClavierOK.libelle, "OK", "libellé d'interface standard, aucun texte juridique")
        XCTAssertEqual(BoutonClavierOK.identifiant, "clavier-ok", "identifiant atteint par les XCUITest (PRINCIPES §6)")
    }

    func testSeulsLesPavesSansToucheEntreePortentLeBouton() {
        for clavier: UIKeyboardType in [.numberPad, .decimalPad, .phonePad, .asciiCapableNumberPad] {
            XCTAssertTrue(BoutonClavierOK.requis(pour: clavier), "pavé sans touche Entrée : \(clavier.rawValue)")
        }
        for clavier: UIKeyboardType in [.default, .emailAddress, .webSearch, .asciiCapable, .URL, .numbersAndPunctuation, .twitter, .namePhonePad] {
            XCTAssertFalse(BoutonClavierOK.requis(pour: clavier), "clavier avec touche Entrée : \(clavier.rawValue)")
        }
    }

    /// Chaque nature de saisie de `JoleneTextField` suit son clavier : téléphone, code, montant, entier, NIR, SIRET et code
    /// postal ont le bouton ; e-mail, recherche, noms et mots de passe gardent leur touche Entrée.
    func testNaturesDeSaisieDeJoleneTextField() {
        let avecBouton: Set<JoleneInputKind> = [.telephone, .otp, .montant, .entier, .nir, .siret, .codePostal]
        for kind in JoleneInputKind.allCases {
            XCTAssertEqual(JoleneInputTraits.resolve(kind).sansToucheEntree, avecBouton.contains(kind), "\(kind.rawValue)")
        }
    }

    @MainActor
    func testBarreUIKitPorteLeBoutonOK() {
        let cible = Cible()
        let barre = BoutonClavierOK.barreUIKit(cible: cible, action: #selector(Cible.fermer))
        let items = barre.items ?? []
        XCTAssertEqual(items.count, 2, "espace flexible puis « OK », à droite comme la barre SwiftUI")
        let ok = items.last
        XCTAssertEqual(ok?.title, "OK")
        XCTAssertEqual(ok?.accessibilityIdentifier, "clavier-ok")
        XCTAssertEqual(ok?.style, .done)
        XCTAssertTrue(ok?.target === cible)
        XCTAssertEqual(ok?.action, #selector(Cible.fermer))
        XCTAssertGreaterThan(barre.frame.height, 0, "barre dimensionnée (aucune contrainte à largeur nulle)")
    }

    /// Le champ OTP (UIKit) porte la même barre : rendu dans une fenêtre, son `UITextField` a l'accessoire « OK », dont
    /// l'action rend le focus (le pavé se ferme sans défilement).
    @MainActor
    func testChampOTPPorteLaBarreEtLaFermetureRendLeFocus() throws {
        let hote = UIHostingController(rootView: OTPField(code: .constant("")))
        let fenetre = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        fenetre.rootViewController = hote
        fenetre.makeKeyAndVisible()
        hote.view.layoutIfNeeded()
        let champ = try XCTUnwrap(Self.premierChamp(dans: hote.view), "UITextField de l'OTPField rendu")
        let barre = try XCTUnwrap(champ.inputAccessoryView as? UIToolbar, "accessoire du pavé")
        let ok = try XCTUnwrap(barre.items?.last)
        XCTAssertEqual(ok.accessibilityIdentifier, "clavier-ok")
        XCTAssertEqual(ok.title, "OK")
        XCTAssertTrue(champ.becomeFirstResponder())
        XCTAssertTrue(champ.isFirstResponder, "focus pris")
        let action = try XCTUnwrap(ok.action)
        let cible = try XCTUnwrap(ok.target as? NSObject, "cible vivante")
        XCTAssertTrue(cible.responds(to: action), "la cible répond à l'action de « OK »")
        _ = cible.perform(action)
        XCTAssertFalse(champ.isFirstResponder, "« OK » ferme le pavé")
        fenetre.isHidden = true
    }

    @MainActor
    private static func premierChamp(dans vue: UIView) -> UITextField? {
        if let champ = vue as? UITextField { return champ }
        for sous in vue.subviews { if let champ = premierChamp(dans: sous) { return champ } }
        return nil
    }

    @MainActor
    private final class Cible: NSObject {
        @objc func fermer() {}
    }
}
