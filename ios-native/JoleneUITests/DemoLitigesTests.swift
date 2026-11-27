import XCTest

/// Litiges (L4-T8) en démonstration, sur iPhone, iPad portrait et iPad paysage : Profil → « Litiges & contestations »
/// (`hub-litiges`, fixtures `demo-litiges.json` et `demo-litige-fil.json` : un litige ouvert, un en médiation, un résolu)
/// → ouverture d'un litige sur une mission terminée du monde démo, relu OUVERT en tête et déplié → message ajouté au fil
/// (un de plus) ; litige résolu : aucun champ de message ; litige ouvert : renvoi « Accord amiable sur jolene.app » vers la
/// page web canonique ; tap d'une notification de litige : écran natif, litige visé déplié. Aucun texte de délai. Aucune
/// requête réseau (sentinelle).
///
/// Les règles (relecture qui confirme, refus du serveur mot pour mot, réconciliation, epoch) sont prouvées par
/// `LitigesModelTests` et `Lot4WiringLitigesTests` ; le transport par `SupabaseLitigesGatewayTests` ; les textes par
/// `LitigesVerbatimTests`.
final class DemoLitigesTests: JoleneUITestCase {
    private enum Attendus {
        static let ouvert = "demo-litige-001"
        static let mediation = "demo-litige-002"
        static let resolu = "demo-litige-003"
        static let nouveau = "demo-litige-ajout-1"
        static let mission = "demo-terminee-001"
        static let avertissement = "⚠️ Un litige déclenche une procédure de résolution entre toi et l'établissement. Privilégie d'abord la messagerie pour résoudre le problème."
        /// Textes de délai du web, non portés (bandeau de médiation, compte à rebours, délais de réponse).
        static let textesDeDelai = ["7 jours", "72h", "72 h", "48h", "48 h", "délai", "escalade", "pénalité"]
    }

