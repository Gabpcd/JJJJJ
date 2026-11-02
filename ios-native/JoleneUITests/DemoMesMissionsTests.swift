import XCTest

/// Mes missions démo (lot 1, T5) sur iPhone, iPad portrait et iPad paysage : onglets Candidatures /
/// À venir / Passées servis par `DemoMesMissionsGateway` (`demo-mes-missions.json` et missions
/// ASSIGNEE de `demo-dashboard.json`, horloge fixée 2026-11-02T00:00:00Z). Les libellés attendus sont
/// ceux que `DemoMesMissionsTests` (JoleneCore) affirme sur le port : un écart entre l'écran et le port
/// fait échouer l'un des deux. Ajout au calendrier (décision 18) : calendrier démo en mémoire, aucune
/// demande système ; un second tap n'ajoute rien (journal) ; accès refusé simulé par la surcharge DEBUG
/// `JOLENE_FORCE_CALENDRIER_REFUS` (`testCalendrierAccesRefuse`). L'écriture EventKit réelle est
/// prouvée sur appareil (`RECETTE_DEVICE_LOT1.md` §4).
final class DemoMesMissionsTests: JoleneUITestCase {
    private static let euro = "\u{00A0}€"

    func testMesMissionsDemo() throws {
        launchDemo()
        connexionDemo()
        let scroll = ouvrirMesMissions()

        // À venir, onglet par défaut (web : `mes_missions`) : prochain créneau, heure de Paris, taux serveur.
        XCTAssertTrue(element("missions-tab-avenir").isSelected, "À venir est l'onglet par défaut, comme le web")
        verifier("mes-mission-demo-assignee-001", dans: scroll, contient: [
            "Assignée", "Démonstration · Mission assignée 1", "Établissement fictif République · Paris",
            "Prochain créneau : 5 nov. · 08h00 → 16h00 (8h)", "27,00\(Self.euro)/h",
        ])
        verifier("mes-mission-demo-assignee-002", dans: scroll, contient: [
            "Établissement fictif des Lilas · Les Lilas", "Prochain créneau : 9 nov. · 08h00 → 16h00 (8h)", "30,00\(Self.euro)/h",
        ])
        XCTAssertFalse(element("missions-load-more").exists, "une seule page en démo : pas de « Charger plus »")
        record("\(proofPrefix)-mes-missions-a-venir")

        // Calendrier : deux créneaux PREVISIONNEL, puis aucun doublon au second tap.
        let bouton = element("calendrier-demo-assignee-002")
        degager(bouton, dans: scroll)
        bouton.tap()
        let issue = element("missions-calendrier-issue")
        require("L'ajout au calendrier rend son issue") { issue.exists && issue.label.contains("2 créneaux ajoutés à votre calendrier.") }
        degager(bouton, dans: scroll)
        bouton.tap()
        require("Un second ajout n'écrit aucun doublon") {
            issue.exists && issue.label.contains("Les créneaux de cette mission sont déjà dans votre calendrier.")
        }
        record("\(proofPrefix)-mes-missions-calendrier")

        // Candidatures en attente : pastilles du web, mission relue, nom par fn_etablissements_safe.
        tap("missions-tab-candidatures")
        require("L'onglet Candidatures est lu", timeout: 30) {
            self.element("missions-tab-candidatures").isSelected && self.element("mes-mission-demo-mission-004").exists
        }
        verifier("mes-mission-demo-mission-004", dans: scroll, contient: [
            "⏳ En attente de réponse", "Salarié", "Démonstration · Soins de suite 4", "Établissement fictif République · Paris",
            "6 nov. · 21h00 → 05h00", "26,00\(Self.euro)/h",
        ])
        verifier("mes-mission-demo-mission-009", dans: scroll, contient: [
            "★ Priorité historique", "Libéral", "Cabinet fictif du Parc · Vincennes", "11 nov. · 08h00 → 16h00",
        ])
        XCTAssertFalse(element("calendrier-demo-mission-004").exists, "le calendrier n'est proposé qu'aux missions à venir")
        record("\(proofPrefix)-mes-missions-candidatures")

        // Passées : période, montant serveur selon le régime, note « net estimé » verbatim.
        tap("missions-tab-passees")
        require("L'onglet Passées est lu", timeout: 30) {
            self.element("missions-tab-passees").isSelected && self.element("mes-mission-demo-terminee-001").exists
        }
        verifier("mes-mission-demo-terminee-001", dans: scroll, contient: [
            "Terminée", "Démonstration · Mission terminée 1", "1 nov. 2026", "Net salarié estimé* : ~162,40\(Self.euro)",
        ])
        verifier("mes-mission-demo-terminee-002", dans: scroll, contient: ["20 oct. → 21 oct. 2026", "Honoraires bruts : 448,00\(Self.euro)"])
        verifier("mes-mission-demo-annulee-001", dans: scroll, contient: ["Annulée", "Démonstration · Mission annulée", "12 oct. 2026"])
        let note = element("missions-note-net-estime")
        scrollTo(note, in: scroll)
        XCTAssertTrue(note.label.hasPrefix("* Pour une mission salariée, le net est estimé"), "note : \(note.label)")
        record("\(proofPrefix)-mes-missions-passees")

        // Détail d'une mission passée, puis retour sur l'onglet Passées.
        let ligne = element("mes-mission-demo-terminee-002")
        degager(ligne, dans: scroll)
        ligne.tap()
        let titre = element("mission-detail-title")
        require("Le détail de la mission passée est rendu") {
            self.containerVisible(self.element("mission-detail")) && self.visible(titre)
        }
        XCTAssertEqual(titre.label, "Démonstration · Mission terminée 2")
        XCTAssertTrue(element("mission-detail-creneau-2").exists, "les deux créneaux sont listés")
        let retour = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(retour) }
        retour.tap()
        require("Mes missions est de retour sur l'onglet Passées") {
            self.containerVisible(self.element("mes-missions-screen")) && self.element("missions-tab-passees").isSelected
                && self.element("mes-mission-demo-terminee-002").exists && !titre.exists
        }
    }

    func testCalendrierAccesRefuse() throws {
        launchDemo(environment: ["JOLENE_FORCE_CALENDRIER_REFUS": "1"])
        connexionDemo()
        let scroll = ouvrirMesMissions()
        let bouton = element("calendrier-demo-assignee-001")
        degager(bouton, dans: scroll)
        bouton.tap()
        let issue = element("missions-calendrier-issue")
        require("L'accès refusé est expliqué, sans écriture") {
            issue.exists && issue.label.contains("L'accès au calendrier n'est pas autorisé.")
        }
        record("\(proofPrefix)-mes-missions-calendrier-refuse")
    }

    // MARK: - Étapes

    private func connexionDemo() {
        require("L'écran de connexion est affiché") { self.containerVisible(self.element("login-scroll")) }
        let scroll = element("login-scroll")
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
        if app.keyboards.firstMatch.exists, !visible(submit) {
            scrollTo(submit, in: scroll)
        }
        submit.tap()
        require("La session démo est prête", timeout: 30) { self.tabBarExists && self.containerVisible(self.element("accueil-screen")) }
    }

    /// Ouvre l'onglet Mes missions et attend la première ligne d'À venir ; rend le conteneur de défilement.
    private func ouvrirMesMissions() -> XCUIElement {
        tabButton("tab-missions", label: "Mes missions").tap()
        require("Mes missions affiche ses missions à venir", timeout: 30) {
            self.containerVisible(self.element("mes-missions-screen")) && self.element("mes-mission-demo-assignee-001").exists
                && !self.element("mes-missions-loading").exists
        }
        XCTAssertFalse(element("mes-missions-error").exists, "aucune erreur en démo")
        for identifiant in ["missions-tab-candidatures", "missions-tab-avenir", "missions-tab-passees"] {
            require("L'onglet \(identifiant) est atteignable") { self.visible(self.element(identifiant)) }
        }
        return element("mes-missions-scroll")
    }

    /// Défilement borné jusqu'à la ligne, puis chaque fragment attendu dans son libellé accessible,
    /// lu une seule fois.
    private func verifier(_ identifiant: String, dans conteneur: XCUIElement, contient fragments: [String],
                          file: StaticString = #filePath, line: UInt = #line) {
        let ligne = element(identifiant)
        scrollTo(ligne, in: conteneur)
        let libelle = ligne.label
        for fragment in fragments {
            XCTAssertTrue(libelle.contains(fragment), "\(identifiant) : « \(fragment) » absent de « \(libelle) »",
                          file: file, line: line)
        }
    }

    /// Barre qui recouvre `cible` : le défilement s'étend sous la barre d'onglets (iPhone) ; sur iPad
    /// (iPadOS 18 et suivants) la barre d'onglets est en haut, sans élément `TabBar`.
    private func recouverte(_ cible: XCUIElement) -> Bool {
        let onglets = app.tabBars.firstMatch
        if onglets.exists, cible.frame.maxY > onglets.frame.minY { return true }
        let selecteur = element("missions-tabs")
        return selecteur.exists && cible.frame.minY < selecteur.frame.maxY
    }

    /// Avant un tap : défilement borné jusqu'à la cible, puis dégagement des barres (glissements courts
    /// et bornés, aucune attente arbitraire).
    private func degager(_ cible: XCUIElement, dans conteneur: XCUIElement) {
        scrollTo(cible, in: conteneur)
        var essais = 0
        while essais < 6, recouverte(cible) {
            let sousOnglets = app.tabBars.firstMatch.exists && cible.frame.maxY > app.tabBars.firstMatch.frame.minY
            if sousOnglets { drag(conteneur, fromY: 0.6, toY: 0.4) } else { drag(conteneur, fromY: 0.4, toY: 0.6) }
            essais += 1
        }
        require("La cible est atteignable hors des barres") { self.visible(cible) && !self.recouverte(cible) }
    }
}
