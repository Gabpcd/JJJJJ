import XCTest

/// Détail des présences et points d'entrée (lot 2, T5a) sur iPhone, iPad portrait et iPad paysage, monde démo
/// (`demo-presences.json`, horloge fixée 2026-11-02T00:00:00Z, soit lundi 2 novembre 01h00 à Paris). Les valeurs
/// attendues sont celles que `PresentationDetailPresencesTests`, `DemoNotationGatewayTests` et `PointsEntreePresencesTests`
/// (JoleneCore) affirment sur le monde démo : un écart entre l'écran et le cœur fait échouer l'un des deux.
///
/// Parcours : Historique › « Détail » (présence à valider : synthèse, segment, contrôles, relance verbatim du serveur
/// puis refus « déjà relancé ») ; présence validée et ligne reconstruite (aucune relance, aucun contrôle) ; détail d'une
/// mission ASSIGNEE › « Présences et pointage » (onglet À venir) ; Accueil (scénario `accueil-pointage`) › widget
/// « Aller pointer » (onglet Aujourd'hui) et « Pointer mon départ maintenant ». Le récapitulatif financier n'est qu'un
/// renvoi web (route forcée web `PresencesRenvois.recapitulatifFinancier`, qui survit au routage natif de T10) : depuis
/// la fusion du lot 3, le présentateur `.safari` du coordinateur des liens (L3-T3b) est injecté, le bouton
/// `presence-revenus-web` est rendu et présente `https://jolene.app/soignant/presences/mission/<id>` (double démo).
/// La feuille de notation se monte dans la zone de pointage de T4b
/// (`notationAuDepart`) : son parcours XCUITest arrive avec cette zone. Sentinelle réseau « 0 requête » relue à la fin
/// du parcours détail + relance et du parcours Accueil (PRINCIPES §7, niveau 2 ; LOT2_PLAN §2.8 ; revue fraîche, m3).
final class DemoPresenceDetailTests: JoleneUITestCase {
    func testHistoriqueDetailDUnePresenceAValiderEtRelance() throws {
        launchDemo()
        connexionDemo()
        ouvrirHistorique()
        let ecran = ouvrirDetail("presence-historique-detail-demo-presence-h2-presence",
                                 ligne: "presence-historique-demo-presence-h2-presence")

        verifier("presence-detail-entete", dans: ecran, contient: [
            "Démonstration · Présence à valider", "Soins de suite", "📅 ven. 30 oct. 2026 · 08:00 → 16:00", "⏱ 8h sur 1 créneau",
            "Progression : 1/1 créneau échu · planning terminé",
        ])
        verifier("presence-detail-synthese", dans: ecran, contient: ["Synthèse des présences", "Heures planifiées", "Heures réelles", "8h"])
        XCTAssertTrue(element("presence-detail-segments-titre").label.contains("Détail des créneaux travaillés (1 segment)"))
        verifier("presence-detail-segment-1", dans: ecran, contient: [
            "Horaire prévu", "ven. 30 oct. 2026 · 08:00 → 16:00", "▶ Arrivée 30/10/2026 08:00:00", "■ Départ 30/10/2026 16:00:00",
            "Durée : 8h00", "✅ Relevé clôturé",
        ])
        verifier("presence-detail-controles", dans: ecran, contient: ["Contrôles du pointage"])
        record("\(proofPrefix)-presence-detail-a-valider")

        // Relance : titre et explication verbatim (TextesWeb, HARD STOP de TL), puis message serveur tel quel.
        verifier("presence-relance", dans: ecran, contient: [
            "⏳ Tes présences attendent la validation de l'établissement",
            "La validation des heures (automatique sous 72 h) est distincte du versement.",
        ])
        let relancer = element("presence-relancer")
        degager(relancer, dans: ecran)
        relancer.tap()
        let retour = element("presence-relance-retour")
        require("La relance affiche le message du serveur") {
            retour.exists && retour.label.contains("Établissement relancé. Il a été notifié de valider tes présences.")
        }
        degager(relancer, dans: ecran)
        relancer.tap()
        require("Une seconde relance affiche le refus du serveur") {
            retour.exists && retour.label.contains("Tu as déjà relancé cet établissement aujourd'hui. Il a été notifié.")
        }
        record("\(proofPrefix)-presence-detail-relance")

        // Récapitulatif financier (décision 11) : route forcée web `PresencesRenvois.recapitulatifFinancier`. Migré à la
        // fusion des lots 2 et 3 (règle 8) : le présentateur `.safari` du coordinateur des liens (L3-T3b) est injecté à la
        // racine, le bouton est donc rendu, et il a son effet — la page web de la mission est présentée (double démo
        // `renvoi-web-demo`, aucune requête réseau), puis « Fermer » rend le détail. Avant la fusion, ce test exigeait
        // son absence (jamais un bouton sans effet).
        let revenus = element("presence-revenus-web")
        require("Le récapitulatif financier propose son renvoi web") { revenus.exists }
        degager(revenus, dans: ecran)
        XCTAssertEqual(revenus.label, "Voir sur jolene.app", "libellé repris du lot 1 (`LibellesDetailPresences.voirSurLeWeb`)")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "💶 Récapitulatif financier"))
                        .firstMatch.exists, "titre de section du web (`DetailPresencesMission.tsx` l.705)")
        revenus.tap()
        liensRenvoiWebAffiche("https://jolene.app/soignant/presences/mission/demo-presence-h2")
        record("\(proofPrefix)-presence-detail-recapitulatif-web")
        liensFermerRenvoiWeb()
        require("Le détail des présences est de retour") { self.containerVisible(ecran) && self.element("presence-detail-entete").exists }

        // Détail › Présences › Profil : le détail et la relance n'ont émis aucune requête réseau.
        revenir()
        attendrePresences()
        revenir()
        sentinelleSansRequete(depuisMonEspace: true)
    }

    func testDetailDUnePresenceValideeEtDUneLigneReconstruite() throws {
        launchDemo()
        connexionDemo()
        ouvrirHistorique()

        var ecran = ouvrirDetail("presence-historique-detail-demo-presence-h1-presence", ligne: "presence-historique-demo-presence-h1-presence")
        verifier("presence-detail-segment-1", dans: ecran, contient: ["✅ Validé le 01/11/2026 15:00", "Durée : 8h00"])
        XCTAssertFalse(element("presence-relance").exists, "présence validée : aucune relance")
        record("\(proofPrefix)-presence-detail-validee")
        revenir()

        ecran = ouvrirDetail("presence-historique-detail-effectifs-mission-demo-presence-h3",
                             ligne: "presence-historique-effectifs-mission-demo-presence-h3")
        XCTAssertTrue(element("presence-detail-segments-titre").label.contains("Détail des créneaux travaillés (2 segments)"))
        verifier("presence-detail-segment-1", dans: ecran, contient: ["▶ Arrivée 28/10/2026 08:00:00", "Durée : 5h00"])
        verifierSansCasse("presence-detail-segment-1", dans: ecran, contient: ["Segment travaillé 1 / 2 · créneau planifié 1/1"])
        verifier("presence-detail-segment-2", dans: ecran, contient: [
            "Pause / interruption depuis le segment précédent : 0h30", "Durée : 2h30", "✅ Relevé clôturé",
        ])
        verifierSansCasse("presence-detail-segment-2", dans: ecran, contient: ["Segment travaillé 2 / 2 · reprise après interruption"])
        XCTAssertFalse(element("presence-detail-controles").exists, "heures pointées sans présence : aucun contrôle")
        XCTAssertFalse(element("presence-relance").exists, "aucune présence : rien à relancer")
        record("\(proofPrefix)-presence-detail-reconstruite")
    }

    func testDetailDUneMissionAssigneeOuvreLesPresencesSurAVenir() throws {
        launchDemo()
        connexionDemo()
        let accueil = element("accueil-screen")
        let ligne = element("accueil-prochaine-demo-assignee-001")
        degager(ligne, dans: accueil)
        ligne.tap()
        let detail = element("mission-detail")
        require("Le détail de la mission assignée est affiché") { self.containerVisible(detail) }
        let entree = element("mission-presences")
        require("« Présences et pointage » est proposé (ASSIGNEE)") { entree.exists }
        degager(entree, dans: detail)
        XCTAssertTrue(entree.label.contains("Présences et pointage"), "libellé du web : \(entree.label)")
        XCTAssertFalse(element("mission-heures").exists, "mission non terminée : pas d'heures pointées")
        entree.tap()
        attendrePresences()
        require("Onglet À venir (aucun créneau aujourd'hui, mission ASSIGNEE)") { self.element("presences-tab-avenir").isSelected }
        record("\(proofPrefix)-mission-vers-presences")
    }

    func testAccueilAllerPointerEtOubliDeDepartOuvrentLesPresences() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_SCENARIO", "accueil-pointage"])
        connexionDemo()
        let accueil = element("accueil-screen")
        require("L'Accueil démo est chargé", timeout: 30) { self.element("accueil-salutation").exists && !self.element("accueil-loading").exists }

        let oubli = element("accueil-oubli-pointage")
        scrollTo(oubli, in: accueil)
        XCTAssertTrue(oubli.label.contains("1 mission semble attendre un pointage de départ. Vérifiez vos présences."),
                      "bandeau : \(oubli.label)")
        verifier("accueil-pointer", dans: accueil, contient: [
            "Créneau de travail actuel", "Démonstration · Pointage du jour — Établissement fictif République",
            "lundi 2 novembre · 01:05 → 09:05",
        ])
        let action = element("accueil-pointer-action")
        degager(action, dans: accueil)
        XCTAssertTrue(action.label.contains("Aller pointer"), "bouton : \(action.label)")
        record("\(proofPrefix)-accueil-aller-pointer")
        action.tap()
        attendrePresences()
        require("Onglet Aujourd'hui (`?tab=aujourdhui`)") { self.element("presences-tab-aujourdhui").isSelected }
        require("La mission du jour est à pointer") { self.element("pointage-bloc-demo-presence-a").exists }
        revenir()

        let depart = element("accueil-oubli-depart")
        require("L'Accueil est de retour") { self.containerVisible(accueil) }
        degager(depart, dans: accueil)
        XCTAssertTrue(depart.label.contains("Pointer mon départ maintenant"), "bouton : \(depart.label)")
        depart.tap()
        attendrePresences()
        record("\(proofPrefix)-accueil-oubli-depart")

        // Onglet Profil : l'Accueil du scénario `accueil-pointage` et la page Présences n'ont émis aucune requête.
        tabButton("tab-profil", label: "Profil").tap()
        sentinelleSansRequete(depuisMonEspace: false)
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
        require("La session démo est prête", timeout: 30) { self.tabBarExists && self.containerVisible(self.element("accueil-screen")) }
    }

    /// Profil › Mon espace › Mes présences › Historique.
    private func ouvrirHistorique() {
        tabButton("tab-profil", label: "Profil").tap()
        let liste = element("profile-list")
        require("Le profil est affiché") { self.containerVisible(liste) }
        let ligne = element("profil-presences")
        if !visible(ligne) { scrollTo(ligne, in: liste) }
        tap("profil-presences")
        attendrePresences()
        tap("presences-tab-historique")
        require("L'onglet Historique est sélectionné") { self.element("presences-tab-historique").isSelected }
    }

    private func attendrePresences() {
        let ecran = element("presences-screen")
        require("La page Présences est chargée", timeout: 30) {
            self.containerVisible(ecran) && self.element("presences-tab-aujourdhui").exists && !self.element("presences-loading").exists
        }
    }

    /// « Détail » d'une ligne d'historique, puis l'écran natif chargé.
    private func ouvrirDetail(_ bouton: String, ligne: String) -> XCUIElement {
        let presences = element("presences-screen")
        let carte = element(ligne)
        require("\(ligne) est rendue", timeout: 15) { carte.exists }
        let detail = element(bouton)
        degager(detail, dans: presences)
        detail.tap()
        let ecran = element("presence-detail-screen")
        require("Le détail des présences est chargé", timeout: 30) {
            self.containerVisible(ecran) && self.element("presence-detail-entete").exists && !self.element("presence-detail-loading").exists
        }
        XCTAssertFalse(element("presence-detail-error").exists, "aucune erreur en démo")
        return ecran
    }

    /// Barre qui recouvre `cible` (le cadre d'un `ScrollView` s'étend sous la barre de navigation et, sur iPhone, sous
    /// la barre d'onglets) : même règle que `DemoAccueilTests`.
    private func barreRecouvre(_ cible: XCUIElement) -> Bool? {
        let navigation = app.navigationBars.firstMatch
        if navigation.exists, cible.frame.minY < navigation.frame.maxY { return false }
        let onglets = app.tabBars.firstMatch
        if onglets.exists, cible.frame.maxY > onglets.frame.minY { return true }
        return nil
    }

    /// Avant un tap : défilement borné jusqu'à la cible, puis dégagement des barres (glissements courts et bornés).
    private func degager(_ cible: XCUIElement, dans ecran: XCUIElement) {
        scrollTo(cible, in: ecran)
        var essais = 0
        while essais < 6, let sousLesOnglets = barreRecouvre(cible) {
            if sousLesOnglets { drag(ecran, fromY: 0.6, toY: 0.4) } else { drag(ecran, fromY: 0.4, toY: 0.6) }
            essais += 1
        }
        require("La cible est atteignable hors des barres") { self.visible(cible) && self.barreRecouvre(cible) == nil }
    }

    private func revenir() {
        let retour = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(retour) }
        retour.tap()
    }

    /// Sentinelle réseau du Profil (`network-sentinel`) : « 0 requête » en démonstration. Elle est au-dessus de « Mon
    /// espace » : défilement borné vers le haut quand la liste en revient, vers le bas sur un Profil ouvert à sa racine.
    private func sentinelleSansRequete(depuisMonEspace: Bool) {
        let liste = element("profile-list")
        require("Le profil est affiché") { self.containerVisible(liste) }
        let sentinelle = element("network-sentinel")
        if !visible(sentinelle) { scrollTo(sentinelle, in: liste, downward: !depuisMonEspace) }
        require("La sentinelle réseau est exposée") { sentinelle.exists }
        XCTAssertEqual(sentinelle.label, "0 requête", "aucune requête réseau en démonstration")
    }

    /// Défilement borné jusqu'au bloc, puis chaque fragment attendu parmi ses textes (requête limitée au bloc).
    private func verifier(_ identifiant: String, dans ecran: XCUIElement, contient fragments: [String],
                          file: StaticString = #filePath, line: UInt = #line) {
        verifier(identifiant, dans: ecran, contient: fragments, operateur: "CONTAINS", file: file, line: line)
    }

    /// Étiquettes de segment affichées en capitales (`text-transform: uppercase` du web) : comparaison sans casse.
    private func verifierSansCasse(_ identifiant: String, dans ecran: XCUIElement, contient fragments: [String],
                                   file: StaticString = #filePath, line: UInt = #line) {
        verifier(identifiant, dans: ecran, contient: fragments, operateur: "CONTAINS[c]", file: file, line: line)
    }

    private func verifier(_ identifiant: String, dans ecran: XCUIElement, contient fragments: [String], operateur: String,
                          file: StaticString, line: UInt) {
        let bloc = element(identifiant)
        require("\(identifiant) est rendu", timeout: 15) { bloc.exists }
        scrollTo(bloc, in: ecran)
        for fragment in fragments {
            let predicat = NSPredicate(format: "label \(operateur) %@", fragment)
            let trouve = bloc.descendants(matching: .any).matching(predicat).firstMatch
            XCTAssertTrue(trouve.exists, "\(identifiant) : « \(fragment) » absent", file: file, line: line)
        }
    }
}
