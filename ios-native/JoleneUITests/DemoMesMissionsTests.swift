import XCTest

/// Mes missions démo (lot 1, T5) sur iPhone, iPad portrait et iPad paysage : onglets Candidatures /
/// À venir / Passées servis par `DemoMesMissionsGateway` (`demo-mes-missions.json` et les dix missions
/// ASSIGNEE de `demo-dashboard.json`, horloge fixée 2026-11-02T00:00:00Z). Les libellés attendus sont
/// ceux que `DemoMesMissionsTests` (JoleneCore) affirme sur le port : un écart entre l'écran et le port
/// fait échouer l'un des deux. Ajout au calendrier (décision 18) : calendrier démo en mémoire, aucune
/// demande système, chaque issue le dit (`IssueAjoutCalendrier.mentionDemo`) ; issue dans un bandeau
/// superposé, visible sans défilement et sans décaler la liste ; un second tap n'ajoute rien (journal) ;
/// accès refusé simulé par la surcharge DEBUG `JOLENE_FORCE_CALENDRIER_REFUS`. L'écriture EventKit
/// réelle est prouvée sur appareil (`RECETTE_DEVICE_LOT1.md` §4).
///
/// Recette des états (CLAUDE.md, revue B8 de T5), surcharges DEBUG lues par `AppContainer`. Budget CI
/// (revue B8 de T5, 2e passe) : chaque lancement coûte une connexion démo (79 à 222 s par test sur
/// iPad paysage, run 41538145532) ; les surcharges compatibles partagent donc un lancement :
/// - `testMesMissionsPanneRepriseChargerPlusEtCalendrierRefuse` : `JOLENE_FORCE_MES_MISSIONS_ECHEC=1`,
///   `JOLENE_DEMO_MES_MISSIONS_PAGE=4` et `JOLENE_FORCE_CALENDRIER_REFUS=1` — erreur puis « Réessayer »,
///   « Charger plus » en lecture cumulative (4, 8 puis 10 missions), accès au calendrier refusé depuis la
///   dernière ligne, liste défilée (la première ligne est sortie par le haut), puis erreur et reprise de
///   l'onglet Passées ;
/// - `testMesMissionsSessionExpireePuisVidesVersExplorer` : `JOLENE_FORCE_MES_MISSIONS_ECHEC=session` et
///   `JOLENE_FORCE_MES_MISSIONS_VIDE=1` — « Vérifier ma session » sur chaque onglet (l'indicateur est rangé
///   par onglet), états vides, puis renvoi vers Explorer.
final class DemoMesMissionsTests: JoleneUITestCase {
    private static let euro = "\u{00A0}€"
    /// `IssueAjoutCalendrier.dejaAjoutes` (JoleneCore) : l'app ne relit pas le calendrier.
    private static let dejaAjoutes = "Les créneaux de cette mission ont déjà été ajoutés à votre calendrier depuis Jolene sur cet appareil."
    /// `IssueAjoutCalendrier.mentionDemo` (JoleneCore) : rien n'est écrit sur l'appareil en démo (PRINCIPES §7).
    private static let mentionDemo = "Démonstration : rien n'est écrit dans le calendrier de l'appareil."
    /// `SessionController.timeoutMessage` : panne simulée comme un délai dépassé.
    private static let messageDelai = "Le service ne répond pas. Vérifiez votre connexion puis réessayez."
    /// `SessionController.sessionExpiredMessage`.
    private static let messageSession = "Votre session a expiré. Reconnectez-vous."

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
        XCTAssertFalse(element("missions-load-more").exists, "dix missions sur une page de 50 : pas de « Charger plus »")
        record("\(proofPrefix)-mes-missions-a-venir")

        // Calendrier : deux créneaux PREVISIONNEL ; bandeau d'issue visible sans défilement, mention de la
        // démo ; fermeture ; puis aucun doublon au second tap.
        let bouton = element("calendrier-demo-assignee-002")
        degager(bouton, dans: scroll)
        bouton.tap()
        let issue = element("missions-calendrier-issue")
        require("L'ajout au calendrier rend son issue, visible hors des barres") {
            self.visible(issue) && !self.recouverte(issue) && issue.label.contains("2 créneaux ajoutés à votre calendrier.")
        }
        XCTAssertTrue(issue.label.contains(Self.mentionDemo), "mode démo affiché : « \(issue.label) »")
        tap("missions-calendrier-issue-fermer")
        require("Le bandeau d'issue se ferme") { !issue.exists }
        degager(bouton, dans: scroll)
        bouton.tap()
        require("Un second ajout n'écrit aucun doublon") {
            self.visible(issue) && !self.recouverte(issue) && issue.label.contains(Self.dejaAjoutes)
        }
        record("\(proofPrefix)-mes-missions-calendrier")

