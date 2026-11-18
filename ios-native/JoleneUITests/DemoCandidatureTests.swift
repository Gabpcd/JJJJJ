import XCTest

/// Candidature depuis le détail de mission, en démo (lot 1, T6b, `LOT1_PLAN.md` §3 T6b). Aucune requête réseau.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - POSTULER (mission en mode candidature, profil démo `JOLENE_DEMO_PROFIL=candidat`) : récapitulatif du planning →
///   « Envoyer ma candidature » → « ✅ Candidature envoyée — En attente de réponse » après la relecture de la
///   candidature, puis la candidature dans Mes missions › Candidatures ;
/// - ACCEPTER (premier arrivé) : récapitulatif → « Accepter tous ces créneaux » → mission relue ASSIGNEE au profil
///   fictif (« ✅ Vous êtes assigné(e) à cette mission ») ;
/// - profil démo par défaut (sans téléphone, RPPS non vérifié, `demo-profil-complet.json`) : soft-gate avec les deux
///   champs nommés, aucune action de candidature, « Compléter mon profil pour postuler » ouvre le profil natif ;
/// - proposition de l'Accueil (`accueil-proposition-demo-proposition-001`, contrat salarié) relue côté serveur par le
///   détail : l'acceptation passe par jolene.app (attestation hebdomadaire non portée, HARD STOP n°4) — renvoi web
///   présenté, jamais un bouton d'acceptation natif — et le refus est natif, relu « Mission déclinée ».
/// Choix de contrat, planning modifié et refus serveur : niveau 1 (`CandidatureEcranTests`, `DemoCandidatureGatewayTests`,
/// `SupabaseCandidatureGatewayTests`), aucune mission démo ne les déclenche.
///
/// Formats : iPhone, iPad portrait, iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`).
final class DemoCandidatureTests: JoleneUITestCase {
    static let varianteProfil = "JOLENE_DEMO_PROFIL"

    func testPostulerPuisCandidatureDansMesMissions() throws {
        ouvrirMission("demo-mission-014", candidat: true)
        let ecran = element("mission-detail")
        let envoyer = element("candidature-submit")
        scrollTo(envoyer, in: ecran)
        XCTAssertEqual(envoyer.label, "📨 Vérifier et postuler")
        XCTAssertTrue(element("candidature-message").exists, "message optionnel à l'établissement")
        envoyer.tap()
        confirmerRecapitulatif("Envoyer ma candidature")
        let envoyee = element("candidature-sent")
        require("La candidature relue est annoncée envoyée", timeout: 30) { envoyee.exists }
        XCTAssertEqual(envoyee.label, "✅ Candidature envoyée — En attente de réponse")
        XCTAssertFalse(element("candidature-error").exists)
        XCTAssertFalse(element("candidature-submit").exists, "plus d'action après l'envoi relu")
        record("\(proofPrefix)-candidature-envoyee")

        tabButton("tab-missions", label: "Mes missions").tap()
        tap("missions-tab-candidatures")
        require("La candidature de la session est dans Mes missions › Candidatures", timeout: 30) {
            self.element("missions-tab-candidatures").isSelected && self.element("mes-mission-demo-mission-014").exists
        }
    }

    func testAccepterPuisMissionRelueAssignee() throws {
        ouvrirMission("demo-mission-013", candidat: true)
        let ecran = element("mission-detail")
        let accepter = element("candidature-submit")
        scrollTo(accepter, in: ecran)
        XCTAssertEqual(accepter.label, "★ Accepter cette mission")
        XCTAssertFalse(element("candidature-message").exists, "aucun message en premier arrivé")
        accepter.tap()
        confirmerRecapitulatif("Accepter tous ces créneaux")
        let assignee = element("candidature-assignee")
        require("La mission relue est attribuée au profil fictif", timeout: 30) { assignee.exists }
        XCTAssertEqual(assignee.label, "✅ Vous êtes assigné(e) à cette mission")
        XCTAssertFalse(element("candidature-submit").exists)
        XCTAssertFalse(element("candidature-error").exists)
        record("\(proofPrefix)-candidature-acceptee")
    }

