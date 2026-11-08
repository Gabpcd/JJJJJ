import XCTest

/// « Mon profil » en démo (lot 3, T9) : onglet Profil → entrée `profil-ouvrir` → profil lu en liste blanche
/// (`DemoProfilGateway`, fixture `demo-profil-complet.json`) → édition → enregistrement → profil RELU.
/// Aucune requête réseau.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - la lecture affiche l'identité du profil fictif ; le type d'exercice n'est pas éditable (encart de renvoi
///   `profil-exercice-web`, HARD STOP n°4 ; son bouton n'existe qu'avec le présentateur Safari de L1-T10) ;
/// - une ville de recherche saisie est enregistrée puis relue (encart « Profil mis à jour avec succès ! »,
///   texte verbatim de `ProfilSoignant.tsx` l.293), et retrouvée à la réouverture de l'écran ;
/// - un prénom vidé est refusé avec le message serveur verbatim (`fn_modifier_mon_profil` l.43906) ;
/// - le référentiel des modes d'exercice (`fn_types_exercice_autorises`, câblé par T8) n'est pas encore lu :
///   état « indisponible » du web, sans « Réessayer la vérification » (verrou du gap : T8 remplace cette
///   assertion par les modes autorisés).
/// L'envoi des seuls champs modifiés, l'audit de consultation et la relecture après un délai dépassé sont
/// prouvés au niveau 1 (`ProfilEditionModelTests`, `ModificationProfilTests`, `SupabaseProfilGatewayTests`).
///
/// Formats : iPhone, iPad portrait, iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`) ; chaque contrôle est
/// amené à l'écran par un défilement borné (`scrollTo`) avant d'être exigé atteignable (PRINCIPES §6).
final class DemoProfilTests: JoleneUITestCase {
    static let succes = "Profil mis à jour avec succès !"
    static let prenomVide = "Le prénom ne peut pas être vide"
    static let indisponible = "Vérification temporairement indisponible. Le mode salarié reste accessible. Vos choix sont conservés ; l’ajout du libéral nécessite une vérification."

    func testEditionDeLaVilleDeRechercheEnregistreeRelueEtRetrouvee() throws {
        launchDemo()
        signInDemo()
        ouvrirProfil()
        let ecran = element("profil-screen")
        XCTAssertEqual(element("profil-nom-complet").label, "Camille Démo")
        XCTAssertTrue(element("profil-profession").exists)
        let enregistrer = element("profil-enregistrer")
        scrollTo(enregistrer, in: ecran)
        XCTAssertFalse(enregistrer.isEnabled, "rien à enregistrer tant que rien n'a changé")

        let ville = element("profil-ville-recherche")
        scrollTo(ville, in: ecran, downward: false)
        focus(ville, in: ecran)
        ville.typeText("Lyon")
        require("La saisie est affichée") { (ville.value as? String) == "Lyon" }
        ville.typeText("\n")
        scrollTo(enregistrer, in: ecran)
        require("La modification active l'enregistrement") { enregistrer.isEnabled }
        record("\(proofPrefix)-profil-saisie")

        tap("profil-enregistrer")
        let succes = element("profil-enregistre")
        require("Le succès est annoncé après la relecture", timeout: 30) { succes.exists }
        XCTAssertTrue(succes.label.hasSuffix(Self.succes), "texte verbatim web : \(succes.label)")
        XCTAssertFalse(element("profil-erreur").exists)
        require("Le profil relu devient la nouvelle base : plus rien à enregistrer") { !enregistrer.isEnabled }
        scrollTo(ville, in: ecran, downward: false)
        XCTAssertEqual(ville.value as? String, "Lyon", "valeur relue")
        record("\(proofPrefix)-profil-enregistre")

        // Réouverture : nouvelle lecture du port, la ville enregistrée est retrouvée.
        let retour = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(retour) }
        retour.tap()
        ouvrirProfil()
        let villeRelue = element("profil-ville-recherche")
        scrollTo(villeRelue, in: element("profil-screen"))
        XCTAssertEqual(villeRelue.value as? String, "Lyon", "profil relu à la réouverture")

