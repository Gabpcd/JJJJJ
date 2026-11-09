import XCTest

/// Étapes communes des XCUITest du pointage démo (lot 2, T4b) : `DemoPointageTests` (parcours nominal, QR, GPS, hors
/// ligne) et `DemoPointageEtatsTests` (session à vérifier, échec du consentement, coupe-circuit ; seconde revue fraîche
/// de T4b, m2 et m3). Aucune méthode de test ici. Monde `DemoPointageGateway` (`demo-presences.json`, horloge fixée
/// 2026-11-02T00:00:00Z ; codes affichés : mission a `123456`, mission b `654321` ; `100001` → refus du code inconnu ;
/// consentement GPS NULL au lancement). Aucune attente par délai fixe : tout passe par `require`.
///
/// Scanner démo (seconde revue fraîche de T4b, MJ1) : en DEBUG, `DemoQRScannerView` ne lit rien d'elle-même ; la feuille
/// `pointage-scanner` reste présentée jusqu'au toucher de `pointage-scanner-demo-lire` (`lireQRDemo()`). L'ouverture de la
/// feuille est donc un état stable, attendu sans course avec sa fermeture, dans tous les scénarios de `-JOLENE_DEMO_QR`.
///
/// Preuves « aucune requête » et « une seule fois » : `pointage-demo-scans` (DEBUG) lit les scans appliqués par le monde
/// démo et ceux qui portent une position (« N scan · M avec position »), sans jamais afficher de coordonnée ; chaque
/// affirmation de compte suit une lecture postérieure à l'action (`compteursRelus`, revue fraîche de T4b, m3, et seconde
/// revue, m8).
class DemoPointageUITestCase: JoleneUITestCase {
    static let missionA = "demo-presence-a"
    static let missionB = "demo-presence-b"

    /// `LibellesPresences.Pointage.codeInvalide` (décision 6, vouvoyée, apostrophe du web).
    static let codeInvalide = "Code de pointage invalide ou expiré. Demandez le code actuel à l’établissement."
    static let segmentOuvert = "Pointage enregistré — segment ouvert"
    static let segmentFerme = "Pointage enregistré — segment fermé"

    func connexionDemo() {
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
        submit.tap()
        require("La session démo est prête", timeout: 30) { self.tabBarExists }
    }

    func ouvrirProfil() {
        tabButton("tab-profil", label: "Profil").tap()
        require("Le profil est affiché") { self.containerVisible(self.element("profile-list")) }
    }

    /// Ligne de « Mon espace » (sous « Application ») : défilement borné, puis tap natif.
    func tapDansProfil(_ identifiant: String) {
        let ligne = element(identifiant)
        if !visible(ligne) { scrollTo(ligne, in: element("profile-list")) }
        tap(identifiant)
    }

    /// Ligne de la section « Mon espace » amenée à l'écran : une cellule hors écran d'une `List` n'existe pas encore dans
    /// l'arbre (et sa `.task` n'a pas tourné) ; glissements bornés jusqu'à ce que l'un des états attendus de la ligne
    /// existe, puis défilement borné jusqu'à `cible`.
    func amenerDansLeProfil(_ cible: XCUIElement, etats: [String]) {
        let liste = element("profile-list")
        let presente = { etats.contains { self.element($0).exists } }
        var glissements = 0
        while !presente() && glissements < 10 {
            drag(liste, fromY: 0.7, toY: 0.35)
            glissements += 1
        }
        require("La ligne du consentement du Profil est rendue", timeout: 30) { presente() }
        require("L'état attendu de la ligne est affiché", timeout: 30) { cible.exists }
        if !visible(cible) { scrollTo(cible, in: liste) }
    }

    @discardableResult
    func ouvrirMesPresences() -> XCUIElement {
        ouvrirProfil()
        tapDansProfil("profil-presences")
        let ecran = element("presences-screen")
        require("La page Présences est chargée", timeout: 30) {
            self.containerVisible(ecran) && self.element("presences-tab-aujourdhui").isSelected && !self.element("presences-loading").exists
        }
        require("La zone de pointage de la mission a est prête", timeout: 30) { self.element("pointage-code-\(Self.missionA)").exists }
        XCTAssertFalse(element("presences-error").exists, "aucune erreur en démo")
        return ecran
    }

