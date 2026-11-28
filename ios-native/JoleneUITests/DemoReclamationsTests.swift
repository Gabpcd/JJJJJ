import XCTest

/// Réclamations générales (L4-T8) en démonstration, sur iPhone, iPad portrait et iPad paysage : Profil → « Litiges &
/// contestations » → onglet « Réclamations » (fixture `demo-reclamations.json` : une réclamation en attente, une résolue
/// avec la réponse de l'équipe) → « Signaler un problème » : sujet et détails saisis, réclamation relue en tête au statut
/// « En attente » ; l'alias `/soignant/reclamations` ouvre l'écran sur cet onglet ; son coupe-circuit
/// (`ios_natif_reclamations_actif`) coupé, l'onglet renvoie vers sa page web. Aucune requête réseau (sentinelle).
///
/// Les règles (relecture qui confirme, refus du serveur mot pour mot, réconciliation) sont prouvées par
/// `ReclamationsModelTests` et `Lot4WiringReclamationsTests` ; le transport par `SupabaseReclamationsGatewayTests` ; les
/// textes par `LitigesVerbatimTests`.
final class DemoReclamationsTests: JoleneUITestCase {
    private enum Attendus {
        static let enAttente = "demo-reclamation-001"
        static let resolue = "demo-reclamation-002"
        static let nouvelle = "demo-reclamation-ajout-1"
    }

    func testReclamationCreeeRelueEnTeteAuStatutEnAttente() throws {
        launchDemo()
        connexionDemo()
        let ecran = ouvrirLitiges()
        tap("litiges-onglet-reclamations")
        require("Les réclamations sont relues", timeout: 30) {
            self.element("litiges-onglet-reclamations").isSelected && self.element("reclamation-\(Attendus.enAttente)").exists
        }
        XCTAssertFalse(element("litige-ouvrir").exists, "l'onglet Litiges n'est plus affiché")
        XCTAssertEqual(elements(withPrefix: "reclamation-statut-").count, 2, "les deux réclamations de la fixture")
        XCTAssertEqual(element("reclamation-statut-\(Attendus.enAttente)").label, "En attente")
        XCTAssertEqual(element("reclamation-statut-\(Attendus.resolue)").label, "Résolue")
        let reponse = element("reclamation-reponse-\(Attendus.resolue)")
        scrollTo(reponse, in: ecran)
        XCTAssertTrue(reponse.label.contains("Réponse Jolene :"), reponse.label)
        XCTAssertTrue(reponse.label.contains("Démonstration · L’horaire a été corrigé, merci de votre signalement."), reponse.label)
        XCTAssertFalse(element("reclamation-reponse-\(Attendus.enAttente)").exists, "sans réponse : aucun bloc")
        record("\(proofPrefix)-reclamations-liste")

        // « Signaler un problème » : catégorie par défaut, sujet et détails.
        let nouvelle = element("reclamation-nouvelle")
        scrollTo(nouvelle, in: ecran, downward: false)
        XCTAssertEqual(nouvelle.label, "Signaler un problème")
        tap("reclamation-nouvelle")
        let feuille = defilement("reclamation-formulaire")
        let envoyer = element("reclamation-envoyer")
        require("La feuille de réclamation est affichée", timeout: 30) { self.containerVisible(feuille) && envoyer.exists }
        XCTAssertTrue(element("reclamation-categorie").exists, "sélecteur de catégorie")
        XCTAssertEqual(envoyer.label, "Envoyer")
        XCTAssertFalse(envoyer.isEnabled, "sans sujet ni détails : envoi impossible")
        let sujet = element("reclamation-sujet")
        focus(sujet, in: feuille)
        sujet.typeText("Montant du planning")
        XCTAssertFalse(envoyer.isEnabled, "sans détails : envoi impossible")
        // « Suivant » du clavier passe aux détails ; sinon le champ est amené à l'écran et touché.
        sujet.typeText("\n")
        let details = element("reclamation-details")
        if !hasKeyboardFocus(details) { focus(details, in: feuille) }
        require("Les détails ont le focus clavier") { self.hasKeyboardFocus(details) }
        details.typeText("Le montant du planning est a revoir.")
        fermerLePaveNumerique()
        require("Un sujet et des détails activent l'envoi") { envoyer.isEnabled }
        record("\(proofPrefix)-reclamation-formulaire")
        scrollTo(envoyer, in: feuille)
        tap("reclamation-envoyer")

        // Réclamation relue : en tête, « En attente ».
        let carte = element("reclamation-\(Attendus.nouvelle)")
        require("La réclamation est relue et la feuille refermée", timeout: 30) {
            !self.element("reclamation-envoyer").exists && carte.exists
        }
        let statuts = elements(withPrefix: "reclamation-statut-")
        XCTAssertEqual(statuts.count, 3)
        XCTAssertEqual(statuts.element(boundBy: 0).identifier, "reclamation-statut-\(Attendus.nouvelle)", "réclamation créée en tête")
        XCTAssertEqual(element("reclamation-statut-\(Attendus.nouvelle)").label, "En attente")
        let confirmation = element("reclamations-confirmation")
        scrollTo(confirmation, in: ecran, downward: false)
        XCTAssertTrue(confirmation.label.contains("Réclamation envoyée — nous reviendrons vers vous rapidement"), confirmation.label)
        XCTAssertFalse(element("reclamations-action-erreur").exists)
        // Le texte saisi n'est pas comparé (correction automatique du clavier du simulateur) : la présence de la carte
        // relue, son rang et son statut sont la preuve ; le contenu envoyé est prouvé par `ReclamationsModelTests`.
        record("\(proofPrefix)-reclamation-creee")
        verifierAucuneRequete()
    }