    func testOuvertureRelueEnTetePuisMessageAjouteAuFil() throws {
        launchDemo()
        connexionDemo()
        let ecran = ouvrirLitiges()
        XCTAssertEqual(elements(withPrefix: "litige-entete-").count, 3, "les trois litiges de la fixture")
        XCTAssertEqual(element("litige-statut-\(Attendus.ouvert)").label, "Ouvert")
        XCTAssertEqual(element("litige-statut-\(Attendus.mediation)").label, "Médiation")
        XCTAssertEqual(element("litige-statut-\(Attendus.resolu)").label, "Accord mutuel ✅")
        XCTAssertEqual(element("litiges-filtre-tous").label, "Tous 3")
        XCTAssertTrue(element("litiges-filtre-tous").isSelected)
        XCTAssertTrue(element("litiges-filtre-ouvert").exists && element("litiges-filtre-mediation").exists
                      && element("litiges-filtre-resolu").exists, "un filtre par groupe non vide")
        XCTAssertFalse(element("litiges-filtre-ferme").exists, "groupe vide : aucun filtre")
        verifierAucunTexteDeDelai(dans: ecran)
        record("\(proofPrefix)-litiges-liste")

        // Filtre « Ouverts » : un seul litige, puis retour à « Tous ».
        XCTAssertEqual(element("litiges-filtre-ouvert").label, "Ouverts 1")
        tap("litiges-filtre-ouvert")
        require("Le filtre Ouverts ne garde que le litige ouvert") {
            self.elements(withPrefix: "litige-entete-").count == 1 && self.element("litige-entete-\(Attendus.ouvert)").exists
                && self.element("litiges-filtre-ouvert").isSelected
        }
        tap("litiges-filtre-tous")
        require("Le filtre Tous rend les trois litiges") { self.elements(withPrefix: "litige-entete-").count == 3 }

        // Ouverture : avertissement du web, mission proposée, motif.
        let ouvrir = element("litige-ouvrir")
        scrollTo(ouvrir, in: ecran, downward: false)
        XCTAssertEqual(ouvrir.label, "Ouvrir un litige")
        tap("litige-ouvrir")
        let feuille = defilement("litige-ouverture")
        let envoyer = element("litige-envoyer")
        require("La feuille d'ouverture est affichée", timeout: 30) { self.containerVisible(feuille) && envoyer.exists }
        XCTAssertTrue(element("litige-avertissement").label.contains(Attendus.avertissement), element("litige-avertissement").label)
        XCTAssertEqual(elements(withPrefix: "litige-mission-").count, 2, "les deux missions terminées du monde démo")
        XCTAssertEqual(envoyer.label, "⚠️ Ouvrir le litige")
        XCTAssertFalse(envoyer.isEnabled, "sans mission ni motif : envoi impossible")
        verifierAucunTexteDeDelai(dans: feuille)
        let mission = element("litige-mission-\(Attendus.mission)")
        scrollTo(mission, in: feuille)
        XCTAssertTrue(mission.label.contains("Démonstration · Mission terminée 1 — Établissement fictif République — 1 nov. 2026"),
                      mission.label)
        mission.tap()
        require("La mission est choisie") { mission.isSelected }
        XCTAssertFalse(envoyer.isEnabled, "sans motif : envoi impossible")
        let motif = element("litige-motif")
        focus(motif, in: feuille)
        motif.typeText("Les heures retenues ne correspondent pas à la mission.")
        fermerLePaveNumerique()
        require("Une mission et un motif activent l'envoi") { envoyer.isEnabled }
        record("\(proofPrefix)-litige-ouverture")
        scrollTo(envoyer, in: feuille)
        tap("litige-envoyer")

        // Litige relu : en tête, OUVERT, déplié sur son fil vide.
        let carte = element("litige-\(Attendus.nouveau)")
        require("Le litige ouvert est relu et la feuille refermée", timeout: 30) {
            !self.element("litige-envoyer").exists && carte.exists
        }
        let entetes = elements(withPrefix: "litige-entete-")
        XCTAssertEqual(entetes.count, 4)
        XCTAssertEqual(entetes.element(boundBy: 0).identifier, "litige-entete-\(Attendus.nouveau)", "litige ouvert en tête")
        XCTAssertEqual(element("litige-statut-\(Attendus.nouveau)").label, "Ouvert")
        XCTAssertTrue(element("litiges-confirmation").label.contains("Litige ouvert avec succès."), element("litiges-confirmation").label)
        XCTAssertFalse(element("litiges-action-erreur").exists)
        XCTAssertEqual(element("litiges-filtre-tous").label, "Tous 4")
        let fil = element("litige-fil-\(Attendus.nouveau)")
        require("Le fil du litige ouvert est déplié, sans message") { fil.exists && self.element("litige-fil-vide").exists }
        XCTAssertEqual(elements(withPrefix: "litige-fil-message-").count, 0)
        record("\(proofPrefix)-litige-ouvert")

        // Message : un de plus dans le fil relu, champ vidé.
        let saisie = element("litige-message-input")
        scrollTo(saisie, in: ecran)
        let envoyerMessage = element("litige-message-envoyer")
        XCTAssertEqual(envoyerMessage.label, "Envoyer")
        XCTAssertFalse(envoyerMessage.isEnabled, "moins de 10 caractères : envoi impossible")
        focus(saisie, in: ecran)
        saisie.typeText("Voici le détail du désaccord.")
        fermerLePaveNumerique()
        require("Un message de 10 caractères active l'envoi") { envoyerMessage.isEnabled }
        scrollTo(envoyerMessage, in: ecran)
        tap("litige-message-envoyer")
        require("Le fil relu compte un message de plus", timeout: 30) {
            self.elements(withPrefix: "litige-fil-message-").count == 1 && !self.element("litige-fil-vide").exists
        }
        // Le texte saisi n'est pas comparé (correction automatique du clavier du simulateur) : l'auteur et le compte du fil
        // relu sont la preuve ; le contenu envoyé est prouvé par `LitigesModelTests`.
        let message = elements(withPrefix: "litige-fil-message-").element(boundBy: 0)
        XCTAssertTrue(message.label.contains("Vous"), message.label)
        XCTAssertFalse(element("litige-message-erreur").exists)
        require("L'envoi est de nouveau désactivé (champ vidé)") { !envoyerMessage.isEnabled }
        verifierAucunTexteDeDelai(dans: ecran)
        record("\(proofPrefix)-litige-message")
        verifierAucuneRequete()
    }

