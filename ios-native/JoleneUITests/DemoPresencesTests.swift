import XCTest

/// Présences démo (lot 2, T4a) sur iPhone, iPad portrait et iPad paysage : Profil › Mon espace › Mes présences,
/// instantané servi par `DemoPointageGateway` (`demo-presences.json`, horloge fixée 2026-11-02T00:00:00Z, soit lundi
/// 2 novembre 01h00 à Paris). Les valeurs attendues sont celles que `PresencesModelTests`, `PresencesAffichageTests`
/// et `LibellesPresencesTests` (JoleneCore) affirment sur le monde démo : un écart entre l'écran et le cœur fait
/// échouer l'un des deux.
///
/// Gaps verrouillés (aucun bouton sans effet) : la saisie du code, le QR, le consentement GPS et le hors ligne sont la
/// tranche T4b (zone `pointage-zone-provisoire-<mission>` d'ici là, migrée par T4b) ; « Voir le contrat » (T9a, sinon
/// renvoi web) et « Voir ou signaler un litige » (lot 4) ne sont rendus qu'avec le présentateur de renvois web, que T10
/// injecte : leur absence est affirmée ici, T10 la remplace par leur présence. « Détail » ouvre le détail natif (T5a).
final class DemoPresencesTests: JoleneUITestCase {
    /// Libellés exacts des onglets (`PresencesSoignant.tsx` l.520-523).
    private static let onglets: [(identifiant: String, libelle: String)] = [
        ("presences-tab-avenir", "À venir"), ("presences-tab-actives", "Actives"),
        ("presences-tab-aujourdhui", "Aujourd'hui"), ("presences-tab-historique", "Historique"),
    ]

    func testMesPresencesDepuisLeProfilOuvreAujourdhui() throws {
        launchDemo()
        connexionDemo()
        let ecran = ouvrirMesPresences()

        require("L'onglet initial est Aujourd'hui (mission du jour présente)") { self.element("presences-tab-aujourdhui").isSelected }
        XCTAssertTrue(text("Mes présences").exists, "titre verbatim du web")
        XCTAssertTrue(text("Pointez vos arrivées et départs pour chaque mission").exists, "sous-titre vouvoyé")

        // Mission a : dans la fenêtre de 15 min, contrat signé → zone de pointage (T4b), aucun motif.
        verifier("pointage-bloc-demo-presence-a", dans: ecran,
                 contient: ["Démonstration · Pointage du jour", "Établissement fictif République"])
        XCTAssertTrue(element("pointage-zone-provisoire-demo-presence-a").exists, "zone de pointage : point d'extension de T4b")
        XCTAssertFalse(element("pointage-indisponible-demo-presence-a").exists)
        // Mission b : segment ouvert → pointable aussi.
        verifier("pointage-bloc-demo-presence-b", dans: ecran, contient: ["Démonstration · Mission en cours"])
        XCTAssertFalse(element("pointage-indisponible-demo-presence-b").exists)
        // Mission c : contrat signé par le soignant seulement → motif CONTRAT, textes du web tels quels.
        verifier("pointage-indisponible-demo-presence-c", dans: ecran,
                 contient: ["Contrat non signé", "Le contrat doit être signé par les deux parties avant le premier pointage."])
        XCTAssertFalse(element("pointage-voir-contrat-demo-presence-c").exists,
                       "« Voir le contrat » sans contrat natif (T9a) ni présentateur web (T10) : jamais un bouton sans effet")
        record("\(proofPrefix)-presences-aujourdhui")

        // Présences validées récemment (7 jours) : la présence validée hier à 15h00 (Paris).
        verifier("presence-validee-demo-presence-h1-presence", dans: ecran,
                 contient: ["Démonstration · Présence validée", "Établissement fictif République", "Validée", "1 nov. 2026 à 15:00"])
        XCTAssertTrue(text("Présences validées récemment").exists)
        XCTAssertFalse(element("presences-bandeau-a-valider").exists, "bandeau « à valider » : filtre du lien seulement")
        record("\(proofPrefix)-presences-validees")
    }

