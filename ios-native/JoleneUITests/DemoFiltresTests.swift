import XCTest

/// Recherches sauvegardées et alerte rapide (L4-T4) en démonstration, sur iPhone, iPad portrait et iPad paysage :
/// Profil → « Recherches sauvegardées » (`hub-recherches`, fixture `demo-filtres.json` : « Nuits autour de Paris » en
/// alerte toutes les heures, « Week-ends en CDD » sans alerte) → cloche relue → suppression après confirmation jusqu'à
/// l'état vide ; Explorer → « Me prévenir des prochaines missions » crée une alerte, puis la même action la réutilise
/// (aucun doublon dans la liste) ; « Aller à la recherche » → Explorer filtré (rayon de la recherche), avis
/// « Filtres « … » appliqués ». Aucune requête réseau (sentinelle).
///
/// Les règles (relecture qui confirme, refus verbatim, validateur, sept clés, epoch) sont prouvées par
/// `FiltresEncodageTests` et `FiltresModelTests` ; le transport par `SupabaseFiltresGatewayTests`.
final class DemoFiltresTests: JoleneUITestCase {
    private enum Attendus {
        static let total = 30
        static let nuits = "demo-recherche-001"
        static let weekEnds = "demo-recherche-002"
    }

    func testClocheEtSuppressionJusquAuVide() throws {
        launchDemo()
        connexionDemo()
        let ecran = ouvrirRecherches()
        XCTAssertEqual(elements(withPrefix: "recherche-appliquer-").count, 2, "les deux recherches de la fixture")
        let etatNuits = element("recherche-etat-\(Attendus.nuits)")
        XCTAssertTrue(etatNuits.label.contains("Alertes toutes les heures"), etatNuits.label)
        XCTAssertTrue(etatNuits.label.contains("Dernier check : 01 nov. 19:00"), "heure de Paris : \(etatNuits.label)")
        XCTAssertTrue(etatNuits.label.contains("3 résultats"), etatNuits.label)
        XCTAssertTrue(element("recherche-etat-\(Attendus.weekEnds)").label.contains("Alertes désactivées"))
        record("\(proofPrefix)-recherches-liste")

        // Cloche : l'alerte n'est annoncée qu'après relecture.
        let cloche = element("recherche-alerte-\(Attendus.weekEnds)")
        scrollTo(cloche, in: ecran)
        XCTAssertEqual(cloche.label, "Activer alertes")
        cloche.tap()
        require("L'alerte relue est active") {
            self.element("recherches-confirmation").exists
                && self.element("recherche-etat-\(Attendus.weekEnds)").label.contains("Alertes quotidien")
        }
        XCTAssertTrue(element("recherches-confirmation").label.contains("Alerte activée"))
        XCTAssertEqual(element("recherche-alerte-\(Attendus.weekEnds)").label, "Désactiver alertes")
        record("\(proofPrefix)-recherches-cloche")

        supprimer(Attendus.nuits, dans: ecran)
        supprimer(Attendus.weekEnds, dans: ecran)
        require("Plus aucune recherche sauvegardée") { self.element("recherches-vide").exists }
        XCTAssertTrue(element("recherches-vide-creer").exists, "« Créer une recherche » mène à Explorer")
        XCTAssertFalse(element("recherches-action-erreur").exists, "aucune erreur en démonstration")
        record("\(proofPrefix)-recherches-vide")
        verifierAucuneRequete()
    }

    func testAlerteRapideSansDoublonPuisAllerALaRecherche() throws {
        launchDemo()
        connexionDemo()
        tabButton("tab-explorer", label: "Explorer").tap()
        attendreExplorer()

        activerAlerteRapide(attendu: "Alerte créée")
        record("\(proofPrefix)-alerte-rapide-creee")
        tap("explorer-avis-fermer")
        require("L'avis est refermé") { !self.element("alerte-confirmee").exists }
        activerAlerteRapide(attendu: "Votre alerte est active")

        let ecran = ouvrirRecherches()
        XCTAssertEqual(elements(withPrefix: "recherche-appliquer-").count, 3, "une recherche créée, réutilisée ensuite : aucun doublon")
        let creee = element("recherche-demo-recherche-ajout-1")
        require("La recherche de l'alerte rapide est listée en tête") { creee.exists }
        XCTAssertTrue(element("recherche-etat-demo-recherche-ajout-1").label.contains("Alertes toutes les heures"))
        record("\(proofPrefix)-alerte-rapide-liste")

        // « Aller à la recherche » : Explorer reçoit les critères de « Nuits autour de Paris » (rayon 30 km, nuit).
        let aller = element("recherche-appliquer-\(Attendus.nuits)")
        scrollTo(aller, in: ecran)
        aller.tap()
        let avis = element("explorer-recherche-appliquee")
        require("Explorer applique la recherche", timeout: 30) {
            avis.exists && self.element("chip-nuit").isSelected
                && (self.containerVisible(self.element("missions-list")) || self.element("missions-empty").exists)
        }
        XCTAssertTrue(avis.label.contains("Filtres « Nuits autour de Paris » appliqués"), avis.label)
        XCTAssertFalse(element("chip-weekend").isSelected, "une seule dimension d'horaire")
        if element("missions-rayon").exists {
            XCTAssertEqual(element("missions-rayon").label, "dans un rayon de 30 km", "rayon de la recherche appliqué")
        }
        record("\(proofPrefix)-recherche-appliquee")
        verifierAucuneRequete()
    }

