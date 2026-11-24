import XCTest

/// Compte de l'espace établissement en démo (lot 5, T12 ; `docs/mobile-swift/LOT5_PLAN.md` §3 T12) sur iPhone, iPad
/// portrait et iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`) : établissement et rôle d'équipe servis, renvois
/// web présents selon les permissions servies (fixture générée depuis le `CASE` SQL), URL de chaque renvoi, ouverture
/// routée vers le présentateur `.safari` (double démo `renvoi-web-demo` : aucune ouverture réelle), déconnexion. Aucune
/// requête réseau. Vérifié par la CI seulement (aucun simulateur en local), éclat « lot5-etablissement » du job
/// `ui-lot1` de `ios-swift-ci.yml` (hors du socle).
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela : l'onglet Compte rend la table des renvois de T12, chaque
/// entrée porte l'URL de la table et l'ouvre par le présentateur de l'app, une entrée réservée est absente sans sa
/// permission, la déconnexion ramène l'écran de connexion. La table, ses conditions par rôle, l'absence de jeton dans
/// les URL et la présence de chaque chemin dans `src/App.tsx` sont prouvées au niveau 1 (`RenvoisWebEtabTests`,
/// `EtabCompteTests`).
///
/// Identifiants : `etab-compte-screen`, `etab-compte-nom`, `etab-compte-role`, `etab-compte-email`,
/// `etab-compte-note-web`, `etab-compte-web-<clé>` (valeur : URL du renvoi), `logout-button`, `network-sentinel`,
/// `renvoi-web-demo`, `renvoi-web-url`, `renvoi-web-fermer`.
final class DemoEtabCompteTests: JoleneUITestCase {
    private let espaceEtablissement = ["-JOLENE_DEMO_ESPACE", "etablissement"]

    /// Renvois du Compte dans l'ordre de l'écran : clé et URL (`RenvoisWebEtab.table`, niveau 1).
    static let renvois: [(cle: String, url: String)] = [
        ("soignants", "https://jolene.app/etablissement/soignants"),
        ("mes-favoris", "https://jolene.app/etablissement/mes-favoris"),
        ("pool-urgence", "https://jolene.app/etablissement/pool-urgence"),
        ("evaluations-a-faire", "https://jolene.app/etablissement/evaluations-a-faire"),
        ("equipe", "https://jolene.app/etablissement/equipe"),
        ("rh", "https://jolene.app/etablissement/rh"),
        ("export-paie", "https://jolene.app/etablissement/export-paie"),
        ("score", "https://jolene.app/etablissement/score"),
        ("parrainage", "https://jolene.app/etablissement/parrainage"),
        ("premium", "https://jolene.app/etablissement/premium"),
        ("parametres", "https://jolene.app/etablissement/parametres?tab=profil"),
        ("facturation", "https://jolene.app/etablissement/facturation"),
        ("sepa", "https://jolene.app/etablissement/facturation"),
        ("chorus-config", "https://jolene.app/etablissement/chorus-config"),
        ("litiges", "https://jolene.app/etablissement/litiges"),
        ("notifications", "https://jolene.app/etablissement/notifications"),
        ("api", "https://jolene.app/etablissement/api"),
        ("aide", "https://jolene.app/aide"),
        ("confidentialite", "https://jolene.app/confidentialite"),
        ("cgu", "https://jolene.app/cgu"),
        ("cgv", "https://jolene.app/cgv"),
        ("mentions-legales", "https://jolene.app/mentions-legales"),
        ("supprimer", "https://jolene.app/etablissement/parametres?tab=securite#suppression-compte"),
    ]

    /// Propriétaire d'un établissement servi comme relevant du secteur public : les vingt-trois renvois, dans l'ordre du
    /// menu web, chacun avec l'URL de la table ; quatre ouvertures routées (page couverte par l'AASA, page réservée au
    /// secteur public, suppression du compte avec sa query et son fragment, page légale hors AASA).
    func testProprietaireTousLesRenvoisEtOuvertureRoutee() throws {
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_DEMO_SECTEUR_PUBLIC", "1"])
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        ouvrirCompte()
        XCTAssertEqual(element("etab-compte-nom").label, DemoEtabSessionTests.nomEtablissement)
        XCTAssertEqual(element("etab-compte-role").label, "Propriétaire")
        XCTAssertTrue(element("etab-compte-email").label.contains(DemoEtabSessionTests.emailEtablissement))
        XCTAssertFalse(element("etab-compte-note-web").label.isEmpty, "la reconnexion web est annoncée (D16)")
        for (cle, url) in Self.renvois {
            let lien = element("etab-compte-web-\(cle)")
            require("Le renvoi « \(cle) » est offert au propriétaire") { lien.exists }
            XCTAssertEqual(lien.value as? String, url, "URL du renvoi « \(cle) »")
        }
        assertOrdre(Self.renvois.map { "etab-compte-web-\($0.cle)" })
        record("\(proofPrefix)-etab-compte-renvois")

        ouvrirRenvoi("facturation", attendu: "https://jolene.app/etablissement/facturation")
        ouvrirRenvoi("chorus-config", attendu: "https://jolene.app/etablissement/chorus-config")
        ouvrirRenvoi("cgv", attendu: "https://jolene.app/cgv")
        ouvrirRenvoi("supprimer", attendu: "https://jolene.app/etablissement/parametres?tab=securite#suppression-compte")

        let sentinelle = element("network-sentinel")
        require("La sentinelle réseau est exposée") { sentinelle.exists }
        XCTAssertEqual(sentinelle.label, "0 requête", "Aucune requête réseau : les renvois sont servis par le double démo")
    }

