import XCTest

/// Confirmation de présence J-1 en démo (lot 1, T6c, `LOT1_PLAN.md` §3 T6c, HARD STOP n°4). Aucune requête réseau.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - le lien du push `RAPPEL_MISSION` (`/soignant/missions/demo-presence-j1`, mission ASSIGNEE démarrant dans 20 h)
///   ouvre le détail natif avec le bloc « Confirmez votre présence » ; « ✓ Je confirme ma présence » → confirmation
///   « Présence confirmée — l'établissement est prévenu. ✓ » après relecture, état « ✓ Présence confirmée —
///   l'établissement est prévenu », bouton masqué (second appel impossible) ;
/// - une mission assignée qui démarre dans plus de 48 h (`demo-assignee-001`) n'affiche aucun bloc.
/// Le titre du push serveur (« Ta mission demain — Je serai là ✓ ») n'est pas un texte d'écran : rien ne le cherche.
/// Refus serveur, relecture sans date, bornes de la fenêtre : niveau 1 (`PresenceRulesTests`, `SupabasePresenceGatewayTests`).
final class DemoConfirmationPresenceTests: JoleneUITestCase {
    static let bouton = "✓ Je confirme ma présence"
    static let confirmation = "Présence confirmée — l'établissement est prévenu. ✓"
    static let etat = "✓ Présence confirmée — l'établissement est prévenu"

    func testLienDuRappelConfirmeLaPresencePuisMasqueLeBouton() throws {
        ouvrirMission("demo-presence-j1")
        let ecran = element("mission-detail")
        let bloc = element("presence-bloc")
        require("Le bloc de confirmation est affiché", timeout: 30) { bloc.exists }
        let confirmer = element("presence-confirmer")
        scrollTo(confirmer, in: ecran)
        XCTAssertTrue(bloc.label.contains("Confirmez votre présence") || text("Confirmez votre présence").exists, "titre vouvoyé")
        XCTAssertEqual(confirmer.label, Self.bouton)
        record("\(proofPrefix)-presence-a-confirmer")
        confirmer.tap()

        let notice = element("presence-confirmation")
        let confirmee = element("presence-confirmee")
        require("La présence relue est confirmée", timeout: 30) { notice.exists && confirmee.exists }
        XCTAssertTrue(notice.label.contains(Self.confirmation), "texte web verbatim : \(notice.label)")
        XCTAssertEqual(confirmee.label, Self.etat)
        XCTAssertFalse(element("presence-confirmer").exists, "bouton masqué après relecture : aucun second appel")
        XCTAssertFalse(element("presence-bloc").exists)
        XCTAssertFalse(element("presence-erreur").exists)
        record("\(proofPrefix)-presence-confirmee")
    }

    func testMissionAuDelaDe48HeuresSansBloc() throws {
        ouvrirMission("demo-assignee-001")
        let assignee = element("candidature-assignee")
        require("Le détail de la mission assignée est affiché", timeout: 30) { assignee.exists }
        requireAbsence("Aucun bloc de confirmation au-delà de 48 h") { self.element("presence-bloc").exists }
        XCTAssertFalse(element("presence-confirmee").exists)
    }

    // MARK: - Étapes

    private func ouvrirMission(_ id: String) {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/soignant/missions/\(id)"])
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
        require("Le détail natif de la mission est ouvert", timeout: 30) {
            self.containerVisible(self.element("mission-detail")) && self.element("mission-detail-title").exists
        }
    }
}
