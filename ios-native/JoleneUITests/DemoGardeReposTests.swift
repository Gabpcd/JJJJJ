import XCTest

/// Témoin de la garde de repos XCUITest (`GardeRepos.swift`, `docs/mobile-swift/DECISIONS_LOT2.md`, « Garde de repos
/// XCUITest — 26/11/2026 »).
///
/// Ce que ce test prouve, et seulement cela :
/// - la garde est posée (sinon `GardeRepos.installation` le dit : échec net, à relire après tout changement d'Xcode) ;
/// - quand aucune attente n'expire, elle ne change rien : aucune relève, gestes rapides (moins de 20 s chacun).
/// Il ne prouve PAS l'efficacité de la garde en condition de gel : la recette par animation UIKit répétée sans fin ne
/// faisait pas expirer l'attente des animations sous iOS 26.2 et Xcode 26.4.1 (série 45737758238), elle est retirée.
/// Gestes : glissements bornés sur l'écran de connexion (`drag`), qui n'activent rien. Socle du job `ui`.
final class DemoGardeReposTests: JoleneUITestCase {
    /// Borne d'un geste sans attente expirée (une attente des animations expirée en coûte 60).
    static let gesteRapide: TimeInterval = 20

    /// Indépendance de l'ordre (revue B8 de #1195) : l'app laissée en vie par le test précédent est arrêtée AVANT que la
    /// garde ne passe à ce test (`GardeRepos.debutDeTest`, appelé par `super.setUpWithError`). Une attente expirée
    /// pendant cet arrêt reste attribuée au test précédent.
    override func setUpWithError() throws {
        let application = app
        MainActor.assumeIsolated {
            if application.state != .notRunning { application.terminate() }
        }
        try super.setUpWithError()
    }

    func testGardePoseeSansEffetQuandAucuneAttenteNExpire() throws {
        guard case .installee = GardeRepos.installation else {
            XCTFail("garde de repos non installée : \(String(describing: GardeRepos.installation))")
            return
        }
        launchDemo()
        let scroll = element("login-scroll")
        require("L'écran de connexion est affiché") { self.visible(scroll) }
        for (index, (de, vers)) in [(0.55, 0.45), (0.45, 0.55), (0.55, 0.45), (0.45, 0.55), (0.55, 0.45)].enumerated() {
            let debut = ProcessInfo.processInfo.systemUptime
            drag(scroll, fromY: de, toY: vers)
            XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - debut, Self.gesteRapide, "geste \(index + 1) : rapide")
        }
        XCTAssertEqual(GardeRepos.expirations(pendant: name), [], "aucune attente expirée, aucune ligne de la garde")
    }
}
