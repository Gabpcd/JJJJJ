import XCTest

/// Pool urgence et exclusions (L4-T11) en démonstration, sur iPhone, iPad portrait et iPad paysage :
/// - lien `/soignant/pool-urgence` → écran natif (fixture `demo-pool-urgence.json` : pool inactif, rayon 30 km) ;
///   activer → rayon 15 km relu (la mission à 22 km sort du pool) ; texte d'engagement et SMS verbatim affichés ;
/// - « J'accepte » → récapitulatif du planning exact → « Confirmer mon acceptation urgente » → statut « En attente de
///   validation étab » relu ; la mission au contrat `TOUS` demande un choix : message et bouton vers le détail ;
/// - détail d'une mission démo → « Ne plus travailler ensemble » → confirmation → Profil › « Établissements exclus » :
///   ligne `exclusion-envoyee-<établissement>` puis retrait après confirmation.
/// Aucune requête réseau (sentinelle). Les règles sont prouvées par `PoolUrgenceModelTests` (JoleneCore) ; le transport
/// par `SupabasePoolUrgenceGatewayTests`, `SupabaseCandidatureUrgenceTests` et `SupabaseExclusionsGatewayTests`.
final class DemoPoolUrgenceTests: JoleneUITestCase {
    private enum Attendus {
        static let proche = "demo-mission-001"
        static let tous = "demo-mission-urgence-tous"
        static let lointaine = "demo-mission-021"
        static let missionDetail = "demo-mission-002"
        static let etablissementDetail = "demo-etab-2"
    }

    func testActiverRayonPuisAccepterEtChoixDeContrat() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/soignant/pool-urgence"])
        connexionDemo()
        let ecran = defilement("pool-screen")
        require("Le pool urgence natif est affiché", timeout: 30) {
            self.containerVisible(ecran) && self.element("pool-toggle").exists
        }
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (T11) : jamais un renvoi web")
        require("Pool inactif à l'ouverture") { self.element("pool-inactif").exists }

        tap("pool-toggle")
        require("L'activation est confirmée par relecture") {
            self.element("pool-confirmation").exists && self.element("pool-rayon").exists
        }
        XCTAssertTrue(element("pool-confirmation").label.contains("Pool urgence activé !"))
        XCTAssertTrue(element("pool-mission-\(Attendus.lointaine)").exists, "rayon 30 km : mission à 22 km servie")
        let consentement = element("pool-consentement")
        scrollTo(consentement, in: ecran)
        XCTAssertTrue(consentement.label.hasPrefix("En activant le pool d'urgence, tu acceptes d'être contacté(e)"), consentement.label)
        XCTAssertTrue(consentement.label.hasSuffix("te rapporte +10 points de fiabilité."), consentement.label)
        XCTAssertTrue(element("pool-sms").exists)
        record("\(proofPrefix)-pool-actif")

        // Rayon 15 km : envoyé à la fin du geste, puis relu.
        let curseur = app.sliders["pool-rayon"]
        scrollTo(curseur, in: ecran, downward: false)
        require("Le curseur du rayon est atteignable") { self.visible(curseur) }
        curseur.adjust(toNormalizedSliderPosition: CGFloat(15 - 5) / CGFloat(50 - 5))
        require("Le rayon 15 km est relu", timeout: 20) {
            self.element("pool-rayon-valeur").label.contains("15 km")
                && !self.element("pool-mission-\(Attendus.lointaine)").exists
        }
        record("\(proofPrefix)-pool-rayon")

        // Acceptation rapide : récapitulatif du planning exact, statut relu.
        let accepter = element("pool-accepter-\(Attendus.proche)")
        scrollTo(accepter, in: ecran)
        require("« J'accepte » est disponible (planning exact)") { accepter.isEnabled }
        accepter.tap()
        require("Le récapitulatif est affiché") {
            self.containerVisible(self.element("pool-recap")) && self.element("pool-recap-confirm").exists
        }
        XCTAssertEqual(element("pool-recap-confirm").label, "Confirmer mon acceptation urgente")
        tap("pool-recap-confirm")
        let statut = element("pool-statut-\(Attendus.proche)")
        require("Statut relu après l'acceptation", timeout: 20) { !self.element("pool-recap").exists && statut.exists }
        XCTAssertEqual(statut.label, "En attente de validation étab")
        XCTAssertFalse(element("pool-accepter-\(Attendus.proche)").exists, "aucune seconde acceptation")
        record("\(proofPrefix)-pool-acceptee")

