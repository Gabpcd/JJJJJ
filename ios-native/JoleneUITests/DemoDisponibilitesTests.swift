import XCTest

/// Disponibilités (L4-T5) en démonstration, sur iPhone, iPad portrait et iPad paysage. Horloge démo : lundi 2 novembre
/// 2026 ; fixture `demo-disponibilites.json` : trois créneaux posés (mardi 3 en journée, jeudi 5 de nuit, samedi 14 en
/// journée).
///
/// L'écran n'a pas d'entrée dans le hub (comme le web) : il est ouvert par son lien universel
/// (`-JOLENE_OPEN_URL`, reçu avant la connexion, rejoué après `.ready`). « Sortie puis retour » : retour au hub (l'écran
/// et son modèle sont détruits), puis le même lien remis pendant un renvoi web affiché (`-JOLENE_OPEN_URL_SUIVANT`,
/// bouton `renvoi-web-lien-suivant` du double démo, comme `DemoLiensLot2Tests`) : l'écran est reconstruit et relit le
/// monde démo.
///
/// Ce que ce test prouve (niveau 2), et seulement cela :
/// - `/soignant/disponibilites` ouvre l'écran natif (`dispos-screen`), jamais un renvoi web ;
/// - la nuit du mardi 3 (`dispo-2026-11-03-NUIT`) est déclarée après relecture, compteur de 3 à 4 ;
/// - l'état est conservé dans la session démo après sortie et retour (relecture), puis le créneau est retiré (3) ;
/// - aucune requête réseau (sentinelle).
/// Une relance de l'app repart de la fixture : aucun état démo n'est persisté. Les règles (grille dérivée de l'horloge,
/// jour passé jamais envoyé, aucune bascule optimiste, refus verbatim, chevauchements, epoch) sont prouvées par
/// `DisponibilitesModelTests` et `DisponibilitesLectureTests` ; le transport par `SupabaseDisponibilitesGatewayTests`.
/// L'horloge démo étant un lundi, la grille n'a aucun jour passé : les jours désactivés se prouvent au niveau 1.
final class DemoDisponibilitesTests: JoleneUITestCase {
    private enum Attendus {
        static let lien = "https://jolene.app/soignant/disponibilites"
        static let nuitDuMardi = "dispo-2026-11-03-NUIT"
        static let jourDuMardi = "dispo-2026-11-03-JOURNEE"
        static let nuitDuJeudi = "dispo-2026-11-05-NUIT"
        static let jourDuSamedi = "dispo-2026-11-14-JOURNEE"
        static let mention = "Déclarer une disponibilité n'engage à rien : c'est un signal de matching, pas un engagement."
    }

    func testBasculeRelueEtConserveeApresSortieEtRetour() throws {
        launchDemo(extraArguments: ["-JOLENE_OPEN_URL", Attendus.lien, "-JOLENE_OPEN_URL_SUIVANT", Attendus.lien])
        connexionDemo()
        var ecran = attendreLEcran()
        XCTAssertEqual(element("deeplink-route").label, "secondaire(disponibilites)", "route présentée par le coordinateur des liens")
        XCTAssertFalse(element("renvoi-web-demo").exists, "écran natif livré (T5) : jamais un renvoi web")

        // Fixture : trois créneaux relus, aucune aide (affichée seulement sans créneau déclaré).
        let compteur = element("dispos-compteur")
        XCTAssertEqual(compteur.label, "3 créneaux déclarés. \(Attendus.mention)")
        XCTAssertFalse(element("dispos-aide").exists, "aide réservée à la grille sans créneau")
        // Quatre semaines depuis le lundi courant, pas une de plus.
        for (rang, entete) in ["Semaine du 2 novembre", "Semaine du 9 novembre", "Semaine du 16 novembre",
                               "Semaine du 23 novembre"].enumerated() {
            XCTAssertEqual(element("dispos-semaine-\(rang + 1)-title").label, entete)
        }
        XCTAssertFalse(element("dispos-semaine-5-title").exists)
        XCTAssertTrue(element("dispo-2026-11-29-NUIT").exists, "dernier jour de la grille : dimanche 29 novembre")
        XCTAssertFalse(element("dispo-2026-11-30-JOURNEE").exists)
        XCTAssertFalse(element("dispo-2026-11-01-JOURNEE").exists, "la grille commence le lundi courant")
        for pose in [Attendus.jourDuMardi, Attendus.nuitDuJeudi, Attendus.jourDuSamedi] {
            XCTAssertTrue(element(pose).isSelected, "\(pose) : posé par la fixture")
        }
        let nuit = element(Attendus.nuitDuMardi)
        scrollTo(nuit, in: ecran)
        XCTAssertEqual(nuit.label, "Mardi 3 Nov., Nuit")
        XCTAssertFalse(nuit.isSelected, "créneau libre au lancement")
        XCTAssertTrue(nuit.isEnabled, "horloge démo un lundi : aucun jour passé")
        record("\(proofPrefix)-disponibilites-fixture")

        // Bascule : la case n'est déclarée qu'après relecture, le compteur passe de 3 à 4.
        tap(Attendus.nuitDuMardi)
        require("La nuit du mardi est déclarée après relecture") {
            nuit.isSelected && nuit.isEnabled && compteur.label.hasPrefix("4 créneaux déclarés.")
        }
        XCTAssertFalse(element("dispos-action-erreur").exists, "aucune erreur en démonstration")
        XCTAssertTrue(element(Attendus.jourDuMardi).isSelected, "l'autre créneau du jour est inchangé")
        record("\(proofPrefix)-disponibilites-bascule")

        // Sortie : retour au hub, l'écran est retiré de la pile.
        let retour = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(retour) }
        retour.tap()
        let hub = element("profile-list")
        require("Retour au hub, racine de l'onglet Profil") {
            self.containerVisible(hub) && !self.element(Attendus.nuitDuMardi).exists
        }