    /// Lecture seule d'un établissement privé (`lecture`, `lecture_paiement`) : factures et prélèvement offerts, Chorus
    /// Pro absent (secteur privé), équipe, litiges et évaluations absents sans leur permission ; la suppression du compte
    /// reste offerte ; la déconnexion ramène l'écran de connexion.
    func testLectureSeuleEntreesReserveesAbsentesPuisDeconnexion() throws {
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_DEMO_ROLE_ETAB", "LECTURE_SEULE"])
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        ouvrirCompte()
        XCTAssertEqual(element("etab-compte-role").label, "Lecture seule", "rôle d'équipe tel que servi")
        let absents: Set<String> = ["equipe", "chorus-config", "litiges", "evaluations-a-faire"]
        for (cle, url) in Self.renvois where !absents.contains(cle) {
            let lien = element("etab-compte-web-\(cle)")
            require("Le renvoi « \(cle) » est offert en lecture seule") { lien.exists }
            XCTAssertEqual(lien.value as? String, url, "URL du renvoi « \(cle) »")
        }
        // Pile non paresseuse : une entrée absente de l'arbre n'est pas rendue (§2.7, fail-closed).
        for cle in absents.sorted() {
            XCTAssertFalse(element("etab-compte-web-\(cle)").exists, "« \(cle) » : masqué sans sa permission ou hors secteur public")
        }
        record("\(proofPrefix)-etab-compte-lecture-seule")
        ouvrirRenvoi("supprimer", attendu: "https://jolene.app/etablissement/parametres?tab=securite#suppression-compte")

        let deconnexion = element("logout-button")
        if !visible(deconnexion) { scrollTo(deconnexion, in: element("etab-compte-screen")) }
        tap("logout-button")
        require("La connexion est proposée après la déconnexion", timeout: 30) {
            self.containerVisible(self.element("login-scroll")) && self.element("login-email").exists
        }
        XCTAssertFalse(tabBarExists, "plus aucun onglet établissement après la déconnexion")
        XCTAssertFalse(element("etab-compte-screen").exists, "aucun écran établissement conservé (epoch)")
    }

    // MARK: Étapes

    /// Onglet Compte : sur iPad portrait il est derrière « Page suivante » de la barre d'onglets, que `tabButton` tourne.
    private func ouvrirCompte() {
        tabButton("tab-etab-compte", label: "Compte").tap()
        require("Le compte de l'établissement est affiché", timeout: 30) {
            self.containerVisible(self.element("etab-compte-screen")) && self.element("etab-compte-nom").exists
        }
    }

    /// Entrées présentes, de haut en bas dans cet ordre (pile non paresseuse : toutes existent, même hors écran).
    private func assertOrdre(_ identifiants: [String], file: StaticString = #filePath, line: UInt = #line) {
        let ordonnees = identifiants.map { element($0).frame.minY }
        XCTAssertEqual(ordonnees, ordonnees.sorted(), "ordre des renvois : \(identifiants)", file: file, line: line)
        XCTAssertEqual(Set(ordonnees).count, ordonnees.count, "un renvoi par ligne", file: file, line: line)
    }

    /// Entrée amenée à l'écran, touchée : le double démo du renvoi web est présenté sur l'URL attendue, puis fermé ; le
    /// Compte reste affiché dessous.
    private func ouvrirRenvoi(_ cle: String, attendu: String) {
        let lien = element("etab-compte-web-\(cle)")
        if !visible(lien) { scrollTo(lien, in: element("etab-compte-screen")) }
        tap("etab-compte-web-\(cle)")
        let renvoi = element("renvoi-web-demo")
        require("Le renvoi « \(cle) » est servi par le présentateur de l'app", timeout: 30) { self.containerVisible(renvoi) }
        XCTAssertEqual(element("renvoi-web-url").label, attendu, "URL canonique du renvoi « \(cle) »")
        tap("renvoi-web-fermer")
        require("Le renvoi web est fermé, le compte reste affiché") {
            !renvoi.exists && self.containerVisible(self.element("etab-compte-screen"))
        }
    }
}
