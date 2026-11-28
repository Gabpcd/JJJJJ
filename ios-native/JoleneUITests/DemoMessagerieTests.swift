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
        toucherOnglet("tab-accueil", label: "Accueil")
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
        toucherOnglet("tab-missions", label: "Mes missions")
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

    /// Suivi de la fin du fil (`SuiviFinDuFil`, revue du delta de la PR #1185, majeurs 1 et 2). Probant en iPad paysage, où
    /// le clavier ne laisse que 72 à 84 pt au fil ; sur les autres formats le fil tient dans la zone et le test passe sans
    /// rien distinguer.
    /// - fil court, clavier ouvert SANS envoi : les derniers messages restent dans la zone (branche « fin visible », aucun
    ///   envoi ; `8651dbe9` les suivait, `8e0b2b8e` non) ;
    /// - envoi : le message et la réponse sont dans la zone ;
    /// - l'utilisateur remonte au premier message, la fenêtre de l'envoi passée (horloge d'interface, jamais l'horloge
    ///   démo figée) : un changement de hauteur (composeur qui grandit) ne le ramène pas en bas.
    func testSuiviDeLaFinDuFilClavierEnvoiEtHistoireRelue() throws {
        launchDemo()
        connexionDemo()
        let bouton = element("nav-messages")
        require("L'onglet Messages est affiché", timeout: 30) { bouton.exists }
        bouton.tap()
        let liste = ouvrirListe()
        let ecran = ouvrirFil(Attendus.etablissement, dans: liste)
        let dernier = "chat-message-demo-message-003"
        require("Le dernier message est dans la zone du fil") { self.dansLaZone(dernier) }

        // Fil court, clavier ouvert sans envoi : la zone rétrécit, la fin était visible, elle suit.
        let saisie = element("chat-input")
        focus(saisie, in: ecran)
        require("Clavier ouvert sans envoi : le dernier message reste dans la zone", timeout: 10) { self.dansLaZone(dernier) }
        record("\(proofPrefix)-messagerie-fin-clavier-sans-envoi")

        // Envoi : message et réponse dans la zone.
        saisie.typeText("Bonjour, je confirme ma disponibilité.")
        tap("chat-envoyer")
        require("Le message envoyé et la réponse sont dans la zone", timeout: 30) {
            self.dansLaZone("chat-message-demo-message-reponse-1") && self.element("chat-message-demo-message-envoi-1").exists
        }

        // Fenêtre de l'envoi passée (2 s, horloge d'interface), l'utilisateur remonte au premier message.
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "fenêtre de l'envoi passée")], timeout: 3)
        let premier = "chat-message-demo-message-001"
        let zone = element("chat-messages")
        for _ in 0..<6 where !dansLaZone(premier) { zone.swipeDown() }
        require("L'utilisateur relit le premier message", timeout: 10) { self.dansLaZone(premier) }
        // Changement de hauteur : le composeur grandit (texte long, non envoyé).
        saisie.typeText(String(repeating: "Je relis le fil avant de répondre. ", count: 8))
        requireAbsence("Historique relu après un envoi : un changement de hauteur ne ramène pas le fil en bas", pendant: 3) {
            !self.dansLaZone(premier)
        }
        record("\(proofPrefix)-messagerie-historique-relu")
        verifierAucuneRequete()
    }

    // MARK: Étapes

    /// L'élément `id` est dans la zone visible du fil (`chat-messages`), sur au moins 20 pt (ou toute sa hauteur).
    private func dansLaZone(_ id: String) -> Bool {
        let cible = element(id)
        let zone = element("chat-messages")
        guard cible.exists, zone.exists else { return false }
        let part = zone.frame.intersection(cible.frame)
        return !part.isNull && part.height >= min(20, cible.frame.height)
    }

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

    /// Retour arrière par le bouton retour de la barre, jamais par « le premier bouton d'une barre ». Ce premier bouton
    /// n'est pas toujours le retour : en local (iOS 18.6, code de `main`),
    /// `testArchiveeBlocageEtSignalement` touchait `nav-messages` au lieu du retour, et `messagerie-screen` restait affiché.
    /// Seul le bouton retour du système (`BackButton`, touchable) est retenu, sans repli : à la racine du Profil,
    /// `nav-messages` est le seul bouton de la barre, et le « plus à gauche » d'avant pouvait le désigner (revue B8 de
    /// #1203, M2). Absent, le retour échoue net (« Le bouton retour est disponible »).
    private func retour(depuis identifiant: String) {
        let back = boutonRetour()
        require("Le bouton retour est disponible") { back().map { self.visible($0) && $0.isHittable } ?? false }
        back()?.tap()
        require("L'écran \(identifiant) est retiré") { !self.element(identifiant).exists }
    }

    private func boutonRetour() -> () -> XCUIElement? {
        {
            let systeme = self.app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch
            return systeme.exists && systeme.isHittable ? systeme : nil
        }
    }

    /// Conteneur de défilement : la `ScrollView` portant l'identifiant, sinon la première correspondance.
    private func defilement(_ identifier: String) -> XCUIElement {
        let typee = app.scrollViews.matching(identifier: identifier).firstMatch
        return typee.exists ? typee : element(identifier)
    }

    /// Profil remis à sa racine (la messagerie y est empilée), puis sentinelle réseau.
    ///
    /// Un fil quitté clavier ouvert est d'abord fermé par son retour. Sur iPhone, le clavier recouvre la barre d'onglets.
    /// Run 45626727902 (main `be5b0d49`, iOS 26.2), `testSuiviDeLaFinDuFilClavierEnvoiEtHistoireRelue` :
    /// - le toucher de l'onglet Profil (« person ») avait un point calculé {-1, -1} et tombait sous le clavier ;
    /// - l'alerte système « Enable Dictation? » s'ouvrait, et le gestionnaire d'interruption par défaut touchait
    ///   « About Siri, Dictation & Privacy… » ;
    /// - le retour suivant n'avait plus d'effet, et `chat-screen` restait affiché (l.255).
    /// En iPad portrait, les onglets sont hors du clavier et le même test passait.
    private func verifierAucuneRequete() {
        if app.keyboards.firstMatch.exists, element("chat-screen").exists {
            retour(depuis: "chat-screen")
        }
        let profil = tabButton("tab-profil", label: "Profil")
        require("L'onglet Profil est touchable") { profil.isHittable && !self.app.keyboards.firstMatch.exists }
        revenirALaRacine("tab-profil", label: "Profil", racine: "profile-list",
                         empiles: ["chat-screen", "messagerie-screen"])
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
