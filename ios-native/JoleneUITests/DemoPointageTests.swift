import XCTest

/// Pointage démo (lot 2, T4b ; blueprint §3 T4b, décisions 2 à 7) sur iPhone, iPad portrait et iPad paysage : Profil ›
/// Mon espace › Mes présences, onglet Aujourd'hui, monde `DemoPointageGateway` (`demo-presences.json`, horloge fixée
/// 2026-11-02T00:00:00Z, soit lundi 2 novembre 01h00 à Paris ; codes affichés : mission a `123456`, mission b `654321` ;
/// `100001` → refus du code inconnu ; consentement GPS NULL au lancement). Les valeurs attendues sont celles que
/// `PointageModelTests`, `ConsentementGpsModelTests`, `PointageSaisieTests` et `LibellesPresencesTests` (JoleneCore)
/// affirment : un écart entre l'écran et le cœur fait échouer l'un des deux.
///
/// Preuves « aucune requête » et « une seule fois » : `pointage-demo-scans` (DEBUG) lit les scans appliqués par le monde
/// démo et ceux qui portent une position (« N scan · M avec position »), sans jamais afficher de coordonnée. Il est relu à
/// chaque issue du pointage et sur l'action explicite `pointage-demo-relire` ; sa valeur d'accessibilité compte les
/// lectures : chaque affirmation de compte suit une lecture postérieure à l'action (`compteursRelus`, revue fraîche de
/// T4b, m3 ; seconde revue, m8 : « un seul scan » compris), jamais un compteur resté celui du lancement ou relu à
/// l'instant du succès. Scénarios DEBUG : `-JOLENE_DEMO_GPS refuse | reduite`, `-JOLENE_DEMO_RESEAU horsligne`,
/// `-JOLENE_DEMO_QR 123456 | illisible | refus` (lecture sur l'action explicite `pointage-scanner-demo-lire`, seconde revue
/// fraîche, MJ1), `-JOLENE_DEMO_SCENARIO scan-incertain`. Aucune attente par délai fixe : tout passe par `require`.
/// Étapes communes : `DemoPointageUITestCase` ; états d'erreur et reprise : `DemoPointageEtatsTests`.
///
/// Identifiants : `pointage-zone-<m>`, `pointage-code-<m>`, `pointage-qr-<m>`, `pointage-submit-<m>`,
/// `pointage-message-<m>`, `pointage-qr-message-<m>`, `pointage-position-<m>`, `pointage-en-service-<m>`,
/// `pointage-segment-<m>-<n>`, `pointage-scanner`, `pointage-scanner-message`, `pointage-scanner-fermer`,
/// `pointage-scanner-demo-lire`, `gps-consent-sheet`, `gps-consent-accepter`, `gps-consent-refuser`, `gps-consent-retour`,
/// `bandeau-sans-gps`, `hors-ligne-bandeau`, `profil-gps-consentement`, `profil-gps-explication`, `profil-gps-retour`,
/// `pointage-demo-relire`.
final class DemoPointageTests: DemoPointageUITestCase {
    // MARK: - Saisie, consentement, refus verbatim, ouverture puis fermeture

