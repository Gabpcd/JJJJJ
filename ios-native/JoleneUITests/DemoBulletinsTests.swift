import XCTest

/// Copies officielles des bulletins (L4-T10) en démonstration, sur iPhone, iPad portrait et iPad paysage : Revenus →
/// « Paie » (`revenus-bulletins-web`) ouvre l'écran natif (fixtures `demo-copies-bulletins.json` et `demo-copie.pdf`) ;
/// mention verbatim de l'employeur ; ouverture de la bonne copie dans le lecteur PDF (partage disponible) ; refus
/// d'intégrité de la copie au SHA-256 faux (aucun PDF affiché) ; copie retirée sans bouton d'ouverture ; signalement
/// `CONTENU` relu ; signalement `DESTINATAIRE` : avertissement verbatim avant confirmation, puis copie relue retirée et
/// bouton d'ouverture absent ; simulations de paie en renvoi web. Aucune requête réseau (sentinelle).
///
/// Les règles (vérification type / taille / SHA-256, 410, relecture qui confirme) sont prouvées par `BulletinsModelTests`
/// (JoleneCore) et `SupabaseBulletinsGatewayTests` (transport).
final class DemoBulletinsTests: JoleneUITestCase {
    private enum Copies {
        static let valide = "c0b1e000-0000-4000-8000-000000000001"
        static let remplacee = "c0b1e000-0000-4000-8000-000000000002"
        static let falsifiee = "c0b1e000-0000-4000-8000-000000000003"
        static let retiree = "c0b1e000-0000-4000-8000-000000000004"
    }

    private enum Textes {
        // TextesWeb.CopiesBulletins (CopiesBulletins.tsx l.44, CopiesBulletinsListe.tsx l.90), verbatim.
        static let mention = "Retrouvez les PDF déposés par l’employeur, déjà remis par son service paie. Une copie disponible ne confirme pas le paiement du salaire."
        static let avertissement = "La copie sera immédiatement retirée et son PDF ne sera plus accessible dans Jolene."
        static let integrite = "L’intégrité du PDF ne peut pas être confirmée. Réessayez."
        static let signalementEnregistre = "Le signalement est enregistré. L’établissement peut le consulter."
        static let copieRetiree = "La copie a été retirée. Son PDF n’est plus accessible dans Jolene."
    }

    func testOuvertureVerifieeRefusDIntegriteEtCopieRetiree() throws {
        launchDemo()
        connexionDemo()
        let ecran = ouvrirBulletins()
        XCTAssertEqual(element("bulletins-mention").label, Textes.mention, "mention de l'employeur verbatim (HARD STOP n°4)")
        XCTAssertEqual(elements(withPrefix: "copie-statut-").count, 4, "les quatre copies de la fixture")
        XCTAssertTrue(element("bulletins-employeur").exists, "deux employeurs : filtre affiché")
        record("\(proofPrefix)-bulletins-liste")

        // Copie retirée : aucun bouton d'ouverture ni de signalement.
        let retiree = element("copie-retiree-\(Copies.retiree)")
        scrollTo(retiree, in: ecran)
        require("La copie retirée l'annonce") { retiree.exists }
        XCTAssertFalse(element("copie-ouvrir-\(Copies.retiree)").exists, "RETIREE : pas de bouton d'ouverture")
        XCTAssertFalse(element("copie-signaler-\(Copies.retiree)").exists)

        // Copie au SHA-256 faux : refus d'intégrité, rien n'est affiché.
        let falsifiee = element("copie-ouvrir-\(Copies.falsifiee)")
        scrollTo(falsifiee, in: ecran, downward: false)
        falsifiee.tap()
        require("Le refus d'intégrité est affiché") { self.element("copie-integrite-erreur").exists }
        XCTAssertTrue(element("copie-integrite-erreur").label.contains(Textes.integrite), element("copie-integrite-erreur").label)
        XCTAssertFalse(element("pdf-lecteur").exists, "empreinte fausse : aucun PDF présenté")
        record("\(proofPrefix)-bulletins-integrite")

        // Bonne copie : lecteur PDF et partage.
        let ouvrir = element("copie-ouvrir-\(Copies.valide)")
        scrollTo(ouvrir, in: ecran, downward: false)
        ouvrir.tap()
        require("Le lecteur affiche le PDF vérifié", timeout: 30) { self.element("pdf-lecteur").exists }
        XCTAssertTrue(element("pdf-partager").exists && element("pdf-partager").isEnabled, "partage disponible")
        record("\(proofPrefix)-bulletins-lecteur")
        tap("pdf-fermer")
        require("Le lecteur est fermé") { !self.element("pdf-lecteur").exists && self.element("bulletins-screen").exists }

        // Simulations de paie : renvoi web (D12).
        let simulations = element("bulletins-simulations-web")
        scrollTo(simulations, in: ecran)
        simulations.tap()
        liensRenvoiWebAffiche("https://jolene.app/soignant/mes-gains?tab=bulletins")
        liensFermerRenvoiWeb()
        verifierAucuneRequete()
    }