    // MARK: Étapes

    private func ouvrirRecherches() -> XCUIElement {
        tabButton("tab-profil", label: "Profil").tap()
        let liste = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(liste) }
        let entree = element("hub-recherches")
        scrollTo(entree, in: liste)
        require("L'entrée « Recherches sauvegardées » est atteignable") { self.visible(entree) }
        XCTAssertTrue(entree.label.contains("Recherches sauvegardées"), entree.label)
        entree.tap()
        let ecran = defilement("recherches-screen")
        require("Les recherches sont relues", timeout: 30) {
            self.containerVisible(ecran) && (self.element("recherche-\(Attendus.nuits)").exists || self.element("recherches-vide").exists)
        }
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (T4) : jamais un renvoi web")
        return ecran
    }

    private func activerAlerteRapide(attendu: String) {
        let bouton = element("explorer-alerte-rapide")
        require("L'alerte rapide est proposée dans la barre d'Explorer") { bouton.exists && bouton.isHittable }
        bouton.tap()
        require("La confirmation de l'alerte est affichée") {
            self.containerVisible(self.element("alerte-rapide")) && self.element("alerte-rapide-confirm").exists
        }
        XCTAssertEqual(element("alerte-rapide-title").label, "🔔 Créer une alerte missions")
        XCTAssertTrue(element("alerte-rapide-message").label.contains("(rayon 50 km)"), element("alerte-rapide-message").label)
        tap("alerte-rapide-confirm")
        require("L'alerte est confirmée par relecture") {
            !self.element("alerte-rapide").exists && self.element("alerte-confirmee").exists
        }
        XCTAssertTrue(element("alerte-confirmee").label.contains(attendu), element("alerte-confirmee").label)
    }

    private func supprimer(_ id: String, dans ecran: XCUIElement) {
        let bouton = element("recherche-supprimer-\(id)")
        scrollTo(bouton, in: ecran)
        bouton.tap()
        require("La confirmation de la suppression est affichée") {
            self.containerVisible(self.element("recherche-suppression")) && self.element("recherche-suppression-confirm").exists
        }
        XCTAssertTrue(element("recherche-suppression-title").label.hasPrefix("Supprimer la recherche « "))
        tap("recherche-suppression-confirm")
        require("La recherche \(id) n'est plus listée") {
            !self.element("recherche-suppression").exists && !self.element("recherche-\(id)").exists
        }
    }

    /// Conteneur de défilement : la `ScrollView` portant l'identifiant, sinon la première correspondance.
    private func defilement(_ identifier: String) -> XCUIElement {
        let typee = app.scrollViews.matching(identifier: identifier).firstMatch
        return typee.exists ? typee : element(identifier)
    }

    private func attendreExplorer() {
        let count = element("missions-count")
        require("Explorer affiche \(Attendus.total) missions", timeout: 30) {
            self.containerVisible(self.element("missions-list")) && count.exists && count.label == "\(Attendus.total) missions"
        }
    }

    /// Profil remis à sa racine (l'écran des recherches y est empilé), puis sentinelle réseau.
    private func verifierAucuneRequete() {
        tabButton("tab-profil", label: "Profil").tap()
        if element("recherches-screen").exists {
            let back = app.navigationBars.buttons.firstMatch
            require("Le bouton retour est disponible") { self.visible(back) }
            back.tap()
            require("L'écran des recherches est retiré") { !self.element("recherches-screen").exists }
        }
        let liste = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(liste) }
        let sentinelle = element("network-sentinel")
        scrollTo(sentinelle, in: liste, downward: false)
        require("La sentinelle réseau est exposée") { sentinelle.exists }
        XCTAssertEqual(sentinelle.label, "0 requête", "les recherches sauvegardées n'émettent aucune requête en démonstration")
    }

    private func connexionDemo() {
        let scroll = element("login-scroll")
        require("L'écran de connexion est affiché") { self.containerVisible(scroll) }
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
        toucherSeConnecter(submit, "La session démo est prête") { self.tabBarExists }
    }
}
