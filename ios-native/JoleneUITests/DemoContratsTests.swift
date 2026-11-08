import XCTest

/// Contrats en démonstration (lot 2, T9a ; `LOT2_PLAN.md` §3 T9a, décisions 17 à 19) : Profil › Mes contrats →
/// liste filtrée comme le web (`ListeContrats.tsx`) → lecture d'un contrat dont l'original est contrôlé par son
/// empreinte (fixtures `demo-contrat-00N.html`, horloge démo `2026-11-02T00:00:00Z`) → certificat, partage du fichier
/// original, CDD à préparer. Aucune signature native dans cette tranche : la zone « Votre signature » est un renvoi
/// web, sans bouton tant qu'aucun présentateur `.safari` n'est injecté (lot 1 T10 ; gap verrouillé, comme
/// `DemoAccueilTests`) ; T9b remplacera la zone par la signature OTP. Aucune requête réseau (sentinelle).
///
/// Identifiants : `profil-contrats` (entrée provisoire, remplacée par `EspaceSoignantSection` de T4a), `contrats-liste`,
/// `contrats-filtre-<statut>`, `contrat-carte-<id>`, `contrats-vide`, `contrat-screen`, `contrat-countdown`,
/// `contrat-titre`, `contrat-statut`, `contrat-lecteur`, `contrat-empreinte`, `contrat-partager`, `contrat-imprimer`,
/// `contrat-certificat` (+ `-<signature>`), `contrat-certificat-ouvrir`, `certificat-screen`, `certificat-signatures-<signature>`,
/// `certificat-empreinte`, `certificat-export`,
/// `contrat-signatures` (+ `-etablissement`, `-soignant`), `contrat-renvoi-web` (+ `-action`, `-indisponible`), `contrat-deja-signe`,
/// `contrat-cdd-a-preparer`, `contrat-contenu-indisponible`, `contrat-pied-de-page`.
final class DemoContratsTests: JoleneUITestCase {
    /// `TextesWeb.CompteARebours.texte` à 62 h (contrat créé 10 h avant l'horloge démo).
    static let compteARebours = "Signature à finaliser sous 62h 00m 00s"
    /// `TextesWeb.Contrat.cddAPreparer` (`ContratMission.tsx` l.603).
    static let cddAPreparer = "Le contrat doit être préparé et confirmé par un représentant autorisé de l’employeur avant les signatures."
    /// `TextesWeb.Contrat.contenuPasDisponible` (l.637).
    static let contenuPasDisponible = "Le contenu du contrat n'est pas encore disponible."
    /// `LibellesWeb.SignatureOtp.signatureNonDisponible` (`SignerContratOtp.tsx` l.230).
    static let signatureNonDisponible = "Signature non disponible pour le moment"