    func testProfilIncompletParDefautOuvreLeProfil() throws {
        ouvrirMission("demo-mission-013", candidat: false)
        let ecran = element("mission-detail")
        let gate = element("candidature-profil-incomplet")
        scrollTo(gate, in: ecran)
        for fragment in ["Il manque 2 informations pour pouvoir postuler :", "Téléphone", "RPPS vérifié"] {
            XCTAssertTrue(gate.label.contains(fragment), "« \(fragment) » absent de « \(gate.label) »")
        }
        XCTAssertFalse(element("candidature-submit").exists, "aucune candidature sans profil complet (soft-gate du web)")
        record("\(proofPrefix)-candidature-profil-incomplet")
        let completer = element("candidature-profil-completer")
        scrollTo(completer, in: ecran)
        completer.tap()
        require("Le profil natif est ouvert", timeout: 30) { self.containerVisible(self.element("profil-screen")) }
    }

    func testPropositionDeLAccueilRenvoiWebPuisRefusNatif() throws {
        launchDemo()
        connexion()
        let accueil = element("accueil-screen")
        let carte = element("accueil-proposition-demo-proposition-001")
        require("L'Accueil affiche la proposition démo", timeout: 30) { self.containerVisible(accueil) && carte.exists }
        scrollTo(carte, in: accueil)
        carte.tap()
        let ecran = element("mission-detail")
        let renvoi = element("proposition-web-demo-proposition-001")
        require("Le détail relit la proposition côté serveur", timeout: 30) { self.containerVisible(ecran) && renvoi.exists }
        scrollTo(renvoi, in: ecran)
        XCTAssertFalse(element("proposition-accepter-demo-proposition-001").exists,
                       "proposition salariée : aucune acceptation native tant que l'attestation n'est pas portée")
        record("\(proofPrefix)-proposition-renvoi")
        renvoi.tap()
        liensRenvoiWebAffiche("https://jolene.app/soignant/tableau-de-bord")
        liensFermerRenvoiWeb()

        let refuser = element("proposition-refuser-demo-proposition-001")
        scrollTo(refuser, in: ecran)
        refuser.tap()
        let refusee = element("proposition-refusee")
        require("Le refus relu est annoncé", timeout: 30) { refusee.exists }
        XCTAssertTrue(refusee.label.contains("La proposition a été refusée."), "texte web : \(refusee.label)")
        XCTAssertFalse(element("proposition-refuser-demo-proposition-001").exists, "proposition refusée relue : plus de réponse")
        XCTAssertFalse(element("proposition-web-demo-proposition-001").exists)
        record("\(proofPrefix)-proposition-refusee")
    }

    // MARK: - Étapes

    /// Lien universel simulé vers le détail (`-JOLENE_OPEN_URL`), rejoué après la connexion démo.
    private func ouvrirMission(_ id: String, candidat: Bool) {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/soignant/missions/\(id)"],
                   environment: candidat ? [Self.varianteProfil: "candidat"] : [:])
        connexion()
        require("Le détail natif de la mission est ouvert", timeout: 30) {
            self.containerVisible(self.element("mission-detail")) && self.element("candidature-bloc").exists
                && !self.element("candidature-loading").exists
        }
    }

    private func confirmerRecapitulatif(_ action: String) {
        let confirmer = element("candidature-recap-confirm")
        require("Le récapitulatif du planning est présenté", timeout: 15) { confirmer.exists }
        XCTAssertEqual(element("candidature-recap-title").label, "Vérifiez votre engagement")
        XCTAssertTrue(element("candidature-recap-planning-creneau-1").exists, "planning exact listé")
        XCTAssertEqual(confirmer.label, action)
        scrollTo(confirmer, in: element("candidature-recap"))
        confirmer.tap()
    }

    private func connexion() {
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
        toucherSeConnecter(submit, "La session démo est prête : la barre d'onglets est affichée") { self.tabBarExists }
    }
}