    func testSignalementContenuPuisDestinataireRetireLaCopie() throws {
        launchDemo()
        connexionDemo()
        let ecran = ouvrirBulletins()

        // CONTENU : signalement relu, la copie reste ouvrable.
        signaler(Copies.valide, motif: "CONTENU", dans: ecran)
        require("Le signalement est confirmé par relecture") {
            self.element("bulletins-confirmation").exists && self.element("copie-signalee-\(Copies.valide)").exists
        }
        XCTAssertTrue(element("bulletins-confirmation").label.contains(Textes.signalementEnregistre))
        XCTAssertTrue(element("copie-ouvrir-\(Copies.valide)").exists, "CONTENU ne retire pas la copie")
        record("\(proofPrefix)-bulletins-signalement-contenu")

        // DESTINATAIRE : avertissement verbatim avant confirmation, puis copie relue retirée.
        let bouton = element("copie-signaler-\(Copies.remplacee)")
        scrollTo(bouton, in: ecran)
        bouton.tap()
        require("La feuille de signalement est ouverte") { self.element("copie-motif-DESTINATAIRE").exists }
        XCTAssertFalse(element("copie-avertissement-retrait").exists, "motif par défaut CONTENU : pas d'avertissement")
        tap("copie-motif-DESTINATAIRE")
        require("L'avertissement de retrait est affiché avant la confirmation") { self.element("copie-avertissement-retrait").exists }
        XCTAssertEqual(element("copie-avertissement-retrait").label, Textes.avertissement, "avertissement verbatim (HARD STOP n°4)")
        record("\(proofPrefix)-bulletins-avertissement-retrait")
        tap("copie-signalement-envoyer")
        require("La copie est relue retirée", timeout: 30) {
            !self.element("copie-signalement").exists && self.element("copie-retiree-\(Copies.remplacee)").exists
        }
        XCTAssertTrue(element("bulletins-confirmation").label.contains(Textes.copieRetiree))
        XCTAssertFalse(element("copie-ouvrir-\(Copies.remplacee)").exists, "copie retirée : bouton d'ouverture absent")
        record("\(proofPrefix)-bulletins-signalement-destinataire")
        verifierAucuneRequete()
    }

    // MARK: Étapes

    private func ouvrirBulletins() -> XCUIElement {
        tabButton("tab-revenus", label: "Revenus").tap()
        let revenus = element("revenus-screen")
        require("L'onglet Revenus est affiché", timeout: 30) { self.containerVisible(revenus) }
        let paie = element("revenus-bulletins-web")
        require("« Paie » est atteignable") { self.visible(paie) }
        paie.tap()
        let ecran = defilement("bulletins-screen")
        require("Les copies sont relues", timeout: 30) {
            self.containerVisible(ecran) && self.element("copie-\(Copies.valide)").exists
        }
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (T10) : jamais un renvoi web")
        return ecran
    }

    private func signaler(_ copie: String, motif: String, dans ecran: XCUIElement) {
        let bouton = element("copie-signaler-\(copie)")
        scrollTo(bouton, in: ecran)
        bouton.tap()
        require("La feuille de signalement est ouverte") { self.element("copie-motif-\(motif)").exists }
        tap("copie-motif-\(motif)")
        tap("copie-signalement-envoyer")
        require("La feuille se referme après relecture", timeout: 30) { !self.element("copie-signalement").exists }
    }

    private func defilement(_ identifier: String) -> XCUIElement {
        let typee = app.scrollViews.matching(identifier: identifier).firstMatch
        return typee.exists ? typee : element(identifier)
    }

    /// Profil remis à sa racine (l'écran des copies y est empilé), puis sentinelle réseau.
    private func verifierAucuneRequete() {
        tabButton("tab-profil", label: "Profil").tap()
        if element("bulletins-screen").exists {
            let back = app.navigationBars.buttons.firstMatch
            require("Le bouton retour est disponible") { self.visible(back) }
            back.tap()
            require("L'écran des copies est retiré") { !self.element("bulletins-screen").exists }
        }
        let liste = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(liste) }
        let sentinelle = element("network-sentinel")
        scrollTo(sentinelle, in: liste, downward: false)
        require("La sentinelle réseau est exposée") { sentinelle.exists }
        XCTAssertEqual(sentinelle.label, "0 requête", "les copies des bulletins n'émettent aucune requête en démonstration")
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