    /// Saisie au clavier numérique du champ de la mission (focus exigé avant `typeText`).
    func saisir(_ code: String, mission: String, dans ecran: XCUIElement) {
        let champ = element("pointage-code-\(mission)")
        require("Le champ du code de \(mission) est rendu", timeout: 30) { champ.exists }
        scrollTo(champ, in: ecran)
        focus(champ, in: ecran)
        // Un code refusé reste dans le champ (comme le web) : effacé avant la nouvelle saisie. Le texte est centré : un
        // toucher au bord de fin place le curseur après le dernier chiffre, puis autant d'effacements que de chiffres
        // (au plus trois passes, bornées).
        var passes = 0
        while let present = valeur("pointage-code-\(mission)"), !present.isEmpty, passes < 3 {
            champ.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
            champ.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: present.count))
            passes += 1
        }
        require("Le champ est vide avant la saisie") { self.valeur("pointage-code-\(mission)") == "" }
        champ.typeText(code)
        require("Le code saisi est dans le champ") { (champ.value as? String) == code }
    }

    /// Le bouton d'action, amené hors du clavier (un glissement de la page le ferme), puis touché.
    func appuyerSurPointer(_ mission: String, dans ecran: XCUIElement) {
        let bouton = element("pointage-submit-\(mission)")
        var glissements = 0
        while (coveredByKeyboard(bouton) || !fullyVisible(bouton, inside: ecran)) && glissements < 10 {
            drag(ecran, fromY: 0.55, toY: 0.45)
            if !coveredByKeyboard(bouton), !fullyVisible(bouton, inside: ecran) { scrollTo(bouton, in: ecran) }
            glissements += 1
        }
        tap("pointage-submit-\(mission)")
    }

    /// Ouvre la feuille du scanner. En DEBUG, le scanner démo attend `lireQRDemo()` : la feuille reste présentée, son
    /// attente est donc sans course (MJ1), quel que soit le scénario `-JOLENE_DEMO_QR`.
    func ouvrirScanner(_ mission: String, dans ecran: XCUIElement) {
        let qr = element("pointage-qr-\(mission)")
        require("Le bouton QR est rendu", timeout: 30) { qr.exists }
        scrollTo(qr, in: ecran)
        tap("pointage-qr-\(mission)")
        require("La feuille du scanner est présentée et attend la lecture démo", timeout: 30) {
            self.containerVisible(self.element("pointage-scanner")) && self.element("pointage-scanner-demo-lire").exists
        }
    }

    /// Lecture du scanner démo sur action explicite (DEBUG, MJ1) : rend le scénario `-JOLENE_DEMO_QR` (deux détections du
    /// même payload, un payload illisible, ou un refus de la caméra).
    func lireQRDemo() {
        let lire = element("pointage-scanner-demo-lire")
        require("Le bouton de lecture du scanner démo est touchable") { lire.exists && lire.isHittable }
        tap("pointage-scanner-demo-lire")
    }

    func accepterConsentement() {
        let feuille = element("gps-consent-sheet")
        require("La feuille de consentement est affichée", timeout: 30) { feuille.exists }
        let accepter = element("gps-consent-accepter")
        if !visible(accepter) { scrollTo(accepter, in: feuille) }
        tap("gps-consent-accepter")
        require("La feuille de consentement est fermée", timeout: 30) { !self.element("gps-consent-sheet").exists }
    }

    /// Interrupteur SwiftUI : touché sur sa poignée (bord de fin), le libellé seul ne le bascule pas.
    func basculer(_ interrupteur: XCUIElement) {
        require("L'interrupteur est actif") { interrupteur.isEnabled && self.visible(interrupteur) }
        let poignee = interrupteur.switches.firstMatch
        let cible = poignee.exists ? poignee : interrupteur
        cible.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    func libelle(_ identifiant: String) -> String {
        element(identifiant).label
    }

    /// Lectures des compteurs démo faites depuis le lancement (valeur d'accessibilité de `pointage-demo-scans`).
    func lecturesCompteurs() -> Int {
        Int(element("pointage-demo-scans").value as? String ?? "") ?? 0
    }

    /// Compteurs démo relus APRÈS l'action qui précède (revue fraîche de T4b, m3) : `pointage-demo-relire` touché, puis une
    /// lecture nouvelle exigée avant de rendre le libellé.
    func compteursRelus(dans ecran: XCUIElement) -> String {
        let avant = lecturesCompteurs()
        let relire = element("pointage-demo-relire")
        require("Le bouton de relecture des compteurs démo est rendu") { relire.exists }
        scrollTo(relire, in: ecran)
        tap("pointage-demo-relire")
        require("Compteurs relus après l'action") { self.lecturesCompteurs() > avant }
        return element("pointage-demo-scans").label
    }

    func valeur(_ identifiant: String) -> String? {
        let champ = element(identifiant)
        let texte = champ.value as? String
        // Un champ vide expose son indication (`placeholderValue`) comme valeur.
        return texte == champ.placeholderValue ? "" : texte
    }
}