    func testOngletsAVenirActivesEtHistoriqueSansRequete() throws {
        launchDemo()
        connexionDemo()
        let ecran = ouvrirMesPresences()

        // À venir : la mission de demain datée, puis le planning à confirmer ; compteur vocalisé du web (l.520).
        choisir("presences-tab-avenir")
        XCTAssertEqual(element("presences-tab-avenir").value as? String, "2 missions à venir")
        verifier("presence-avenir-demo-presence-d", dans: ecran, contient: [
            "MAR.", "3", "nov.", "Assignée", "Démonstration · Mission de demain", "Établissement fictif République · Paris",
            "08h00 → 16h00 (8h)",
        ])
        verifier("presence-avenir-demo-presence-e", dans: ecran, contient: [
            "Démonstration · Planning à confirmer", "Établissement fictif des Lilas · Les Lilas",
            "Planning détaillé à confirmer avec l’établissement",
        ])
        record("\(proofPrefix)-presences-a-venir")

        // Actives : seule la mission EN_COURS, même entre deux créneaux.
        choisir("presences-tab-actives")
        verifier("pointage-bloc-demo-presence-b", dans: ecran, contient: ["Démonstration · Mission en cours", "Établissement fictif des Lilas"])
        XCTAssertFalse(element("pointage-bloc-demo-presence-a").exists, "mission ASSIGNEE : pas dans Actives")
        record("\(proofPrefix)-presences-actives")

        // Historique : présence validée, présence à valider, ligne reconstruite depuis les segments EFFECTIF.
        choisir("presences-tab-historique")
        verifier("presence-historique-demo-presence-h1-presence", dans: ecran, contient: [
            "Démonstration · Présence validée", "31 oct. 2026", "✅ Validée", "Arrivée :", "31 oct. · 08h00", "Départ :",
            "31 oct. · 16h00", "Heures :", "8.0h", "🔢 Code",
        ])
        verifier("presence-historique-demo-presence-h2-presence", dans: ecran, contient: [
            "Démonstration · Présence à valider", "⏳ Non validée", "30 oct. · 08h00", "8.0h",
        ])
        verifier("presence-historique-effectifs-mission-demo-presence-h3", dans: ecran, contient: [
            "Démonstration · Heures pointées sans présence", "Cabinet fictif du Parc", "⏳ Non validée", "28 oct. · 08h00",
            "28 oct. · 16h00", "7.5h",
            "Relevé reconstruit depuis les segments de pointage. La validation historique n’est pas disponible sur cet ancien dossier.",
        ])
        XCTAssertFalse(element("presence-historique-litige-effectifs-mission-demo-presence-h3").exists,
                       "« Voir ou signaler un litige » sans présentateur web (T10) : jamais un bouton sans effet")
        XCTAssertTrue(element("presence-historique-detail-demo-presence-h1-presence").exists,
                      "« Détail » ouvre le détail natif des présences (T5a, `DemoPresenceDetailTests`)")
        record("\(proofPrefix)-presences-historique")

        // Retour au Profil : aucune requête réseau en démonstration.
        revenir()
        let sentinelle = element("network-sentinel")
        let liste = element("profile-list")
        // La sentinelle est au-dessus de « Mon espace », d'où la liste a été ouverte : défilement vers le haut.
        if !visible(sentinelle) { scrollTo(sentinelle, in: liste, downward: false) }
        XCTAssertEqual(sentinelle.label, "0 requête", "aucune requête réseau en démonstration")
    }

