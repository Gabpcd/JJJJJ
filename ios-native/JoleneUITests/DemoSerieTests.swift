import XCTest

/// Détail de série (L4-T12) en démonstration, sur iPhone, iPad portrait et iPad paysage : lien universel simulé
/// (`-JOLENE_OPEN_URL https://jolene.app/soignant/missions/serie/<id>`, rejoué après la connexion) → écran natif
/// `serie-screen` empilé sur le Profil, jamais un renvoi web (fixture `demo-serie.json`).
///
/// - Pack de cinq missions : toutes cochées, décochage puis recochage, récapitulatif des créneaux, acceptation en
///   boucle, une issue par mission (quatre acceptées, une refusée par le serveur pour un conflit de planning, message
///   mot pour mot), mission refusée marquée en conflit et action bloquée tant qu'elle est cochée.
/// - Pack à l'arrêt : choix de contrat requis (lien vers le détail de la mission, aucune feuille de choix rejouée),
///   mission acceptée, refus de conformité du serveur affiché **tel que servi** dans `serie-code-travail`, mission
///   suivante jamais envoyée, mission déjà pourvue sans case à cocher ; après décochage, la suite s'accepte.
/// - Coupe-circuit `ios_natif_serie_actif` coupé : renvoi web de l'écran ; série inconnue : « Pack introuvable ».
/// Aucune requête réseau (sentinelle).
///
/// Les règles (boucle séquentielle, arrêt, aucun renvoi, réconciliation par relecture, textes à leur ligne web) sont
/// prouvées par `SerieModelTests`, `Lot4WiringSerieTests` et `SerieVerbatimTests` ; le transport par
/// `SupabaseSerieGatewayTests`.
final class DemoSerieTests: JoleneUITestCase {
    private enum Attendus {
        static let pack = "SERIE_1793577600000_demo01"
        static let arret = "SERIE_1793577600000_demo02"
        /// Refus du serveur (`fn_conflit_planning_soignant`), rejoué par la fixture.
        static let conflit = "Tu es déjà confirmé(e) sur « Démonstration · Mission assignée 4 » le 15/11 08h00–15/11 16h00. Ce créneau chevauche la mission."
        /// Exception du trigger de conformité, telle que servie (HARD STOP n°4 : jamais reformulée).
        static let refusConformite = "[CODE DU TRAVAIL] Repos insuffisant avant mission : 5.0 heures au lieu de 11h minimum (Art. L3131-1). Assignation bloquée."
        static let assignee = "✅ Vous êtes assigné(e) à cette mission"
    }

