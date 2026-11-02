import XCTest

/// Favoris du lot 1 (T4b) en mode démonstration, sur iPhone, iPad portrait et iPad paysage :
/// étoile d'une carte Explorer → « Mes favoris » (fixture `demo-favoris.json` : demo-mission-002 et
/// l'établissement des Lilas) → retrait des missions jusqu'à l'état vide → retrait de l'établissement
/// après confirmation → retour à Explorer, étoile éteinte (un seul modèle) ; « Voir les missions
/// ouvertes » → Explorer filtré sur l'établissement, bandeau retirable ; étoile du détail synchronisée
/// avec la carte. Aucune requête réseau (sentinelle).
///
/// Les règles (relecture qui confirme, délai, second appui, session, epoch) sont prouvées par
/// `FavorisModelTests` ; le monde démo par `DemoFavorisGatewayTests` ; le transport par
/// `SupabaseFavorisGatewayTests`.
final class DemoFavorisTests: JoleneUITestCase {
    private enum Attendus {
        static let total = 30
        /// Missions démo de l'établissement des Lilas (`DemoWorldTests`, filtre `etablissementId`).
        static let lilas = 10
        static let filtreLilas = "Missions de « Établissement fictif des Lilas »"
        static let badgeLilas = "10 missions"
        static let favoriDepuis = "Favori depuis le 15 oct. 2026"
        static let titreRetrait = "Retirer cet établissement de vos favoris ?"
    }

