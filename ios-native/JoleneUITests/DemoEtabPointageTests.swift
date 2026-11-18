import CoreImage
import XCTest

/// Code de pointage rotatif de l'espace établissement en démo (lot 5, T7 ; `docs/mobile-swift/LOT5_PLAN.md` §3 T7, D4,
/// D5) sur iPhone, iPad portrait et iPad paysage (`JOLENE_UI_ORIENTATION`, `proofPrefix`) : destination `.pointage` du
/// registre ouverte depuis le détail de mission (T5), code relu `123 456` (M4), plein écran dont le QR est **décodé dans
/// le test** (`CIDetector` sur la capture de l'élément) en la valeur affichée, puis, la cadence accélérée
/// (`-JOLENE_POLL_INTERVAL 4`), l'état relu après le scan d'arrivée du soignant (`100 002`, segment en cours, départ
/// attendu) affiché et décodé sans aucune action ; code masqué faute de contrat signé (M5) et hors créneau avec les
/// pointages enregistrés (M6). Aucune requête réseau. Vérifié par la CI seulement (aucun simulateur en local), dans
/// l'éclat « lot3-profil-photo » de `ios-swift-ci.yml`, hors du socle.
///
/// Ce que ces tests prouvent (niveau 2), et seulement cela : l'écran rendu par la destination `.pointage` est celui de
/// T7, sur les réponses serveur enregistrées de la démo, et son QR encode la valeur affichée. Cadence, arrêt en
/// arrière-plan, backoff, epoch, permission et écran maintenu allumé sont prouvés au niveau 1 (`CodeRotatifModelTests`,
/// `IdleTimerControllerTests`, `DemoEtabPointageGatewayTests`, `SupabaseEtabPointageGatewayTests`) ; la veille réelle et
/// le scan par un second appareil relèvent de la recette appareil (niveau 5).
final class DemoEtabPointageTests: JoleneUITestCase {
    private let espaceEtablissement = ["-JOLENE_DEMO_ESPACE", "etablissement"]

    func testCodeReluQRDecodeEnPleinEcranPuisEtatReluApresLeScan() throws {
        launchDemo(extraArguments: espaceEtablissement + ["-JOLENE_POLL_INTERVAL", "4"])
        connecter(email: DemoEtabSessionTests.emailEtablissement)
        ouvrirPointage(mission: "demo-etab-m04", filtre: "ASSIGNEE", intitule: "Démonstration · Nuit en cours")

        let code = element("etab-pointage-code")
        XCTAssertEqual(code.label, "123 456", "code relu au serveur (réponse démo enregistrée)")
        XCTAssertTrue(element("etab-pointage-prochain").label.hasSuffix("Prochain pointage attendu : Arrivée."),
                      element("etab-pointage-prochain").label)
        XCTAssertEqual(element("etab-pointage-creneau").label, "Créneau 1/1 · lundi 2 novembre 2026 à 00:00 → 08:00")
        XCTAssertTrue(element("etab-pointage-qr").exists)
        XCTAssertFalse(element("placeholder-etab-pointage").exists, "écran de T7, jamais le provisoire")
        record("\(proofPrefix)-etab-pointage-code")

        scrollTo(element("etab-pointage-plein-ecran"), in: element("etab-pointage-scroll"))
        tap("etab-pointage-plein-ecran")
        let vue = element("etab-pointage-plein-ecran-vue")
        require("Le code est présenté en plein écran") { vue.exists && self.element("etab-pointage-plein-ecran-qr").exists }
        XCTAssertFalse(element("etab-pointage-scroll").exists, "le plein écran remplace l'écran du code")
        let codePleinEcran = element("etab-pointage-plein-ecran-code")
        let affiche = codePleinEcran.label
        let lu = try XCTUnwrap(decoderQR(element("etab-pointage-plein-ecran-qr")), "QR du plein écran illisible")
        if codePleinEcran.label == affiche {
            XCTAssertEqual(lu, affiche.replacingOccurrences(of: " ", with: ""), "le QR encode la valeur affichée (D4)")
        }
        XCTAssertTrue(["123456", "100002"].contains(lu), lu)
        record("\(proofPrefix)-etab-pointage-plein-ecran")

        require("L'état relu après le scan d'arrivée est affiché sans action", timeout: 40) { codePleinEcran.label == "100 002" }
        XCTAssertEqual(try XCTUnwrap(decoderQR(element("etab-pointage-plein-ecran-qr"))), "100002",
                       "le QR suit la dernière valeur relue, jamais une valeur calculée")
        record("\(proofPrefix)-etab-pointage-plein-ecran-rotation")

        tap("etab-pointage-fermer")
        require("Le plein écran est fermé") { !vue.exists && self.element("etab-pointage-code").exists }
        XCTAssertEqual(element("etab-pointage-code").label, "100 002")
        XCTAssertTrue(element("etab-pointage-segment-en-cours").exists, "segment en cours")
        XCTAssertTrue(element("etab-pointage-prochain").label.hasSuffix("Prochain pointage attendu : Départ ou pause."),
                      element("etab-pointage-prochain").label)
        let segment = element("etab-pointage-segment-0")
        scrollTo(segment, in: element("etab-pointage-scroll"))
        XCTAssertTrue(segment.label.contains("Segment 1 · 02/11/2026 00h58 → en cours"), segment.label)
        record("\(proofPrefix)-etab-pointage-segment-ouvert")
    }