    func testPackAcceptationEnBoucleUneIssueParMission() throws {
        let ecran = ouvrirSerie(Attendus.pack, premiere: "demo-mission-001")
        XCTAssertEqual(element("serie-disponibles").label, "📋 5 missions disponibles sur 5")
        XCTAssertEqual(elements(withPrefix: "serie-selection-").count, 5, "cinq missions ouvertes au planning exact")
        let accepter = element("serie-accepter")
        scrollTo(accepter, in: ecran)
        XCTAssertEqual(accepter.label, "★ Accepter la sélection (5)", "toutes cochées à l'ouverture")
        XCTAssertFalse(element("serie-code-travail").exists)
        record("\(proofPrefix)-serie-pack")

        // Décochage puis recochage : la sélection envoyée est exactement celle affichée.
        let case28 = element("serie-selection-demo-mission-028")
        scrollTo(case28, in: ecran)
        XCTAssertTrue(case28.isSelected)
        XCTAssertEqual(case28.label, "Sélectionner la mission du 30 novembre 2026")
        // Bascules locales : un toucher perdu est rejoué une fois, seulement si la case et le compte sont inchangés.
        toucherPuisExiger(case28, "La mission est décochée",
                          rienNAChange: { case28.isSelected && accepter.label == "★ Accepter la sélection (5)" }) {
            !case28.isSelected && accepter.label == "★ Accepter la sélection (4)"
        }
        toucherPuisExiger(case28, "La mission est recochée",
                          rienNAChange: { !case28.isSelected && accepter.label == "★ Accepter la sélection (4)" }) {
            case28.isSelected && accepter.label == "★ Accepter la sélection (5)"
        }

        scrollTo(accepter, in: ecran)
        accepter.tap()
        confirmerSelection(missions: ["demo-mission-001", "demo-mission-010", "demo-mission-013", "demo-mission-025", "demo-mission-028"])

        let bilan = element("serie-bilan")
        require("Le bilan de la boucle est affiché", timeout: 60) { bilan.exists && !self.element("serie-confirmation").exists }
        scrollTo(bilan, in: ecran, downward: false)
        XCTAssertTrue(bilan.label.contains("4 mission(s) acceptée(s), 1 en conflit."), bilan.label)
        XCTAssertFalse(element("serie-code-travail").exists, "refus structuré du serveur : affiché sur la mission, pas d'arrêt")
        for id in ["demo-mission-001", "demo-mission-010", "demo-mission-025", "demo-mission-028"] {
            let issue = element("serie-resultat-\(id)")
            scrollTo(issue, in: ecran)
            XCTAssertTrue(issue.label.contains(Attendus.assignee), "\(id) : \(issue.label)")
            XCTAssertFalse(element("serie-selection-\(id)").exists, "\(id) relue attribuée : plus de case à cocher")
        }
        let refus = element("serie-resultat-demo-mission-013")
        scrollTo(refus, in: ecran)
        XCTAssertTrue(refus.label.contains(Attendus.conflit), "refus du serveur mot pour mot : \(refus.label)")
        XCTAssertEqual(element("serie-conflit-demo-mission-013").label, "⚠️ Conflit détecté")
        XCTAssertEqual(element("serie-disponibles").label, "📋 1 mission disponible sur 5")
        record("\(proofPrefix)-serie-pack-issues")

        // La mission refusée reste cochée : rien n'est renvoyé tant qu'elle n'est pas décochée.
        scrollTo(accepter, in: ecran)
        XCTAssertEqual(accepter.label, "Décochez les missions en conflit pour continuer")
        XCTAssertFalse(accepter.isEnabled)
        XCTAssertTrue(element("serie-contrats").exists, "accès aux contrats après une acceptation")
        verifierAucuneRequete()
    }