    func testLitigeResoluSansChampEtRenvoiDeLAccordSurLeWeb() throws {
        launchDemo()
        connexionDemo()
        let ecran = ouvrirLitiges()

        // Litige résolu : clôture et texte du serveur, aucun champ de message, aucun renvoi d'accord.
        let resolu = element("litige-entete-\(Attendus.resolu)")
        scrollTo(resolu, in: ecran)
        resolu.tap()
        require("Le fil du litige résolu est déplié", timeout: 30) {
            self.element("litige-fil-\(Attendus.resolu)").exists && self.elements(withPrefix: "litige-fil-message-").count == 1
        }
        XCTAssertEqual(element("litige-cloture").label, "Litige clôturé")
        XCTAssertEqual(element("litige-resolution").label, "Démonstration · Accord trouvé entre les parties.", "texte du serveur")
        XCTAssertFalse(element("litige-message-input").exists, "litige résolu : champ de message absent")
        XCTAssertFalse(element("litige-message-envoyer").exists, "litige résolu : aucun envoi")
        XCTAssertFalse(element("litige-accord-web").exists, "litige résolu : aucun accord à proposer")
        verifierAucunTexteDeDelai(dans: ecran)
        record("\(proofPrefix)-litige-resolu")

        // Litige en médiation : champ présent, aucun texte de délai (le bandeau « 7 jours » du web n'est pas porté).
        let mediation = element("litige-entete-\(Attendus.mediation)")
        scrollTo(mediation, in: ecran, downward: false)
        mediation.tap()
        require("Le fil du litige en médiation est déplié", timeout: 30) {
            self.element("litige-fil-\(Attendus.mediation)").exists && !self.element("litige-fil-\(Attendus.resolu)").exists
        }
        XCTAssertTrue(element("litige-message-input").exists, "litige en médiation : champ de message présent")
        XCTAssertTrue(element("litige-fil-message-demo-litige-message-002").label.contains("🛡️ Jolene"), "message de l'équipe")
        verifierAucunTexteDeDelai(dans: ecran)

        // Litige ouvert : fil de la fixture, puis renvoi de l'accord amiable vers la page web canonique du litige.
        let ouvert = element("litige-entete-\(Attendus.ouvert)")
        scrollTo(ouvert, in: ecran, downward: false)
        ouvert.tap()
        require("Le fil du litige ouvert est déplié", timeout: 30) {
            self.element("litige-fil-\(Attendus.ouvert)").exists && self.elements(withPrefix: "litige-fil-message-").count == 2
        }
        XCTAssertTrue(element("litige-fil-message-demo-litige-message-003").label.contains("Vous"), "message du soignant")
        XCTAssertTrue(element("litige-fil-message-demo-litige-message-004").label.contains("Établissement"), "message de l'établissement")
        let accord = element("litige-accord-web-ouvrir")
        scrollTo(accord, in: ecran)
        XCTAssertEqual(element("litige-accord-web-title").label, "Accord amiable sur jolene.app")
        XCTAssertEqual(element("litige-accord-web-url").label, "jolene.app/soignant/litiges?litige=\(Attendus.ouvert)")
        tap("litige-accord-web-ouvrir")
        liensRenvoiWebAffiche("https://jolene.app/soignant/litiges?litige=\(Attendus.ouvert)")
        record("\(proofPrefix)-litige-accord-web")
        liensFermerRenvoiWeb()
        require("Les litiges restent affichés après le renvoi") { self.containerVisible(ecran) && ouvert.exists }
        verifierAucuneRequete()
    }