    func testConsentementAccepteRefusVerbatimPuisOuvertureEtFermeture() throws {
        launchDemo()
        connexionDemo()
        let ecran = ouvrirMesPresences()
        XCTAssertFalse(element("bandeau-sans-gps").exists, "consentement NULL : aucun bandeau")
        XCTAssertFalse(element("hors-ligne-bandeau").exists)
        require("Aucun scan au lancement") { self.element("pointage-demo-scans").label == "0 scan · 0 avec position" }

        // Code inconnu : la feuille de consentement s'ouvre d'abord (premier pointage, consentement NULL).
        saisir("100001", mission: Self.missionA, dans: ecran)
        appuyerSurPointer(Self.missionA, dans: ecran)
        let feuille = element("gps-consent-sheet")
        require("La feuille de consentement verbatim s'ouvre avant le premier pointage") { self.containerVisible(feuille) }
        for texte in ["Autorisation de géolocalisation",
                      "Jolene utilise votre position pour vérifier que vous êtes bien dans l'établissement lors du pointage.",
                      "Ce que nous faisons :", "Relevé ponctuel au moment du clic sur « Pointer »",
                      "Ce que nous ne faisons pas :", "Aucun traçage en arrière-plan",
                      "Base légale : consentement (Art. 6.1.a RGPD). Vous pouvez retirer votre consentement à tout moment depuis votre profil."] {
            XCTAssertTrue(feuille.staticTexts.matching(NSPredicate(format: "label == %@", texte)).firstMatch.exists, "« \(texte) » verbatim")
        }
        record("\(proofPrefix)-pointage-consentement")
        accepterConsentement()
        require("Consentement enregistré, retour du web (l.76)") { self.libelle("gps-consent-retour").contains("Consentement GPS enregistré.") }
        require("Refus du code inconnu, surcharge vouvoyée de la décision 6") {
            self.libelle("pointage-message-\(Self.missionA)").contains(Self.codeInvalide)
        }
        XCTAssertEqual(valeur("pointage-code-\(Self.missionA)"), "100001", "un refus garde le code saisi (comme le web)")
        XCTAssertEqual(compteursRelus(dans: ecran), "0 scan · 0 avec position", "un refus n'enregistre aucun scan (relu après le refus)")
        record("\(proofPrefix)-pointage-refus")

        // Code affiché de la mission a : consentement déjà donné, aucune feuille ; segment ouvert, position jointe.
        saisir("123456", mission: Self.missionA, dans: ecran)
        appuyerSurPointer(Self.missionA, dans: ecran)
        require("Arrivée enregistrée et relue", timeout: 30) { self.libelle("pointage-message-\(Self.missionA)").contains(Self.segmentOuvert) }
        XCTAssertFalse(element("gps-consent-sheet").exists, "consentement relu vrai : aucune seconde feuille")
        let segment = element("pointage-segment-\(Self.missionA)-1")
        require("Segment 1 en cours") { segment.exists && segment.label.contains("Segment 1") && segment.label.contains("→ en cours") }
        XCTAssertTrue(segment.label.contains("01h00"), "début du segment à l'heure du scan (horloge démo, Paris)")
        require("En service depuis l'ouverture") { self.libelle("pointage-en-service-\(Self.missionA)").contains("En service depuis 01h00") }
        XCTAssertEqual(valeur("pointage-code-\(Self.missionA)"), "", "champ vidé après un succès (web l.144)")
        XCTAssertEqual(compteursRelus(dans: ecran), "1 scan · 1 avec position",
                       "un scan appliqué, avec position (consentement donné), relu après le succès")
        record("\(proofPrefix)-pointage-ouverture")

        // Mission b (segment ouvert depuis la veille) : départ, segment fermé.
        saisir("654321", mission: Self.missionB, dans: ecran)
        XCTAssertTrue(libelle("pointage-submit-\(Self.missionB)").contains("Pointer mon départ / pause"), "libellé du web (l.107)")
        appuyerSurPointer(Self.missionB, dans: ecran)
        require("Départ enregistré et relu", timeout: 30) { self.libelle("pointage-message-\(Self.missionB)").contains(Self.segmentFerme) }
        let segmentB = element("pointage-segment-\(Self.missionB)-1")
        require("Segment de la mission b fermé") { segmentB.exists && segmentB.label.contains("23h00 → 01h00") }
        XCTAssertEqual(compteursRelus(dans: ecran), "2 scan · 2 avec position", "deux scans appliqués, chacun une fois (relu)")
        record("\(proofPrefix)-pointage-fermeture")
    }

    // MARK: - Consentement refusé

