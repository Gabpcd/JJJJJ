import XCTest

/// Espace établissement en démo (lot 5, T2a ; `docs/mobile-swift/LOT5_PLAN.md` §3 T2) : session confirmée
/// par le serveur fictif, coquille à cinq onglets (Accueil · Missions · Présences · Messages · Compte,
/// D13), drapeaux d'écran (D14), rôle d'équipe servi (aucune action sans la permission), compte legacy,
/// et frontière d'epoch entre deux espaces dans la même session. Écrit pour iPhone, iPad portrait et
/// iPad paysage (`JOLENE_UI_ORIENTATION`, helpers de `UITestSupport.swift`). Aucune requête réseau.
///
/// Identifiants : `tab-etab-{accueil|missions|presences|messages|compte}`, `placeholder-etab-*`,
/// `etab-missions-publier`, `etab-renvoi-web` (+ `-message`, `-ouvrir`), `etab-compte-list`,
/// `etab-compte-{nom|role|email}`, `logout-button`, `network-sentinel`. Les écrans provisoires
/// (`placeholder-etab-*`) sont remplacés par la tranche de leur domaine, qui migre ces assertions.
final class DemoEtabSessionTests: JoleneUITestCase {
    static let emailEtablissement = "etablissement-demonstration@example.invalid"
    /// Nom de `demo-etab-1` (`demo-etablissement.json`, dérivé de `demo-etablissements.json`).
    static let nomEtablissement = "Établissement fictif République"
    static let ongletsEtablissement = ["Accueil", "Missions", "Présences", "Messages", "Compte"]
    static let ongletsSoignant = ["Accueil", "Explorer", "Mes missions", "Revenus", "Profil"]

    private let espaceEtablissement = ["-JOLENE_DEMO_ESPACE", "etablissement"]

    func testEspaceEtablissementCinqOngletsSansReseau() throws {
        launchDemo(extraArguments: espaceEtablissement)
        connecter(email: Self.emailEtablissement)
        XCTAssertEqual(tabLabels, Self.ongletsEtablissement, "barre d'onglets de l'espace établissement (D13)")
        require("L'Accueil établissement est affiché") { self.containerVisible(self.element("placeholder-etab-accueil")) }
        XCTAssertFalse(element("tab-accueil").exists, "aucun onglet soignant dans l'espace établissement")
        record("\(proofPrefix)-etab-accueil")

        ouvrirOnglet("tab-etab-missions", label: "Missions", contenu: "placeholder-etab-missions")
        let publier = element("etab-missions-publier")
        require("« Publier » est offert au propriétaire (permission missions)") { self.visible(publier) }
        tap("etab-missions-publier")
        require("Le registre de destinations ouvre la publication") {
            self.containerVisible(self.element("placeholder-etab-publication"))
        }
        record("\(proofPrefix)-etab-publication")

        ouvrirOnglet("tab-etab-presences", label: "Présences", contenu: "placeholder-etab-presences")
        ouvrirOnglet("tab-etab-messages", label: "Messages", contenu: "placeholder-etab-messages")
        ouvrirCompte()
        XCTAssertEqual(element("etab-compte-nom").label, Self.nomEtablissement)
        XCTAssertEqual(element("etab-compte-role").label, "Propriétaire")
        XCTAssertTrue(element("etab-compte-email").label.contains(Self.emailEtablissement))
        let sentinelle = element("network-sentinel")
        require("La sentinelle réseau est exposée") { sentinelle.exists }
        XCTAssertEqual(sentinelle.label, "0 requête", "Aucune requête réseau en démonstration")
        record("\(proofPrefix)-etab-compte")
    }

    func testCompteLegacyOuvreLeMemeEspace() throws {
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_DEMO_LEGACY", "1"])
        connecter(email: Self.emailEtablissement)
        XCTAssertEqual(tabLabels, Self.ongletsEtablissement)
        ouvrirCompte()
        XCTAssertEqual(element("etab-compte-nom").label, Self.nomEtablissement, "établissement confirmé par le serveur fictif")
        XCTAssertEqual(element("etab-compte-role").label, "Propriétaire", "un compte legacy est propriétaire")
        record("\(proofPrefix)-etab-legacy")
    }

    func testLectureSeuleOngletsPresentsActionsAbsentes() throws {
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_DEMO_ROLE_ETAB", "LECTURE_SEULE"])
        connecter(email: Self.emailEtablissement)
        XCTAssertEqual(tabLabels, Self.ongletsEtablissement, "les cinq onglets restent présents (lecture)")
        ouvrirOnglet("tab-etab-missions", label: "Missions", contenu: "placeholder-etab-missions")
        XCTAssertFalse(element("etab-missions-publier").exists, "aucune publication sans la permission missions")
        XCTAssertFalse(element("etab-acces-refuse").exists, "la lecture reste ouverte")
        ouvrirCompte()
        XCTAssertEqual(element("etab-compte-role").label, "Lecture seule")
        record("\(proofPrefix)-etab-lecture-seule")
    }