    /// Tap d'une notification de litige (`/soignant/litiges#<id>`, `pushNative.ts`) : écran natif, litige visé déplié.
    func testTapPushDUnLitigeOuvreLEcranNatifSurLeLitigeVise() throws {
        launchDemo(extraArguments: ["-JOLENE_SIMULER_PUSH", "NOUVEAU_MESSAGE_LITIGE:litige_id=\(Attendus.mediation)"])
        connexionDemo()
        let ecran = defilement("litiges-screen")
        require("Les litiges natifs sont ouverts par le tap, litige visé déplié", timeout: 30) {
            self.containerVisible(ecran) && self.element("litige-fil-\(Attendus.mediation)").exists
        }
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (T8) : jamais la page web")
        XCTAssertFalse(element("litige-fil-\(Attendus.ouvert)").exists, "seul le litige visé est déplié")
        XCTAssertTrue(element("litiges-onglet-litiges").isSelected, "onglet Litiges mission")
        XCTAssertEqual(element("deeplink-route").label, "secondaire(litiges, sans onglet, id masqué)")
        XCTAssertFalse(element("access-blocked").exists)
        XCTAssertFalse(element("env-blocked").exists)
        record("\(proofPrefix)-litige-push")
    }

    // MARK: Étapes

    private func ouvrirLitiges() -> XCUIElement {
        toucherOnglet("tab-profil", label: "Profil")
        let liste = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(liste) }
        let entree = element("hub-litiges")
        scrollTo(entree, in: liste)
        require("L'entrée « Litiges & contestations » est atteignable") { self.visible(entree) }
        XCTAssertTrue(entree.label.contains("Litiges & contestations"), entree.label)
        entree.tap()
        let ecran = defilement("litiges-screen")
        require("Les litiges sont relus", timeout: 30) {
            self.containerVisible(ecran) && self.element("litige-\(Attendus.ouvert)").exists
        }
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (T8) : jamais un renvoi web")
        XCTAssertTrue(app.navigationBars["Litiges & contestations"].exists, "titre du web")
        XCTAssertEqual(element("litiges-onglet-litiges").label, "Litiges mission")
        XCTAssertEqual(element("litiges-onglet-reclamations").label, "Réclamations")
        XCTAssertTrue(element("litiges-onglet-litiges").isSelected, "onglet par défaut")
        return ecran
    }

    /// Aucun texte de délai, de pénalité ou d'escalade dans le conteneur (HARD STOP de T8).
    private func verifierAucunTexteDeDelai(dans conteneur: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for texte in Attendus.textesDeDelai {
            let trouve = conteneur.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", texte)).firstMatch
            XCTAssertFalse(trouve.exists, "texte de délai affiché : « \(texte) »", file: file, line: line)
        }
    }

    /// Conteneur de défilement : la `ScrollView` portant l'identifiant, sinon la première correspondance.
    private func defilement(_ identifier: String) -> XCUIElement {
        let typee = app.scrollViews.matching(identifier: identifier).firstMatch
        return typee.exists ? typee : element(identifier)
    }

    /// Profil remis à sa racine (l'écran des litiges y est empilé), puis sentinelle réseau.
    private func verifierAucuneRequete() {
        revenirALaRacine("tab-profil", label: "Profil", racine: "profile-list", empiles: ["litiges-screen"])
        let liste = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(liste) }
        let sentinelle = element("network-sentinel")
        scrollTo(sentinelle, in: liste, downward: false)
        require("La sentinelle réseau est exposée") { sentinelle.exists }
        XCTAssertEqual(sentinelle.label, "0 requête", "les litiges n'émettent aucune requête en démonstration")
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
