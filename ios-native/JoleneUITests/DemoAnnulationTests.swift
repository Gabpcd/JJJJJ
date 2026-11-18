import XCTest

/// Annulation d'une participation en démo (lot 1, T7) : Mes missions › À venir → détail d'une mission assignée →
/// « Annuler ma participation ». Aucune requête réseau.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - mission attribuée sans candidature (`demo-assignee-001`) : confirmation simple, sans message de pénalité (barème
///   client non porté, décision 4), puis « Participation annulée. Ton score sera mis à jour. » (verbatim web, HARD STOP
///   n°4) après la relecture, et le bouton disparaît ;
/// - candidature retenue (`demo-assignee-003`) : modale de candidature, textes du web verbatim (avertissement sur les
///   données de santé, case des conséquences, notification de l'établissement), bouton inactif tant que motif,
///   explication de 20 caractères et case ne sont pas remplis, justificatif choisi (sélecteur démo, PNG fictif) puis
///   « Candidature annulée. » après la relecture, modale refermée.
/// Le reçu durable (journalisé avant le dépôt, 403 → `not_sent`, dépôt incertain réconcilié par HEAD, reprise sans second
/// dépôt, journal illisible bloquant) est prouvé au niveau 1 (`AnnulationModelTests`, `RecuJustificatifTests`,
/// `SupabaseJustificatifStorageTests`) ; la photothèque et Fichiers réels relèvent de l'appareil (niveau 5).
///
/// Formats : iPhone, iPad portrait, iPad paysage ; chaque contrôle est amené à l'écran par un défilement borné
/// (`scrollTo`) avant d'être touché (PRINCIPES §6). Classe non rangée dans un éclat existant : la PR d'intégration de la
/// vague B du lot 1 crée l'éclat `lot1-missions` qui la reçoit (d'ici là, l'éclat socle la lance par défaut).
final class DemoAnnulationTests: JoleneUITestCase {
    static let participationAnnulee = "Participation annulée. Ton score sera mis à jour."
    static let candidatureAnnulee = "Candidature annulée."
    static let avertissementSante = "N'envoyez aucun certificat médical ni document mentionnant un diagnostic ou une information de santé. Vous pouvez joindre uniquement une preuve non médicale, par exemple un billet de transport annulé ou une attestation employeur ne contenant aucune donnée de santé."
    static let consequences = "J'ai compris les conséquences (impact score le cas échéant) et je confirme l'annulation de ma candidature."
    static let notification = "L'établissement sera notifié immédiatement. Si la pénalité vous semble injuste, vous pourrez la contester depuis votre page score."
    private let explication = "Train supprimé ce matin, aucun autre trajet possible."

    func testAnnulationSansCandidatureConfirmeeEtRelue() throws {
        launchDemo()
        signInDemo()
        let detail = ouvrirMission("demo-assignee-001")
        let ouvrir = element("annulation-ouvrir")
        scrollTo(ouvrir, in: detail)
        XCTAssertEqual(ouvrir.label, "Annuler ma participation", "libellé du web (l.1521)")
        ouvrir.tap()

        let oui = element("annulation-mission-oui")
        scrollTo(oui, in: detail)
        XCTAssertEqual(element("annulation-mission-confirmation-titre").label, "⚠️ Annuler votre participation ?")
        XCTAssertEqual(oui.label, "Oui, annuler")
        XCTAssertEqual(element("annulation-mission-non").label, "Non, garder")
        XCTAssertFalse(textContaining("points sur ton score").exists, "aucun barème de pénalité côté client")
        record("\(proofPrefix)-annulation-confirmation")
        oui.tap()

        let succes = element("annulation-succes")
        require("L'annulation relue est annoncée", timeout: 30) { succes.exists }
        XCTAssertTrue(succes.label.hasSuffix(Self.participationAnnulee), "texte verbatim du web : \(succes.label)")
        XCTAssertFalse(element("annulation-ouvrir").exists, "plus de bouton après l'annulation")
        XCTAssertFalse(element("annulation-mission-oui").exists)
        record("\(proofPrefix)-annulation-mission-annulee")
    }

