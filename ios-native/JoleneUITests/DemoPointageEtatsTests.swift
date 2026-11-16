import XCTest

/// États d'erreur, reprise et coupe-circuit du pointage démo (lot 2, T4b ; seconde revue fraîche de T4b, m1 à m3 ;
/// CLAUDE.md « Recette frontend systématique » : les correctifs M1 et m4 de la première revue n'avaient qu'une preuve
/// unitaire) sur iPhone, iPad portrait et iPad paysage. Mêmes étapes et même monde que `DemoPointageTests`
/// (`DemoPointageUITestCase`). Scénarios DEBUG de `-JOLENE_DEMO_SCENARIO` (`DemoPointageGateway.Scenario`, installés par
/// `AppContainer` avec une authentification démo liée, `DemoPointageGateway.Scenario.installer(dans:)`) :
/// - `session-expiree-scan` : le premier scan est appliqué, puis sa réponse est un 401 ; tout appel du pointage répond 401
///   jusqu'à « Vérifier ma session » (`restoreSession` revalide la session démo) — preuve de M1 : bloc « Session à
///   vérifier » dans la zone, puis réconciliation du reçu gardé, sans renvoi ;
/// - `consentement-echec` : le premier `fn_consentir_gps` échoue (service indisponible), le suivant aboutit — preuve de m4 :
///   l'échec s'affiche dans la zone qui a ouvert la feuille, rien n'est envoyé, la feuille revient au pointage suivant ;
/// - `session-expiree-consentement` : la première lecture du consentement répond 401, puis 401 jusqu'à la revalidation —
///   preuve de m1 (seconde revue) : la ligne du Profil montre « Session à vérifier » et non un « Réessayer » inopérant.
/// Coupe-circuit D-FLAGS (m3) : `-JOLENE_FLAG_ios_natif_presences_actif false` (`DemoFlagsGateway.surcharges`) → la page
/// Présences devient un renvoi web, sans zone de pointage ; « Voir sur jolene.app » y présente la page web (présentateur
/// `.safari` du coordinateur des liens, injecté depuis la fusion du lot 3).
///
/// Identifiants : `pointage-session-expired-<m>`, `pointage-session-check-<m>`, `pointage-consentement-echec-<m>`,
/// `gps-consent-retour`, `profil-gps-session-expired`, `profil-gps-session-check`, `profil-gps-consentement`,
/// `presences-desactive-renvoi`, `presences-desactive-web`, `pointage-demo-scans`, `pointage-demo-relire`.
final class DemoPointageEtatsTests: DemoPointageUITestCase {
    private static let sessionExpiree = "Votre session a expiré. Reconnectez-vous."
    /// `SessionController.timeoutMessage`, message de la panne simulée de `fn_consentir_gps`.
    private static let serviceIndisponible = "Le service ne répond pas. Vérifiez votre connexion puis réessayez."

    // MARK: - Session expirée au scan (M1 de la première revue)

    func testSessionExpireeAuScanVerifierMaSessionReconcilieSansRenvoi() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_SCENARIO", "session-expiree-scan"])
        connexionDemo()
        let ecran = ouvrirMesPresences()
        saisir("123456", mission: Self.missionA, dans: ecran)
        appuyerSurPointer(Self.missionA, dans: ecran)
        accepterConsentement()

        let bloc = element("pointage-session-expired-\(Self.missionA)")
        require("401 au scan : bloc « Session à vérifier » du lot 1 dans la zone", timeout: 30) {
            bloc.exists && bloc.label.contains("Session à vérifier") && bloc.label.contains(Self.sessionExpiree)
        }
        XCTAssertFalse(element("pointage-submit-\(Self.missionA)").exists, "aucun bouton de pointage tant que la session est à vérifier")
        XCTAssertFalse(element("pointage-message-\(Self.missionA)").exists, "jamais « Vérification du pointage… » sans fin")
        XCTAssertFalse(element("pointage-reessayer-\(Self.missionA)").exists, "jamais un « Réessayer » inopérant")
        XCTAssertEqual(compteursRelus(dans: ecran), "1 scan · 1 avec position", "scan appliqué une fois avant le 401 (relu)")
        record("\(proofPrefix)-pointage-session-expiree")