        // Candidatures en attente : pastilles du web, mission relue, nom par fn_etablissements_safe.
        tap("missions-tab-candidatures")
        require("L'onglet Candidatures est lu", timeout: 30) {
            self.element("missions-tab-candidatures").isSelected && self.element("mes-mission-demo-mission-004").exists
        }
        XCTAssertFalse(issue.exists, "le bandeau d'issue ne suit pas le changement d'onglet")
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

    // MARK: - Recette des états (revue B8 de T5), lancements partagés (budget CI, 2e passe)

    /// `JOLENE_FORCE_MES_MISSIONS_ECHEC=1` (première lecture de chaque onglet en panne, comme un délai
    /// dépassé), `JOLENE_DEMO_MES_MISSIONS_PAGE=4` (pages de 4 missions) et
    /// `JOLENE_FORCE_CALENDRIER_REFUS=1` (accès au calendrier refusé), dans une même session.
    func testMesMissionsPanneRepriseChargerPlusEtCalendrierRefuse() throws {
        launchDemo(environment: ["JOLENE_FORCE_MES_MISSIONS_ECHEC": "1", "JOLENE_DEMO_MES_MISSIONS_PAGE": "4",
                                 "JOLENE_FORCE_CALENDRIER_REFUS": "1"])
        connexionDemo()
        tabButton("tab-missions", label: "Mes missions").tap()
        let scroll = element("mes-missions-scroll")
        let erreur = element("mes-missions-error")

        // 1. Panne de la première lecture, puis « Réessayer ».
        require("Mes missions affiche l'état d'erreur", timeout: 30) {
            self.containerVisible(erreur) && !self.element("mes-missions-loading").exists
        }
        XCTAssertTrue(text("Missions momentanément indisponibles").exists, "titre de l'état d'erreur")
        XCTAssertTrue(text(Self.messageDelai).exists, "message de la panne simulée")
        XCTAssertFalse(element("mes-missions-session-expired").exists, "une panne n'est pas une session expirée")
        XCTAssertFalse(element("mes-mission-demo-assignee-001").exists, "aucune mission fabriquée")
        record("\(proofPrefix)-mes-missions-erreur")

        activer("mes-missions-retry", dans: scroll)
        require("« Réessayer » relit la première page des missions à venir", timeout: 30) {
            self.element("mes-mission-demo-assignee-004").exists && !erreur.exists && !self.element("mes-missions-loading").exists
        }
        XCTAssertFalse(element("mes-mission-demo-assignee-005").exists, "pages de quatre : seule la première est lue")
        verifier("mes-mission-demo-assignee-001", dans: scroll, contient: [
            "Démonstration · Mission assignée 1", "Prochain créneau : 5 nov. · 08h00 → 16h00 (8h)",
        ])
        record("\(proofPrefix)-mes-missions-reprise")

        // 2. « Charger plus » : lecture cumulative tant que la lecture est pleine (4, puis 8), puis absent (10).
        let plus = element("missions-load-more")
        degager(plus, dans: scroll)
        XCTAssertEqual(plus.label, "Charger plus de missions")
        plus.tap()
        require("« Charger plus » relit les deux premières pages", timeout: 30) {
            self.element("mes-mission-demo-assignee-008").exists && plus.exists && plus.isEnabled
        }
        XCTAssertFalse(element("mes-mission-demo-assignee-009").exists, "deux pages de quatre")
        XCTAssertTrue(element("mes-mission-demo-assignee-001").exists, "lecture cumulative : la première mission reste")
        record("\(proofPrefix)-mes-missions-charger-plus")
        degager(plus, dans: scroll)
        plus.tap()
        require("Après une lecture incomplète, « Charger plus » disparaît", timeout: 30) {
            !plus.exists && self.element("mes-mission-demo-assignee-010").exists
        }
        XCTAssertFalse(element("missions-load-more-error").exists)
        verifier("mes-mission-demo-assignee-010", dans: scroll, contient: ["Prochain créneau : 28 nov. · 08h00 → 16h00 (8h)"])
        record("\(proofPrefix)-mes-missions-charger-plus-fin")

        // 3. Calendrier refusé depuis la dernière ligne, liste défilée : le bandeau superposé reste visible
        //    sans défilement et ne décale pas la liste (un bandeau inséré en tête de liste serait hors écran).
        let bouton = element("calendrier-demo-assignee-010")
        degager(bouton, dans: scroll)
        let avant = cadreImmobile(bouton)
        XCTAssertGreaterThan(avant.midY, scroll.frame.midY, "la ligne touchée est dans la moitié basse du défilement")
        let premiere = element("mes-mission-demo-assignee-001")
        XCTAssertTrue(!premiere.exists || premiere.frame.maxY <= scroll.frame.minY + 1,
                      "liste défilée : la première ligne est sortie par le haut (\(premiere.frame) / \(scroll.frame))")
        bouton.tap()
        let issue = element("missions-calendrier-issue")
        require("L'accès refusé est expliqué, visible sans défilement") {
            self.visible(issue) && !self.recouverte(issue) && issue.label.contains("L'accès au calendrier n'est pas autorisé.")
        }
        XCTAssertTrue(issue.label.contains(Self.mentionDemo), "mode démo affiché : « \(issue.label) »")
        XCTAssertEqual(bouton.frame.minY, avant.minY, accuracy: 1, "le bandeau superposé ne décale pas la liste")
        record("\(proofPrefix)-mes-missions-calendrier-refuse")
        tap("missions-calendrier-issue-fermer")
        require("Le bandeau d'issue se ferme") { !issue.exists }

        // 4. Autre onglet : sa première lecture échoue aussi, puis « Réessayer » le relit.
        tap("missions-tab-passees")
        require("Passées affiche l'état d'erreur", timeout: 30) {
            self.element("missions-tab-passees").isSelected && self.containerVisible(erreur)
        }
        XCTAssertFalse(element("mes-mission-demo-terminee-001").exists, "aucune mission passée fabriquée")
        activer("mes-missions-retry", dans: scroll)
        require("« Réessayer » relit les missions passées", timeout: 30) {
            self.element("mes-mission-demo-terminee-001").exists && !erreur.exists && !self.element("mes-missions-loading").exists
        }
        verifier("mes-mission-demo-terminee-001", dans: scroll, contient: ["Net salarié estimé* : ~162,40\(Self.euro)"])
        record("\(proofPrefix)-mes-missions-reprise-passees")
    }

