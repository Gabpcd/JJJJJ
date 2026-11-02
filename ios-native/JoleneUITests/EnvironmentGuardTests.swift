import XCTest

/// Garde d'environnement (plan §4.2, critère de sortie lot 0) : une clé secrète injectée
/// en staging doit produire l'écran bloquant `env-blocked`, sans aucun autre écran.
/// L'injection `JOLENE_FORCE_BAD_KEY` n'est honorée par l'app qu'en build DEBUG.
final class EnvironmentGuardTests: JoleneUITestCase {
    func testSecretKeyIsRefusedWithBlockingScreen() throws {
        app.launchArguments = ["-JOLENE_MODE", "staging"]
        app.launchEnvironment = ["JOLENE_FORCE_BAD_KEY": "sb_secret_x"]
        app.launch()
        applyOrientation()

        let blocked = element("env-blocked")
        require("L'écran bloquant d'environnement est visible") { self.visible(blocked) }
        let message = element("env-blocked-message")
        require("Le message de refus est affiché") { message.exists && !message.label.isEmpty }
        XCTAssertTrue(message.label.contains("secrète"), "Le refus nomme la clé secrète (sans la citer)")
        XCTAssertFalse(message.label.contains("sb_secret_x"), "La valeur de la clé ne doit jamais apparaître à l'écran")
        XCTAssertTrue(message.label.contains("staging"), "L'environnement refusé est nommé")
        XCTAssertTrue(element("env-blocked-open-web").exists, "Le bouton Ouvrir jolene.app est proposé")
        XCTAssertFalse(element("login-scroll").exists, "Aucun écran de connexion ne doit s'afficher")
        XCTAssertFalse(tabBarExists, "Aucune barre d'onglets ne doit s'afficher")
        record("\(proofPrefix)-env-blocked")
    }
}
