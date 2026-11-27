import XCTest

/// Parrainage (L4-T6) en démonstration, sur iPhone, iPad portrait et iPad paysage (`JOLENE_UI_ORIENTATION`,
/// `proofPrefix`) :
/// - Profil → « Parrainage » (`hub-parrainage`, fixture `demo-parrainage.json`) : code `JOLENE-DEMO`, QR code, lien qui
///   ne porte que le code, copie, partage, compteurs et trois filleuls avec leur statut serveur ; aucun montant ni
///   condition de prime (bloc T6-HS, HARD STOP n°4) ; renvoi neutre « Voir sur jolene.app » vers la page web ;
/// - lien `/inscription/soignant?ref=demo-xyz` reçu au lancement, déconnecté : le compte rapide natif du lot 3 s'ouvre
///   (lot 3 T7 livré : `.inscription(.soignant)` natif, jamais un renvoi web) ; retour à la connexion, connexion démo :
///   le code capté est appliqué au premier `.ready`, avis « Code de parrainage enregistré. » ;
/// - lien `?ref=<script>` (hors forme) : aucune capture, aucun avis après la connexion.
/// Aucune requête réseau (sentinelle). Les règles (forme, `ETB-`, fenêtre de 30 jours, double capture, marqueur, refus
/// définitifs, erreur réseau) sont prouvées par `ParrainageCaptureTests` ; la lecture et le message serveur jamais
/// affiché par `ParrainageModelTests` et `SupabaseParrainageGatewayTests`.
final class DemoParrainageTests: JoleneUITestCase {
    /// Surcharge démo et DEBUG de la durée de l'avis (`DureeAvisParrainage.variable`, JoleneCore).
    static let variableDureeAvis = "JOLENE_DEMO_PARRAINAGE_AVIS"

    private enum Attendus {
        static let lien = "https://jolene.app/inscription/soignant?ref=JOLENE-DEMO"
        static let filleuls = ["demo-filleul-001", "demo-filleul-002", "demo-filleul-003"]
        static let enregistre = "Code de parrainage enregistré."
    }

    func testEcranParrainageSansMontantNiCondition() throws {
        launchDemo()
        connexionDemo(emailDejaSaisi: false)
        let ecran = ouvrirParrainage()
        XCTAssertEqual(element("parrainage-code").label, "JOLENE-DEMO")
        XCTAssertEqual(element("parrainage-lien").label, Attendus.lien, "le lien ne porte que le code")
        XCTAssertTrue(element("parrainage-qr").exists)
        XCTAssertEqual(element("parrainage-qr").label, "QR code de ton lien de parrainage")
        XCTAssertFalse(element("parrainage-badge").exists, "badge non débloqué : ni badge ni condition affichés")
        record("\(proofPrefix)-parrainage-code")

        let copierLien = element("parrainage-copier-lien")
        scrollTo(copierLien, in: ecran)
        XCTAssertEqual(copierLien.label, "Copier le lien")
        copierLien.tap()
        require("La copie du lien est confirmée") { self.element("parrainage-copier-lien").label == "Copié !" }
        XCTAssertTrue(element("parrainage-partager").exists, "feuille de partage du système proposée")

        let inscrits = element("parrainage-compteur-inscrits")
        scrollTo(inscrits, in: ecran)
        XCTAssertTrue(inscrits.label.contains("3"), inscrits.label)
        XCTAssertTrue(inscrits.label.contains("filleuls inscrits"), inscrits.label)
        XCTAssertTrue(element("parrainage-compteur-missions").label.contains("mission terminée"))
        for id in Attendus.filleuls {
            let ligne = element("parrainage-filleul-\(id)")
            scrollTo(ligne, in: ecran)
            require("Le filleul \(id) est listé") { ligne.exists }
        }
        XCTAssertTrue(element("parrainage-filleul-demo-filleul-001").label.contains("1ère mission faite"))
        XCTAssertTrue(element("parrainage-filleul-demo-filleul-002").label.contains("En attente"))
        XCTAssertTrue(element("parrainage-filleul-demo-filleul-003").label.contains("Inscrit"))
        record("\(proofPrefix)-parrainage-filleuls")

        // Aucun montant, aucune condition de prime dans l'écran natif.
        for interdit in ["€", "Prime", "primes", "prime de", "IBAN", "Comment ça marche"] {
            XCTAssertEqual(ecran.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", interdit)).count, 0,
                           "« \(interdit) » absent de l'écran natif (T6-HS)")
        }

        let web = element("parrainage-web")
        scrollTo(web, in: ecran)
        XCTAssertEqual(web.label, "Voir sur jolene.app", "libellé neutre de navigation")
        web.tap()
        liensRenvoiWebAffiche("https://jolene.app/soignant/parrainage")
        liensFermerRenvoiWeb()
        verifierAucuneRequete()
    }