    func testConsentementRefusePointeSansPositionEtAfficheLeBandeau() throws {
        launchDemo()
        connexionDemo()
        let ecran = ouvrirMesPresences()
        saisir("654321", mission: Self.missionB, dans: ecran)
        appuyerSurPointer(Self.missionB, dans: ecran)
        let refuser = element("gps-consent-refuser")
        require("La feuille de consentement est affichée") { self.element("gps-consent-sheet").exists }
        if !visible(refuser) { scrollTo(refuser, in: element("gps-consent-sheet")) }
        tap("gps-consent-refuser")
        require("Un refus ne bloque jamais le pointage", timeout: 30) {
            self.libelle("pointage-message-\(Self.missionB)").contains(Self.segmentFerme)
        }
        require("Bandeau du pointage sans localisation (verbatim, tutoiement du web)") {
            self.libelle("bandeau-sans-gps").contains("Pointage sans localisation activé. Lorsque tu pointeras, l'établissement validera manuellement ta présence.")
        }
        XCTAssertTrue(libelle("gps-consent-retour").contains("Pointage sans GPS activé"), "retour du web (l.95)")
        XCTAssertEqual(compteursRelus(dans: ecran), "1 scan · 0 avec position", "scan appliqué une fois, sans aucune coordonnée (relu)")
        record("\(proofPrefix)-pointage-sans-gps")
    }

    // MARK: - Localisation de l'appareil