    func testEtoileFavorisRetraitJusquAuVide() throws {
        ouvrirExplorer()

        // Étoile de la première carte : éteinte, puis allumée après relecture.
        let etoile = element("favori-toggle-demo-mission-001")
        require("L'étoile de la première carte est atteignable et éteinte") {
            self.visible(etoile) && (etoile.value as? String) == "Non sauvegardée"
        }
        etoile.tap()
        require("La sauvegarde est relue : l'étoile est allumée") { (etoile.value as? String) == "Sauvegardée" }
        record("\(proofPrefix)-favoris-etoile")

        ouvrirFavoris()
        let ecran = defilement("favoris-screen")
        require("Les deux missions sauvegardées sont listées") {
            self.element("favori-mission-demo-mission-001").exists && self.element("favori-mission-demo-mission-002").exists
        }
        XCTAssertEqual(element("favoris-missions-title").label, "Missions sauvegardées (2)")
        XCTAssertEqual(element("favori-etab-depuis-demo-etab-2").label, Attendus.favoriDepuis)
        record("\(proofPrefix)-favoris-liste")

        // Retrait des deux missions jusqu'à l'état vide.
        retirerMission("demo-mission-001", dans: ecran)
        retirerMission("demo-mission-002", dans: ecran)
        require("Plus aucune mission sauvegardée") { self.element("favoris-missions-vide").exists }
        XCTAssertEqual(element("favoris-missions-title").label, "Missions sauvegardées")

        // Retrait de l'établissement, après confirmation (jamais d'ajout en natif, décision 8).
        let retirer = element("favori-etab-retirer-demo-etab-2")
        scrollTo(retirer, in: ecran)
        retirer.tap()
        require("La confirmation du retrait est affichée") {
            self.containerVisible(self.element("favori-etab-retrait")) && self.element("favori-etab-retrait-confirm").exists
        }
        XCTAssertEqual(element("favori-etab-retrait-title").label, Attendus.titreRetrait)
        record("\(proofPrefix)-favoris-retrait-etablissement")
        tap("favori-etab-retrait-confirm")
        require("La feuille est refermée après la relecture") { !self.element("favori-etab-retrait").exists }
        require("Plus aucun établissement suivi") { self.element("favoris-etablissements-vide").exists }
        XCTAssertFalse(element("favori-etab-demo-etab-2").exists)
        XCTAssertFalse(element("favoris-action-erreur").exists, "aucune erreur en démonstration")
        record("\(proofPrefix)-favoris-vide")

        // Retour à Explorer : l'étoile suit la relecture (un seul modèle pour la carte et l'écran).
        let back = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(back) }
        back.tap()
        require("Explorer est de retour, étoile éteinte") {
            self.containerVisible(self.element("missions-list"))
                && (self.element("favori-toggle-demo-mission-001").value as? String) == "Non sauvegardée"
        }
        verifierAucuneRequete()
    }

    func testVoirMissionsOuvertesPuisEtoileDuDetail() throws {
        ouvrirExplorer()
        ouvrirFavoris()
        let ecran = defilement("favoris-screen")
        let voir = element("favori-etab-missions-demo-etab-2")
        scrollTo(voir, in: ecran)
        XCTAssertEqual(element("favori-etab-badge-demo-etab-2").label, Attendus.badgeLilas, "valeur serveur affichée telle quelle")
        voir.tap()

        // Explorer filtré sur l'établissement (web : `/soignant/recherche-missions?etablissement=`), bandeau retirable.
        attendreCompteur(Attendus.lilas)
        let libelle = element("explorer-filtre-etablissement-libelle")
        require("Le filtre établissement est annoncé") { libelle.exists && libelle.label == Attendus.filtreLilas }
        record("\(proofPrefix)-favoris-voir-missions")

        // Détail de la mission de la fixture : étoile allumée, éteinte depuis le détail.
        let rangee = element("mission-row-demo-mission-002")
        require("La mission sauvegardée est en tête de la liste filtrée") { self.visible(rangee) }
        rangee.tap()
        require("Le détail de la mission est rendu") {
            self.containerVisible(self.element("mission-detail")) && self.visible(self.element("mission-detail-title"))
        }
        let detail = defilement("mission-detail")
        let etoileDetail = detail.descendants(matching: .any).matching(identifier: "favori-toggle-demo-mission-002").firstMatch
        require("L'étoile du détail est allumée") {
            self.visible(etoileDetail) && (etoileDetail.value as? String) == "Sauvegardée"
        }
        etoileDetail.tap()
        require("Le retrait est relu depuis le détail") { (etoileDetail.value as? String) == "Non sauvegardée" }
        record("\(proofPrefix)-favoris-detail")

        let back = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(back) }
        back.tap()
        require("La carte suit le détail") {
            self.containerVisible(self.element("missions-list"))
                && (self.element("favori-toggle-demo-mission-002").value as? String) == "Non sauvegardée"
        }

        // Retirer le filtre : retour aux 30 missions, critères par défaut du profil.
        tap("explorer-filtre-etablissement-retirer")
        attendreCompteur(Attendus.total)
        XCTAssertFalse(element("explorer-filtre-etablissement").exists, "plus de bandeau sans filtre établissement")
        verifierAucuneRequete()
    }

    // MARK: Étapes

    /// Conteneur de défilement : la `ScrollView` portant l'identifiant, sinon la première correspondance.
    private func defilement(_ identifier: String) -> XCUIElement {
        let typee = app.scrollViews.matching(identifier: identifier).firstMatch
        return typee.exists ? typee : element(identifier)
    }

    /// Connexion démo puis onglet Explorer à 30 missions.
    private func ouvrirExplorer() {
        launchDemo()
        let scroll = element("login-scroll")
        require("L'écran de connexion est affiché") { self.visible(scroll) }
        let email = element("login-email")
        focus(email, in: scroll)
        email.typeText(Self.demoEmail)
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

        tabButton("tab-explorer", label: "Explorer").tap()
        attendreCompteur(Attendus.total, timeout: 30)
    }

    private func ouvrirFavoris() {
        tap("explorer-favoris-ouvrir")
        require("L'écran Mes favoris est affiché avec la fixture") {
            self.containerVisible(self.element("favoris-screen")) && self.element("favori-etab-demo-etab-2").exists
        }
    }

    private func retirerMission(_ id: String, dans ecran: XCUIElement) {
        let bouton = element("favori-mission-retirer-\(id)")
        scrollTo(bouton, in: ecran)
        bouton.tap()
        require("La mission \(id) n'est plus listée") { !self.element("favori-mission-\(id)").exists }
    }

    private func attendreCompteur(_ attendu: Int, timeout: TimeInterval = 15) {
        let libelle = "\(attendu) mission\(attendu > 1 ? "s" : "")"
        let count = element("missions-count")
        require("Explorer affiche \(libelle)", timeout: timeout) {
            self.containerVisible(self.element("missions-list")) && count.exists && count.label == libelle
        }
        XCTAssertEqual(count.label, libelle)
    }

    private func verifierAucuneRequete() {
        tabButton("tab-profil", label: "Profil").tap()
        let sentinel = element("network-sentinel")
        require("La sentinelle réseau est exposée") { sentinel.exists }
        XCTAssertEqual(sentinel.label, "0 requête", "les favoris n'émettent aucune requête en démonstration")
    }
}
