import XCTest

/// Hub « Mon compte » du lot 3 (T11) en démo : mot de passe, thème, export RGPD. Aucune requête réseau.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - « Changer mon mot de passe » (`compte-mdp-ouvrir` → `compte-mdp-screen`) : critères et force affichés dès la
///   saisie (textes de `ChangementMotDePasse.tsx` l.211-229), correspondance de la confirmation (l.171, l.176),
///   bouton inactif tant que le formulaire est invalide ; ancien mot de passe faux → « Ancien mot de passe
///   incorrect. » (l.58) ; ancien démo (`demo-motdepasse`) → « Mot de passe modifié avec succès. » (l.96) et
///   formulaire vidé ;
/// - thème Système / Clair / Sombre (`compte-theme-*`, D16) : le segment choisi est sélectionné et appliqué à
///   la racine (libellé DEBUG `compte-theme-effectif`, schéma de couleurs lu dans l'environnement SwiftUI) ;
/// - export RGPD : texte RGPD verbatim web (tutoiement, HARD STOP n°4) ; « Exporter JSON » écrit le fichier du
///   jour et l'ouvre dans la feuille de partage réelle (`UIActivityViewController` présentée par UIKit ; libellé
///   DEBUG `compte-export-pret` posé dans la feuille : `mes-donnees-jolene-2026-11-02.json`) ; revue B8 (M1),
///   une seule fin, `completionWithItemsHandler` : (a) feuille fermée sans partage (bouton de fermeture, ou hors du
///   popover sur iPad) → aucun `compte-export-succes`, boutons réactivés, fichier supprimé (libellé DEBUG
///   `compte-export-residus` = « 0 »), « 0 requête » ; (b) activité aboutie (« Copier ») → « Données exportées en
///   JSON. » (`SectionConfidentialite.tsx` l.73), boutons réactivés, fichier supprimé ; un refus du serveur
///   (variante `JOLENE_FORCE_EXPORT_ECHEC=1`, message verbatim de `fn_rgpd_exporter_rate_limited`) est affiché et
///   n'ouvre aucune feuille ;
/// - « Aide & légal » : depuis l'intégration du lot 3 (présentateur Safari du coordinateur des liens de L3-T3b, qui
///   remplace L1-T10), chaque entrée ouvre sa page publique par le renvoi web (URL canonique, double démo sans
///   réseau) ; avant, le test exigeait leur absence (verrou du gap).
/// Persistance du thème, présentation différée tant que le hub est hors écran, suppression du fichier en fin de
/// session, aplatissement CSV, audit et refus GoTrue sont prouvés au niveau 1 (`PreferenceThemeTests`,
/// `ExportRGPDModelTests`, `ExportRGPDTests`, `MotDePasseModelTests`, `SupabaseMotDePasseGatewayTests`).
///
/// Feuille de partage : ses contrôles sont ceux du système (libellés anglais ou français selon la langue du
/// simulateur : « Close » / « Fermer », « Copy » / « Copier ») ; sur iPad la feuille est un popover, fermé hors de
/// son cadre (`PopoverDismissRegion`) quand il n'a pas de bouton de fermeture.
///
/// Formats : iPhone, iPad portrait, iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`) ; chaque contrôle est
/// amené à l'écran par un défilement borné (`scrollTo`) avant d'être exigé atteignable (PRINCIPES §6).
final class DemoCompteLot3Tests: JoleneUITestCase {
    static let ancienDemo = "demo-motdepasse"
    static let ancienFaux = "faux-mdp"
    static let incorrect = "Ancien mot de passe incorrect."
    static let succes = "Mot de passe modifié avec succès."
    static let nonCorrespondance = "Les mots de passe ne correspondent pas."
    static let correspondance = "Mots de passe identiques."
    static let descriptionExport = "Télécharge l'intégralité de tes données personnelles dans le format de ton choix."
    static let refusLimite = "Trop d'exports en peu de temps. Réessayez dans quelques minutes."
    static let fichierDuJour = "mes-donnees-jolene-2026-11-02.json"
    static let exportJSONReussi = "Données exportées en JSON."
    /// Contrôles système de la feuille de partage (langue du simulateur).
    static let libellesCopier = ["Copy", "Copier"]
    static let libellesFermer = ["Close", "Fermer"]