    func testArretSurLeRefusDeConformiteAfficheTelQueServi() throws {
        let ecran = ouvrirSerie(Attendus.arret, premiere: "demo-mission-002")
        XCTAssertEqual(element("serie-disponibles").label, "📋 4 missions disponibles sur 5")
        XCTAssertEqual(elements(withPrefix: "serie-selection-").count, 4)
        // Mission déjà pourvue : statut affiché, aucune case à cocher.
        let pourvue = element("serie-statut-demo-assignee-004")
        scrollTo(pourvue, in: ecran)
        XCTAssertEqual(pourvue.label, "Déjà pourvue")
        XCTAssertFalse(element("serie-selection-demo-assignee-004").exists)

        let accepter = element("serie-accepter")
        scrollTo(accepter, in: ecran)
        XCTAssertEqual(accepter.label, "★ Accepter la sélection (4)")
        accepter.tap()
        confirmerSelection(missions: ["demo-mission-002", "demo-mission-005", "demo-mission-008", "demo-mission-023"])

        let conformite = element("serie-code-travail")
        require("Le refus de conformité du serveur est affiché", timeout: 60) {
            conformite.exists && !self.element("serie-confirmation").exists
        }
        scrollTo(conformite, in: ecran, downward: false)
        // HARD STOP n°4 : le texte du serveur, entier et sans ajout (préfixe de ton de l'encart mis à part).
        XCTAssertEqual(conformite.label, "Erreur : \(Attendus.refusConformite)")
        XCTAssertEqual(element("serie-arret").label, "L’acceptation s’est arrêtée sur ce refus. Les missions suivantes n’ont pas été envoyées.")
        let bilan = element("serie-bilan")
        scrollTo(bilan, in: ecran, downward: false)
        XCTAssertTrue(bilan.label.contains("1 mission(s) acceptée(s), 2 en conflit."), bilan.label)
        record("\(proofPrefix)-serie-arret")

        // Une issue par mission : choix de contrat requis (lien vers le détail), acceptée, refusée, jamais envoyée.
        let choix = element("serie-resultat-demo-mission-002")
        scrollTo(choix, in: ecran)
        XCTAssertTrue(choix.label.contains("Choix de contrat requis"), choix.label)
        XCTAssertTrue(choix.label.contains("ouvrez son détail pour choisir votre mode de contrat avant d'accepter."), choix.label)
        XCTAssertTrue(element("serie-detail-demo-mission-002").exists)
        XCTAssertFalse(element("choix-contrat").exists, "aucune feuille de choix de contrat rejouée par la série")
        let acceptee = element("serie-resultat-demo-mission-005")
        scrollTo(acceptee, in: ecran)
        XCTAssertTrue(acceptee.label.contains(Attendus.assignee), acceptee.label)
        let refusee = element("serie-resultat-demo-mission-008")
        scrollTo(refusee, in: ecran)
        XCTAssertEqual(refusee.label, "Erreur : \(Attendus.refusConformite)", "même texte sur la mission, mot pour mot")
        let nonEnvoyee = element("serie-resultat-demo-mission-023")
        scrollTo(nonEnvoyee, in: ecran)
        XCTAssertTrue(nonEnvoyee.label.contains("Non envoyée"), nonEnvoyee.label)
        XCTAssertTrue(element("serie-selection-demo-mission-023").isSelected, "jamais envoyée : toujours ouverte et cochée")

        // Bloquée tant que les missions refusées sont cochées ; décochées, la mission restante s'accepte.
        scrollTo(accepter, in: ecran)
        XCTAssertEqual(accepter.label, "Décochez les missions en conflit pour continuer")
        XCTAssertFalse(accepter.isEnabled)
        for id in ["demo-mission-008", "demo-mission-002"] {
            let coche = element("serie-selection-\(id)")
            scrollTo(coche, in: ecran)
            // Témoin complet, comme pour `case28` : case et libellé du bouton « Accepter la sélection » inchangés.
            let accepterAvant = accepter.label
            toucherPuisExiger(coche, "\(id) est décochée",
                              rienNAChange: { coche.isSelected && accepter.label == accepterAvant }) { !coche.isSelected }
        }
        scrollTo(accepter, in: ecran)
        require("L'action reprend sur la mission restante") { accepter.label == "★ Accepter la sélection (1)" && accepter.isEnabled }
        accepter.tap()
        confirmerSelection(missions: ["demo-mission-023"])
        require("La mission restante est acceptée", timeout: 60) {
            self.element("serie-resultat-demo-mission-023").exists
                && self.element("serie-resultat-demo-mission-023").label.contains(Attendus.assignee)
        }
        XCTAssertFalse(element("serie-code-travail").exists, "nouvelle boucle sans refus de conformité")
        let refusGarde = element("serie-resultat-demo-mission-008")
        scrollTo(refusGarde, in: ecran)
        XCTAssertEqual(refusGarde.label, "Erreur : \(Attendus.refusConformite)", "le refus de la mission décochée reste affiché")
        record("\(proofPrefix)-serie-arret-reprise")

        // Lien vers le détail natif de la mission au choix de contrat requis.
        let detail = element("serie-detail-demo-mission-002")
        scrollTo(detail, in: ecran)
        detail.tap()
        require("Le détail natif de la mission est ouvert", timeout: 30) {
            self.containerVisible(self.element("mission-detail")) && self.element("mission-detail-title").exists
        }
        XCTAssertEqual(element("mission-detail-title").label, "Démonstration · Soins de suite 2")
        verifierAucuneRequete()
    }

    /// Coupe-circuit coupé (`-JOLENE_FLAG_ios_natif_serie_actif false`) : `SecondaryRouter` sert le renvoi web de l'écran.
    func testCoupeCircuitCoupeRenvoiWebDeLEcran() throws {
        let lien = "https://jolene.app/soignant/missions/serie/\(Attendus.pack)"
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", lien, "-JOLENE_FLAG_ios_natif_serie_actif", "false"])
        connexionDemo()
        let renvoi = element("secondaire-serie")
        require("Le renvoi web de l'écran est servi", timeout: 30) { self.containerVisible(renvoi) && self.element("renvoi-web-message").exists }
        XCTAssertEqual(element("renvoi-web-message").label, "Cet écran est disponible sur jolene.app.")
        XCTAssertFalse(element("serie-screen").exists, "coupe-circuit coupé : l'écran natif n'est pas construit")
        tap("renvoi-web-ouvrir")
        liensRenvoiWebAffiche(lien)
        liensFermerRenvoiWeb()
    }

