import XCTest

/// Candidatures d'une mission de l'espace établissement en démo (lot 5, T6 ; `docs/mobile-swift/LOT5_PLAN.md` §3 T6) sur
/// iPhone, iPad portrait et iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`) : destination `.candidatures` du registre
/// ouverte depuis le détail de mission (T5), planning incomplet bloquant (M3), acceptation par récapitulatif relu puis
/// statut « Acceptée » relu (M1), étudiante aide-soignante renvoyée au web (D10), lien neutre vers les CGV (mention
/// verbatim en attente de validation HARD STOP n°4), alerte de planning modifié puis reconfirmation
/// (`-JOLENE_DEMO_PLANNING_MODIFIE 1`), refus relu. Aucune requête réseau. Vérifié par la CI seulement (aucun simulateur
/// en local), dans l'éclat « presences » de `ios-swift-ci.yml`, hors du socle.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela : l'écran rendu par la destination `.candidatures` est celui de
/// T6, sur les données fictives ; les règles (relectures, empreinte, issues serveur verbatim, D25, interceptions) sont
/// prouvées au niveau 1 (`CandidaturesEtabModelTests`, `CandidaturesEtabRulesTests`,
/// `SupabaseEtabCandidaturesGatewayTests`).
final class DemoEtabCandidaturesTests: JoleneUITestCase {
    private let espaceEtablissement = ["-JOLENE_DEMO_ESPACE", "etablissement"]

    func testPlanningIncompletBloquantPuisAcceptationRelueEtEtudianteRenvoyeeAuWeb() throws {
        launchDemo(extraArguments: espaceEtablissement)
        connecter(email: DemoEtabSessionTests.emailEtablissement)

        ouvrirCandidatures(mission: "demo-etab-m03", intitule: "Démonstration · Planning à compléter")
        let ecran = element("etab-candidatures-screen")
        let bloquant = element("etab-candidatures-planning-bloquant")
        scrollTo(bloquant, in: ecran)
        XCTAssertTrue(bloquant.label.contains("Planning incomplet : 2 créneaux attendus, 1 chargé."), bloquant.label)
        let accepterM3 = element("etab-candidature-accepter-demo-etab-m03-cand-1")
        scrollTo(accepterM3, in: ecran)
        XCTAssertFalse(accepterM3.isEnabled, "acceptation désactivée tant que le planning n'est pas exact")
        XCTAssertFalse(element("placeholder-etab-candidatures").exists, "écran de T6, jamais le provisoire")
        record("\(proofPrefix)-etab-candidatures-m3-bloquant")
        revenirALaListe()

        ouvrirCandidatures(mission: "demo-etab-m01", intitule: "Démonstration · Candidatures à examiner")
        let cgv = element("etab-candidatures-cgv-lien")
        scrollTo(cgv, in: ecran)
        XCTAssertEqual(cgv.value as? String, "https://jolene.app/cgv#art8", "lien de la mention vers les CGV")
        XCTAssertTrue(cgv.label.hasPrefix("Avant d’accepter un candidat, consultez les conditions de non-contournement"),
                      "mention CGV art. 8 du web, mot pour mot (décision c) : \(cgv.label)")
        let etudiante = element("etab-candidature-web-demo-etab-m01-cand-3")
        scrollTo(etudiante, in: ecran)
        XCTAssertEqual(etudiante.value as? String, "https://jolene.app/etablissement/missions/demo-etab-m01",
                       "étudiante aide-soignante : acceptation sur jolene.app (D10)")
        XCTAssertFalse(element("etab-candidature-accepter-demo-etab-m01-cand-3").exists, "aucune case juridique en natif")
        record("\(proofPrefix)-etab-candidatures-m1")

        accepter("demo-etab-m01-cand-1")
        XCTAssertEqual(element("etab-recap-total").label, "1 créneau · 12 h au total")
        XCTAssertTrue(element("etab-recap-creneaux").exists)
        record("\(proofPrefix)-etab-recap-acceptation")
        confirmerRecap()
        attendreStatut("demo-etab-m01-cand-1", "Acceptée")
        XCTAssertTrue(element("etab-candidatures-succes").exists, "succès affiché après relecture seulement")
        XCTAssertEqual(element("etab-candidature-statut-demo-etab-m01-cand-2").label, "Refusée",
                       "les autres candidatures en attente sont refusées par le serveur (démo)")
        record("\(proofPrefix)-etab-candidature-acceptee")
    }