    // MARK: - Mot de passe

    func testMotDePasseCriteresRefusDeLAncienPuisSucces() throws {
        launchDemo()
        compteSeConnecter()
        compteOuvrirProfil()
        let ecran = compteOuvrirMotDePasse()
        let soumettre = element("compte-mdp-submit")
        scrollTo(soumettre, in: ecran)
        XCTAssertFalse(soumettre.isEnabled, "formulaire vide : bouton inactif (l.183)")
        XCTAssertFalse(element("compte-mdp-force").exists, "jauge absente avant toute saisie (l.156)")

        // Nouveau mot de passe faible : jauge et critères verbatim.
        compteSaisir("compte-mdp-nouveau", "abc", dans: ecran)
        let force = element("compte-mdp-force")
        require("La jauge de force s'affiche dès la saisie") { force.exists }
        XCTAssertEqual(force.label, "Force : Faible")
        XCTAssertEqual(element("compte-mdp-critere-longueur").label, "12 caractères minimum, critère non rempli")
        XCTAssertEqual(element("compte-mdp-critere-minuscule").label, "1 minuscule, critère rempli")
        XCTAssertEqual(element("compte-mdp-critere-special").label, "1 caractère spécial, critère non rempli")

        // Complété à cinq critères (même champ, focus conservé : un champ sécurisé refocalisé serait vidé par
        // iOS à la frappe), puis confirmation d'abord différente, puis identique.
        element("compte-mdp-nouveau").typeText("Def-1234567")
        require("Les cinq critères sont remplis") { force.label == "Force : Excellent" }
        compteSaisir("compte-mdp-confirmation", "abcDef-123456", dans: ecran)
        let correspondance = element("compte-mdp-correspondance")
        require("La confirmation différente est signalée") { correspondance.exists && correspondance.label == Self.nonCorrespondance }
        element("compte-mdp-confirmation").typeText("7\n")
        require("La confirmation identique est signalée") { correspondance.label == Self.correspondance }
        scrollTo(soumettre, in: ecran)
        XCTAssertFalse(soumettre.isEnabled, "ancien mot de passe encore vide (l.40)")

        // Ancien mot de passe faux : refus verbatim, saisie conservée.
        compteSaisir("compte-mdp-ancien", "\(Self.ancienFaux)\n", dans: ecran, remonter: true)
        scrollTo(soumettre, in: ecran)
        require("Le formulaire valide active le bouton") { soumettre.isEnabled }
        record("\(proofPrefix)-compte-mdp-saisie")
        tap("compte-mdp-submit")
        let erreur = element("compte-mdp-erreur")
        require("Le refus de l'ancien mot de passe est affiché", timeout: 30) { erreur.exists }
        XCTAssertTrue(erreur.label.hasSuffix(Self.incorrect), "texte verbatim web : \(erreur.label)")
        XCTAssertFalse(element("compte-mdp-succes").exists)
        XCTAssertTrue(soumettre.isEnabled, "nouvel essai possible : la saisie est conservée")
        record("\(proofPrefix)-compte-mdp-refus")

        // Ancien mot de passe démo : succès, formulaire vidé.
        let ancien = element("compte-mdp-ancien")
        scrollTo(ancien, in: ecran, downward: false)
        focus(ancien, in: ecran)
        // Effacement : iOS vide d'un coup un champ sécurisé refocalisé ; sinon, un effacement par caractère suffit.
        ancien.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: Self.ancienFaux.count))
        ancien.typeText("\(Self.ancienDemo)\n")
        require("Une nouvelle saisie efface le refus") { !erreur.exists }
        scrollTo(soumettre, in: ecran)
        require("Le bouton est actif") { soumettre.isEnabled }
        tap("compte-mdp-submit")
        let succes = element("compte-mdp-succes")
        require("Le succès est annoncé", timeout: 30) { succes.exists }
        XCTAssertTrue(succes.label.hasSuffix(Self.succes), "texte verbatim web : \(succes.label)")
        require("Le formulaire est vidé après le succès (l.98-100)") { !soumettre.isEnabled }
        XCTAssertFalse(element("compte-mdp-force").exists, "nouveau mot de passe effacé : plus de jauge")
        record("\(proofPrefix)-compte-mdp-succes")

        compteRetourAuProfil()
        compteSentinelleSansRequete()
    }

    // MARK: - Thème

    func testThemeSombreClairPuisSystemeAppliquesALaRacine() throws {
        launchDemo()
        compteSeConnecter()
        compteOuvrirProfil()
        let liste = element("profile-list")
        let sombre = element("compte-theme-sombre")
        scrollTo(sombre, in: liste)
        let systeme = element("compte-theme-systeme")
        let clair = element("compte-theme-clair")
        XCTAssertTrue(systeme.isSelected, "défaut Système (D16)")
        XCTAssertFalse(sombre.isSelected)
        XCTAssertFalse(clair.isSelected)

        tap("compte-theme-sombre")
        require("Le thème sombre est choisi") { sombre.isSelected && !systeme.isSelected }
        let effectif = element("compte-theme-effectif")
        require("Le thème sombre est appliqué à la racine") { effectif.exists && effectif.label == "sombre" }
        record("\(proofPrefix)-compte-theme-sombre")

        tap("compte-theme-clair")
        require("Le thème clair est choisi et appliqué") { clair.isSelected && effectif.label == "clair" }
        record("\(proofPrefix)-compte-theme-clair")

        tap("compte-theme-systeme")
        require("Le thème de l'appareil est rétabli") { systeme.isSelected && !clair.isSelected && !sombre.isSelected }
        compteSentinelleSansRequete()
    }

    // MARK: - Export RGPD

    /// (a) Feuille fermée sans partage : aucune annonce, boutons réactivés, fichier supprimé, aucune requête.
    func testExportJSONFeuilleFermeeSansPartageAucunSucces() throws {
        launchDemo()
        compteSeConnecter()
        compteOuvrirProfil()
        let json = compteAmenerExport()
        XCTAssertEqual(element("compte-export-info").label, Self.descriptionExport, "texte RGPD verbatim web (tutoiement)")
        XCTAssertEqual(element("compte-export-residus").label, "0", "aucun fichier d'export avant la demande")
        let pret = compteOuvrirFeuille()
        XCTAssertFalse(element("compte-export-erreur").exists)
        record("\(proofPrefix)-compte-export-partage")

        compteFermerFeuilleSansPartage()
        require("La feuille de partage est fermée") { !pret.exists }
        let csv = element("compte-export-csv")
        require("Les deux boutons sont réactivés") { json.isEnabled && csv.isEnabled }
        XCTAssertFalse(element("compte-export-succes").exists, "feuille fermée sans partage : aucun succès (écart 3, DECISIONS_LOT3)")
        XCTAssertFalse(element("compte-export-erreur").exists)
        require("Le fichier exporté est supprimé à la fermeture") { self.element("compte-export-residus").label == "0" }
        record("\(proofPrefix)-compte-export-ferme")
        compteSentinelleSansRequete()
    }

    /// (b) Activité aboutie (« Copier ») : « Données exportées en JSON. », boutons réactivés, fichier supprimé.
    func testExportJSONPartageAboutiAnnonceLeSucces() throws {
        launchDemo()
        compteSeConnecter()
        compteOuvrirProfil()
        let json = compteAmenerExport()
        let pret = compteOuvrirFeuille()

        // « Copier » : bouton ou cellule selon la version de la feuille système.
        let libelleCopier = NSPredicate(format: "label IN %@", Self.libellesCopier)
        let boutonCopier = app.buttons.matching(libelleCopier).firstMatch
        let celluleCopier = app.cells.matching(libelleCopier).firstMatch
        require("L'action « Copier » de la feuille est atteignable", timeout: 30) {
            self.visible(boutonCopier) || self.visible(celluleCopier)
        }
        (visible(boutonCopier) ? boutonCopier : celluleCopier).tap()
        let succes = element("compte-export-succes")
        require("Le partage abouti est annoncé", timeout: 30) { succes.exists }
        XCTAssertTrue(succes.label.hasSuffix(Self.exportJSONReussi), "texte verbatim web (l.73) : \(succes.label)")
        XCTAssertFalse(pret.exists, "la feuille s'est fermée d'elle-même")
        let csv = element("compte-export-csv")
        require("Les deux boutons sont réactivés") { json.isEnabled && csv.isEnabled }
        require("Le fichier exporté est supprimé après le partage") { self.element("compte-export-residus").label == "0" }
        record("\(proofPrefix)-compte-export-succes")
        compteSentinelleSansRequete()
    }

    func testExportRefuseParLeServeurAfficheLeMessageSansFeuille() throws {
        launchDemo(environment: ["JOLENE_FORCE_EXPORT_ECHEC": "1"])
        compteSeConnecter()
        compteOuvrirProfil()
        let liste = element("profile-list")
        let csv = element("compte-export-csv")
        scrollTo(csv, in: liste)
        tap("compte-export-csv")
        let erreur = element("compte-export-erreur")
        require("Le refus du serveur est affiché", timeout: 30) { erreur.exists }
        XCTAssertTrue(erreur.label.hasSuffix(Self.refusLimite), "message serveur verbatim : \(erreur.label)")
        XCTAssertFalse(element("compte-export-pret").exists, "aucun fichier, aucune feuille de partage")
        require("Nouvel essai manuel possible") { csv.isEnabled && self.element("compte-export-json").isEnabled }
        record("\(proofPrefix)-compte-export-refus")

        compteSentinelleSansRequete()
    }

    /// Intégration du lot 3 (règle 8) : le présentateur `.safari` du coordinateur des liens (L3-T3b) est injecté, la
    /// section « Aide & légal » (`MonCompteSoignant.tsx` l.126-136) est donc montée ; chaque entrée ouvre sa page
    /// publique, URL canonique (double démo `renvoi-web-demo`, aucune requête réseau), jamais `openURL`. Avant T3b, le
    /// test exigeait l'absence des quatre entrées (jamais un lien sans effet).
    func testAideEtLegalOuvreLesPagesPubliquesParLeRenvoiWeb() throws {
        launchDemo()
        compteSeConnecter()
        compteOuvrirProfil()
        let liste = element("profile-list")
        let pages = [("compte-aide", "Centre d'aide", "https://jolene.app/aide"),
                     ("compte-confidentialite", "Confidentialité", "https://jolene.app/confidentialite"),
                     ("compte-cgu", "Conditions générales", "https://jolene.app/cgu"),
                     ("compte-mentions-legales", "Mentions légales", "https://jolene.app/mentions-legales")]
        for (identifiant, libelle, url) in pages {
            let entree = element(identifiant)
            scrollTo(entree, in: liste)
            XCTAssertTrue(entree.label.contains(libelle), "libellé verbatim web : \(entree.label)")
            tap(identifiant)
            liensRenvoiWebAffiche(url)
            if identifiant == "compte-cgu" { record("\(proofPrefix)-compte-aide-legal-cgu") }
            liensFermerRenvoiWeb()
            require("Retour au hub après le renvoi") { self.containerVisible(liste) }
        }
        compteSentinelleSansRequete()
    }

    // MARK: - Étapes

    private func compteSeConnecter() {
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

    private func compteOuvrirProfil() {
        tabButton("tab-profil", label: "Profil").tap()
        require("Le profil affiche l'email de démonstration") {
            self.visible(self.element("profile-email")) && self.element("profile-email").label.contains(Self.demoEmail)
        }
    }

    /// Section « Connexion & sécurité » du hub, puis l'écran du mot de passe.
    @discardableResult
    private func compteOuvrirMotDePasse() -> XCUIElement {
        let liste = element("profile-list")
        let entree = element("compte-mdp-ouvrir")
        scrollTo(entree, in: liste)
        XCTAssertTrue(entree.label.contains("Changer mon mot de passe"), entree.label)
        tap("compte-mdp-ouvrir")
        let ecran = element("compte-mdp-screen")
        require("L'écran du mot de passe est affiché") { self.containerVisible(ecran) && self.element("compte-mdp-ancien").exists }
        XCTAssertTrue(app.navigationBars["Changer mon mot de passe"].exists, "titre verbatim web (l.206)")
        return ecran
    }

    /// Section « Mes données (RGPD) » amenée à l'écran ; rend « Exporter JSON », exigé actif.
    private func compteAmenerExport() -> XCUIElement {
        let json = element("compte-export-json")
        scrollTo(json, in: element("profile-list"))
        require("« Exporter JSON » et « Exporter CSV » sont actifs") { json.isEnabled && self.element("compte-export-csv").isEnabled }
        return json
    }

    /// « Exporter JSON », puis la feuille de partage du fichier du jour (libellé DEBUG posé dans la feuille).
    private func compteOuvrirFeuille() -> XCUIElement {
        tap("compte-export-json")
        let pret = element("compte-export-pret")
        require("La feuille de partage reçoit le fichier du jour", timeout: 30) { pret.exists }
        XCTAssertEqual(pret.label, Self.fichierDuJour)
        return pret
    }

    /// Ferme la feuille sans rien partager : son bouton de fermeture s'il en a un, sinon un tap natif dans la zone de
    /// fermeture que UIKit expose (`PopoverDismissRegion`), hors du cadre de la feuille.
    ///
    /// Intégration du lot 3 (premier run CI, 42536888984, UI — iphone) : sur iPhone (iOS 26.2), la feuille n'a pas de
    /// bouton « Close » / « Fermer » et `PopoverDismissRegion` (voile de la présentation en feuille) couvre tout
    /// l'écran ; le coin bas gauche visé pour le popover de l'iPad tombe SOUS la feuille, qui est restée ouverte. Sur
    /// iPhone, le tap vise donc le voile au-dessus du bord haut de la feuille (libellé DEBUG `compte-export-pret`, posé
    /// en (0, 0) de la vue de la feuille) ; si la feuille est encore là au terme d'une attente bornée (détente haute),
    /// elle est glissée vers le bas depuis son bord haut, geste de fermeture d'une feuille. La fermeture reste exigée
    /// par l'appelant (`!pret.exists`), aucune assertion n'est relâchée.
    private func compteFermerFeuilleSansPartage() {
        let fermer = app.buttons.matching(NSPredicate(format: "label IN %@ OR identifier IN %@",
                                                      Self.libellesFermer, Self.libellesFermer)).firstMatch
        let horsPopover = app.otherElements["PopoverDismissRegion"]
        require("La feuille de partage peut être fermée", timeout: 30) { self.visible(fermer) || horsPopover.exists }
        if visible(fermer) {
            fermer.tap()
        } else if UIDevice.current.userInterfaceIdiom == .pad {
            horsPopover.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.97)).tap()
        } else {
            let pret = element("compte-export-pret")
            let origine = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            let milieu = app.frame.width / 2
            let bordHaut = pret.frame.minY - app.frame.minY
            origine.withOffset(CGVector(dx: milieu, dy: max(2, bordHaut / 2))).tap()
            if !pret.waitForNonExistence(timeout: 10) {
                let depart = origine.withOffset(CGVector(dx: milieu, dy: bordHaut + 12))
                let arrivee = origine.withOffset(CGVector(dx: milieu, dy: app.frame.height - 4))
                depart.press(forDuration: 0.05, thenDragTo: arrivee, withVelocity: .fast, thenHoldForDuration: 0)
            }
        }
    }

    /// Saisie dans un champ de l'écran (amené à l'écran, focus clavier exigé) ; `remonter` : le champ est au-dessus.
    private func compteSaisir(_ identifiant: String, _ texte: String, dans ecran: XCUIElement, remonter: Bool = false) {
        let champ = element(identifiant)
        scrollTo(champ, in: ecran, downward: !remonter)
        focus(champ, in: ecran)
        champ.typeText(texte)
    }

    private func compteRetourAuProfil() {
        let retour = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(retour) }
        retour.tap()
        require("Retour au hub") { self.containerVisible(self.element("profile-list")) && !self.element("compte-mdp-screen").exists }
    }

    /// La sentinelle (section « Application », en tête du hub) affiche « 0 requête ».
    private func compteSentinelleSansRequete() {
        let sentinel = element("network-sentinel")
        scrollTo(sentinel, in: element("profile-list"), downward: false)
        XCTAssertEqual(sentinel.label, "0 requête", "Aucune requête réseau en démonstration")
    }
}