    /// `JOLENE_FORCE_MES_MISSIONS_ECHEC=session` (première lecture de chaque onglet en « session
    /// expirée ») et `JOLENE_FORCE_MES_MISSIONS_VIDE=1` (aucune ligne), dans une même session :
    /// « Vérifier ma session » revalide la session démo (même identité, aucun démontage) puis relit
    /// l'onglet, vide ; chaque onglet porte son propre état de session ; l'action de l'état vide ouvre
    /// Explorer (la recherche de missions ne vit qu'à cet onglet, comme sur le web).
    func testMesMissionsSessionExpireePuisVidesVersExplorer() throws {
        launchDemo(environment: ["JOLENE_FORCE_MES_MISSIONS_ECHEC": "session", "JOLENE_FORCE_MES_MISSIONS_VIDE": "1"])
        connexionDemo()
        tabButton("tab-missions", label: "Mes missions").tap()
        let scroll = element("mes-missions-scroll")
        let expiree = element("mes-missions-session-expired")

        // À venir : session à vérifier, puis vérification et état vide.
        require("Mes missions demande de vérifier la session", timeout: 30) {
            self.containerVisible(expiree) && !self.element("mes-missions-loading").exists
        }
        XCTAssertTrue(text("Session à vérifier").exists, "titre de l'état de session")
        XCTAssertTrue(text(Self.messageSession).exists, "message de la session expirée")
        XCTAssertFalse(element("mes-missions-error").exists, "une session expirée n'est pas une panne")
        XCTAssertFalse(element("mes-missions-retry").exists, "« Vérifier ma session » plutôt que « Réessayer »")
        record("\(proofPrefix)-mes-missions-session-expiree")

        activer("mes-missions-session-check", dans: scroll)
        require("La session revalidée relit À venir, vide", timeout: 30) {
            self.containerVisible(self.element("missions-empty-avenir")) && !expiree.exists
                && !self.element("mes-missions-loading").exists
        }
        XCTAssertTrue(element("missions-tab-avenir").isSelected, "Mes missions reste affiché, onglet À venir")
        XCTAssertFalse(element("login-scroll").exists, "session démo toujours valide : aucune reconnexion")
        XCTAssertTrue(text("Aucune mission à venir").exists)
        XCTAssertTrue(text("Découvrez les missions disponibles et postulez.").exists)
        XCTAssertTrue(element("missions-empty-action-avenir").exists, "action « Voir les missions disponibles »")
        XCTAssertFalse(element("mes-missions-error").exists, "une liste vide n'est pas une erreur")
        XCTAssertFalse(element("missions-load-more").exists, "rien à charger ensuite")
        XCTAssertEqual(elements(withPrefix: "mes-mission-").count, 0, "aucune ligne fabriquée")
        record("\(proofPrefix)-mes-missions-vide-a-venir")

        // Candidatures : sa propre session à vérifier (indicateur rangé par onglet), puis vide.
        tap("missions-tab-candidatures")
        require("Candidatures demande de vérifier la session", timeout: 30) {
            self.element("missions-tab-candidatures").isSelected && self.containerVisible(expiree)
        }
        activer("mes-missions-session-check", dans: scroll)
        require("Candidatures affiche son état vide", timeout: 30) {
            self.containerVisible(self.element("missions-empty-candidatures")) && !expiree.exists
        }
        XCTAssertTrue(text("Aucune candidature en attente").exists)

        // Passées : idem, puis renvoi vers Explorer depuis l'état vide.
        tap("missions-tab-passees")
        require("Passées demande de vérifier la session", timeout: 30) {
            self.element("missions-tab-passees").isSelected && self.containerVisible(expiree)
        }
        activer("mes-missions-session-check", dans: scroll)
        require("Passées affiche son état vide", timeout: 30) {
            self.containerVisible(self.element("missions-empty-passees")) && !expiree.exists
        }
        XCTAssertTrue(text("Aucune mission dans l'historique").exists)
        XCTAssertFalse(element("missions-note-net-estime").exists, "aucune note « net estimé » sans mission")
        record("\(proofPrefix)-mes-missions-vide-passees")

        activer("missions-empty-action-passees", dans: scroll)
        require("L'action de l'état vide ouvre Explorer", timeout: 30) {
            self.containerVisible(self.element("missions-list")) && self.element("missions-count").label == "30 missions"
        }
        record("\(proofPrefix)-mes-missions-vide-vers-explorer")
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

    /// Défilement borné jusqu'au contrôle, dégagement des barres, puis tap natif.
    private func activer(_ identifiant: String, dans conteneur: XCUIElement) {
        let cible = element(identifiant)
        degager(cible, dans: conteneur)
        require("Le contrôle \(identifiant) est activable") { cible.isEnabled }
        cible.tap()
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

    /// Cadre de `cible` une fois la liste immobile : deux lectures successives du prédicat borné
    /// identiques (fin de l'inertie du dernier glissement), aucune attente arbitraire.
    private func cadreImmobile(_ cible: XCUIElement) -> CGRect {
        var precedent = CGRect.null
        var immobile = CGRect.null
        require("La liste est immobile avant la mesure") {
            let courant = cible.frame
            defer { precedent = courant }
            guard !courant.isEmpty, courant == precedent else { return false }
            immobile = courant
            return true
        }
        return immobile
    }

    /// Barre qui recouvre `cible` : le défilement s'étend sous la barre d'onglets (iPhone) ; sur iPad
    /// (iPadOS 18 et suivants) la barre d'onglets est en haut, sans élément `TabBar`. Le bandeau
    /// d'issue du calendrier, superposé en haut de la liste, recouvre aussi ce qui passe dessous
    /// (sauf ses propres éléments).
    private func recouverte(_ cible: XCUIElement) -> Bool {
        let onglets = app.tabBars.firstMatch
        if onglets.exists, cible.frame.maxY > onglets.frame.minY { return true }
        let selecteur = element("missions-tabs")
        if selecteur.exists, cible.frame.minY < selecteur.frame.maxY { return true }
        let bandeau = element("missions-calendrier-bandeau")
        if !cible.identifier.hasPrefix("missions-calendrier-"), bandeau.exists, cible.frame.intersects(bandeau.frame) { return true }
        return false
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