    func testLienInscriptionAvecCodeCapteEtAppliqueApresConnexion() throws {
        // L'avis se retire seul après 8 s dans l'app : au run 45446351274 (iPad paysage), le premier relevé a eu lieu 14,7 s
        // après « Se connecter », l'avis était déjà parti. `JOLENE_DEMO_PARRAINAGE_AVIS` (démo, DEBUG) le garde affiché
        // pendant le test ; la règle des 8 s est prouvée par `ParrainageCaptureTests`.
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/inscription/soignant?ref=demo-xyz"],
                   environment: [DemoParrainageTests.variableDureeAvis: "300"])
        allerALaConnexionDepuisLInscription()
        connexionDemo(emailDejaSaisi: true)
        let avis = element("parrainage-avis")
        require("Le code capté est appliqué au premier `.ready`", timeout: 30) { avis.exists }
        XCTAssertTrue(avis.label.contains(Attendus.enregistre), avis.label)
        XCTAssertFalse(avis.label.contains("prime"), "le message serveur de succès n'est jamais affiché")
        record("\(proofPrefix)-parrainage-applique")
        // Refermable : jamais laissé au-dessus de l'espace (le retrait seul est neutralisé ici par la surcharge).
        tap("parrainage-avis-fermer")
        require("L'avis est refermé") { !self.element("parrainage-avis").exists }
        verifierAucuneRequete()
    }

    func testLienAvecCodeHorsFormeNeCaptureRien() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/inscription/soignant?ref=%3Cscript%3E"])
        allerALaConnexionDepuisLInscription()
        connexionDemo(emailDejaSaisi: true)
        requireAbsence("Aucun code capté : aucun avis de parrainage", pendant: 5) { self.element("parrainage-avis").exists }
        record("\(proofPrefix)-parrainage-hors-forme")
        verifierAucuneRequete()
    }

    // MARK: Étapes

    /// Compte rapide natif ouvert par le lien (jamais un renvoi web), adresse démo saisie, retour à la connexion.
    private func allerALaConnexionDepuisLInscription() {
        let scroll = element("inscription-scroll")
        require("Le compte rapide natif est ouvert par le lien", timeout: 30) { self.containerVisible(scroll) }
        XCTAssertFalse(element("renvoi-web-demo").exists, "inscription native livrée (lot 3, T7) : jamais un renvoi web")
        XCTAssertFalse(tabBarExists, "aucun espace sans compte")
        record("\(proofPrefix)-parrainage-inscription")
        let email = element("inscription-email")
        focus(email, in: scroll)
        email.typeText(Self.demoEmail)
        email.typeText("\n")
        let retour = element("inscription-se-connecter")
        scrollTo(retour, in: scroll)
        tap("inscription-se-connecter")
        require("L'écran de connexion est de retour") { self.visible(self.element("login-scroll")) }
        require("L'adresse saisie est reprise") { (self.element("login-email").value as? String) == Self.demoEmail }
    }

    private func ouvrirParrainage() -> XCUIElement {
        toucherOnglet("tab-profil", label: "Profil")
        let liste = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(liste) }
        let entree = element("hub-parrainage")
        scrollTo(entree, in: liste)
        require("L'entrée « Parrainage » est atteignable") { self.visible(entree) }
        XCTAssertTrue(entree.label.contains("Parrainage"), entree.label)
        entree.tap()
        let ecran = defilement("parrainage-screen")
        require("Le parrainage est lu", timeout: 30) {
            self.containerVisible(ecran) && self.element("parrainage-code").exists
        }
        XCTAssertFalse(element("parrainage-indisponible").exists)
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (T6) : jamais un renvoi web")
        return ecran
    }

    /// Conteneur de défilement : la `ScrollView` portant l'identifiant, sinon la première correspondance.
    private func defilement(_ identifier: String) -> XCUIElement {
        let typee = app.scrollViews.matching(identifier: identifier).firstMatch
        return typee.exists ? typee : element(identifier)
    }

    /// Profil remis à sa racine (l'écran du parrainage y est empilé), puis sentinelle réseau.
    private func verifierAucuneRequete() {
        toucherOnglet("tab-profil", label: "Profil")
        if element("parrainage-screen").exists {
            let back = app.navigationBars.buttons.firstMatch
            require("Le bouton retour est disponible") { self.visible(back) }
            back.tap()
            require("L'écran du parrainage est retiré") { !self.element("parrainage-screen").exists }
        }
        let liste = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(liste) }
        let sentinelle = element("network-sentinel")
        scrollTo(sentinelle, in: liste, downward: false)
        require("La sentinelle réseau est exposée") { sentinelle.exists }
        XCTAssertEqual(sentinelle.label, "0 requête", "le parrainage n'émet aucune requête en démonstration")
    }

    private func connexionDemo(emailDejaSaisi: Bool) {
        let scroll = element("login-scroll")
        require("L'écran de connexion est affiché") { self.containerVisible(scroll) }
        let password = element("login-password")
        if emailDejaSaisi {
            focus(password, in: scroll)
        } else {
            let email = element("login-email")
            focus(email, in: scroll)
            email.typeText(Self.demoEmail)
            email.typeText("\n")
            if !hasKeyboardFocus(password) { focus(password, in: scroll) }
        }
        require("Le mot de passe a le focus clavier") { self.hasKeyboardFocus(password) }
        password.typeText(Self.demoPassword)
        let submit = element("login-submit")
        require("Le bouton de connexion est activé") { submit.isEnabled }
        if app.keyboards.firstMatch.exists, !visible(submit) { scrollTo(submit, in: scroll) }
        toucherSeConnecter(submit, "La session démo est prête") { self.tabBarExists }
    }
}
