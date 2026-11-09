import XCTest

/// Photo de profil et position de « Mon profil » en démo (lot 3, T10) : onglet Profil → « Mon profil » → photo choisie
/// (source démo : HEIC de synthèse, aucune feuille système) → convertie, déposée en mémoire, `avatar_url` RELUE ;
/// « Utiliser ma position actuelle » (localisation démo, aucune autorisation système) → géocodage démo → ville posée
/// dans le formulaire → « Enregistrer les modifications » → profil RELU. Aucune requête réseau.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela :
/// - la photo passe de l'état « initiales » à « photo » (libellé DEBUG `profil-avatar-etat`, démo seulement) après
///   l'encart « Photo mise à jour ! » (`AvatarUpload.tsx` l.164, verbatim), et la photo relue est retrouvée à la
///   réouverture de l'écran (lecture par le port, sans réseau) ;
/// - un refus du stockage (`-JOLENE_DEMO_AVATAR refus`) affiche le message du web (l.166) et laisse les initiales ;
/// - la position renseigne la ville (« Lyon ») et le libellé de l'adresse trouvée, n'écrit rien avant
///   « Enregistrer », puis est enregistrée et relue à la réouverture (ville « Lyon », « Position enregistrée — … ») ;
/// - localisation refusée (`-JOLENE_DEMO_LOCALISATION refusee`) : message du web vouvoyé, rien à enregistrer ;
/// - géocodage sans résultat (`-JOLENE_DEMO_GEOCODAGE echec`) : « Position récupérée. », ville inchangée.
/// La conversion HEIC → JPEG, le reçu durable (403 → `refused`, aucun `p_avatar_url` ; arrêt entre dépôt et RPC →
/// relecture sans second envoi) et l'en-tête des requêtes sont prouvés au niveau 1 (`ConversionAvatarTests`,
/// `EnvoiAvatarTests`, `SupabaseAvatarStorageTests`, `ApiAdresseGeocodageTests`). Feuilles système réelles
/// (photothèque, appareil photo, autorisation de position) et HEIC d'un iPhone : niveau 5 (`RECETTE_DEVICE_LOT3.md`).
///
/// Formats : iPhone, iPad portrait, iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`) ; chaque contrôle est amené à
/// l'écran par un défilement borné (`scrollTo`) avant d'être exigé atteignable (PRINCIPES §6). Éclat CI dédié
/// « lot3-profil-photo » (l'éclat « lot3-notifications » aurait dépassé 20 min).
final class DemoPhotoPositionTests: JoleneUITestCase {
    static let photoMiseAJour = "Photo mise à jour !"
    static let echecEnvoi = "Une erreur est survenue lors de l'upload. Veuillez réessayer."
    static let adresseDemo = "Place Bellecour 69002 Lyon"
    static let positionRecuperee = "Position récupérée."
    static let localisationRefusee = "Localisation refusée ou indisponible. Vous pouvez saisir votre adresse manuellement."
    static let positionEnregistree = "Position enregistrée — votre ville est renseignée ci-dessous."
    static let succesProfil = "Profil mis à jour avec succès !"

    func testPhotoChoisieConvertieEnvoyeeRelueEtRetrouvee() throws {
        launchDemo()
        signInDemo()
        ouvrirProfil()
        let ecran = element("profil-screen")
        let etat = element("profil-avatar-etat")
        require("L'état de la photo est exposé (démo)") { etat.exists }
        XCTAssertEqual(etat.label, "initiales", "profil démo sans photo")
        let avatar = element("profil-avatar")
        scrollTo(avatar, in: ecran, downward: false)
        XCTAssertEqual(avatar.label, "Camille Démo", "texte alternatif du web (`alt`)")
        let changer = element("profil-avatar-changer")
        XCTAssertTrue(changer.label.contains("Changer ma photo de profil"), "libellé web : \(changer.label)")
        tap("profil-avatar-changer")
        let phototheque = element("profil-avatar-phototheque")
        require("Le choix de la source est affiché") { self.visible(phototheque) }
        XCTAssertTrue(element("profil-avatar-camera").exists, "appareil photo proposé (démo)")
        record("\(proofPrefix)-photo-choix")
        tap("profil-avatar-phototheque")

        let avis = element("profil-avatar-avis")
        require("Le succès est annoncé après la relecture", timeout: 30) { avis.exists }
        XCTAssertTrue(avis.label.hasSuffix(Self.photoMiseAJour), "texte verbatim web : \(avis.label)")
        require("La photo remplace les initiales") { etat.label == "photo" }
        XCTAssertFalse(element("profil-avatar-phototheque").exists, "le choix est refermé")
        record("\(proofPrefix)-photo-envoyee")

        // Réouverture : la photo relue est lue par le port démo (aucun réseau).
        retour()
        ouvrirProfil()
        let etatRelu = element("profil-avatar-etat")
        require("La photo relue est affichée à la réouverture", timeout: 30) { etatRelu.label == "photo" }
        XCTAssertFalse(element("profil-avatar-avis").exists, "aucun avis sans nouvel envoi")
        retour()
        sentinelleSansRequete()
    }

