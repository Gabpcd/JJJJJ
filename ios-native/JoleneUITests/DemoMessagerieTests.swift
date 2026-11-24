import XCTest

/// Messagerie native (L4-T7b) en démonstration, sur iPhone, iPad portrait et iPad paysage. Fixtures
/// `demo-conversations.json` / `demo-messages.json` : `demo-conv-001` (établissement fictif République, mission ouverte,
/// deux messages non lus), `demo-conv-002` (Jolene), `demo-conv-003` (archivée).
///
/// - badge Messages = valeur démo de `fn_messages_non_lus` (2) ; ouverture du fil → non-lus à 0 (liste et badge) ;
/// - envoi → bulle relue (`demo-message-envoi-1`) → réponse démo de l'établissement affichée sans geste
///   (`demo-message-reponse-1`, INSERT émis sur le flux entrant) ;
/// - « 06 12 34 56 78 » dans le fil d'une mission non attribuée → feuille anti-fuite verbatim, texte conservé ;
/// - conversation archivée → composeur remplacé par la mention de lecture seule ;
/// - bloquer (confirmation) puis débloquer, signaler (motif) → confirmations verbatim (Apple 1.2) ;
/// - détail d'une mission attribuée → « Écrire à l'établissement » → fil de cette mission.
/// Aucune requête réseau (sentinelle).
///
/// Les règles (fusion par id, relecture, non confirmé sans renvoi, epoch, cycle Realtime) sont prouvées par
/// `FilModelTests`, `ConversationsModelTests`, `RealtimeLifecycleTests`, `ModerationModelsTests` ; les textes par
/// `MessagerieVerbatimTests`.
final class DemoMessagerieTests: JoleneUITestCase {
    private enum Attendus {
        static let etablissement = "demo-conv-001"
        static let archivee = "demo-conv-003"
        static let mission = "demo-assignee-001"
        static let filMission = "demo-conv-mission-demo-assignee-001"
        static let nomEtablissement = "Établissement fictif République"
    }

    func testBadgeLectureEnvoiReponseEtAntiFuite() throws {
        launchDemo()
        connexionDemo()
        let bouton = element("nav-messages")
        require("Le badge Messages affiche les non-lus de la démo", timeout: 30) {
            bouton.exists && (bouton.value as? String) == "2"
        }
        XCTAssertEqual(bouton.label, "Messages")
        record("\(proofPrefix)-messagerie-badge")
        bouton.tap()
        let liste = ouvrirListe()
        let pastille = element("conversation-nonlus-\(Attendus.etablissement)")
        require("La conversation de l'établissement compte deux non-lus") { pastille.exists && pastille.label == "2" }
        XCTAssertTrue(element("conversation-demo-conv-002").exists, "conversation avec Jolene listée")
        XCTAssertFalse(element("conversation-\(Attendus.archivee)").exists, "l'archivée n'est pas dans l'onglet Actives")
        record("\(proofPrefix)-messagerie-liste")

        // Ouverture : non-lus à 0, puis envoi relu et réponse entrante sans geste.
        let ecran = ouvrirFil(Attendus.etablissement, dans: liste)
        require("Les messages de la fixture sont affichés") { self.element("chat-message-demo-message-003").exists }
        let saisie = element("chat-input")
        focus(saisie, in: ecran)
        saisie.typeText("Bonjour, je confirme ma disponibilité.")
        tap("chat-envoyer")
        require("Le message envoyé est relu puis affiché", timeout: 30) { self.element("chat-message-demo-message-envoi-1").exists }
        XCTAssertFalse(element("chat-non-confirme").exists, "envoi confirmé par relecture")
        XCTAssertFalse((saisie.value as? String ?? "").contains("je confirme"), "composeur vidé après l'envoi confirmé")
        require("La réponse de l'établissement démo s'affiche sans geste", timeout: 30) {
            self.element("chat-message-demo-message-reponse-1").exists
        }
        record("\(proofPrefix)-messagerie-envoi-reponse")

        // Anti-fuite : mission non attribuée, numéro de téléphone refusé, texte conservé.
        focus(saisie, in: ecran)
        saisie.typeText("Appelez-moi au 06 12 34 56 78")
        tap("chat-envoyer")
        let feuille = element("chat-antifuite")
        require("La feuille anti-fuite est présentée", timeout: 30) { self.containerVisible(feuille) }
        XCTAssertEqual(element("chat-antifuite-titre").label, "Pour votre sécurité")
        XCTAssertEqual(element("chat-antifuite-description").label,
                       "Les numéros de téléphone ne peuvent pas être échangés via la messagerie Jolene.")
        XCTAssertTrue(element("chat-antifuite-explication").label.hasPrefix("Toutes les communications doivent rester sur la plateforme"))
        record("\(proofPrefix)-messagerie-antifuite")
        tap("chat-antifuite-compris")
        require("La feuille est refermée") { !self.element("chat-antifuite").exists }
        XCTAssertTrue((saisie.value as? String ?? "").contains("06 12 34 56 78"), "le texte saisi est conservé")
        XCTAssertFalse(element("chat-message-demo-message-envoi-2").exists, "rien n'a été envoyé")

        // Retour à la liste : la conversation n'a plus de non-lus, ni le badge.
        retour(depuis: "chat-screen")
        require("Plus aucun non-lu sur la conversation lue") { !self.element("conversation-nonlus-\(Attendus.etablissement)").exists }
        record("\(proofPrefix)-messagerie-lue")
        verifierAucuneRequete()
        let badge = element("nav-messages")
        tabButton("tab-accueil", label: "Accueil").tap()
        require("Le badge Messages est relu à zéro") { badge.exists && (badge.value as? String ?? "") == "" }
    }

