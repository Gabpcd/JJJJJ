import XCTest

/// Liens du lot 2 en démo (L2-T10 ; `docs/mobile-swift/LOT2_PLAN.md` §3 T10) sur iPhone, iPad portrait et iPad paysage
/// (`JOLENE_UI_ORIENTATION`, `proofPrefix`). Le lien est injecté au lancement par l'argument DEBUG
/// `-JOLENE_OPEN_URL <url>` (lien universel simulé à froid, mêmes refus qu'un lien réel), donc **avant** la connexion :
/// la démo s'ouvre sur l'écran de connexion, le lien de l'espace est mémorisé puis rejoué une seule fois après `.ready`.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - `/contrat/<id démo>` ouvre le contrat natif (`contrat-screen`), `/contrat/<id>/certificat` la page native du
///   certificat (`certificat-screen`) — `/contrat/<id>` n'est plus un renvoi web (changement volontaire de T10) ;
/// - `/soignant/presences?tab=historique` ouvre la page Présences sur l'onglet Historique (`?tab=` aux valeurs exactes du
///   web), sans le bandeau « à valider » ; `&filtre=a_valider` l'affiche et ne garde que les présences à valider ;
/// - `/soignant/presences/mission/<id>` ouvre le détail natif des présences de la mission ;
/// - `/soignant/mes-documents?tab=contrats` ouvre « Mes documents » sur l'onglet Contrats natif ;
/// - `/soignant/dpae` reste un renvoi web, présenté aussitôt, sans session, jamais rejoué après la connexion ;
/// - chaque écran de « Mon espace » s'empile sur l'onglet Profil remis à sa racine : le retour ramène au hub ;
/// - libellé DEBUG `deeplink-route` (démo) : route effectivement présentée par le coordinateur ; aucune requête réseau.
/// Ailleurs, pour tenir l'éclat « documents » sous ses 30 min (décision 22) : le coupe-circuit `ios_natif_contrats_actif`
/// (D-FLAGS, à la charge de T10) dans `DemoContratsTests.testCoupeCircuitDesContratsRenvoieLeLienEtLaListeAuWeb`
/// (éclat « contrats ») ; la pile du Profil remise à sa racine quand un écran de « Mon espace » poussé par son entrée est
/// affiché (revue B8 de la PR #1131, m3) dans `DemoRevenusTests.testPresencesDUneMissionRemettentLeProfilASaRacine`
/// (éclat « lot3-revenus ») ; le tap push `CONTRAT_A_SIGNER` dans `DemoPushTests.testTapContratASignerOuvreLeContratNatif`.
/// Les règles (table des chemins, onglets inconnus, alias, liens de push, aiguillage, routes forcées web) sont prouvées au
/// niveau 1 (`LinksRouterLot2Tests`). Le lien universel réel (AASA, tap depuis Mail) se prouve sur appareil (T12).
final class DemoLiensLot2Tests: JoleneUITestCase {
    func testLienContratRecuAvantConnexionOuvreLeContratNatif() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/contrat/demo-contrat-001"])
        lot2AucunePresentationSurLaConnexion()
        lot2ConnexionDemo()
        let ecran = element("contrat-screen")
        let titre = element("contrat-titre")
        require("Le contrat natif est ouvert après `.ready`", timeout: 30) { self.containerVisible(ecran) && titre.exists }
        XCTAssertEqual(titre.label, "Contrat DEMO-0001")
        XCTAssertFalse(element("renvoi-web-demo").exists, "contrat natif (T9a) : jamais un renvoi web")
        XCTAssertFalse(element("contrats-desactive-renvoi").exists, "coupe-circuit fail-open : écran natif")
        XCTAssertEqual(element("deeplink-route").label, "contrat demo-contrat-001")
        record("\(proofPrefix)-liens-lot2-contrat")
        lot2RetourAuHub(depuis: ecran)
    }

    func testLienCertificatOuvreLaPageNativeDuCertificat() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/contrat/demo-contrat-002/certificat"])
        lot2AucunePresentationSurLaConnexion()
        lot2ConnexionDemo()
        let page = element("certificat-screen")
        let empreinte = element("certificat-empreinte")
        require("La page native du certificat est ouverte après `.ready`", timeout: 30) {
            self.containerVisible(page) && empreinte.exists
        }
        XCTAssertEqual(empreinte.label.count, 64)
        XCTAssertTrue(empreinte.label.hasPrefix("1d12b5ba"), "empreinte du contrat démo signé (fixture de l'exporteur)")
        XCTAssertFalse(element("renvoi-web-demo").exists, "certificat natif (T9a) : jamais un renvoi web")
        XCTAssertEqual(element("deeplink-route").label, "contratCertificat demo-contrat-002")
        record("\(proofPrefix)-liens-lot2-certificat")
        lot2RetourAuHub(depuis: page)
    }

    func testLienPresencesOngletHistorique() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/soignant/presences?tab=historique"])
        lot2AucunePresentationSurLaConnexion()
        lot2ConnexionDemo()
        let ecran = lot2PageDesPresences()
        require("L'onglet Historique est sélectionné (`?tab=historique`)") { self.element("presences-tab-historique").isSelected }
        require("L'historique est affiché") { self.element("presence-historique-demo-presence-h1-presence").exists }
        XCTAssertTrue(element("presence-historique-demo-presence-h2-presence").exists)
        XCTAssertFalse(element("presences-bandeau-a-valider").exists, "bandeau « à valider » : filtre du lien seulement")
        XCTAssertEqual(element("deeplink-route").label, "presences(historique, sans filtre)")
        record("\(proofPrefix)-liens-lot2-presences-historique")
        lot2RetourAuHub(depuis: ecran)
    }

    /// `?filtre=a_valider` (lien « À valider » du pipeline Revenus du web, `MesGains.tsx` l.452) : bandeau verbatim
    /// (`TextesWeb.Presences.bandeauAValider`, D2) et seules les présences à pointage complet non validées.
    func testLienPresencesFiltreAValiderAfficheLeBandeau() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/soignant/presences?tab=historique&filtre=a_valider"])
        lot2AucunePresentationSurLaConnexion()
        lot2ConnexionDemo()
        let ecran = lot2PageDesPresences()
        require("L'onglet Historique est sélectionné") { self.element("presences-tab-historique").isSelected }
        let bandeau = element("presences-bandeau-a-valider")
        require("Le bandeau « à valider » est affiché") { bandeau.exists }
        XCTAssertTrue(bandeau.label.contains(Self.bandeauAValider), bandeau.label)
        require("La présence à valider est listée") { self.element("presence-historique-demo-presence-h2-presence").exists }
        XCTAssertFalse(element("presence-historique-demo-presence-h1-presence").exists, "présence validée : filtrée")
        XCTAssertEqual(element("deeplink-route").label, "presences(historique, a_valider)")
        record("\(proofPrefix)-liens-lot2-presences-a-valider")
        lot2RetourAuHub(depuis: ecran)
    }

    func testLienDetailDesPresencesDUneMission() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/soignant/presences/mission/demo-presence-h2"])
        lot2AucunePresentationSurLaConnexion()
        lot2ConnexionDemo()
        let ecran = element("presence-detail-screen")
        let entete = element("presence-detail-entete")
        require("Le détail natif des présences est ouvert après `.ready`", timeout: 30) {
            self.containerVisible(ecran) && entete.exists
        }
        // Requête limitée à l'en-tête (comme `DemoPresenceDetailTests.verifier`), jamais à tout l'arbre de l'app.
        XCTAssertTrue(entete.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Démonstration · Présence à valider"))
                        .firstMatch.exists, "en-tête de la mission démo")
        XCTAssertFalse(element("presence-detail-introuvable").exists)
        XCTAssertFalse(element("renvoi-web-demo").exists, "détail natif (T5a) : jamais un renvoi web")
        XCTAssertEqual(element("deeplink-route").label, "presencesMission demo-presence-h2")
        record("\(proofPrefix)-liens-lot2-detail-presences")
        lot2RetourAuHub(depuis: ecran)
    }

    func testLienMesDocumentsOngletContrats() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/soignant/mes-documents?tab=contrats"])
        lot2AucunePresentationSurLaConnexion()
        lot2ConnexionDemo()
        let ecran = element("documents-screen")
        require("« Mes documents » est ouvert après `.ready`", timeout: 30) { self.containerVisible(ecran) }
        require("L'onglet Contrats est sélectionné (`?tab=contrats`)") { self.element("documents-tab-contrats").isSelected }
        require("La liste native des contrats est affichée") {
            self.element("contrats-liste").exists && self.element("contrat-carte-demo-contrat-001").exists
        }
        XCTAssertFalse(element("documents-tab-justificatifs").isSelected)
        XCTAssertFalse(element("renvoi-web-demo").exists, "onglet Contrats natif (T9a) : jamais un renvoi web")
        XCTAssertEqual(element("deeplink-route").label, "documents(contrats)")
        record("\(proofPrefix)-liens-lot2-documents-contrats")
        lot2RetourAuHub(depuis: ecran)
        let sentinelle = element("network-sentinel")
        scrollTo(sentinelle, in: element("profile-list"), downward: false)
        require("La sentinelle réseau est exposée") { sentinelle.exists }
        XCTAssertEqual(sentinelle.label, "0 requête", "liens démo du lot 2 : aucune requête réseau")
    }

    /// DPAE (décision 16 du lot 2) : page web, présentée aussitôt sans session, jamais mémorisée ni rejouée.
    func testLienDpaeRenvoiWebAussitotSansSession() throws {
        let lien = "https://jolene.app/soignant/dpae"
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", lien])
        liensRenvoiWebAffiche(lien)
        XCTAssertFalse(tabBarExists, "aucun espace : le renvoi n'en a pas besoin")
        record("\(proofPrefix)-liens-lot2-dpae")
        liensFermerRenvoiWeb()
        require("L'écran de connexion est de nouveau affiché") { self.containerVisible(self.element("login-scroll")) }
        XCTAssertEqual(element("deeplink-route").label, "safari \(lien)")
        lot2ConnexionDemo()
        require("L'Accueil est affiché, sans rejeu du lien", timeout: 30) { self.containerVisible(self.element("accueil-screen")) }
        XCTAssertFalse(element("renvoi-web-demo").exists, "renvoi déjà présenté : jamais rejoué après `.ready`")
        XCTAssertFalse(element("documents-screen").exists)
    }

    /// `TextesWeb.Presences.bandeauAValider` (début, verbatim du web ; garde au caractère près par `textes-juridiques-ios`).
    private static let bandeauAValider = "⏳ Présences en attente de validation par l'établissement (validation automatique sous 72 h)."

    // MARK: Étapes

    /// Écran de connexion affiché, et rien de présenté par-dessus ni à sa place (lien de l'espace mémorisé) : absence
    /// bornée (attente inversée), comme `DemoLiensLot3Tests`.
    private func lot2AucunePresentationSurLaConnexion() {
        require("L'écran de connexion est affiché") { self.containerVisible(self.element("login-scroll")) }
        requireAbsence("Rien n'est présenté avant `.ready` : ni renvoi web, ni route, ni espace, ni alerte") {
            self.element("renvoi-web-demo").exists || self.element("deeplink-route").exists || self.tabBarExists
                || self.app.alerts.count > 0
        }
        XCTAssertTrue(containerVisible(element("login-scroll")), "l'écran de connexion reste affiché")
    }

    private func lot2ConnexionDemo() {
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
        submit.tap()
        require("La session démo est prête : la barre d'onglets est affichée", timeout: 30) { self.tabBarExists }
    }

    /// Page Présences chargée (onglets affichés, aucun chargement ni erreur).
    private func lot2PageDesPresences() -> XCUIElement {
        let ecran = element("presences-screen")
        require("La page Présences est ouverte après `.ready`", timeout: 30) {
            self.containerVisible(ecran) && self.element("presences-tab-historique").exists && !self.element("presences-loading").exists
        }
        XCTAssertFalse(element("presences-error").exists, "aucune erreur en démo")
        XCTAssertFalse(element("renvoi-web-demo").exists, "page native (T4a) : jamais un renvoi web")
        return ecran
    }

    /// L'écran de « Mon espace » est empilé sur le Profil remis à sa racine : le retour mène au hub.
    private func lot2RetourAuHub(depuis ecran: XCUIElement) {
        let retour = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(retour) }
        retour.tap()
        require("Retour au hub, racine de l'onglet Profil") {
            self.containerVisible(self.element("profile-list")) && !ecran.exists
        }
    }
}