    /// Onglets lisibles en entier sur chaque format (iPad paysage compris) : libellé exact, cadre dans la fenêtre,
    /// cible tactile de 44 pt ; barre des onglets de l'app intacte (`assertMissionsTabLabelFits`).
    func testOngletsDesPresencesLisiblesSansTroncature() throws {
        launchDemo()
        connexionDemo()
        _ = ouvrirMesPresences()
        for (identifiant, libelle) in Self.onglets {
            let onglet = element(identifiant)
            require("L'onglet \(libelle) est visible") { self.visible(onglet) }
            XCTAssertEqual(onglet.label, libelle, "libellé entier de l'onglet")
            XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(onglet.frame), "\(libelle) tient dans la fenêtre")
            // Cadre relu en virgule flottante après conversion d'échelle : iPhone 17 rend `minHeight: 44` en
            // 43,99999999999997 pt (run CI 42528556340). Comparaison au millième de point, très en deçà d'un pixel
            // (1/3 pt) : une cible réellement plus petite que 44 pt échoue toujours.
            let hauteur = (onglet.frame.height * 1000).rounded() / 1000
            XCTAssertGreaterThanOrEqual(hauteur, 44, "\(libelle) : cible tactile d'au moins 44 pt")
            let texte = onglet.staticTexts[libelle]
            if texte.exists {
                XCTAssertTrue(onglet.frame.insetBy(dx: -1, dy: -1).contains(texte.frame), "\(libelle) : texte non tronqué hors du bouton")
            }
        }
        assertMissionsTabLabelFits()
        record("\(proofPrefix)-presences-onglets")
    }

    /// Migré aux intégrations de T7 et T9a : « Mes documents » ouvre l'écran natif (`documents-screen`, onglet
    /// Justificatifs par défaut, contenu affirmé par `DemoDocumentsTests`) et « Mes contrats » la liste native
    /// (`contrats-liste`, contenu affirmé par `DemoContratsTests`) ; plus aucun écran provisoire.
    func testMesDocumentsEtMesContratsNatifsDepuisMonEspace() throws {
        launchDemo()
        connexionDemo()
        ouvrirProfil()

        tapDansProfil("profil-documents")
        require("Mes documents : écran natif (T7)") { self.containerVisible(self.element("documents-screen")) }
        require("L'onglet Justificatifs est ouvert par défaut") { self.element("documents-tab-justificatifs").isSelected }
        XCTAssertFalse(element("placeholder-documents").exists, "écran provisoire retiré par T7")
        record("\(proofPrefix)-profil-documents")
        revenir()

        tapDansProfil("profil-contrats")
        require("Mes contrats : liste native (T9a)") { self.containerVisible(self.element("contrats-liste")) }
        require("Les contrats démo sont chargés", timeout: 30) { self.element("contrat-carte-demo-contrat-001").exists }
        XCTAssertFalse(element("placeholder-contrats").exists, "écran provisoire retiré par T9a")
        record("\(proofPrefix)-profil-contrats")
        revenir()
        require("Le profil est de retour") { self.containerVisible(self.element("profile-list")) }
    }

    // MARK: - Étapes

    private func connexionDemo() {
        let scroll = element("login-scroll")
        require("L'écran de connexion est affiché") { self.containerVisible(scroll) }
        let email = element("login-email")
        focus(email, in: scroll)
        email.typeText(Self.demoEmail)
        let password = element("login-password")
        // Retour sur l'email : `onSubmit` donne le focus au mot de passe (iPad paysage : un tap ne le prend pas).
        email.typeText("\n")
        if !hasKeyboardFocus(password) { focus(password, in: scroll) }
        require("Le mot de passe a le focus clavier") { self.hasKeyboardFocus(password) }
        password.typeText(Self.demoPassword)
        let submit = element("login-submit")
        require("Le bouton de connexion est activé") { submit.isEnabled }
        if app.keyboards.firstMatch.exists, !visible(submit) { scrollTo(submit, in: scroll) }
        submit.tap()
        require("La session démo est prête", timeout: 30) { self.tabBarExists }
    }

    private func ouvrirProfil() {
        tabButton("tab-profil", label: "Profil").tap()
        require("Le profil est affiché") { self.containerVisible(self.element("profile-list")) }
    }

    /// Ligne de la section « Mon espace », placée sous « Application » : défilement borné vers le bas tant qu'elle
    /// n'est pas entièrement visible (une cellule hors écran d'une `List` n'existe pas encore dans l'arbre), puis tap natif.
    private func tapDansProfil(_ identifiant: String) {
        let ligne = element(identifiant)
        if !visible(ligne) { scrollTo(ligne, in: element("profile-list")) }
        XCTAssertTrue(element("profil-espace").exists, "section « Mon espace » du Profil (décision 24)")
        tap(identifiant)
    }

    @discardableResult
    private func ouvrirMesPresences() -> XCUIElement {
        ouvrirProfil()
        tapDansProfil("profil-presences")
        let ecran = element("presences-screen")
        require("La page Présences est chargée", timeout: 30) {
            self.containerVisible(ecran) && self.element("presences-tab-aujourdhui").exists && !self.element("presences-loading").exists
        }
        XCTAssertFalse(element("presences-error").exists, "aucune erreur en démo")
        return ecran
    }

    private func choisir(_ onglet: String) {
        tap(onglet)
        require("L'onglet \(onglet) est sélectionné") { self.element(onglet).isSelected }
    }

    private func revenir() {
        let retour = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(retour) }
        retour.tap()
    }

    /// Défilement borné jusqu'au bloc, puis chaque fragment attendu parmi ses textes (requête limitée au bloc).
    private func verifier(_ identifiant: String, dans ecran: XCUIElement, contient fragments: [String],
                          file: StaticString = #filePath, line: UInt = #line) {
        let bloc = element(identifiant)
        require("\(identifiant) est rendu", timeout: 15) { bloc.exists }
        scrollTo(bloc, in: ecran)
        for fragment in fragments {
            let trouve = bloc.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
            XCTAssertTrue(trouve.exists, "\(identifiant) : « \(fragment) » absent", file: file, line: line)
        }
    }
}