    func testArchiveeBlocageEtSignalement() throws {
        launchDemo()
        connexionDemo()
        let bouton = element("nav-messages")
        require("Le bouton Messages est affiché", timeout: 30) { self.visible(bouton) }
        bouton.tap()
        let liste = ouvrirListe()

        // Conversation archivée : lecture seule.
        tap("messagerie-onglet-archivees")
        let archivee = element("conversation-\(Attendus.archivee)")
        require("La conversation archivée est listée") { archivee.exists }
        _ = ouvrirFil(Attendus.archivee, dans: liste)
        require("Le composeur est désactivé") { self.element("chat-archivee").exists }
        XCTAssertEqual(element("chat-archivee").label, "Conversation archivée — lecture seule.")
        XCTAssertFalse(element("chat-input").exists, "aucun champ de saisie dans une conversation archivée")
        record("\(proofPrefix)-messagerie-archivee")
        retour(depuis: "chat-screen")

        // Blocage en deux temps, puis déblocage direct.
        tap("messagerie-onglet-actives")
        _ = ouvrirFil(Attendus.etablissement, dans: liste)
        let bloquer = element("chat-bloquer")
        require("Le statut de blocage est lu") { self.visible(bloquer) && bloquer.label == "Bloquer" }
        bloquer.tap()
        require("La confirmation du blocage est demandée") { self.element("chat-bloquer-question").exists }
        XCTAssertEqual(element("chat-bloquer-question").label, "Bloquer l’établissement ?")
        tap("chat-bloquer-confirmer")
        let avis = element("chat-moderation-confirmation")
        require("Le blocage relu est annoncé") {
            avis.exists && avis.label.contains("L’établissement bloqué — les nouveaux messages sont coupés dans les deux sens.")
        }
        require("Le bouton propose le déblocage") { self.element("chat-bloquer").label == "Débloquer" }
        record("\(proofPrefix)-messagerie-bloque")
        tap("chat-bloquer")
        require("Le déblocage relu est annoncé") { avis.exists && avis.label.contains("L’établissement débloqué.") }
        require("Le bouton propose de nouveau le blocage") { self.element("chat-bloquer").label == "Bloquer" }

        // Signalement de l'établissement, motif obligatoire.
        tap("chat-signaler")
        let feuille = element("signalement-sheet")
        require("La feuille de signalement est présentée") { self.containerVisible(feuille) }
        XCTAssertFalse(element("signalement-envoyer").isEnabled, "motif obligatoire (10 caractères minimum)")
        let motif = element("signalement-motif")
        focus(motif, in: feuille)
        motif.typeText("Propos déplacés dans la conversation.")
        let envoyer = element("signalement-envoyer")
        if app.keyboards.firstMatch.exists, !visible(envoyer) { scrollTo(envoyer, in: feuille) }
        require("L'envoi est possible") { envoyer.isEnabled }
        envoyer.tap()
        require("Le signalement est confirmé") {
            !self.element("signalement-sheet").exists
                && avis.label.contains("Signalement transmis à Jolene. Merci, notre équipe va l’examiner.")
        }
        record("\(proofPrefix)-messagerie-signalement")
        retour(depuis: "chat-screen")
        verifierAucuneRequete()
    }