    /// Alias `/soignant/reclamations` (`src/App.tsx`) : l'écran s'ouvre sur l'onglet « Réclamations ».
    func testLienReclamationsOuvreLOngletReclamations() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/soignant/reclamations"])
        connexionDemo()
        let ecran = defilement("litiges-screen")
        require("L'écran natif est ouvert sur l'onglet Réclamations", timeout: 30) {
            self.containerVisible(ecran) && self.element("reclamation-\(Attendus.enAttente)").exists
        }
        XCTAssertTrue(element("litiges-onglet-reclamations").isSelected)
        XCTAssertFalse(element("litiges-onglet-litiges").isSelected)
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (T8) : jamais un renvoi web")
        XCTAssertEqual(element("deeplink-route").label, "secondaire(litiges, reclamations, sans id)")
        record("\(proofPrefix)-reclamations-lien")
    }

    /// Coupe-circuit propre à l'onglet (`ios_natif_reclamations_actif`) : coupé, l'onglet renvoie vers sa page web, sans
    /// rien lire ; l'onglet des litiges, lui, reste natif.
    func testOngletReclamationsCoupeRenvoieVersLeWeb() throws {
        launchDemo(extraArguments: ["-JOLENE_FLAG_ios_natif_reclamations_actif", "false"])
        connexionDemo()
        let ecran = ouvrirLitiges()
        tap("litiges-onglet-reclamations")
        let renvoi = element("litiges-onglet-renvoi")
        require("L'onglet coupé montre son renvoi web") { renvoi.exists && self.element("renvoi-web-ouvrir").exists }
        XCTAssertEqual(element("renvoi-web-message").label, "Cet écran est disponible sur jolene.app.")
        XCTAssertFalse(element("reclamation-nouvelle").exists, "onglet coupé : aucun contenu natif")
        XCTAssertFalse(element("reclamation-\(Attendus.enAttente)").exists)
        let ouvrir = element("renvoi-web-ouvrir")
        scrollTo(ouvrir, in: ecran)
        tap("renvoi-web-ouvrir")
        liensRenvoiWebAffiche("https://jolene.app/soignant/litiges?tab=reclamations")
        liensFermerRenvoiWeb()
        tap("litiges-onglet-litiges")
        require("L'onglet des litiges reste natif") { self.element("litige-ouvrir").exists && !renvoi.exists }
        record("\(proofPrefix)-reclamations-coupe-circuit")
    }

    // MARK: Étapes

    private func ouvrirLitiges() -> XCUIElement {
        toucherOnglet("tab-profil", label: "Profil")
        let liste = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(liste) }
        let entree = element("hub-litiges")
        scrollTo(entree, in: liste)
        require("L'entrée « Litiges & contestations » est atteignable") { self.visible(entree) }
        entree.tap()
        let ecran = defilement("litiges-screen")
        require("L'écran des litiges est affiché", timeout: 30) {
            self.containerVisible(ecran) && self.element("litiges-onglet-reclamations").exists && self.element("litige-ouvrir").exists
        }
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (T8) : jamais un renvoi web")
        return ecran
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
        XCTAssertEqual(sentinelle.label, "0 requête", "les réclamations n'émettent aucune requête en démonstration")
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
