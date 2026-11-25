import XCTest
@testable import JoleneCore

/// `SuiviFinDuFil` (revue fraîche de la PR #1185, mineur 1 ; revue du delta, majeurs 1 et 2) : un changement de hauteur
/// du fil ne ramène en bas que si la fin était visible avant, ou juste après un envoi daté sur l'horloge d'interface ; la
/// visibilité est recalculée des valeurs mémorisées, quel que soit l'ordre des mesures.
final class SuiviFinDuFilTests: XCTestCase {
    /// Horloge d'interface pilotée (secondes).
    private final class Horloge: @unchecked Sendable {
        var t: TimeInterval = 1_000
        var interface: HorlogeInterface { HorlogeInterface { [unowned self] in self.t } }
    }

    func testFinVisibleSeulementSiLeRepereEstDansLaZone() {
        XCTAssertTrue(SuiviFinDuFil.finVisible(hautDuRepere: 80, hauteurVisible: 83.5), "repère dans la zone")
        XCTAssertTrue(SuiviFinDuFil.finVisible(hautDuRepere: 83.5 + 24, hauteurVisible: 83.5), "repère à la tolérance")
        XCTAssertFalse(SuiviFinDuFil.finVisible(hautDuRepere: 83.5 + 25, hauteurVisible: 83.5), "repère sous le bas visible")
        XCTAssertFalse(SuiviFinDuFil.finVisible(hautDuRepere: 0, hauteurVisible: 0), "hauteur inconnue : non visible")
        XCTAssertFalse(SuiviFinDuFil().finVisible, "repère non mesuré : non visible")
    }

    /// Branche « fin visible » sans aucun envoi : fil court (le repère ne bouge jamais), clavier ouvert sur iPad paysage
    /// (480,5 → 83,5 pt) : les derniers messages suivent (majeur 2 ; `8651dbe9` les suivait).
    func testFilCourtClavierOuvertSansEnvoiSuit() {
        var suivi = SuiviFinDuFil()
        suivi.hauteurMesuree(480.5)
        suivi.repere(330)
        XCTAssertTrue(suivi.finVisible)
        XCTAssertTrue(suivi.hauteurChangee(83.5, a: 1_000), "fin visible avant le clavier : suivie")
        XCTAssertNil(suivi.dernierEnvoi, "aucun envoi : seule la branche « fin visible » a décidé")
    }

    /// L'ordre des `onAppear` (repère mesuré avant la hauteur) ne change pas la décision : la visibilité est recalculée.
    func testOrdreDesMesuresSansEffet() {
        var repereDAbord = SuiviFinDuFil()
        repereDAbord.repere(330)
        XCTAssertFalse(repereDAbord.finVisible, "hauteur inconnue")
        repereDAbord.hauteurMesuree(480.5)
        XCTAssertTrue(repereDAbord.finVisible, "recalculée dès que la hauteur est connue")
        var hauteurDAbord = SuiviFinDuFil()
        hauteurDAbord.hauteurMesuree(480.5)
        hauteurDAbord.repere(330)
        XCTAssertEqual(repereDAbord, hauteurDAbord)
        XCTAssertTrue(repereDAbord.hauteurChangee(83.5, a: 1_000))
    }

    /// Historique relu (repère loin sous le bas visible), aucun envoi : le fil ne bouge pas.
    func testHistoriqueReluNeBougePas() {
        var suivi = SuiviFinDuFil()
        suivi.hauteurMesuree(83.5)
        suivi.repere(600)
        XCTAssertFalse(suivi.hauteurChangee(50, a: 1_000), "composeur qui grandit : position de lecture gardée")
        XCTAssertFalse(suivi.hauteurChangee(480.5, a: 1_001), "clavier fermé : position de lecture gardée")
    }

    /// Branche « envoi récent », horloge d'interface pilotée : suit dans la fenêtre, plus au-delà, même si la fin vient
    /// de passer sous le bas visible (le clavier se ferme puis se rouvre à l'envoi).
    func testEnvoiRecentSuitPuisLaFenetreSeFerme() {
        let horloge = Horloge()
        var suivi = SuiviFinDuFil()
        suivi.hauteurMesuree(83.5)
        suivi.repere(600)
        suivi.envoi(a: horloge.interface.maintenant())
        horloge.t += 0.1
        XCTAssertTrue(suivi.hauteurChangee(480.5, a: horloge.interface.maintenant()), "0,1 s après l'envoi : suivi")
        horloge.t += SuiviFinDuFil.fenetreApresEnvoi
        XCTAssertFalse(suivi.hauteurChangee(83.5, a: horloge.interface.maintenant()), "fenêtre close : la règle de visibilité décide")
    }

    /// L'utilisateur relit l'historique après un envoi : passé la fenêtre, un changement de hauteur ne le ramène pas en bas.
    func testHistoriqueReluApresUnEnvoiNeBougePas() {
        let horloge = Horloge()
        var suivi = SuiviFinDuFil()
        suivi.hauteurMesuree(83.5)
        suivi.repere(80)
        suivi.envoi(a: horloge.interface.maintenant())
        horloge.t += 5
        suivi.repere(400) // l'utilisateur remonte dans le fil
        XCTAssertFalse(suivi.hauteurChangee(50, a: horloge.interface.maintenant()))
    }

    /// Horloge incohérente (envoi daté dans le futur) : jamais suivi au titre de l'envoi.
    func testEnvoiDansLeFuturNeSuitPas() {
        var suivi = SuiviFinDuFil()
        suivi.hauteurMesuree(83.5)
        suivi.envoi(a: 2_000)
        XCTAssertFalse(suivi.envoiRecent(a: 1_000))
        XCTAssertFalse(suivi.hauteurChangee(50, a: 1_000))
    }

    /// Hauteur encore inconnue : retenue sans décision.
    func testPremiereHauteurSansDecision() {
        var suivi = SuiviFinDuFil()
        suivi.repere(10)
        XCTAssertFalse(suivi.hauteurChangee(480.5, a: 1_000))
        XCTAssertEqual(suivi.hauteurVisible, 480.5)
    }

    /// L'horloge du système est monotone et avance (jamais figée comme l'horloge démo).
    func testHorlogeSystemeAvance() {
        let a = HorlogeInterface.systeme.maintenant()
        let b = HorlogeInterface.systeme.maintenant()
        XCTAssertGreaterThanOrEqual(b, a)
        XCTAssertGreaterThan(a, 0)
    }
}