    func testListeFiltresPuisContratEnAttenteLuSansRequete() throws {
        launchDemo()
        signInDemo()
        openContrats()
        let liste = element("contrats-liste")
        for id in ["demo-contrat-001", "demo-contrat-002", "demo-contrat-003"] {
            require("La carte \(id) est affichée") { self.element("contrat-carte-\(id)").exists }
        }
        record("\(proofPrefix)-contrats-liste")

        tap("contrats-filtre-SIGNE_COMPLET")
        require("Filtre « Signés » : seul le contrat signé reste") {
            self.element("contrat-carte-demo-contrat-002").exists && !self.element("contrat-carte-demo-contrat-001").exists
                && !self.element("contrat-carte-demo-contrat-003").exists
        }
        tap("contrats-filtre-ANNULE")
        require("Filtre « Annulés » : état vide du web") { self.element("contrats-vide").exists }
        XCTAssertFalse(element("contrat-carte-demo-contrat-002").exists)
        tap("contrats-filtre-EN_ATTENTE_SIGNATURES")
        require("Filtre « En attente » : les deux contrats non signés") {
            self.element("contrat-carte-demo-contrat-001").exists && self.element("contrat-carte-demo-contrat-003").exists
                && !self.element("contrat-carte-demo-contrat-002").exists
        }
        tap("contrats-filtre-Tous")
        require("Filtre « Tous » : trois contrats") { self.element("contrat-carte-demo-contrat-002").exists }

        openCarte("demo-contrat-001", in: liste)
        let ecran = element("contrat-screen")
        let rebours = element("contrat-countdown")
        require("Le compte à rebours de 72 h est affiché") { rebours.exists }
        XCTAssertEqual(rebours.label, Self.compteARebours, "dérivé de `cree_le`, horloge démo fixée")
        XCTAssertEqual(element("contrat-titre").label, "Contrat DEMO-0001")
        XCTAssertEqual(element("contrat-statut").label, "Statut : ⏳ En attente de signatures")
        XCTAssertTrue(element("contrat-empreinte").label.hasPrefix("Document officiel figé le 01/11/2026 à 15:05 — empreinte "))

        let lecteur = element("contrat-lecteur")
        require("Le lecteur isolé affiche l'original contrôlé", timeout: 30) {
            lecteur.exists && lecteur.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "DEMO-0001")).count > 0
        }
        // Lecteur pleine largeur de la colonne, sans débordement horizontal (iPad paysage compris).
        XCTAssertGreaterThanOrEqual(lecteur.frame.width, app.frame.width * 0.6, "lecteur pleine largeur")
        XCTAssertLessThanOrEqual(lecteur.frame.minX, app.frame.width)
        XCTAssertGreaterThanOrEqual(lecteur.frame.minX, app.frame.minX - 1, "aucun débordement à gauche")
        XCTAssertLessThanOrEqual(lecteur.frame.maxX, app.frame.maxX + 1, "aucun débordement à droite")
        XCTAssertTrue(element("contrat-imprimer").exists, "impression du lecteur proposée")
        record("\(proofPrefix)-contrat-en-attente")

        // Zone « Votre signature » : renvoi web, sans bouton tant que T10 n'a pas injecté le présentateur.
        let indisponible = element("contrat-renvoi-web-indisponible")
        require("La zone de signature est rendue") { indisponible.exists }
        scrollTo(indisponible, in: ecran)
        XCTAssertTrue(element("contrat-renvoi-web").exists, "zone de signature en renvoi web")
        XCTAssertEqual(indisponible.label, Self.signatureNonDisponible)
        XCTAssertFalse(element("contrat-renvoi-web-action").exists, "aucun bouton sans effet avant T10 (présentateur `.safari`)")
        XCTAssertFalse(element("contract-otp").exists, "aucune signature native avant T9b")
        XCTAssertFalse(element("contrat-deja-signe").exists)
        XCTAssertEqual(element("contrat-signatures-etablissement").label, "Établissement : ⏳ En attente")
        XCTAssertEqual(element("contrat-signatures-soignant").label, "Soignant(e) : ⏳ En attente")
        let pied = element("contrat-pied-de-page")
        scrollTo(pied, in: ecran)
        XCTAssertTrue(pied.label.hasPrefix("Contrat salarié écrit — art. L.1242-12 du Code du travail."), "pied de page verbatim")
        record("\(proofPrefix)-contrat-renvoi-signature")

        // Retour au profil : aucune requête réseau pendant la lecture.
        goBack()
        require("La liste des contrats est de retour") { self.containerVisible(self.element("contrats-liste")) }
        goBack()
        assertNoNetworkRequest()
    }

    func testContratSigneCertificatEtPartageDuFichierOriginal() throws {
        launchDemo()
        signInDemo()
        openContrats()
        openCarte("demo-contrat-002", in: element("contrats-liste"))
        let ecran = element("contrat-screen")
        require("Le contrat signé est affiché") { self.element("contrat-statut").exists }
        XCTAssertEqual(element("contrat-statut").label, "Statut : ✅ Signé")
        XCTAssertFalse(element("contrat-countdown").exists, "aucun compte à rebours pour un contrat signé")
        XCTAssertFalse(element("contrat-renvoi-web").exists, "aucune zone de signature pour un contrat signé")

        let ligneEtablissement = element("contrat-certificat-demo-signature-002-etab")
        require("Le certificat résumé est rendu") { ligneEtablissement.exists }
        scrollTo(ligneEtablissement, in: ecran)
        XCTAssertTrue(element("contrat-certificat").exists)
        XCTAssertTrue(element("contrat-certificat-demo-signature-002-soignant").exists)
        XCTAssertEqual(element("contrat-signatures-etablissement").label, "Établissement : ✅ Signé le 29/10/2026 à 02:00")
        XCTAssertEqual(element("contrat-signatures-soignant").label, "Soignant(e) : ✅ Signé le 29/10/2026 à 03:00")
        let dejaSigne = element("contrat-deja-signe")
        scrollTo(dejaSigne, in: ecran)
        XCTAssertEqual(dejaSigne.label, "✅ Vous avez déjà signé ce contrat")
        record("\(proofPrefix)-contrat-signe-certificat")

        // Page du certificat : empreinte complète, export PDF en renvoi web (aucun bouton avant T10).
        let ouvrir = element("contrat-certificat-ouvrir")
        scrollTo(ouvrir, in: ecran)
        tap("contrat-certificat-ouvrir")
        let page = element("certificat-screen")
        require("La page du certificat est affichée") { self.containerVisible(page) }
        let empreinte = element("certificat-empreinte")
        require("L'empreinte complète du document signé est affichée") { empreinte.exists }
        XCTAssertEqual(empreinte.label.count, 64)
        XCTAssertTrue(empreinte.label.hasPrefix("1d12b5ba"), "empreinte du contrat démo signé (fixture de l'exporteur)")
        XCTAssertTrue(element("certificat-signatures-demo-signature-002-soignant").exists, "certificat résumé repris sur la page")
        XCTAssertFalse(element("certificat-export").exists, "export PDF : renvoi web, aucun bouton avant T10")
        record("\(proofPrefix)-certificat")
        goBack()

        // Partage : la feuille système présente le fichier original contrôlé.
        let partager = element("contrat-partager")
        scrollTo(partager, in: ecran)
        require("Le partage est possible pour un original contrôlé") { partager.isEnabled }
        tap("contrat-partager")
        require("La feuille de partage du système est présentée", timeout: 20) {
            self.app.otherElements["ActivityListView"].exists || self.app.navigationBars["UIActivityContentView"].exists
        }
        record("\(proofPrefix)-contrat-partage")
    }

    func testCddSansOriginalAfficheLeMessageDuWebSansLecteur() throws {
        launchDemo()
        signInDemo()
        openContrats()
        openCarte("demo-contrat-003", in: element("contrats-liste"))
        let message = element("contrat-cdd-a-preparer")
        require("Le CDD à préparer affiche le message du web") { message.exists }
        XCTAssertEqual(message.label, Self.cddAPreparer)
        let contenu = element("contrat-contenu-indisponible")
        require("Le contenu indisponible est annoncé") { contenu.exists }
        XCTAssertEqual(contenu.label, Self.contenuPasDisponible)
        XCTAssertFalse(element("contrat-lecteur").exists, "aucun original : aucun lecteur, aucune reconstitution")
        XCTAssertFalse(element("contrat-partager").isEnabled, "rien à partager")
        XCTAssertFalse(element("contrat-imprimer").exists)
        XCTAssertFalse(element("contrat-renvoi-web").exists, "aucune action soignant pour un CDD à préparer (décision 19)")
        XCTAssertTrue(element("contrat-countdown").exists)
        record("\(proofPrefix)-contrat-cdd-a-preparer")
    }

    // MARK: Étapes

    private func signInDemo() {
        let scroll = element("login-scroll")
        require("L'écran de connexion est affiché") { self.visible(scroll) }
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
        require("La session est prête : la barre d'onglets est affichée", timeout: 30) { self.tabBarExists }
    }

    private func openContrats() {
        tabButton("tab-profil", label: "Profil").tap()
        require("La liste du profil est affichée") { self.containerVisible(self.element("profile-list")) }
        tap("profil-contrats")
        require("La liste des contrats est affichée") { self.containerVisible(self.element("contrats-liste")) }
    }

    private func openCarte(_ id: String, in liste: XCUIElement) {
        let carte = element("contrat-carte-\(id)")
        require("La carte \(id) est chargée") { carte.exists }
        if !visible(carte) { scrollTo(carte, in: liste) }
        tap("contrat-carte-\(id)")
        require("L'écran du contrat \(id) est affiché") { self.containerVisible(self.element("contrat-screen")) }
    }

    /// Bouton retour de la barre de navigation (premier bouton de la barre affichée).
    private func goBack() {
        let retour = app.navigationBars.buttons.element(boundBy: 0)
        require("Le bouton retour est atteignable") { self.visible(retour) }
        retour.tap()
    }

    /// Sentinelle « 0 requête » du profil (DEBUG), atteinte par glissements bornés dans la liste.
    private func assertNoNetworkRequest() {
        let list = element("profile-list")
        require("Le profil est de retour") { self.containerVisible(list) }
        let sentinel = element("network-sentinel")
        var glissements = 0
        while !sentinel.exists && glissements < 4 {
            drag(list, fromY: 0.8, toY: 0.4)
            glissements += 1
        }
        require("La sentinelle réseau est exposée") { sentinel.exists }
        XCTAssertEqual(sentinel.label, "0 requête", "Aucune requête réseau en démonstration")
    }
}