    /// Série sans mission accessible : « Pack introuvable » et retour vers Explorer, comme le web.
    func testSerieInconnuePackIntrouvable() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/soignant/missions/serie/SERIE_1793577600000_absent"])
        connexionDemo()
        let introuvable = element("serie-introuvable")
        require("« Pack introuvable » est affiché", timeout: 30) { self.containerVisible(introuvable) }
        XCTAssertTrue(text("Pack introuvable").exists)
        XCTAssertTrue(text("Ce pack ne contient plus de mission accessible. Vous pouvez poursuivre votre recherche.").exists)
        XCTAssertFalse(element("serie-accepter").exists)
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré : jamais un renvoi web")
        tap("serie-introuvable-explorer")
        require("Explorer est ouvert", timeout: 30) { self.containerVisible(self.element("missions-list")) || self.element("missions-empty").exists }
    }

    // MARK: Étapes

    /// Lien universel simulé vers la série, rejoué après la connexion démo : écran natif empilé sur le Profil.
    private func ouvrirSerie(_ id: String, premiere: String) -> XCUIElement {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/soignant/missions/serie/\(id)"])
        connexionDemo()
        let ecran = defilement("serie-screen")
        require("Le détail de série natif est ouvert et relu", timeout: 30) {
            self.containerVisible(ecran) && self.element("serie-mission-\(premiere)").exists && !self.element("serie-chargement").exists
        }
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (T12) : jamais un renvoi web")
        XCTAssertFalse(element("secondaire-serie").exists, "coupe-circuit absent : écran natif (fail-open)")
        XCTAssertTrue(element("serie-entete").exists)
        return ecran
    }

    /// Récapitulatif « Vérifiez tous vos engagements » : chaque mission sélectionnée y figure avec ses créneaux exacts.
    private func confirmerSelection(missions: [String]) {
        let feuille = element("serie-confirmation")
        let confirmer = element("serie-confirmation-confirm")
        require("Le récapitulatif des engagements est présenté") { self.containerVisible(feuille) && confirmer.exists }
        XCTAssertEqual(element("serie-confirmation-title").label, "Vérifiez tous vos engagements")
        XCTAssertEqual(element("serie-confirmation-message").label,
                       "Confirmez uniquement si vous pouvez assurer chacun des créneaux exacts sélectionnés.")
        XCTAssertEqual(elements(withPrefix: "serie-confirmation-mission-").count, missions.count, "exactement la sélection affichée")
        for id in missions {
            XCTAssertTrue(element("serie-confirmation-mission-\(id)").exists, id)
        }
        scrollTo(confirmer, in: feuille)
        XCTAssertEqual(confirmer.label, "Accepter tous ces créneaux")
        confirmer.tap()
    }

    /// Conteneur de défilement : la `ScrollView` portant l'identifiant, sinon la première correspondance.
    private func defilement(_ identifier: String) -> XCUIElement {
        let typee = app.scrollViews.matching(identifier: identifier).firstMatch
        return typee.exists ? typee : element(identifier)
    }

    /// Profil remis à sa racine (l'écran de série y est empilé), puis sentinelle réseau.
    private func verifierAucuneRequete() {
        toucherOnglet("tab-profil", label: "Profil")
        if element("serie-screen").exists {
            let back = app.navigationBars.buttons.firstMatch
            require("Le bouton retour est disponible") { self.visible(back) }
            back.tap()
            require("L'écran de série est retiré") { !self.element("serie-screen").exists }
        }
        let liste = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(liste) }
        let sentinelle = element("network-sentinel")
        scrollTo(sentinelle, in: liste, downward: false)
        require("La sentinelle réseau est exposée") { sentinelle.exists }
        XCTAssertEqual(sentinelle.label, "0 requête", "le détail de série n'émet aucune requête en démonstration")
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
