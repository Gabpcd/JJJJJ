import XCTest

/// Pool urgence et exclusions (L4-T11) en démonstration, sur iPhone, iPad portrait et iPad paysage :
/// - lien `/soignant/pool-urgence` → écran natif (fixture `demo-pool-urgence.json` : pool inactif, rayon 30 km) ;
///   activer → rayon réduit entre 9 et 21 km, la valeur atteinte relue exactement (la mission à 22 km sort du pool,
///   celles à 4,2 et 8 km restent) ; texte d'engagement et SMS verbatim affichés ;
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
        /// Rayon accepté après le geste : au-dessus de 8 km (`tous`), au-dessous de 22 km (`lointaine`).
        static let rayonPlage = 9...21
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
        XCTAssertTrue(consentement.label.hasSuffix("Tu restes libre de refuser."), consentement.label)
        XCTAssertFalse(consentement.label.contains("+10"), "promesse de +10 points non affichée (précision 17)")
        XCTAssertFalse(app.staticTexts["+10 points fiabilité par mission urgence terminée"].exists, "avantage non affiché")
        XCTAssertTrue(element("pool-sms").exists)
        record("\(proofPrefix)-pool-actif")

        // Rayon réduit : envoyé à la fin du geste, puis relu. La plage 9-21 km garde les missions à 4,2 et 8 km (acceptation
        // et choix de contrat, plus bas) et retire celle à 22 km. Aucune valeur exacte n'est visée : sous iOS 26.2, le geste
        // d'`adjust` n'est pas fidèle (run 45626727902, `reglerCurseur(_:dansLaPlage:)`). La valeur réellement atteinte N
        // est exigée dans la plage, puis relue EXACTEMENT et tenue.
        let curseur = app.sliders["pool-rayon"]
        scrollTo(curseur, in: ecran, downward: false)
        require("Le curseur du rayon est atteignable") { self.visible(curseur) }
        let atteint = reglerCurseur(curseur, dansLaPlage: Attendus.rayonPlage, minimum: 5, maximum: 50)
        guard let rayon = atteint, Attendus.rayonPlage.contains(rayon) else {
            XCTFail("Le rayon atteint (\(atteint.map(String.init) ?? "illisible")) est entre 9 et 21 km")
            return
        }
        let relu = {
            self.element("pool-rayon-valeur").label.hasSuffix(" \(rayon) km")
                && self.valeurEntiere(curseur) == rayon
                && !self.element("pool-mission-\(Attendus.lointaine)").exists
                && self.element("pool-mission-\(Attendus.proche)").exists
                && self.element("pool-mission-\(Attendus.tous)").exists
        }
        require("Le rayon \(rayon) km est relu", timeout: 20, condition: relu)
        requireAbsence("Le rayon \(rayon) km reste relu (aucun recalage après la relecture)", pendant: 2) { !relu() }
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
        // Mission ouverte non assignée : l'exclusion est rangée sous « Autres actions », comme le web (décision e).
        let autres = element("mission-autres-actions")
        scrollTo(autres, in: detail)
        autres.tap()
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
        toucherOnglet("tab-profil", label: "Profil")
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
        toucherOnglet("tab-profil", label: "Profil")
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
