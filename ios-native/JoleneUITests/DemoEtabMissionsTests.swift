import XCTest

/// Missions de l'espace établissement en démo (lot 5, T5 ; `docs/mobile-swift/LOT5_PLAN.md` §3 T5) sur iPhone, iPad
/// portrait et iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`) : liste par filtre avec compteurs dérivés des onze
/// missions fictives (`demo-etab-missions.json`, M1…M11), détail relu (planning incomplet de M3, soignant de M4, fil natif
/// de M4 ouvert par « Contacter le soignant », T11), liens
/// vers les écrans non livrés servis par le renvoi web (double démo `renvoi-web-demo`), liens et actions masqués sans
/// leur permission (`LECTURE_SEULE`). Aucune requête réseau. Vérifié par la CI seulement (aucun simulateur en local),
/// dans l'éclat « lot3-profil-photo » de `ios-swift-ci.yml`, avec la session établissement (hors du socle).
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela : l'écran rendu par l'onglet Missions et par la destination
/// `.detailMission` du registre est celui de T5, sur les données fictives ; les règles (requêtes, montants absents,
/// filtre d'établissement, permissions, complétude) sont prouvées au niveau 1 (`EtabMissionTests`,
/// `EtabMissionsModelTests`, `SupabaseEtabMissionsGatewayTests`).
final class DemoEtabMissionsTests: JoleneUITestCase {
    private let espaceEtablissement = ["-JOLENE_DEMO_ESPACE", "etablissement"]

    func testListeFiltresCompteursEtPlanningIncompletDeM3() throws {
        launchDemo(extraArguments: espaceEtablissement)
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        ouvrirMissions()
        XCTAssertEqual(element("etab-missions-filtre-toutes").label, "Toutes (11)", "compteurs dérivés des onze missions")
        XCTAssertEqual(element("etab-missions-filtre-OUVERTE").label, "Ouvertes (5)")
        XCTAssertEqual(element("etab-missions-count").label, "11 missions trouvées")
        record("\(proofPrefix)-etab-missions-toutes")

        tap("etab-missions-filtre-OUVERTE")
        require("Le filtre Ouvertes est relu") { self.element("etab-missions-count").label == "5 missions trouvées" }
        let m1 = element("etab-mission-card-demo-etab-m01")
        scrollTo(m1, in: element("etab-missions-scroll"))
        XCTAssertTrue(m1.label.contains("3 candidatures à traiter"), m1.label)
        XCTAssertFalse(m1.label.contains("€"), "aucun montant sur la carte (D15)")
        record("\(proofPrefix)-etab-missions-ouvertes")

        let m3 = element("etab-mission-card-demo-etab-m03")
        scrollTo(m3, in: element("etab-missions-scroll"), downward: false)
        XCTAssertTrue(m3.label.contains("Planning détaillé à confirmer"), m3.label)
        m3.tap()
        require("Le détail de M3 est relu") { self.element("etab-mission-titre").label == "Démonstration · Planning à compléter" }
        let detail = element("etab-mission-detail")
        let incomplet = element("etab-mission-planning-incomplet")
        scrollTo(incomplet, in: detail)
        XCTAssertFalse(element("placeholder-etab-detail-mission").exists, "écran de T5, jamais le provisoire")
        let candidatures = element("etab-mission-lien-candidatures")
        scrollTo(candidatures, in: detail)
        XCTAssertNotEqual(candidatures.value as? String, "https://jolene.app/etablissement/missions/demo-etab-m03",
                          "T6 livrée : écran natif, plus la page web")
        record("\(proofPrefix)-etab-mission-m3")
        candidatures.tap()
        require("Le lien livré ouvre l'écran natif des candidatures (T6)") {
            self.containerVisible(self.element("etab-candidatures-screen"))
        }
        XCTAssertFalse(element("renvoi-web-demo").exists)
    }

    func testLectureSeuleSansCandidaturesNiContratNiActionsDeGestion() throws {
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_DEMO_ROLE_ETAB", "LECTURE_SEULE"])
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        ouvrirMissions()
        XCTAssertFalse(element("etab-missions-publier").exists, "aucune publication sans la permission missions")
        XCTAssertEqual(element("etab-missions-filtre-ASSIGNEE").label, "Assignées (2)")
        let m4 = element("etab-mission-card-demo-etab-m04")
        scrollTo(m4, in: element("etab-missions-scroll"))
        XCTAssertFalse(m4.label.contains("candidature"), "aucune candidature lue sans la permission")
        m4.tap()
        require("Le détail de M4 est relu") { self.element("etab-mission-titre").label == "Démonstration · Nuit en cours" }
        let detail = element("etab-mission-detail")
        let soignant = element("etab-mission-soignant-nom")
        scrollTo(soignant, in: detail)
        XCTAssertEqual(soignant.label, "Camille Démo", "soignant servi par fn_soignant_pour_etablissement (démo)")
        let message = element("etab-mission-lien-message")
        scrollTo(message, in: detail)
        for absent in ["etab-mission-lien-candidatures", "etab-mission-lien-contrat", "etab-mission-lien-pointage",
                       "etab-mission-web-modifier", "etab-mission-web-annuler", "etab-mission-web-dupliquer"] {
            XCTAssertFalse(element(absent).exists, "\(absent) : masqué sans sa permission (§2.7)")
        }
        record("\(proofPrefix)-etab-mission-lecture-seule")
        // T11 livrée : « Contacter le soignant » ouvre le fil natif de la mission (permission `lecture` seule suffit).
        XCTAssertTrue(message.label.contains("Contacter le soignant"), message.label)
        message.tap()
        require("Le lien du message ouvre le fil natif de M4 (T11)") { self.containerVisible(self.element("chat-screen")) }
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran livré : jamais un renvoi web")
        XCTAssertTrue(element("chat-message-demo-etab-message-004").waitForExistence(timeout: 10))
    }

    // MARK: Étapes

    private func ouvrirMissions() {
        tabButton("tab-etab-missions", label: "Missions").tap()
        require("La liste des missions est relue") {
            self.containerVisible(self.element("etab-missions-screen")) && self.element("etab-missions-count").exists
        }
    }
}