        let verifier = element("pointage-session-check-\(Self.missionA)")
        require("« Vérifier ma session » est proposé") { verifier.exists && verifier.label == "Vérifier ma session" }
        scrollTo(verifier, in: ecran)
        tap("pointage-session-check-\(Self.missionA)")
        require("Session revalidée : le reçu gardé est réconcilié par relecture", timeout: 30) {
            self.libelle("pointage-message-\(Self.missionA)").contains(Self.segmentOuvert)
        }
        XCTAssertFalse(element("pointage-session-expired-\(Self.missionA)").exists)
        XCTAssertTrue(element("pointage-segment-\(Self.missionA)-1").exists)
        XCTAssertFalse(element("pointage-segment-\(Self.missionA)-2").exists, "un seul segment créé")
        XCTAssertEqual(compteursRelus(dans: ecran), "1 scan · 1 avec position", "jamais de renvoi du code (relu après la reprise)")
        record("\(proofPrefix)-pointage-session-reprise")
    }

    // MARK: - Échec de l'enregistrement du consentement (m4 de la première revue)

    func testEchecDuConsentementAfficheDansLaZoneRienNEstEnvoyePuisLaFeuilleRevient() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_SCENARIO", "consentement-echec"])
        connexionDemo()
        let ecran = ouvrirMesPresences()
        saisir("123456", mission: Self.missionA, dans: ecran)
        appuyerSurPointer(Self.missionA, dans: ecran)
        accepterConsentement()

        require("Échec de l'enregistrement affiché dans la zone qui a ouvert la feuille", timeout: 30) {
            self.libelle("pointage-consentement-echec-\(Self.missionA)").contains(Self.serviceIndisponible)
        }
        XCTAssertTrue(libelle("gps-consent-retour").contains(Self.serviceIndisponible), "et en tête de page (retour du consentement)")
        XCTAssertFalse(element("pointage-message-\(Self.missionA)").exists, "aucune hypothèse locale : rien n'est envoyé")
        XCTAssertFalse(element("bandeau-sans-gps").exists, "un échec n'est pas un refus")
        XCTAssertEqual(valeur("pointage-code-\(Self.missionA)"), "123456", "le code saisi reste dans le champ")
        XCTAssertEqual(compteursRelus(dans: ecran), "0 scan · 0 avec position", "aucun scan après l'échec (relu)")
        record("\(proofPrefix)-pointage-consentement-echec")

        // Pointage suivant : le retour d'échec est levé, la feuille revient (consentement toujours NULL), puis le
        // consentement aboutit et le pointage part une seule fois.
        appuyerSurPointer(Self.missionA, dans: ecran)
        require("La feuille de consentement revient au pointage suivant", timeout: 30) { self.element("gps-consent-sheet").exists }
        XCTAssertFalse(element("pointage-consentement-echec-\(Self.missionA)").exists, "échec levé au pointage suivant")
        accepterConsentement()
        require("Consentement enregistré, pointage parti", timeout: 30) {
            self.libelle("pointage-message-\(Self.missionA)").contains(Self.segmentOuvert)
        }
        XCTAssertTrue(libelle("gps-consent-retour").contains("Consentement GPS enregistré."))
        XCTAssertEqual(compteursRelus(dans: ecran), "1 scan · 1 avec position", "un seul scan, avec position (relu)")
        record("\(proofPrefix)-pointage-consentement-reprise")
    }

    // MARK: - Session expirée à la lecture du consentement, dans le Profil (m1 de la seconde revue)

    func testSessionExpireeDuConsentementDansLeProfilPuisVerifierMaSession() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_SCENARIO", "session-expiree-consentement"])
        connexionDemo()
        ouvrirProfil()
        let liste = element("profile-list")
        let bloc = element("profil-gps-session-expired")
        amenerDansLeProfil(bloc, etats: ["profil-gps-chargement", "profil-gps-session-expired", "profil-gps-erreur",
                                         "profil-gps-consentement"])
        require("401 à la lecture : « Session à vérifier », jamais « Réessayer »", timeout: 30) {
            bloc.exists && bloc.label.contains("Session à vérifier") && bloc.label.contains(Self.sessionExpiree)
        }
        XCTAssertFalse(element("profil-gps-reessayer").exists, "un « Réessayer » ne réparerait rien")
        XCTAssertFalse(element("profil-gps-consentement").exists, "aucun interrupteur sans valeur relue")
        XCTAssertFalse(element("profil-gps-retour").exists, "aucun doublon du message sous la ligne")
        record("\(proofPrefix)-profil-gps-session-expiree")

        let verifier = element("profil-gps-session-check")
        if !visible(verifier) { scrollTo(verifier, in: liste) }
        XCTAssertEqual(verifier.label, "Vérifier ma session")
        tap("profil-gps-session-check")
        let interrupteur = element("profil-gps-consentement")
        require("Session revalidée : consentement relu, interrupteur rendu", timeout: 30) {
            interrupteur.exists && !self.element("profil-gps-session-expired").exists
        }
        XCTAssertEqual(interrupteur.value as? String, "0", "NULL relu, affiché éteint (D-T4b-1)")
        record("\(proofPrefix)-profil-gps-session-reprise")
    }

    // MARK: - Coupe-circuit D-FLAGS (m3 de la seconde revue)

    func testDrapeauPresencesDesactiveRenvoieLaPageAuWebSansZoneDePointage() throws {
        launchDemo(extraArguments: ["-JOLENE_FLAG_ios_natif_presences_actif", "false"])
        connexionDemo()
        ouvrirProfil()
        tapDansProfil("profil-presences")
        let renvoi = element("presences-desactive-renvoi")
        require("Drapeau à faux : la page Présences devient un renvoi web", timeout: 30) {
            renvoi.exists && renvoi.label.contains("Cet espace n'est pas encore disponible dans l'application. Rendez-vous sur jolene.app.")
        }
        XCTAssertTrue(containerVisible(element("presences-screen")))
        XCTAssertFalse(element("presences-tab-aujourdhui").exists, "aucun onglet natif")
        XCTAssertFalse(element("pointage-zone-\(Self.missionA)").exists, "aucune zone de pointage")
        XCTAssertFalse(element("pointage-code-\(Self.missionA)").exists)
        XCTAssertFalse(element("pointage-demo-scans").exists, "la page native n'est pas montée")
        record("\(proofPrefix)-presences-coupe-circuit")
        // Fusion des lots 2 et 3 : le présentateur `.safari` du coordinateur des liens (L3-T3b) est injecté, le bouton du
        // renvoi est donc rendu et il a son effet — la page web des présences est présentée (double démo, aucune requête
        // réseau), puis « Fermer » rend le renvoi (jamais un bouton sans effet).
        let web = element("presences-desactive-web")
        require("Le renvoi propose « Voir sur jolene.app »") { web.exists }
        XCTAssertEqual(web.label, "Voir sur jolene.app")
        tap("presences-desactive-web")
        liensRenvoiWebAffiche("https://jolene.app/soignant/presences")
        liensFermerRenvoiWeb()
        require("Le renvoi de la page Présences est de retour") { renvoi.exists }
    }
}
