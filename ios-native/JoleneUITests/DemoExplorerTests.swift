import XCTest

/// Explorer du lot 1 (T4a) en mode démonstration, sur iPhone, iPad portrait et iPad paysage :
/// chips rapides, feuille de filtres (rayon, contrat, réinitialisation), compteur, badge du
/// bouton filtres, état vide (action secondaire du web ET « Actualiser ») et carte en lecture
/// seule du détail (aperçu hors ligne : aucune requête).
///
/// Les comptes attendus sont prouvés par `MissionsBusinessFiltresTests.testComptesDuMondeDemoParFiltre`
/// et `testEtatVideDuMondeDemoProposeElargirEtActualiser` (`DemoExplorerAttendus`, JoleneCoreTests)
/// sur les mêmes fixtures que l'app ; la relecture « mêmes critères » d'« Actualiser » par
/// `ExplorerModelsTests.testEtatVideActualiserRelitAvecLesMemesCriteres`.
final class DemoExplorerTests: JoleneUITestCase {
    private enum Attendus {
        static let total = 30
        static let urgentes = 6
        static let weekend = 11
        static let nuit = 7
        /// Rayon minimum (5 km) : seul l'établissement à 1,4 km du profil démo reste.
        static let rayonMinimum = 10
        static let cdd = 20
        /// Rayon minimum + Libéral : 0 ; « Élargir le rayon (+20 km) » → 25 km, 10 missions libérales.
        static let liberalApresElargissement = 10
        static let premierEtablissement = "Établissement fictif République · 75011 Paris"
    }

    func testChipsRapidesFiltrentLaListe() throws {
        ouvrirExplorer()

        basculer("chip-urgentes", attendu: Attendus.urgentes, selectionnee: true)
        record("\(proofPrefix)-explorer-chip-urgentes")
        basculer("chip-urgentes", attendu: Attendus.total, selectionnee: false)

        basculer("chip-weekend", attendu: Attendus.weekend, selectionnee: true)
        // Une seule dimension d'horaire : « Nuit » remplace « Week-end ».
        basculer("chip-nuit", attendu: Attendus.nuit, selectionnee: true)
        XCTAssertFalse(element("chip-weekend").isSelected, "Week-end n'est plus sélectionnée une fois Nuit choisie")
        record("\(proofPrefix)-explorer-chip-nuit")
        basculer("chip-nuit", attendu: Attendus.total, selectionnee: false)
        XCTAssertEqual(element("explorer-filtres-ouvrir").value as? String, "Aucun filtre actif",
                       "les chips ne comptent pas dans le badge du bouton Filtres")
    }

    func testFiltresRayonContratEtReinitialisation() throws {
        ouvrirExplorer()
        XCTAssertEqual(element("explorer-filtres-ouvrir").value as? String, "Aucun filtre actif")

        // Rayon minimum : le compteur baisse.
        ouvrirFiltres()
        let rayon = app.sliders.matching(identifier: "filtre-rayon").firstMatch
        scrollTo(rayon, in: feuilleFiltres)
        XCTAssertEqual(element("filtre-rayon-valeur").label, "Rayon : 50 km", "rayon du profil démo")
        rayon.adjust(toNormalizedSliderPosition: 0)
        require("Le rayon minimum est sélectionné") { self.element("filtre-rayon-valeur").label == "Rayon : 5 km" }
        record("\(proofPrefix)-explorer-filtres-rayon")
        appliquerFiltres(attendu: Attendus.rayonMinimum)
        XCTAssertEqual(element("missions-rayon").label, "dans un rayon de 5 km")

        // Réinitialiser : retour aux 30 missions.
        reinitialiserFiltres()
        XCTAssertEqual(element("missions-rayon").label, "dans un rayon de 50 km")

        // Contrat CDD : un critère actif dans le badge.
        ouvrirFiltres()
        let contrat = app.segmentedControls.matching(identifier: "filtre-contrat").firstMatch
        scrollTo(contrat, in: feuilleFiltres)
        let cdd = contrat.buttons.element(boundBy: 1)
        require("Le segment CDD est atteignable") { self.visible(cdd) }
        cdd.tap()
        require("CDD est sélectionné") { cdd.isSelected }
        appliquerFiltres(attendu: Attendus.cdd)
        require("Le bouton Filtres annonce un critère actif") {
            (self.element("explorer-filtres-ouvrir").value as? String) == "1 filtre actif"
        }
        record("\(proofPrefix)-explorer-filtres-cdd")

        reinitialiserFiltres()
        XCTAssertEqual(element("explorer-filtres-ouvrir").value as? String, "Aucun filtre actif")
    }