        // Retour : le même lien, remis pendant un renvoi web affiché, reconstruit l'écran, qui relit le monde démo.
        let aide = element("compte-aide")
        scrollTo(aide, in: hub)
        tap("compte-aide")
        liensRenvoiWebAffiche("https://jolene.app/aide")
        let suivant = element("renvoi-web-lien-suivant")
        require("Le double du renvoi remet le lien des disponibilités") { self.visible(suivant) && suivant.isEnabled }
        XCTAssertEqual(suivant.label, Attendus.lien)
        suivant.tap()
        require("Le renvoi est fermé", timeout: 30) { !self.element("renvoi-web-demo").exists }
        ecran = attendreLEcran()
        let nuitRelue = element(Attendus.nuitDuMardi)
        let compteurRelu = element("dispos-compteur")
        require("L'état est conservé dans la session démo après sortie et retour") {
            nuitRelue.isSelected && compteurRelu.label == "4 créneaux déclarés. \(Attendus.mention)"
        }
        record("\(proofPrefix)-disponibilites-retour")

        // Retrait : la case redevient libre après relecture, le compteur revient à 3.
        scrollTo(nuitRelue, in: ecran)
        tap(Attendus.nuitDuMardi)
        require("La nuit du mardi est retirée après relecture") {
            !nuitRelue.isSelected && nuitRelue.isEnabled && compteurRelu.label.hasPrefix("3 créneaux déclarés.")
        }
        XCTAssertFalse(element("dispos-action-erreur").exists, "aucune erreur en démonstration")
        verifierAucuneRequete()
    }

    // MARK: Étapes

    /// Écran natif affiché et créneaux relus (la grille n'existe qu'après la relecture).
    private func attendreLEcran() -> XCUIElement {
        let ecran = defilement("dispos-screen")
        require("Les disponibilités sont relues", timeout: 30) {
            self.containerVisible(ecran) && self.element(Attendus.nuitDuMardi).exists && self.element("dispos-compteur").exists
        }
        XCTAssertFalse(element("dispos-erreur").exists, "aucune erreur de lecture en démonstration")
        XCTAssertFalse(element("dispos-chargement").exists)
        return ecran
    }

    /// Conteneur de défilement : la `ScrollView` portant l'identifiant, sinon la première correspondance.
    private func defilement(_ identifier: String) -> XCUIElement {
        let typee = app.scrollViews.matching(identifier: identifier).firstMatch
        return typee.exists ? typee : element(identifier)
    }

    /// Profil remis à sa racine (l'écran des disponibilités y est empilé), puis sentinelle réseau.
    private func verifierAucuneRequete() {
        let retour = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(retour) }
        retour.tap()
        let liste = element("profile-list")
        require("La liste du profil est affichée") {
            self.containerVisible(liste) && !self.element(Attendus.nuitDuMardi).exists
        }
        let sentinelle = element("network-sentinel")
        scrollTo(sentinelle, in: liste, downward: false)
        require("La sentinelle réseau est exposée") { sentinelle.exists }
        XCTAssertEqual(sentinelle.label, "0 requête", "les disponibilités n'émettent aucune requête en démonstration")
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