        retour.tap()
        let sentinel = element("network-sentinel")
        require("La sentinelle réseau est exposée") { sentinel.exists }
        XCTAssertEqual(sentinel.label, "0 requête", "Lecture et enregistrement démo : aucune requête réseau")
        record("\(proofPrefix)-profil-retour")
    }

    func testPrenomVideRefuseAvecLeMessageServeur() throws {
        launchDemo()
        signInDemo()
        ouvrirProfil()
        let ecran = element("profil-screen")
        let prenom = element("profil-prenom")
        scrollTo(prenom, in: ecran)
        focus(prenom, in: ecran)
        let longueur = (prenom.value as? String)?.count ?? 0
        XCTAssertGreaterThan(longueur, 0, "prénom de démonstration lu")
        prenom.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: longueur))
        require("Le prénom est vidé") { ((prenom.value as? String) ?? "").isEmpty || (prenom.value as? String) == "Prénom" }
        prenom.typeText("\n")

        let enregistrer = element("profil-enregistrer")
        scrollTo(enregistrer, in: ecran)
        tap("profil-enregistrer")
        let erreur = element("profil-erreur")
        require("Le refus serveur est affiché", timeout: 30) { erreur.exists }
        XCTAssertTrue(erreur.label.hasSuffix(Self.prenomVide), "message serveur verbatim : \(erreur.label)")
        XCTAssertFalse(element("profil-enregistre").exists, "aucun succès annoncé")
        XCTAssertEqual(element("profil-nom-complet").label, "Camille Démo", "rien n'a été enregistré")
        record("\(proofPrefix)-profil-prenom-vide")
    }

    func testTypeDExerciceEnRenvoiEtModesSansReferentiel() throws {
        launchDemo()
        signInDemo()
        ouvrirProfil()
        let ecran = element("profil-screen")
        let indisponible = element("profil-modes-indisponible")
        scrollTo(indisponible, in: ecran)
        XCTAssertEqual(indisponible.label, Self.indisponible, "texte verbatim web (ChoixModesExercice.tsx l.43)")
        XCTAssertFalse(element("profil-modes-reessayer").exists,
                       "référentiel non câblé (T8) : aucun « Réessayer la vérification » sans effet")
        XCTAssertTrue(element("profil-mode-salarie").exists, "le mode salarié reste accessible")
        XCTAssertTrue(element("profil-mode-liberal").exists, "le libéral coché du profil démo reste visible")

        let exercice = element("profil-exercice-web")
        scrollTo(exercice, in: ecran)
        XCTAssertTrue(exercice.label.contains("Type d'exercice"), "renvoi libellé : \(exercice.label)")
        XCTAssertFalse(element("profil-exercice-web-action").exists,
                       "sans présentateur Safari (L1-T10), aucun bouton sans effet")
        XCTAssertFalse(textContaining("L1222-5").exists, "aucun texte juridique du type d'exercice porté")
        record("\(proofPrefix)-profil-exercice")
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

    /// Onglet Profil → entrée « Mon profil » (après « Application ») → écran d'édition chargé.
    private func ouvrirProfil() {
        tabButton("tab-profil", label: "Profil").tap()
        let list = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(list) }
        let entree = element("profil-ouvrir")
        scrollTo(entree, in: list)
        XCTAssertTrue(entree.label.contains("Mon profil"), "libellé du hub web (MonCompteSoignant.tsx l.59)")
        tap("profil-ouvrir")
        let ecran = element("profil-screen")
        require("L'écran « Mon profil » est affiché") { self.containerVisible(ecran) }
        require("Le profil est lu", timeout: 30) { self.element("profil-nom-complet").exists }
        XCTAssertFalse(element("profil-erreur-chargement").exists)
    }
}
