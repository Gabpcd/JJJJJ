import XCTest
@testable import JoleneCore

/// `SuiviFinDuFil` (revue fraîche de la PR #1185, mineur 1) : un changement de hauteur du fil ne ramène en bas que si la
/// fin était visible avant, ou juste après un envoi ; un fil dont l'historique est relu garde sa position.
final class SuiviFinDuFilTests: XCTestCase {
    private let maintenant = Date(timeIntervalSince1970: 1_000_000)

    func testFinVisibleSeulementSiLeRepereEstDansLaZone() {
        XCTAssertTrue(SuiviFinDuFil.finVisible(hautDuRepere: 80, hauteurVisible: 83.5), "repère dans la zone")
        XCTAssertTrue(SuiviFinDuFil.finVisible(hautDuRepere: 83.5 + 24, hauteurVisible: 83.5), "repère à la tolérance")
        XCTAssertFalse(SuiviFinDuFil.finVisible(hautDuRepere: 83.5 + 25, hauteurVisible: 83.5), "repère sous le bas visible")
        XCTAssertFalse(SuiviFinDuFil.finVisible(hautDuRepere: 900, hauteurVisible: 480.5), "historique relu : fin loin dessous")
        XCTAssertFalse(SuiviFinDuFil.finVisible(hautDuRepere: 0, hauteurVisible: 0), "hauteur inconnue : non visible")
    }

    /// Fin visible avant le changement (ouverture du clavier, rotation) : le fil suit.
    func testFinVisibleAvantLeChangementSuit() {
        XCTAssertTrue(SuiviFinDuFil.suivreApresChangementDeHauteur(finVisibleAvant: true, dernierEnvoi: nil, maintenant: maintenant))
    }

    /// Historique relu (fin non visible), aucun envoi récent : le fil ne bouge pas.
    func testHistoriqueReluNeBougePas() {
        XCTAssertFalse(SuiviFinDuFil.suivreApresChangementDeHauteur(finVisibleAvant: false, dernierEnvoi: nil, maintenant: maintenant))
        let ancien = maintenant.addingTimeInterval(-SuiviFinDuFil.fenetreApresEnvoi)
        XCTAssertFalse(SuiviFinDuFil.suivreApresChangementDeHauteur(finVisibleAvant: false, dernierEnvoi: ancien, maintenant: maintenant),
                       "envoi trop ancien : la relecture de l'historique l'emporte")
    }

    /// Juste après un envoi, le clavier se ferme puis se rouvre : le fil suit même si la fin venait de passer sous le bas.
    func testJusteApresUnEnvoiSuit() {
        let envoi = maintenant.addingTimeInterval(-0.1)
        XCTAssertTrue(SuiviFinDuFil.suivreApresChangementDeHauteur(finVisibleAvant: false, dernierEnvoi: envoi, maintenant: maintenant))
        let futur = maintenant.addingTimeInterval(1)
        XCTAssertFalse(SuiviFinDuFil.suivreApresChangementDeHauteur(finVisibleAvant: false, dernierEnvoi: futur, maintenant: maintenant),
                       "horloge incohérente : jamais suivi")
    }
}