    func testCodeMasqueSansContratSigneEtHorsCreneau() throws {
        launchDemo(extraArguments: espaceEtablissement)
        connecter(email: DemoEtabSessionTests.emailEtablissement)

        ouvrirPointage(mission: "demo-etab-m05", filtre: "ASSIGNEE", intitule: "Démonstration · Contrat à signer")
        XCTAssertEqual(element("etab-pointage-masque-titre").label, "Code masqué — contrat non signé")
        XCTAssertEqual(element("etab-pointage-masque-motif").label,
                       "Le code d’arrivée sera disponible lorsque le contrat aura été signé par les deux parties.")
        for absent in ["etab-pointage-code", "etab-pointage-qr", "etab-pointage-plein-ecran"] {
            XCTAssertFalse(element(absent).exists, "\(absent) : aucun code sans contrat signé")
        }
        record("\(proofPrefix)-etab-pointage-contrat")
        revenirALaListe()

        ouvrirPointage(mission: "demo-etab-m06", filtre: "EN_COURS", intitule: "Démonstration · Mission active")
        XCTAssertEqual(element("etab-pointage-masque-titre").label, "Code masqué hors créneau")
        XCTAssertEqual(element("etab-pointage-masque-motif").label,
                       "Le code sera affiché 15 minutes avant le créneau 2/2, le mardi 3 novembre 2026 à 07:00.")
        XCTAssertFalse(element("etab-pointage-qr").exists)
        let segment = element("etab-pointage-segment-0")
        scrollTo(segment, in: element("etab-pointage-scroll"))
        XCTAssertTrue(segment.label.contains("Segment 1 · 01/11/2026 07h02 → 01/11/2026 15h01"), segment.label)
        record("\(proofPrefix)-etab-pointage-hors-creneau")
    }

    // MARK: Étapes

    private func ouvrirPointage(mission id: String, filtre: String, intitule: String) {
        if !containerVisible(element("etab-missions-screen")) { tabButton("tab-etab-missions", label: "Missions").tap() }
        require("La liste des missions est relue") {
            self.containerVisible(self.element("etab-missions-screen")) && self.element("etab-missions-count").exists
        }
        tap("etab-missions-filtre-\(filtre)")
        let carte = element("etab-mission-card-\(id)")
        require("La mission filtrée est listée") { carte.exists }
        scrollTo(carte, in: element("etab-missions-scroll"))
        carte.tap()
        require("Le détail de la mission est relu") { self.element("etab-mission-titre").label == intitule }
        let lien = element("etab-mission-lien-pointage")
        scrollTo(lien, in: element("etab-mission-detail"))
        XCTAssertEqual(lien.label.contains("sur jolene.app"), false, "T7 livrée : écran natif, plus la page web")
        lien.tap()
        require("Le code de pointage de la mission est relu") {
            self.containerVisible(self.element("etab-pointage-screen")) && !self.element("etab-pointage-loading").exists
                && (self.element("etab-pointage-code").exists || self.element("etab-pointage-masque").exists)
        }
    }

    private func revenirALaListe() {
        for _ in 0..<3 where !containerVisible(element("etab-missions-screen")) {
            let retour = app.navigationBars.buttons.firstMatch
            require("Le bouton retour est disponible") { self.visible(retour) }
            retour.tap()
        }
        require("La liste des missions est affichée") { self.containerVisible(self.element("etab-missions-screen")) }
    }

    /// QR de l'élément relu sur sa capture (`CIDetector`, précision haute) ; `nil` si aucun QR n'est lu.
    private func decoderQR(_ element: XCUIElement) -> String? {
        guard element.exists, let image = CIImage(image: element.screenshot().image),
              let detecteur = CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(options: [.useSoftwareRenderer: true]),
                                         options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else { return nil }
        return detecteur.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
}
