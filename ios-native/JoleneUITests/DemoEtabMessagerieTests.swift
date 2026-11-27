import XCTest

/// Messagerie de l'espace établissement en démo (lot 5, T11 ; `docs/mobile-swift/LOT5_PLAN.md` §3 T11) sur iPhone, iPad
/// portrait et iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`). Fixture `demo-etab-messagerie.json` :
/// `demo-etab-conv-001` (mission M4, soignant Camille Démo, un message d'un collègue, deux non lus du soignant),
/// `demo-etab-conv-002` (mission M8, archivée).
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela : l'onglet Messages rend l'écran de la messagerie du lot 4 en
/// contexte établissement (pas un second écran) ; non-lus du soignant (2) ; bulle « Équipe établissement » ; envoi
/// affiché seulement après relecture, réponse démo du soignant affichée sans geste ; conversation archivée en lecture
/// seule ; blocage et signalement atteignables depuis le fil, libellé de cible du rôle établissement (« cet
/// utilisateur ») ; aucune requête réseau. Les règles (auteur = utilisateur courant, contexte du port, non confirmé sans
/// renvoi, compteur relu) sont prouvées au niveau 1 (`MessagerieEtablissementTests`,
/// `SupabaseMessagerieEtablissementTests`). Vérifié par la CI seulement (aucun simulateur en local), dans l'éclat
/// « lot4 » du job `ui-lot1` de `ios-swift-ci.yml`, avec la messagerie du lot 4 qu'elle réemploie (hors du socle).
final class DemoEtabMessagerieTests: JoleneUITestCase {
    private let espaceEtablissement = ["-JOLENE_DEMO_ESPACE", "etablissement"]

    private enum Attendus {
        static let active = "demo-etab-conv-001"
        static let archivee = "demo-etab-conv-002"
        static let messageCollegue = "demo-etab-message-002"
        static let dernierSoignant = "demo-etab-message-004"
    }

    func testListeEquipeEnvoiReluEtReponseDuSoignant() throws {
        launchDemo(extraArguments: espaceEtablissement)
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        let liste = ouvrirMessages()
        let pastille = element("conversation-nonlus-\(Attendus.active)")
        require("La conversation de M4 compte les deux messages du soignant") { pastille.exists && pastille.label == "2" }
        XCTAssertFalse(element("conversation-\(Attendus.archivee)").exists, "l'archivée n'est pas dans l'onglet Actives")
        record("\(proofPrefix)-etab-messagerie-liste")

        let ecran = ouvrirFil(Attendus.active, dans: liste)
        require("Les messages de la fixture sont affichés") { self.element("chat-message-\(Attendus.dernierSoignant)").exists }
        let equipe = element("chat-equipe-\(Attendus.messageCollegue)")
        XCTAssertTrue(equipe.exists, "message d'un collègue du côté de l'établissement")
        XCTAssertEqual(equipe.label, "Équipe établissement")
        XCTAssertTrue(element("chat-signaler").exists, "signalement atteignable depuis le fil (blocage : second test)")
        record("\(proofPrefix)-etab-messagerie-fil")

        let saisie = element("chat-input")
        focus(saisie, in: ecran)
        saisie.typeText("Un badge vous attend à l'accueil.")
        tap("chat-envoyer")
        require("Le message envoyé est relu puis affiché", timeout: 30) {
            self.element("chat-message-demo-etab-message-envoi-1").exists
        }
        XCTAssertFalse(element("chat-non-confirme").exists, "envoi confirmé par relecture")
        require("La réponse du soignant démo s'affiche sans geste", timeout: 30) {
            self.element("chat-message-demo-etab-message-reponse-1").exists
        }
        record("\(proofPrefix)-etab-messagerie-envoi")

        retour(depuis: "chat-screen")
        require("Plus aucun non-lu sur la conversation lue") { !self.element("conversation-nonlus-\(Attendus.active)").exists }
        verifierAucuneRequete()
    }

    func testArchiveeBlocageEtSignalementDuSoignant() throws {
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_DEMO_ROLE_ETAB", "RH"])
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        let liste = ouvrirMessages()

        tap("messagerie-onglet-archivees")
        require("La conversation archivée est listée") { self.element("conversation-\(Attendus.archivee)").exists }
        _ = ouvrirFil(Attendus.archivee, dans: liste)
        require("Le composeur est désactivé") { self.element("chat-archivee").exists }
        XCTAssertFalse(element("chat-input").exists, "aucun champ de saisie dans une conversation archivée")
        record("\(proofPrefix)-etab-messagerie-archivee")
        retour(depuis: "chat-screen")

        tap("messagerie-onglet-actives")
        _ = ouvrirFil(Attendus.active, dans: liste)
        let bloquer = element("chat-bloquer")
        require("Le statut de blocage est lu") { self.visible(bloquer) && bloquer.label == "Bloquer" }
        bloquer.tap()
        require("La confirmation du blocage est demandée") { self.element("chat-bloquer-question").exists }
        XCTAssertEqual(element("chat-bloquer-question").label, "Bloquer cet utilisateur ?",
                       "rôle établissement : libellé par défaut du web (BloquerUtilisateur.tsx l.20)")
        tap("chat-bloquer-annuler")

        tap("chat-signaler")
        let feuille = element("signalement-sheet")
        require("La feuille de signalement du soignant est présentée") { self.containerVisible(feuille) }
        XCTAssertFalse(element("signalement-envoyer").isEnabled, "motif obligatoire (10 caractères minimum)")
        record("\(proofPrefix)-etab-messagerie-signalement")
        tap("signalement-annuler")
        require("La feuille est refermée") { !self.element("signalement-sheet").exists }
        retour(depuis: "chat-screen")
        verifierAucuneRequete()
    }

    // MARK: Étapes

    private func ouvrirMessages() -> XCUIElement {
        toucherOnglet("tab-etab-messages", label: "Messages")
        let liste = defilement("messagerie-screen")
        require("La messagerie de l'établissement est relue", timeout: 30) {
            self.containerVisible(liste) && self.element("conversation-\(Attendus.active)").exists
        }
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (T11) : jamais un renvoi web")
        return liste
    }

    private func ouvrirFil(_ id: String, dans liste: XCUIElement) -> XCUIElement {
        let ligne = element("conversation-\(id)")
        scrollTo(ligne, in: liste)
        ligne.tap()
        let ecran = element("chat-screen")
        require("Le fil est affiché", timeout: 30) { self.containerVisible(ecran) && !self.element("chat-chargement").exists }
        return ecran
    }

    private func retour(depuis identifiant: String) {
        let back = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(back) }
        back.tap()
        require("L'écran \(identifiant) est retiré") { !self.element(identifiant).exists }
    }

    private func defilement(_ identifier: String) -> XCUIElement {
        let typee = app.scrollViews.matching(identifier: identifier).firstMatch
        return typee.exists ? typee : element(identifier)
    }

    /// Compte de l'établissement, puis sentinelle réseau.
    private func verifierAucuneRequete() {
        toucherOnglet("tab-etab-compte", label: "Compte")
        let liste = element("etab-compte-screen")
        require("Le compte de l'établissement est affiché") { self.containerVisible(liste) }
        let sentinelle = element("network-sentinel")
        scrollTo(sentinelle, in: liste)
        require("La sentinelle réseau est exposée") { sentinelle.exists }
        XCTAssertEqual(sentinelle.label, "0 requête", "la messagerie n'émet aucune requête en démonstration")
    }
}