    /// Revue T4a (majeur) : dans le cas courant (rayon < 100 km, aucune chip), l'état vide garde
    /// « Actualiser » à côté de l'action secondaire du web ; l'actualisation conserve les critères.
    func testEtatVideGardeActualiserACoteDeLActionSecondaire() throws {
        ouvrirExplorer()

        // Rayon minimum + Libéral : aucune mission démo dans 5 km n'est libérale.
        ouvrirFiltres()
        let rayon = app.sliders.matching(identifier: "filtre-rayon").firstMatch
        scrollTo(rayon, in: feuilleFiltres)
        rayon.adjust(toNormalizedSliderPosition: 0)
        require("Le rayon minimum est sélectionné") { self.element("filtre-rayon-valeur").label == "Rayon : 5 km" }
        let contrat = app.segmentedControls.matching(identifier: "filtre-contrat").firstMatch
        scrollTo(contrat, in: feuilleFiltres)
        let liberal = contrat.buttons.element(boundBy: 2)
        require("Le segment Libéral est atteignable") { self.visible(liberal) }
        liberal.tap()
        require("Libéral est sélectionné") { liberal.isSelected }
        tap("filtres-apply")
        require("La feuille de filtres est fermée") { !self.element("explorer-filtres").exists }

        attendreEtatVide()
        let elargir = element("missions-empty-action")
        let actualiser = element("missions-refresh")
        require("« Élargir le rayon » et « Actualiser » sont tous deux atteignables") {
            self.visible(elargir) && self.visible(actualiser)
        }
        XCTAssertEqual(elargir.label, "Élargir le rayon (+20 km)")
        XCTAssertEqual(actualiser.label, "Actualiser")
        record("\(proofPrefix)-explorer-etat-vide")

        // Actualiser : relecture avec les mêmes critères, l'état vide et le badge demeurent.
        actualiser.tap()
        attendreEtatVide()
        require("Les critères sont conservés par l'actualisation") {
            (self.element("explorer-filtres-ouvrir").value as? String) == "1 filtre actif"
        }
        require("« Actualiser » reste disponible après la relecture") {
            self.visible(self.element("missions-refresh")) && self.element("missions-refresh").isEnabled
        }
        XCTAssertFalse(element("missions-refresh-error").exists, "aucune erreur d'actualisation en démonstration")

        // Élargir le rayon : 25 km atteint le cabinet libéral.
        tap("missions-empty-action")
        attendreCompteur(Attendus.liberalApresElargissement)
        XCTAssertEqual(element("missions-rayon").label, "dans un rayon de 25 km")
        record("\(proofPrefix)-explorer-etat-vide-elargi")

        reinitialiserFiltres()
        XCTAssertEqual(element("explorer-filtres-ouvrir").value as? String, "Aucun filtre actif")
    }