    func testAnnulationCandidatureAvecJustificatifRelue() throws {
        launchDemo()
        signInDemo()
        let detail = ouvrirMission("demo-assignee-003")
        let ouvrir = element("annulation-ouvrir")
        scrollTo(ouvrir, in: detail)
        ouvrir.tap()

        let feuille = element("annulation-sheet")
        let titre = element("annulation-sheet-titre")
        require("La modale d'annulation est ouverte") { self.visible(titre) }
        XCTAssertEqual(titre.label, "Annuler votre candidature")
        let confirmer = element("annulation-confirmer")
        XCTAssertFalse(confirmer.isEnabled, "inactif tant que le formulaire est incomplet")
        record("\(proofPrefix)-annulation-modale")

        let motif = element("annulation-motif-PROBLEME_TRANSPORT")
        scrollTo(motif, in: feuille)
        XCTAssertEqual(motif.label, "🚗 Problème de transport")
        motif.tap()
        require("Le motif est sélectionné") { motif.isSelected }

        let champ = element("annulation-texte")
        scrollTo(champ, in: feuille)
        focus(champ, in: feuille)
        champ.typeText(explication)
        fermerLePaveNumerique()
        let compteur = element("annulation-texte-compteur")
        require("Le compteur suit la saisie") { compteur.label == "\(self.explication.utf16.count) / 20+" }

        let fichiers = element("annulation-justificatif-fichiers")
        scrollTo(fichiers, in: feuille)
        fichiers.tap()
        let choisi = element("annulation-justificatif-choisi")
        require("Le justificatif démo est choisi") { choisi.exists }
        XCTAssertEqual(choisi.label, "justificatif-demo.png")
        let avertissement = element("annulation-avertissement-sante")
        scrollTo(avertissement, in: feuille)
        XCTAssertEqual(avertissement.label, Self.avertissementSante, "HARD STOP n°4 : verbatim du web (l.220)")

        let coche = element("annulation-confirmation")
        scrollTo(coche, in: feuille)
        XCTAssertTrue(coche.label.contains(Self.consequences), "HARD STOP n°4 : verbatim du web (l.234) : \(coche.label)")
        XCTAssertFalse(confirmer.isEnabled, "la case n'est pas encore cochée")
        coche.tap()
        require("La case est cochée") { coche.isSelected }
        let notification = element("annulation-notification-etablissement")
        scrollTo(notification, in: feuille)
        XCTAssertTrue(notification.label.hasSuffix(Self.notification), "verbatim du web (l.240) : \(notification.label)")

        scrollTo(confirmer, in: feuille)
        require("La confirmation est active") { confirmer.isEnabled }
        XCTAssertEqual(confirmer.label, "Confirmer l'annulation")
        record("\(proofPrefix)-annulation-modale-remplie")
        confirmer.tap()

        let succes = element("annulation-succes")
        require("L'annulation relue est annoncée, modale refermée", timeout: 30) { succes.exists && !titre.exists }
        XCTAssertTrue(succes.label.hasSuffix(Self.candidatureAnnulee), "0 point serveur : \(succes.label)")
        XCTAssertFalse(element("annulation-ouvrir").exists, "plus de bouton après l'annulation")
        record("\(proofPrefix)-annulation-candidature-annulee")
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
        toucherSeConnecter(submit, "La session est prête : la barre d'onglets est affichée") { self.tabBarExists }
    }

    /// Mes missions › À venir → détail de la mission ; rend le conteneur du détail.
    private func ouvrirMission(_ id: String) -> XCUIElement {
        tabButton("tab-missions", label: "Mes missions").tap()
        let scroll = element("mes-missions-scroll")
        let ligne = element("mes-mission-\(id)")
        require("Mes missions affiche ses missions à venir", timeout: 30) {
            self.containerVisible(self.element("mes-missions-screen")) && ligne.exists
                && !self.element("mes-missions-loading").exists
        }
        scrollTo(ligne, in: scroll)
        ligne.tap()
        let detail = element("mission-detail")
        require("Le détail de la mission est rendu", timeout: 30) {
            self.containerVisible(detail) && self.element("mission-detail-title").exists
        }
        return detail
    }
}
