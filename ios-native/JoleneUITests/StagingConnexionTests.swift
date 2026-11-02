import XCTest

/// Connexion réelle STAGING (plan §5 lot 0, §11 jours 6-7 ; PORTE_LOT0 1.1, 1.3, 6.2).
/// Lancé uniquement par `ios-swift-staging.yml` (`-only-testing:JoleneUITests/StagingConnexionTests`,
/// scheme `Jolene-Staging`) avec la cohorte TEST dans `JOLENE_AUTH_COHORT_JSON` (runner seulement,
/// jamais dans l'environnement de l'app). Hors de ce contexte le test est ignoré (`XCTSkip`) ;
/// le job UI démo l'exclut explicitement (`-skip-testing`).
///
/// Assertions : écran Accueil (`tab-accueil`) visible, rôle affiché `SOIGNANT` (valeur renvoyée par
/// `fn_get_my_role` via le port de rôle), session restaurée après arrêt du processus (Keychain),
/// déconnexion. Aucune valeur saisie n'est journalisée ni jointe : les pièces jointes sont masquées.
final class StagingConnexionTests: JoleneUITestCase {
    private struct Actor {
        let email: String
        let password: String
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        let environment = ProcessInfo.processInfo.environment
        guard environment["JOLENE_MODE"] == "staging" else {
            throw XCTSkip("Connexion STAGING : JOLENE_MODE=staging absent du runner (lancé hors ios-swift-staging.yml).")
        }
        guard let cohort = environment["JOLENE_AUTH_COHORT_JSON"], !cohort.isEmpty else {
            throw XCTSkip("Connexion STAGING : cohorte TEST absente (JOLENE_AUTH_COHORT_JSON).")
        }
    }

    /// Lit l'acteur A de la cohorte (schéma `native-auth-staging-v1`, policy.mjs) sans rien journaliser.
    private func actorA() throws -> Actor {
        let raw = ProcessInfo.processInfo.environment["JOLENE_AUTH_COHORT_JSON"] ?? ""
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any], "cohorte illisible")
        XCTAssertEqual(json["purpose"] as? String, "native-auth-staging-v1")
        XCTAssertEqual(json["projectRef"] as? String, "mejpriaetwgtcstbgfid", "STAGING uniquement")
        let actors = try XCTUnwrap(json["actors"] as? [[String: Any]])
        let a = try XCTUnwrap(actors.first { ($0["alias"] as? String) == "A" }, "acteur A absent")
        let email = try XCTUnwrap(a["email"] as? String)
        let password = try XCTUnwrap(a["password"] as? String)
        XCTAssertTrue(email.hasSuffix("@example.invalid"), "la cohorte n'emploie que des adresses invalides")
        return Actor(email: email, password: password)
    }

    private func launchStaging() {
        app.launchArguments = ["-JOLENE_MODE", "staging"]
        app.launchEnvironment = [:] // jamais la cohorte dans l'environnement de l'app
        app.launch()
        applyOrientation()
    }

    func testConnexionStagingAccueilRoleRestaurationDeconnexion() throws {
        let actor = try actorA()
        launchStaging()

        // 1. Aucun écran bloquant : la clé publishable STAGING et le ref du projet sont acceptés.
        require("L'écran de connexion STAGING est affiché", timeout: 30) { self.visible(self.element("login-scroll")) }
        XCTAssertFalse(element("env-blocked").exists, "la garde d'environnement accepte la configuration STAGING")
        XCTAssertFalse(element("login-demo-banner").exists, "pas de bandeau démo en STAGING")

        // 2. Connexion réelle (email + mot de passe de l'acteur A ; valeurs jamais jointes).
        let scroll = element("login-scroll")
        let email = element("login-email")
        focus(email, in: scroll)
        email.typeText(actor.email)
        let password = element("login-password")
        email.typeText("\n")
        if !hasKeyboardFocus(password) { focus(password, in: scroll) }
        require("Le mot de passe a le focus clavier") { self.hasKeyboardFocus(password) }
        password.typeText(actor.password)
        let submit = element("login-submit")
        require("Le bouton de connexion est activé") { submit.isEnabled }
        if app.keyboards.firstMatch.exists, !visible(submit) {
            scrollTo(submit, in: element("login-scroll"))
        }
        submit.tap()

        // 3. Accueil visible, rôle SOIGNANT (réponse serveur fn_get_my_role via le port de rôle).
        require("La session STAGING est prête : Accueil affiché", timeout: 60) {
            self.tabBarExists && self.visible(self.element("placeholder-accueil"))
        }
        XCTAssertFalse(element("login-error").exists, "aucune erreur de connexion")
        XCTAssertFalse(element("access-blocked").exists, "le compte TEST est un soignant servi nativement")
        tabButton("tab-profil", label: "Profil").tap()
        let role = element("profile-role")
        require("Le rôle est affiché") { role.exists && !role.label.isEmpty }
        XCTAssertTrue(role.label.contains("SOIGNANT"), "rôle renvoyé par fn_get_my_role : SOIGNANT")
        XCTAssertTrue(element("profile-version").label.contains("staging"), "environnement staging affiché")
        attachRedactedProof(name: "\(proofPrefix)-staging-accueil", actor: actor)

        // 4. Restauration après arrêt du processus : la session Keychain rouvre l'espace sans saisie.
        app.terminate()
        launchStaging()
        require("La session est restaurée après arrêt (Keychain)", timeout: 60) {
            self.tabBarExists && self.visible(self.element("placeholder-accueil"))
        }
        XCTAssertFalse(element("login-scroll").exists, "aucune saisie demandée après restauration")

        // 5. Déconnexion : retour à l'écran de connexion sans message d'erreur.
        tabButton("tab-profil", label: "Profil").tap()
        tap("logout-button")
        require("La déconnexion ramène à l'écran de connexion", timeout: 30) { self.visible(self.element("login-scroll")) }
        XCTAssertFalse(tabBarExists)
        XCTAssertFalse(element("login-error").exists)

        // 6. Après déconnexion, un nouveau lancement ne restaure rien.
        app.terminate()
        launchStaging()
        require("Aucune session restaurée après déconnexion", timeout: 30) { self.visible(self.element("login-scroll")) }
        XCTAssertFalse(tabBarExists)
    }

    /// Dump d'accessibilité avec l'email et le mot de passe de l'acteur masqués ; aucune capture
    /// d'écran (elle pourrait montrer l'email du compte TEST).
    private func attachRedactedProof(name: String, actor: Actor) {
        var dump = app.debugDescription
        for value in [actor.email, actor.password] where !value.isEmpty {
            dump = dump.replacingOccurrences(of: value, with: "[PRIVATE]")
        }
        attachText(dump, name: "\(name)-accessibilite.redacted.txt")
    }
}
