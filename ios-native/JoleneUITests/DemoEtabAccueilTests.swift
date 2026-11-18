import XCTest

/// Accueil de l'espace établissement en démo (lot 5, T4 ; `docs/mobile-swift/LOT5_PLAN.md` §3 T4) sur iPhone, iPad
/// portrait et iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`) : actions prioritaires sans graphique, dans l'ordre
/// du web, filtrées par les permissions servies (fixture générée depuis le `CASE` SQL), action native (onglet de la
/// coquille) ou renvoi web de l'URL canonique (double démo du présentateur `.safari`, aucune ouverture réelle), planning
/// des 31 prochains jours. Aucune requête réseau. Vérifié par la CI seulement (aucun simulateur en local), éclat
/// « lot3-profil-photo » de `ios-swift-ci.yml` (hors du socle, comme `DemoEtabSessionTests`).
///
/// Ce que ces tests prouvent (niveau 2) : ordre et présence des actions par rôle, blocage en tête, sorties des actions
/// (onglet Messages natif, Missions filtrées sur « Ouvertes » pour les candidatures, litiges et facturation sur
/// jolene.app). Règles, textes et formats : niveau 1
/// (`PrioriteActionsTests`, `EtabPlanningAccueilTests`, `EtabAccueilModelTests`).
final class DemoEtabAccueilTests: JoleneUITestCase {
    private let espaceEtablissement = ["-JOLENE_DEMO_ESPACE", "etablissement"]

    func testProprietaireActionsDansLOrdreDuWebEtLeursSorties() throws {
        launchDemo(extraArguments: espaceEtablissement)
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        ouvrirAccueil()
        XCTAssertEqual(element("etab-accueil-nom").label, DemoEtabSessionTests.nomEtablissement)
        XCTAssertEqual(element("etab-accueil-role").label, "Propriétaire")
        assertOrdre(["etab-action-candidatures", "etab-action-presences", "etab-action-litiges", "etab-action-evaluations",
                     "etab-action-messages"])
        XCTAssertFalse(element("etab-action-blocage").exists)
        XCTAssertFalse(element("etab-action-verification").exists)
        XCTAssertFalse(element("etab-action-factures").exists, "aucune facture à régler dans la fixture")
        XCTAssertTrue(element("etab-accueil-publier").exists, "« Publier une mission » offert au propriétaire")
        XCTAssertTrue(element("etab-accueil-planning-compteur").exists, "planning des 31 prochains jours")
        XCTAssertFalse(element("etab-accueil-partiel").exists)
        record("\(proofPrefix)-etab-accueil-actions")

        toucher("etab-action-litiges-cta")
        renvoiWeb(attendu: "https://jolene.app/etablissement/litiges", "Les litiges sont servis par le renvoi web")

        toucher("etab-action-messages-cta")
        require("L'action « messages » ouvre l'onglet Messages de la coquille") {
            self.containerVisible(self.element("placeholder-etab-messages"))
        }
        XCTAssertFalse(element("renvoi-web-demo").exists, "onglet natif : jamais un renvoi web")
        record("\(proofPrefix)-etab-accueil-messages")

        // Intégration de la vague C (revues B8 de #1160 et #1162, m1) : l'action « candidatures »
        // (`/etablissement/missions?statut=OUVERTE`) passe par `EtablissementTabView.ouvrir(_:)`, qui rejoue le filtre
        // `?statut=` de la liste des missions, comme un lien : Missions s'ouvre sur « Ouvertes », jamais sur « Toutes ».
        tabButton("tab-etab-accueil", label: "Accueil").tap()
        ouvrirAccueil()
        toucher("etab-action-candidatures-cta")
        require("L'action « candidatures » ouvre Missions sur le filtre Ouvertes", timeout: 30) {
            self.containerVisible(self.element("etab-missions-screen"))
                && self.element("etab-missions-filtre-OUVERTE").isSelected
        }
        XCTAssertFalse(element("etab-missions-filtre-toutes").isSelected, "le filtre « Toutes » n'est pas sélectionné")
        require("La liste relue est celle des missions ouvertes") {
            self.element("etab-missions-count").label == "5 missions trouvées"
        }
        XCTAssertFalse(element("renvoi-web-demo").exists, "onglet natif : jamais un renvoi web")
        record("\(proofPrefix)-etab-accueil-candidatures-ouvertes")
    }

    func testPointageSeulementPresencesEtMessages() throws {
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_DEMO_ROLE_ETAB", "POINTAGE_ONLY"])
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        ouvrirAccueil()
        XCTAssertEqual(element("etab-accueil-role").label, "Pointage uniquement")
        assertOrdre(["etab-action-presences", "etab-action-messages"])
        for absente in ["candidatures", "litiges", "evaluations", "factures", "blocage", "verification"] {
            XCTAssertFalse(element("etab-action-\(absente)").exists, "POINTAGE_ONLY : pas d'action « \(absente) »")
        }
        XCTAssertFalse(element("etab-accueil-publier").exists, "aucune publication sans la permission missions")
        record("\(proofPrefix)-etab-accueil-pointage")
    }

    func testBlocageEnTeteEtRenvoiFacturation() throws {
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_DEMO_BLOCAGE", "1"])
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        ouvrirAccueil()
        assertOrdre(["etab-action-blocage", "etab-action-candidatures", "etab-action-presences"])
        XCTAssertFalse(element("etab-action-verification").exists, "un seul blocage, la suspension d'abord")
        record("\(proofPrefix)-etab-accueil-blocage")
        toucher("etab-action-blocage-cta")
        renvoiWeb(attendu: "https://jolene.app/etablissement/facturation", "Le blocage mène à la facturation sur jolene.app")
    }

    // MARK: Étapes

    private func ouvrirAccueil() {
        require("L'Accueil établissement est affiché", timeout: 30) {
            self.containerVisible(self.element("etab-accueil-screen")) && self.element("etab-accueil-actions").exists
        }
    }

    /// Actions présentes, de haut en bas dans cet ordre (pile non paresseuse : toutes existent, même hors écran).
    private func assertOrdre(_ identifiants: [String], file: StaticString = #filePath, line: UInt = #line) {
        for identifiant in identifiants {
            require("L'action \(identifiant) est affichée") { self.element(identifiant).exists }
        }
        let ordonnees = identifiants.map { element($0).frame.minY }
        XCTAssertEqual(ordonnees, ordonnees.sorted(), "ordre des actions : \(identifiants)", file: file, line: line)
        XCTAssertEqual(Set(ordonnees).count, ordonnees.count, "une action par ligne", file: file, line: line)
    }

    /// Bouton d'action amené à l'écran dans le défilement de l'Accueil, puis touché.
    private func toucher(_ identifiant: String) {
        let cible = element(identifiant)
        if !visible(cible) { scrollTo(cible, in: element("etab-accueil-screen")) }
        tap(identifiant)
    }

    /// Double démo du renvoi web présenté sur l'URL attendue, puis fermé : l'espace reste ouvert dessous.
    private func renvoiWeb(attendu: String, _ description: String) {
        let renvoi = element("renvoi-web-demo")
        require(description, timeout: 30) { self.containerVisible(renvoi) }
        XCTAssertEqual(element("renvoi-web-url").label, attendu, "URL canonique du renvoi")
        tap("renvoi-web-fermer")
        require("Le renvoi web est fermé, l'espace reste ouvert") { !renvoi.exists && self.tabBarExists }
    }
}