    func testCarteEnLectureSeuleDansLeDetailSansRequete() throws {
        ouvrirExplorer()
        let rows = elements(withPrefix: "mission-row-")
        require("Au moins une cellule mission est visible") { rows.count > 0 && self.visible(rows.firstMatch) }
        rows.firstMatch.tap()
        require("Le détail de la mission est rendu") {
            self.containerVisible(self.element("mission-detail")) && self.visible(self.element("mission-detail-title"))
        }
        // Résolu une fois le détail affiché, pour retenir la `ScrollView` si elle porte l'identifiant.
        let detail = defilement("mission-detail")
        let legende = element("mission-detail-carte-legende")
        scrollTo(legende, in: detail)
        XCTAssertEqual(legende.label, Attendus.premierEtablissement,
                       "la carte est centrée sur l'établissement de la mission la plus proche")
        XCTAssertTrue(containerVisible(element("mission-detail-carte")), "le bloc carte est affiché")
        XCTAssertTrue(element("mission-detail-carte-demo").exists, "démonstration : aperçu dessiné localement")
        XCTAssertFalse(element("mission-detail-carte-map").exists, "aucune carte Apple Plans (tuiles réseau) en démonstration")
        record("\(proofPrefix)-mission-detail-carte")

        let back = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(back) }
        back.tap()
        require("La liste est de retour") { self.containerVisible(self.element("missions-list")) }

        tabButton("tab-profil", label: "Profil").tap()
        let sentinel = element("network-sentinel")
        require("La sentinelle réseau est exposée") { sentinel.exists }
        XCTAssertEqual(sentinel.label, "0 requête", "le détail et sa carte n'émettent aucune requête en démonstration")
    }

    // MARK: Étapes

    /// Conteneur de défilement : la `ScrollView` portant l'identifiant (le glissement de `scrollTo`
    /// se fait dans son cadre), sinon la première correspondance, comme `element(_:)` du lot 0.
    private func defilement(_ identifier: String) -> XCUIElement {
        let typee = app.scrollViews.matching(identifier: identifier).firstMatch
        return typee.exists ? typee : element(identifier)
    }

    /// Défilement de la feuille de filtres.
    private var feuilleFiltres: XCUIElement { defilement("explorer-filtres") }

    /// Connexion démo puis onglet Explorer à 30 missions. N'attend que la barre d'onglets : le
    /// contenu de l'onglet Accueil évolue avec le lot 1 (T3).
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
        for chip in ["chip-urgentes", "chip-weekend", "chip-nuit", "chip-jour"] {
            XCTAssertTrue(element(chip).exists, "La chip \(chip) est affichée")
            XCTAssertFalse(element(chip).isSelected, "La chip \(chip) est inactive au départ")
        }
        record("\(proofPrefix)-explorer-chips")
    }

    private func attendreCompteur(_ attendu: Int, timeout: TimeInterval = 15) {
        let libelle = "\(attendu) mission\(attendu > 1 ? "s" : "")"
        let count = element("missions-count")
        require("Explorer affiche \(libelle)", timeout: timeout) {
            self.containerVisible(self.element("missions-list")) && count.exists && count.label == libelle
        }
        XCTAssertEqual(count.label, libelle)
    }

    /// État vide d'Explorer affiché (conteneur seulement : jamais `isHittable` sur un défilement).
    private func attendreEtatVide() {
        require("Explorer affiche l'état vide") {
            self.containerVisible(self.element("missions-empty")) && !self.element("missions-list").exists
        }
    }

    private func basculer(_ chip: String, attendu: Int, selectionnee: Bool) {
        tap(chip)
        attendreCompteur(attendu)
        require("La chip \(chip) est \(selectionnee ? "sélectionnée" : "désélectionnée")") {
            self.element(chip).isSelected == selectionnee
        }
    }

    private func ouvrirFiltres() {
        tap("explorer-filtres-ouvrir")
        require("La feuille de filtres est affichée") {
            self.containerVisible(self.element("explorer-filtres")) && self.visible(self.element("filtres-apply"))
        }
    }

    private func appliquerFiltres(attendu: Int) {
        tap("filtres-apply")
        require("La feuille de filtres est fermée") { !self.element("explorer-filtres").exists }
        attendreCompteur(attendu)
    }

    private func reinitialiserFiltres() {
        ouvrirFiltres()
        tap("filtres-reset")
        require("Le rayon revient à celui du profil") { self.element("filtre-rayon-valeur").label == "Rayon : 50 km" }
        appliquerFiltres(attendu: Attendus.total)
    }
}