    func testRefusReluPuisPlanningModifieAlerteEtReconfirmation() throws {
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_DEMO_PLANNING_MODIFIE", "1"])
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        ouvrirCandidatures(mission: "demo-etab-m01", intitule: "Démonstration · Candidatures à examiner")
        let ecran = element("etab-candidatures-screen")

        let refuser = element("etab-candidature-refuser-demo-etab-m01-cand-2")
        scrollTo(refuser, in: ecran)
        refuser.tap()
        attendreStatut("demo-etab-m01-cand-2", "Refusée")
        record("\(proofPrefix)-etab-candidature-refusee")

        accepter("demo-etab-m01-cand-1")
        confirmerRecap()
        let alerte = element("etab-recap-alerte")
        require("Le planning modifié est signalé dans le récapitulatif, rien n'est accepté") {
            alerte.exists && self.element("etab-recap").exists
        }
        XCTAssertEqual(alerte.label.contains("Le planning a changé depuis son affichage."), true, alerte.label)
        record("\(proofPrefix)-etab-recap-planning-modifie")
        confirmerRecap()
        attendreStatut("demo-etab-m01-cand-1", "Acceptée")
    }

    // MARK: Étapes

    private func ouvrirCandidatures(mission id: String, intitule: String) {
        if !containerVisible(element("etab-missions-screen")) { toucherOnglet("tab-etab-missions", label: "Missions") }
        require("La liste des missions est relue") {
            self.containerVisible(self.element("etab-missions-screen")) && self.element("etab-missions-count").exists
        }
        tap("etab-missions-filtre-OUVERTE")
        require("Le filtre Ouvertes est relu") { self.element("etab-missions-count").label == "5 missions trouvées" }
        let carte = element("etab-mission-card-\(id)")
        scrollTo(carte, in: element("etab-missions-scroll"))
        carte.tap()
        require("Le détail de la mission est relu") { self.element("etab-mission-titre").label == intitule }
        let lien = element("etab-mission-lien-candidatures")
        scrollTo(lien, in: element("etab-mission-detail"))
        lien.tap()
        require("Les candidatures de la mission sont relues") {
            self.containerVisible(self.element("etab-candidatures-screen")) && self.element("etab-candidatures-en-attente").exists
        }
    }

    private func accepter(_ candidature: String) {
        let bouton = element("etab-candidature-accepter-\(candidature)")
        scrollTo(bouton, in: element("etab-candidatures-screen"))
        bouton.tap()
        require("Le récapitulatif relu est présenté") {
            self.element("etab-recap").exists && self.element("etab-recap-total").exists
        }
    }

    /// « Confirmer et assigner » : la feuille s'ouvre à mi-hauteur, le bouton est d'abord ramené dans la vue.
    private func confirmerRecap() {
        let confirmer = element("etab-recap-confirm")
        require("Le récapitulatif est présenté") { confirmer.exists }
        XCTAssertEqual(element("etab-recap-title").label, "Confirmer l’acceptation")
        scrollTo(confirmer, in: element("etab-recap"))
        require("La confirmation est active") { confirmer.isEnabled }
        confirmer.tap()
    }

    private func attendreStatut(_ candidature: String, _ statut: String) {
        let badge = element("etab-candidature-statut-\(candidature)")
        require("La candidature est relue « \(statut) »", timeout: 30) {
            !self.element("etab-recap").exists && badge.exists && badge.label == statut
        }
    }

    private func revenirALaListe() {
        for _ in 0..<3 where !containerVisible(element("etab-missions-screen")) {
            let retour = app.navigationBars.buttons.firstMatch
            require("Le bouton retour est disponible") { self.visible(retour) }
            retour.tap()
        }
        require("La liste des missions est affichée") { self.containerVisible(self.element("etab-missions-screen")) }
    }
}