    func testEcrireALEtablissementDepuisUneMissionAttribuee() throws {
        launchDemo()
        connexionDemo()
        tabButton("tab-missions", label: "Mes missions").tap()
        let scroll = element("mes-missions-scroll")
        let ligne = element("mes-mission-\(Attendus.mission)")
        require("Mes missions affiche ses missions à venir", timeout: 30) {
            self.containerVisible(self.element("mes-missions-screen")) && ligne.exists && !self.element("mes-missions-loading").exists
        }
        scrollTo(ligne, in: scroll)
        ligne.tap()
        let detail = element("mission-detail")
        require("Le détail de la mission est rendu", timeout: 30) { self.containerVisible(detail) && self.element("mission-detail-title").exists }
        let contact = element("mission-contact")
        scrollTo(contact, in: detail)
        XCTAssertEqual(contact.label, "Écrire à l'établissement")
        contact.tap()
        require("Le fil de la mission est ouvert", timeout: 30) {
            self.containerVisible(self.element("chat-screen")) && self.element("chat-vide").exists
        }
        XCTAssertTrue(text(Attendus.nomEtablissement).exists, "fil de l'établissement de la mission")
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (T7b) : jamais un renvoi web")
        record("\(proofPrefix)-messagerie-fil-mission")
        retour(depuis: "chat-screen")
        require("La conversation de la mission est listée") { self.element("conversation-\(Attendus.filMission)").exists }
        verifierAucuneRequete()
    }

    // MARK: Étapes

    private func ouvrirListe() -> XCUIElement {
        let liste = defilement("messagerie-screen")
        require("La liste des conversations est relue", timeout: 30) {
            self.containerVisible(liste) && self.element("conversation-\(Attendus.etablissement)").exists
        }
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (T7b) : jamais un renvoi web")
        return liste
    }

    private func ouvrirFil(_ id: String, dans liste: XCUIElement) -> XCUIElement {
        let ligne = element("conversation-\(id)")
        scrollTo(ligne, in: liste)
        ligne.tap()
        let ecran = element("chat-screen")
        require("Le fil est affiché", timeout: 30) {
            self.containerVisible(ecran) && !self.element("chat-chargement").exists
        }
        return ecran
    }

    private func retour(depuis identifiant: String) {
        let back = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(back) }
        back.tap()
        require("L'écran \(identifiant) est retiré") { !self.element(identifiant).exists }
    }

    /// Conteneur de défilement : la `ScrollView` portant l'identifiant, sinon la première correspondance.
    private func defilement(_ identifier: String) -> XCUIElement {
        let typee = app.scrollViews.matching(identifier: identifier).firstMatch
        return typee.exists ? typee : element(identifier)
    }

    /// Profil remis à sa racine (la messagerie y est empilée), puis sentinelle réseau.
    private func verifierAucuneRequete() {
        tabButton("tab-profil", label: "Profil").tap()
        for ecran in ["chat-screen", "messagerie-screen"] where element(ecran).exists {
            retour(depuis: ecran)
        }
        let liste = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(liste) }
        let sentinelle = element("network-sentinel")
        scrollTo(sentinelle, in: liste, downward: false)
        require("La sentinelle réseau est exposée") { sentinelle.exists }
        XCTAssertEqual(sentinelle.label, "0 requête", "la messagerie n'émet aucune requête en démonstration")
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
