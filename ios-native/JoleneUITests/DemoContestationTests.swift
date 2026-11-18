import XCTest

/// Contestation d'une présence validée (lot 2, T5b, HARD STOP n°4) en démo, sur iPhone, iPad portrait et iPad paysage :
/// onglet Aujourd'hui › « Présences validées récemment » › « Contester cette présence » › motif › « Envoyer la
/// contestation » → statut « Ouvert » relu (`DemoContestationGateway`, fenêtre ouverte, aucun litige au lancement).
/// Aucun texte de délai n'est affiché, ni dans la feuille, ni après l'envoi (Q9, D12). Règles affirmées dans JoleneCore
/// (`ContestationModelTests`) et JoleneSupabase (`SupabaseContestationGatewayTests`). Vérifié par la CI seulement.
final class DemoContestationTests: DemoPointageUITestCase {
    private static let presence = "demo-presence-h1-presence"
    /// Textes de délai du panneau web, jamais repris (`ANCRES_Q9`).
    private static let textesDeDelai = ["72", "pour répondre", "tranchera", "pour contester", "délai"]

    func testContesterLaPresenceValideeAfficheLeStatutOuvertSansTexteDeDelai() throws {
        launchDemo()
        connexionDemo()
        let ecran = ouvrirMesPresences()

        let ouvrir = element("contestation-ouvrir-\(Self.presence)")
        require("« Contester cette présence » est proposé (fenêtre ouverte selon le serveur démo)", timeout: 30) { ouvrir.exists }
        scrollTo(ouvrir, in: ecran)
        XCTAssertEqual(ouvrir.label, "Contester cette présence", "libellé du web")
        XCTAssertFalse(element("contestation-statut-\(Self.presence)").exists, "aucun litige au lancement")
        tap("contestation-ouvrir-\(Self.presence)")

        let feuille = element("contestation-sheet")
        require("La feuille de contestation est ouverte") { self.containerVisible(feuille) }
        let envoyer = element("contestation-envoyer")
        require("« Envoyer la contestation » est rendu") { envoyer.exists }
        XCTAssertEqual(envoyer.label, "Envoyer la contestation")
        XCTAssertFalse(envoyer.isEnabled, "sans motif : envoi impossible")
        verifierAucunTexteDeDelai(dans: feuille)
        let motif = element("contestation-motif")
        focus(motif, in: feuille)
        motif.typeText("Les heures validées ne correspondent pas à ma présence réelle.")
        fermerLePaveNumerique()
        require("Un motif saisi active l'envoi") { envoyer.isEnabled }
        record("\(proofPrefix)-contestation-motif")
        tap("contestation-envoyer")

        let statut = element("contestation-statut-\(Self.presence)")
        require("Le statut relu « Ouvert » est affiché", timeout: 30) { statut.exists && statut.label == "Ouvert" }
        require("La feuille est fermée") { !self.element("contestation-sheet").exists }
        XCTAssertFalse(element("contestation-ouvrir-\(Self.presence)").exists, "litige relu : plus de bouton")
        XCTAssertFalse(element("contestation-erreur").exists)
        verifierAucunTexteDeDelai(dans: element("presence-validee-\(Self.presence)"))
        record("\(proofPrefix)-contestation-ouverte")
    }

    /// Aucun texte de délai dans le conteneur (la feuille, puis la ligne de la présence contestée).
    private func verifierAucunTexteDeDelai(dans conteneur: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for texte in Self.textesDeDelai {
            let trouve = conteneur.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", texte)).firstMatch
            XCTAssertFalse(trouve.exists, "texte de délai affiché (Q9) : « \(texte) »", file: file, line: line)
        }
    }
}
