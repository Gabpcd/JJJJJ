import XCTest
import SwiftUI
import UIKit
import JoleneCore
@testable import JoleneDesign

/// Lot 2 (T9a) : `CountdownLabel`, compte à rebours de la signature (`Countdown72hSignature.tsx`). Le palier vient
/// de `EtatCompteARebours72h` (JoleneCore, testé par `CompteARebours72hTests`) ; ce composant n'en fait que la
/// couleur et l'icône du web : vert au-delà de 48 h, orange de 24 à 48 h, rouge en deçà (l.53-56), triangle
/// d'alerte à l'expiration (l.38-46). Le texte est fourni par l'écran (`TextesWeb.CompteARebours.texte`).
final class JoleneDesignLot2Tests: XCTestCase {
    func testTonDuComptesAReboursSuitLesPaliersDuWeb() {
        XCTAssertEqual(CountdownLabel.ton(EtatCompteARebours72h(restantSecondes: 62 * 3600)), .success)
        XCTAssertEqual(CountdownLabel.ton(EtatCompteARebours72h(restantSecondes: 48 * 3600)), .success, "48 h pile : vert (`heures >= 48`)")
        XCTAssertEqual(CountdownLabel.ton(EtatCompteARebours72h(restantSecondes: 48 * 3600 - 1)), .warning)
        XCTAssertEqual(CountdownLabel.ton(EtatCompteARebours72h(restantSecondes: 24 * 3600)), .warning)
        XCTAssertEqual(CountdownLabel.ton(EtatCompteARebours72h(restantSecondes: 24 * 3600 - 1)), .error)
        XCTAssertEqual(CountdownLabel.ton(EtatCompteARebours72h(restantSecondes: 0)), .error, "expiré : rouge")
    }

    func testIconeHorlogeSaufALExpiration() {
        XCTAssertEqual(CountdownLabel.symbole(EtatCompteARebours72h(restantSecondes: 1)), "clock")
        XCTAssertEqual(CountdownLabel.symbole(EtatCompteARebours72h(restantSecondes: 0)), "exclamationmark.triangle")
    }

    func testLibelleVocaliseEstLeTexteAffiche() {
        let texte = "Signature à finaliser sous 62h 00m 00s"
        XCTAssertEqual(CountdownLabel.libelleAccessibilite(texte: texte), texte, "aucun préfixe : le texte du web, tel quel")
    }

    @MainActor
    func testLeCorpsSEvalueDansUnHebergeur() {
        let vue = CountdownLabel(texte: "Signature à finaliser sous 62h 00m 00s",
                                 etat: EtatCompteARebours72h(restantSecondes: 62 * 3600), identifier: "contrat-countdown")
        let hebergeur = UIHostingController(rootView: vue)
        let taille = hebergeur.sizeThatFits(in: CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertGreaterThan(taille.height, 0)
        XCTAssertLessThanOrEqual(taille.width, 390)
    }
}