    func testLocalisationRefuseeParLAppareilPointeSansCoordonnees() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_GPS", "refuse"])
        connexionDemo()
        let ecran = ouvrirMesPresences()
        saisir("123456", mission: Self.missionA, dans: ecran)
        appuyerSurPointer(Self.missionA, dans: ecran)
        accepterConsentement()
        require("Pointage réussi malgré le refus de l'appareil", timeout: 30) {
            self.libelle("pointage-message-\(Self.missionA)").contains(Self.segmentOuvert)
        }
        XCTAssertEqual(compteursRelus(dans: ecran), "1 scan · 0 avec position", "aucun champ de coordonnée dans le scan enregistré (relu)")
        XCTAssertFalse(element("bandeau-sans-gps").exists, "consentement donné : le bandeau ne suit qu'un refus du consentement")
        record("\(proofPrefix)-pointage-gps-refuse")
    }

    func testPrecisionReduiteNEnvoieAucunePositionEtAfficheLEncart() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_GPS", "reduite"])
        connexionDemo()
        let ecran = ouvrirMesPresences()
        saisir("123456", mission: Self.missionA, dans: ecran)
        appuyerSurPointer(Self.missionA, dans: ecran)
        accepterConsentement()
        require("Pointage réussi en précision réduite", timeout: 30) {
            self.libelle("pointage-message-\(Self.missionA)").contains(Self.segmentOuvert)
        }
        require("Encart « Position exacte » (décision 5)") {
            self.libelle("pointage-position-\(Self.missionA)").contains("activez « Position exacte » pour Jolene")
        }
        XCTAssertEqual(compteursRelus(dans: ecran), "1 scan · 0 avec position", "précision réduite : aucune coordonnée")
        record("\(proofPrefix)-pointage-precision-reduite")
    }

    // MARK: - Hors ligne

    func testHorsLigneDesactiveLePointageSansAucunEnvoi() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_RESEAU", "horsligne"])
        connexionDemo()
        let ecran = ouvrirMesPresences()
        require("Bandeau hors ligne du web") { self.libelle("hors-ligne-bandeau").contains("Pas de connexion internet") }
        saisir("123456", mission: Self.missionA, dans: ecran)
        let bouton = element("pointage-submit-\(Self.missionA)")
        scrollTo(bouton, in: ecran)
        XCTAssertFalse(bouton.isEnabled, "hors ligne : bouton désactivé, aucun scan mis en file (décision 2)")
        XCTAssertFalse(element("pointage-qr-\(Self.missionA)").isEnabled, "hors ligne : scanner désactivé")
        XCTAssertFalse(element("gps-consent-sheet").exists)
        XCTAssertEqual(compteursRelus(dans: ecran), "0 scan · 0 avec position", "aucune action dans le monde démo (relu après la saisie)")
        record("\(proofPrefix)-pointage-hors-ligne")
    }

    // MARK: - QR

    func testQRDetecteDeuxFoisNEnvoieQuUnScan() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_QR", "123456"])
        connexionDemo()
        let ecran = ouvrirMesPresences()
        ouvrirScanner(Self.missionA, dans: ecran)
        record("\(proofPrefix)-pointage-qr-scanner")
        // Lecture démo sur action explicite (MJ1) : deux détections du même QR, un seul code remis, la feuille se ferme.
        lireQRDemo()
        accepterConsentement()
        require("QR lu et pointage enregistré", timeout: 30) {
            self.libelle("pointage-message-\(Self.missionA)").contains(Self.segmentOuvert)
        }
        XCTAssertFalse(element("pointage-scanner").exists, "feuille du scanner fermée après la remise")
        XCTAssertEqual(compteursRelus(dans: ecran), "1 scan · 1 avec position",
                       "un seul scan malgré deux détections, relu après le succès (un second envoi s'y verrait)")
        XCTAssertFalse(element("pointage-segment-\(Self.missionA)-2").exists, "un seul segment")
        record("\(proofPrefix)-pointage-qr")
    }

    func testQRIllisibleGardeLaCameraPuisSaisieManuelle() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_QR", "illisible"])
        connexionDemo()
        let ecran = ouvrirMesPresences()
        ouvrirScanner(Self.missionA, dans: ecran)
        lireQRDemo()
        require("QR non reconnu : message du web, caméra conservée", timeout: 30) {
            self.libelle("pointage-scanner-message").contains("QR non reconnu. Saisissez le code à 6 chiffres.")
        }
        XCTAssertTrue(element("pointage-scanner").exists, "la feuille du scanner reste ouverte")
        XCTAssertTrue(text("Scanner le QR de pointage").exists, "titre du dialogue web (l.233)")
        record("\(proofPrefix)-pointage-qr-illisible")
        tap("pointage-scanner-fermer")
        require("Feuille fermée, saisie manuelle disponible") {
            !self.element("pointage-scanner").exists && self.element("pointage-code-\(Self.missionA)").exists
        }
        XCTAssertFalse(element("gps-consent-sheet").exists, "aucun code remis : rien n'est demandé")
        XCTAssertEqual(compteursRelus(dans: ecran), "0 scan · 0 avec position", "relu après la fermeture du scanner")
    }

    func testRefusDeLaCameraRendLaSaisieManuelle() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_QR", "refus"])
        connexionDemo()
        let ecran = ouvrirMesPresences()
        ouvrirScanner(Self.missionA, dans: ecran)
        // Refus de la caméra rendu sur action explicite (MJ1) : la feuille se ferme, la saisie manuelle reste.
        lireQRDemo()
        require("Caméra refusée : message du web (l.192)", timeout: 30) {
            self.libelle("pointage-qr-message-\(Self.missionA)").contains("Scan impossible. Saisissez le code manuellement.")
        }
        XCTAssertFalse(element("pointage-scanner").exists)
        record("\(proofPrefix)-pointage-camera-refusee")
        saisir("123456", mission: Self.missionA, dans: ecran)
        appuyerSurPointer(Self.missionA, dans: ecran)
        accepterConsentement()
        require("La saisie manuelle pointe", timeout: 30) {
            self.libelle("pointage-message-\(Self.missionA)").contains(Self.segmentOuvert)
        }
    }

    // MARK: - Réponse perdue

    func testScanIncertainReconcilieParRelectureSansSecondScan() throws {
        launchDemo(extraArguments: ["-JOLENE_DEMO_SCENARIO", "scan-incertain"])
        connexionDemo()
        let ecran = ouvrirMesPresences()
        saisir("123456", mission: Self.missionA, dans: ecran)
        appuyerSurPointer(Self.missionA, dans: ecran)
        accepterConsentement()
        // Réponse perdue après application : la vérification (« Vérification du pointage… », transitoire, prouvée par
        // `PointageModelTests`) se conclut par la relecture des preuves, sans renvoi.
        require("Pointage enregistré par réconciliation", timeout: 45) {
            self.libelle("pointage-message-\(Self.missionA)").contains(Self.segmentOuvert)
        }
        XCTAssertEqual(compteursRelus(dans: ecran), "1 scan · 1 avec position",
                       "un seul scan appliqué, relu après la réconciliation : jamais de renvoi")
        XCTAssertTrue(element("pointage-segment-\(Self.missionA)-1").exists)
        XCTAssertFalse(element("pointage-segment-\(Self.missionA)-2").exists, "un seul segment créé")
        record("\(proofPrefix)-pointage-reconcilie")
    }

    // MARK: - Profil : retrait et réactivation (correction 15)

    func testConsentementRetireEtReactiveDepuisLeProfil() throws {
        launchDemo()
        connexionDemo()
        ouvrirProfil()
        let interrupteur = element("profil-gps-consentement")
        amenerDansLeProfil(interrupteur, etats: ["profil-gps-chargement", "profil-gps-erreur", "profil-gps-consentement"])
        require("Consentement lu (NULL : éteint)") { interrupteur.isEnabled }
        XCTAssertEqual(interrupteur.value as? String, "0", "NULL n'est jamais présenté comme un consentement donné")
        XCTAssertTrue(text("Consentement GPS").exists, "titre du web (SectionPreferences.tsx l.129)")
        XCTAssertEqual(libelle("profil-gps-explication"),
                       "Sans GPS, tes pointages seront validés manuellement par l'établissement — rien à faire de ton côté.")
        record("\(proofPrefix)-profil-gps-nul")

        // Premier consentement (NULL → activé, revue fraîche de T4b, M2) : la feuille verbatim d'abord, comme au premier
        // pointage (finalité, durée de conservation, base légale), puis la RPC, la relecture et l'audit.
        basculer(interrupteur)
        let feuille = element("gps-consent-sheet")
        require("Activer depuis NULL présente la feuille de consentement verbatim") { self.containerVisible(feuille) }
        XCTAssertTrue(feuille.staticTexts.matching(NSPredicate(format: "label == %@", "Autorisation de géolocalisation")).firstMatch.exists)
        XCTAssertTrue(feuille.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Base légale : consentement")).firstMatch.exists)
        record("\(proofPrefix)-profil-gps-feuille")
        accepterConsentement()
        require("Premier consentement relu au serveur") {
            (interrupteur.value as? String) == "1" && self.libelle("profil-gps-retour").contains("Consentement GPS enregistré.")
        }
        XCTAssertEqual(libelle("profil-gps-explication"), "Ta position sera capturée uniquement au moment de l'arrivée et du départ.")
        record("\(proofPrefix)-profil-gps-premier-consentement")

        basculer(interrupteur)
        require("Retrait relu au serveur") {
            (interrupteur.value as? String) == "0"
                && self.libelle("profil-gps-retour").contains("Consentement GPS retiré — tes pointages seront validés manuellement par l'établissement.")
        }
        record("\(proofPrefix)-profil-gps-retire")

        // Réactivation (faux → vrai) : la personne a déjà répondu, aucune feuille.
        basculer(interrupteur)
        require("Réactivation relue au serveur") {
            (interrupteur.value as? String) == "1" && self.libelle("profil-gps-retour").contains("Consentement GPS activé.")
        }
        XCTAssertFalse(element("gps-consent-sheet").exists, "réactivation : aucune seconde feuille")
        record("\(proofPrefix)-profil-gps-active")

        basculer(interrupteur)
        require("Second retrait relu au serveur") {
            (interrupteur.value as? String) == "0" && self.libelle("profil-gps-retour").contains("Consentement GPS retiré")
        }

        // Les présences lisent le même consentement : bandeau du refus, et le pointage part sans feuille.
        tapDansProfil("profil-presences")
        let ecran = element("presences-screen")
        require("La page Présences est chargée", timeout: 30) {
            self.containerVisible(ecran) && self.element("presences-tab-aujourdhui").exists && !self.element("presences-loading").exists
        }
        require("Bandeau du pointage sans localisation") { self.element("bandeau-sans-gps").exists }
        saisir("123456", mission: Self.missionA, dans: ecran)
        appuyerSurPointer(Self.missionA, dans: ecran)
        require("Pointage sans position, sans feuille de consentement", timeout: 30) {
            self.libelle("pointage-message-\(Self.missionA)").contains(Self.segmentOuvert)
        }
        XCTAssertFalse(element("gps-consent-sheet").exists)
        XCTAssertEqual(compteursRelus(dans: ecran), "1 scan · 0 avec position")
    }
}