    func testPhotoRefuseeParLeStockageAfficheLeMessageDuWeb() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_AVATAR", "refus"])
        signInDemo()
        ouvrirProfil()
        let ecran = element("profil-screen")
        let changer = element("profil-avatar-changer")
        scrollTo(changer, in: ecran, downward: false)
        tap("profil-avatar-changer")
        let camera = element("profil-avatar-camera")
        require("L'appareil photo est proposé (démo)") { self.visible(camera) }
        tap("profil-avatar-camera")
        let avis = element("profil-avatar-avis")
        require("Le refus est affiché", timeout: 30) { avis.exists }
        XCTAssertTrue(avis.label.hasSuffix(Self.echecEnvoi), "texte verbatim web : \(avis.label)")
        XCTAssertEqual(element("profil-avatar-etat").label, "initiales", "aucune photo liée après le refus")
        record("\(proofPrefix)-photo-refusee")
    }

    func testPositionRenseigneLaVilleEnregistreeEtRelue() throws {
        launchDemo()
        signInDemo()
        ouvrirProfil()
        let ecran = element("profil-screen")
        let localiser = element("profil-localiser")
        scrollTo(localiser, in: ecran)
        XCTAssertTrue(localiser.label.contains("Utiliser ma position actuelle"), "libellé web : \(localiser.label)")
        let aide = element("profil-position-aide")
        XCTAssertEqual(aide.label, Self.positionEnregistree, "profil démo déjà localisé : texte vouvoyé, sans coordonnées")
        let enregistrer = element("profil-enregistrer")
        tap("profil-localiser")

        let avis = element("profil-localisation-avis")
        require("L'adresse trouvée est annoncée", timeout: 30) { avis.exists }
        XCTAssertTrue(avis.label.hasSuffix(Self.adresseDemo), "libellé de l'adresse : \(avis.label)")
        XCTAssertFalse(avis.label.contains("📍"), "pictogramme décoratif retiré")
        let ville = element("profil-ville-recherche")
        scrollTo(ville, in: ecran)
        XCTAssertEqual(ville.value as? String, "Lyon", "ville posée par le géocodage")
        XCTAssertFalse(element("profil-enregistre").exists, "rien n'est écrit avant « Enregistrer les modifications »")
        record("\(proofPrefix)-position-trouvee")

        scrollTo(enregistrer, in: ecran)
        require("La position et la ville activent l'enregistrement") { enregistrer.isEnabled }
        tap("profil-enregistrer")
        let succes = element("profil-enregistre")
        require("Le succès est annoncé après la relecture", timeout: 30) { succes.exists }
        XCTAssertTrue(succes.label.hasSuffix(Self.succesProfil), "texte verbatim web : \(succes.label)")
        require("Le profil relu devient la nouvelle base") { !enregistrer.isEnabled }
        record("\(proofPrefix)-position-enregistree")

        retour()
        ouvrirProfil()
        let villeRelue = element("profil-ville-recherche")
        scrollTo(villeRelue, in: element("profil-screen"))
        XCTAssertEqual(villeRelue.value as? String, "Lyon", "ville relue à la réouverture")
        XCTAssertEqual(element("profil-position-aide").label, Self.positionEnregistree)
        retour()
        sentinelleSansRequete()
    }

    func testLocalisationRefuseeAfficheLeMessageDuWebSansRienModifier() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_LOCALISATION", "refusee"])
        signInDemo()
        ouvrirProfil()
        let ecran = element("profil-screen")
        let localiser = element("profil-localiser")
        scrollTo(localiser, in: ecran)
        tap("profil-localiser")
        let avis = element("profil-localisation-avis")
        require("Le refus est affiché", timeout: 30) { avis.exists }
        XCTAssertTrue(avis.label.hasSuffix(Self.localisationRefusee), "texte web vouvoyé : \(avis.label)")
        let enregistrer = element("profil-enregistrer")
        scrollTo(enregistrer, in: ecran)
        XCTAssertFalse(enregistrer.isEnabled, "formulaire inchangé : rien à enregistrer")
        record("\(proofPrefix)-position-refusee")
    }

    func testGeocodageSansResultatPositionRecupereeVilleInchangee() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_GEOCODAGE", "echec"])
        signInDemo()
        ouvrirProfil()
        let ecran = element("profil-screen")
        let localiser = element("profil-localiser")
        scrollTo(localiser, in: ecran)
        tap("profil-localiser")
        let avis = element("profil-localisation-avis")
        require("La position est annoncée sans adresse", timeout: 30) { avis.exists }
        XCTAssertTrue(avis.label.hasSuffix(Self.positionRecuperee), "texte verbatim web : \(avis.label)")
        let ville = element("profil-ville-recherche")
        scrollTo(ville, in: ecran)
        XCTAssertNotEqual(ville.value as? String, "Lyon", "aucune ville sans adresse")
        let enregistrer = element("profil-enregistrer")
        scrollTo(enregistrer, in: ecran)
        XCTAssertTrue(enregistrer.isEnabled, "la position seule reste à enregistrer")
        record("\(proofPrefix)-position-sans-adresse")
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

    /// Onglet Profil → entrée « Mon profil » → écran d'édition chargé.
    private func ouvrirProfil() {
        tabButton("tab-profil", label: "Profil").tap()
        let list = element("profile-list")
        require("La liste du profil est affichée") { self.containerVisible(list) }
        let entree = element("profil-ouvrir")
        scrollTo(entree, in: list)
        tap("profil-ouvrir")
        let ecran = element("profil-screen")
        require("L'écran « Mon profil » est affiché") { self.containerVisible(ecran) }
        require("Le profil est lu", timeout: 30) { self.element("profil-nom-complet").exists }
    }

    private func retour() {
        let bouton = app.navigationBars.buttons.firstMatch
        require("Le bouton retour est disponible") { self.visible(bouton) }
        bouton.tap()
        require("Retour au hub du profil") { self.containerVisible(self.element("profile-list")) }
    }

    private func sentinelleSansRequete() {
        let sentinel = element("network-sentinel")
        require("La sentinelle réseau est exposée") { sentinel.exists }
        XCTAssertEqual(sentinel.label, "0 requête", "photo, position et géocodage démo : aucune requête réseau")
    }
}
