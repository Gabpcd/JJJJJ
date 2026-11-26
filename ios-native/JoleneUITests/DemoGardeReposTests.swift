import XCTest

/// Recette de la garde de repos XCUITest (`GardeRepos.swift`, `docs/mobile-swift/DECISIONS_LOT2.md`, « Garde de repos
/// XCUITest — 26/11/2026 »). L'état relevé sur iPad (XCTest attend les animations de l'app sans jamais recevoir leur fin)
/// est reproduit à coup sûr par l'argument DEBUG `-JOLENE_UITEST_ANIMATION_OUVERTE 1` (`SondeAnimationOuverte`,
/// JoleneCore) : une animation UIKit répétée sans fin sur une vue de 1 pt invisible.
///
/// Ce que ces tests prouvent, et seulement cela :
/// - avec l'animation ouverte : une seule attente expirée (au moins 50 s) entre le lancement et le premier geste, relevée
///   par la garde pour ce test (la même relève écrit la ligne « Jolene diagnostic repos-xcuitest » au journal de
///   l'éclat), puis des gestes rapides (moins de 20 s chacun, contre 60 s sans la garde) ;
/// - sans l'argument : aucune relève, gestes rapides (la garde ne change rien quand aucune attente n'expire).
/// Gestes : glissements bornés sur l'écran de connexion (`drag`), qui n'activent rien. La cause de l'attente sans fin
/// après le « OK » du clavier sur iPad n'est PAS prouvée ici. Socle du job `ui` (aucun `-only-testing`).
final class DemoGardeReposTests: JoleneUITestCase {
    static let argumentAnimationOuverte = "-JOLENE_UITEST_ANIMATION_OUVERTE"
    /// Borne d'un geste quand la garde a suspendu l'attente des animations (sans elle : 60 s au moins).
    static let gesteRapide: TimeInterval = 20

    func testAnimationOuverteUneSeuleAttenteExpireePuisGestesRapides() throws {
        guard case .installee = GardeRepos.installation else {
            XCTFail("garde de repos non installée : \(String(describing: GardeRepos.installation))")
            return
        }
        let debut = ProcessInfo.processInfo.systemUptime
        launchDemo(extraArguments: [Self.argumentAnimationOuverte, "1"])
        let scroll = element("login-scroll")
        require("L'écran de connexion est affiché") { self.visible(scroll) }
        drag(scroll, fromY: 0.55, toY: 0.45)
        let jusquAuPremierGeste = ProcessInfo.processInfo.systemUptime - debut
        let relevees = GardeRepos.expirations(pendant: name)
        XCTAssertEqual(relevees.count, 1, "une attente des animations expirée, relevée une fois : \(relevees)")
        XCTAssertGreaterThanOrEqual(relevees.first?.duree ?? 0, GardeReposDecision.seuilExpiration, "attente expirée relevée")
        XCTAssertGreaterThanOrEqual(jusquAuPremierGeste, GardeReposDecision.seuilExpiration,
                                    "lancement et premier geste : l'attente des animations a bien expiré une fois")
        for (index, (de, vers)) in [(0.45, 0.55), (0.55, 0.45), (0.45, 0.55), (0.55, 0.45)].enumerated() {
            let duree = chronometrer { drag(scroll, fromY: de, toY: vers) }
            XCTAssertLessThan(duree, Self.gesteRapide, "geste \(index + 2) : attente des animations suspendue pour ce processus")
        }
        XCTAssertEqual(GardeRepos.expirations(pendant: name).count, 1, "une seule relève (et une seule ligne) par processus")
    }

    func testSansAnimationOuverteLaGardeNeChangeRien() throws {
        launchDemo()
        let scroll = element("login-scroll")
        require("L'écran de connexion est affiché") { self.visible(scroll) }
        for (index, (de, vers)) in [(0.55, 0.45), (0.45, 0.55), (0.55, 0.45), (0.45, 0.55), (0.55, 0.45)].enumerated() {
            let duree = chronometrer { drag(scroll, fromY: de, toY: vers) }
            XCTAssertLessThan(duree, Self.gesteRapide, "geste \(index + 1) : rapide sans animation ouverte")
        }
        XCTAssertEqual(GardeRepos.expirations(pendant: name), [], "aucune attente expirée, aucune ligne de la garde")
    }

    private func chronometrer(_ geste: () -> Void) -> TimeInterval {
        let debut = ProcessInfo.processInfo.systemUptime
        geste()
        return ProcessInfo.processInfo.systemUptime - debut
    }
}