        // Contrat à choisir : jamais rejoué ici, renvoi au détail de la mission.
        let accepterTous = element("pool-accepter-\(Attendus.tous)")
        scrollTo(accepterTous, in: ecran)
        accepterTous.tap()
        require("Le récapitulatif est affiché") { self.element("pool-recap-confirm").exists }
        tap("pool-recap-confirm")
        require("Le choix de contrat est demandé, avec le lien vers le détail", timeout: 20) {
            self.element("pool-choix-\(Attendus.tous)").exists && self.element("pool-detail-\(Attendus.tous)").exists
        }
        XCTAssertTrue(element("pool-choix-\(Attendus.tous)").label.contains("Choisissez votre mode de contrat."))
        XCTAssertFalse(element("pool-statut-\(Attendus.tous)").exists, "aucune candidature posée")
        record("\(proofPrefix)-pool-choix-contrat")
        verifierAucuneRequete()
    }

    func testExclureDepuisLeDetailPuisRetirer() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", "https://jolene.app/soignant/missions/\(Attendus.missionDetail)"])
        connexionDemo()
        let detail = defilement("mission-detail")
        require("Le détail de la mission est affiché", timeout: 30) { self.element("mission-detail-title").exists }
        let exclure = element("mission-exclure")
        scrollTo(exclure, in: detail)
        XCTAssertEqual(exclure.label, "🚫 Ne plus travailler ensemble")
        exclure.tap()
        require("La confirmation de l'exclusion est affichée") { self.element("mission-exclusion-confirmer").exists }
        XCTAssertEqual(element("mission-exclusion-titre").label, "🚫 Confirmer l'exclusion")
        XCTAssertEqual(element("mission-exclusion-effet").label,
                       "Les missions de cette partie ne seront plus visibles. Vous pourrez annuler cette exclusion depuis vos paramètres.")
        tap("mission-exclusion-confirmer")
        require("L'exclusion est confirmée par relecture", timeout: 20) {
            !self.element("mission-exclusion").exists && self.element("mission-exclure-confirmation").exists
        }
        XCTAssertTrue(element("mission-exclure-confirmation").label.contains("Exclusion enregistrée."))
        record("\(proofPrefix)-exclusion-creee")

        let ecran = ouvrirExclusions()
        let ligne = element("exclusion-envoyee-\(Attendus.etablissementDetail)")
        require("L'établissement exclu est listé") { ligne.exists }
        record("\(proofPrefix)-exclusions-liste")
        let retirer = element("exclusion-retirer-\(Attendus.etablissementDetail)")
        scrollTo(retirer, in: ecran)
        retirer.tap()
        require("La confirmation du retrait est affichée") { self.element("exclusion-suppression-confirm").exists }
        XCTAssertEqual(element("exclusion-suppression-title").label, "Supprimer cette exclusion ?")
        tap("exclusion-suppression-confirm")
        require("L'exclusion est retirée après relecture", timeout: 20) {
            !self.element("exclusion-suppression").exists && !self.element("exclusion-envoyee-\(Attendus.etablissementDetail)").exists
        }
        XCTAssertTrue(element("exclusions-confirmation").label.contains("Exclusion supprimée."))
        XCTAssertTrue(element("exclusion-envoyee-demo-etab-ancien").exists, "l'exclusion de la fixture reste")
        record("\(proofPrefix)-exclusions-retiree")
        verifierAucuneRequete()
    }

    // MARK: Étapes

    private func ouvrirExclusions() -> XCUIElement {
        tabButton("tab-profil", label: "Profil").tap()
        let liste = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(liste) }
        let entree = element("hub-exclusions")
        scrollTo(entree, in: liste)
        require("L'entrée « Établissements exclus » est atteignable") { self.visible(entree) }
        entree.tap()
        let ecran = defilement("exclusions-screen")
        require("Les exclusions sont relues", timeout: 30) {
            self.containerVisible(ecran) && self.element("exclusions-onglets").exists
        }
        return ecran
    }

    private func defilement(_ identifier: String) -> XCUIElement {
        let typee = app.scrollViews.matching(identifier: identifier).firstMatch
        return typee.exists ? typee : element(identifier)
    }

    /// Profil remis à sa racine, puis sentinelle réseau.
    private func verifierAucuneRequete() {
        tabButton("tab-profil", label: "Profil").tap()
        let liste = element("profile-list")
        for ecran in ["pool-screen", "exclusions-screen"] where element(ecran).exists {
            let back = app.navigationBars.buttons.firstMatch
            require("Le bouton retour est disponible") { self.visible(back) }
            back.tap()
            require("L'écran \(ecran) est retiré") { !self.element(ecran).exists }
        }
        require("La liste du profil est affichée") { self.containerVisible(liste) }
        let sentinelle = element("network-sentinel")
        scrollTo(sentinelle, in: liste, downward: false)
        require("La sentinelle réseau est exposée") { sentinelle.exists }
        XCTAssertEqual(sentinelle.label, "0 requête", "pool urgence et exclusions : aucune requête en démonstration")
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
