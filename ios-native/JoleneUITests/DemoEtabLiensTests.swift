import XCTest

/// Liens de l'espace établissement en démo (lot 5, T2b ; `docs/mobile-swift/LOT5_PLAN.md` §3 T2, D29) sur iPhone, iPad
/// portrait et iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`). Le lien est injecté au lancement par l'argument
/// DEBUG `-JOLENE_OPEN_URL <url>` (lien universel simulé à froid), donc **avant** la connexion : en démo, l'espace
/// établissement est ouvrable (`OuvertureEspaceEtablissement.pour(mode: .demo)`), le lien est mémorisé puis rejoué une
/// seule fois dans l'espace qui s'ouvre. Aucune requête réseau.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - `/etablissement/messagerie` ouvre l'onglet Messages de la coquille établissement (écran provisoire), jamais un
///   renvoi web ; libellé DEBUG `deeplink-route` = « etab messagerie » ;
/// - `/etablissement/missions/<id>` (détail, T5 non livrée) et `/contrat/<id>` (contrat établissement, T10 non livrée)
///   sont des renvois web de leur URL canonique dans l'espace établissement — jamais le contrat soignant ;
/// - un lien soignant reçu pour l'espace établissement est un renvoi web, jamais un écran soignant ;
/// - dans l'espace soignant, un lien établissement est un renvoi web, jamais un onglet établissement.
/// Les règles (table, alias, query, mémorisation, epoch, anti-boucle) sont prouvées au niveau 1 (`EtabRouteTests`,
/// `DeepLinkCoordinatorTests`). Vérifié par la CI seulement (aucun simulateur en local), dans l'éclat « presences » de
/// `ios-swift-ci.yml` (revue B8 de #1147, m5 : hors du socle). Le lien universel réel (AASA, tap depuis Mail) se prouve
/// sur appareil (`RECETTE_DEVICE_LOT5.md`).
final class DemoEtabLiensTests: JoleneUITestCase {
    private let espaceEtablissement = ["-JOLENE_DEMO_ESPACE", "etablissement"]

    func testLienMessagerieOuvreLOngletMessagesApresConnexion() throws {
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_OPEN_URL", "https://jolene.app/etablissement/messagerie"])
        aucunePresentationSurLaConnexion()
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        let messages = element("placeholder-etab-messages")
        require("L'onglet Messages est ouvert par le lien après `.readyEtablissement`", timeout: 30) {
            self.containerVisible(messages)
        }
        XCTAssertFalse(element("renvoi-web-demo").exists, "onglet natif : jamais un renvoi web")
        XCTAssertFalse(element("placeholder-etab-accueil").exists, "l'onglet du lien remplace l'Accueil")
        XCTAssertEqual(element("deeplink-route").label, "etab messagerie")
        record("\(proofPrefix)-etab-lien-messagerie")
    }

    func testDetailDeMissionNonLivreEstUnRenvoiWebDansLEspaceEtablissement() throws {
        let lien = "https://jolene.app/etablissement/missions/demo-mission-001?source=mail"
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_OPEN_URL", lien])
        aucunePresentationSurLaConnexion()
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        renvoiWeb(attendu: lien, "Le détail (T5 non livrée) est servi par le renvoi web")
        XCTAssertFalse(element("placeholder-etab-detail-mission").exists, "aucun écran provisoire empilé par un lien")
        record("\(proofPrefix)-etab-lien-detail-web")
    }

    func testContratDansLEspaceEtablissementNOuvreJamaisLeContratSoignant() throws {
        let lien = "https://jolene.app/contrat/demo-contrat-001"
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_OPEN_URL", lien])
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        renvoiWeb(attendu: lien, "Le contrat établissement (T10 non livrée) est servi par le renvoi web")
        XCTAssertFalse(element("contrat-screen").exists, "jamais l'écran du contrat soignant dans l'espace établissement")
        record("\(proofPrefix)-etab-lien-contrat-web")
    }

    func testLienSoignantDansLEspaceEtablissementEstUnRenvoiWeb() throws {
        let lien = "https://jolene.app/soignant/mes-gains"
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_OPEN_URL", lien])
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        renvoiWeb(attendu: lien, "Un lien soignant est servi par le renvoi web dans l'espace établissement")
        XCTAssertFalse(element("tab-revenus").exists, "aucun onglet soignant dans l'espace établissement")
        record("\(proofPrefix)-etab-lien-soignant-web")
    }

    func testLienEtablissementDansLEspaceSoignantEstUnRenvoiWeb() throws {
        let lien = "https://jolene.app/etablissement/messagerie"
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", lien])
        connecter(email: JoleneUITestCase.demoEmail)
        renvoiWeb(attendu: lien, "Dans l'espace soignant, un lien établissement est servi par le renvoi web")
        XCTAssertFalse(element("placeholder-etab-messages").exists, "jamais un onglet établissement dans l'espace soignant")
        XCTAssertFalse(element("tab-etab-messages").exists)
        record("\(proofPrefix)-soignant-lien-etab-web")
    }

    // MARK: Étapes

    /// Écran de connexion affiché, rien de présenté par-dessus (lien mémorisé) : absence bornée, comme les liens du lot 2.
    private func aucunePresentationSurLaConnexion() {
        require("L'écran de connexion est affiché") { self.containerVisible(self.element("login-scroll")) }
        requireAbsence("Rien n'est présenté avant l'espace : ni renvoi web, ni route, ni onglet") {
            self.element("renvoi-web-demo").exists || self.element("deeplink-route").exists || self.tabBarExists
        }
    }

    /// Double démo du renvoi web présenté sur l'URL attendue, puis fermé : l'espace reste ouvert dessous.
    private func renvoiWeb(attendu: String, _ description: String) {
        let renvoi = element("renvoi-web-demo")
        require(description, timeout: 30) { self.containerVisible(renvoi) }
        XCTAssertEqual(element("renvoi-web-url").label, attendu, "URL canonique, query conservée")
        tap("renvoi-web-fermer")
        require("Le renvoi web est fermé, l'espace reste ouvert") { !renvoi.exists && self.tabBarExists }
    }
}