    func testDrapeauPresencesCoupeAfficheLeRenvoiWeb() throws {
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_FLAG_ios_natif_etab_presences_actif", "false"])
        connecter(email: Self.emailEtablissement)
        XCTAssertEqual(tabLabels, Self.ongletsEtablissement, "l'onglet coupé garde sa place dans la barre")
        tabButton("tab-etab-presences", label: "Présences").tap()
        let renvoi = element("etab-renvoi-web")
        require("L'onglet Présences coupé affiche le renvoi web") { self.containerVisible(renvoi) }
        XCTAssertFalse(element("placeholder-etab-presences").exists, "l'écran natif coupé n'est jamais monté")
        XCTAssertFalse(element("etab-renvoi-web-message").label.isEmpty)
        let ouvrir = element("etab-renvoi-web-ouvrir")
        require("La sortie web est atteignable") { self.visible(ouvrir) }
        XCTAssertEqual(ouvrir.value as? String, "https://jolene.app/etablissement/presences", "URL du renvoi routée")
        record("\(proofPrefix)-etab-renvoi-presences")

        ouvrirOnglet("tab-etab-accueil", label: "Accueil", contenu: "placeholder-etab-accueil")
        XCTAssertFalse(element("etab-renvoi-web").exists, "seul l'onglet coupé est renvoyé au web")
    }

    func testDeconnexionPuisConnexionSoignantDansLaMemeSession() throws {
        launchDemo(extraArguments: espaceEtablissement)
        connecter(email: Self.emailEtablissement)
        XCTAssertEqual(tabLabels, Self.ongletsEtablissement)
        ouvrirCompte()
        let deconnexion = element("logout-button")
        if !visible(deconnexion) { scrollTo(deconnexion, in: element("etab-compte-list")) }
        tap("logout-button")
        require("La connexion est proposée après la déconnexion") { self.visible(self.element("login-scroll")) }
        XCTAssertFalse(tabBarExists, "plus aucun onglet établissement après la déconnexion")

        connecter(email: Self.demoEmail)
        XCTAssertEqual(tabLabels, Self.ongletsSoignant, "nouvelle identité, nouvel espace : onglets soignant")
        XCTAssertFalse(element("tab-etab-accueil").exists)
        XCTAssertFalse(element("placeholder-etab-accueil").exists, "aucun écran établissement conservé (epoch)")
        record("\(proofPrefix)-etab-puis-soignant")
    }

    // MARK: Étapes

    /// Connexion démo avec `email` ; le champ est vidé s'il garde la saisie d'une connexion précédente.
    private func connecter(email adresse: String) {
        let scroll = element("login-scroll")
        require("L'écran de connexion est affiché") { self.visible(scroll) }
        let email = element("login-email")
        focus(email, in: scroll)
        viderChamp(email)
        email.typeText(adresse)
        let password = element("login-password")
        email.typeText("\n")
        if !hasKeyboardFocus(password) { focus(password, in: scroll) }
        require("Le mot de passe a le focus clavier") { self.hasKeyboardFocus(password) }
        password.typeText(Self.demoPassword)
        let submit = element("login-submit")
        require("Le bouton de connexion est activé") { submit.isEnabled }
        if app.keyboards.firstMatch.exists, !visible(submit) { scrollTo(submit, in: scroll) }
        submit.tap()
        require("La session est prête : la barre d'onglets est affichée", timeout: 30) { self.tabBarExists }
    }

    /// Efface la valeur saisie lors d'une connexion précédente : curseur amené à droite du texte, puis
    /// autant de retours arrière que de caractères ; un texte plus large que le champ peut laisser le
    /// curseur au milieu, d'où au plus trois passes (le reste, plus court, tient alors dans le champ).
    private func viderChamp(_ champ: XCUIElement) {
        func saisie() -> String {
            let valeur = (champ.value as? String) ?? ""
            return valeur == champ.placeholderValue ? "" : valeur
        }
        var passes = 0
        while !saisie().isEmpty && passes < 3 {
            champ.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            champ.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: saisie().count))
            passes += 1
        }
        require("Le champ email est vide avant la saisie") { saisie().isEmpty }
    }

    private func ouvrirOnglet(_ identifiant: String, label: String, contenu: String) {
        tabButton(identifiant, label: label).tap()
        require("L'onglet \(label) affiche son contenu") { self.containerVisible(self.element(contenu)) }
    }

    private func ouvrirCompte() {
        tabButton("tab-etab-compte", label: "Compte").tap()
        require("Le compte de l'établissement est affiché") {
            self.containerVisible(self.element("etab-compte-list")) && self.element("etab-compte-nom").exists
        }
    }
}
