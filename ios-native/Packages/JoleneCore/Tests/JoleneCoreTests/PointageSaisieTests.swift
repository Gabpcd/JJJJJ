import XCTest
@testable import JoleneCore

/// Saisie du pointage (lot 2, T4b) : lecture du QR (une seule remise par session de scanner, payload accepté
/// seulement s'il vaut six chiffres après `trim`, décision 3 ; tests web `PointageRotatifSoignant.qr.test.tsx`), état
/// du réseau suivi par `NetworkPathPort` (hors ligne : bouton désactivé, décision 2), scénarios DEBUG du monde démo
/// (`-JOLENE_DEMO_GPS`, `-JOLENE_DEMO_RESEAU`, `-JOLENE_DEMO_QR`, `-JOLENE_DEMO_SCENARIO`) et relecture des présences
/// après un scan (revue fraîche de T4a, m1 ; web l.145-149).
@MainActor
final class PointageSaisieTests: XCTestCase {
    // MARK: - QR

    func testDeuxDetectionsDuMemeQRNeRemettentQuUnCode() {
        var session = SessionScanQR()
        XCTAssertEqual(session.recevoir("123456"), .code("123456"))
        XCTAssertEqual(session.recevoir("123456"), .ignore, "une seule remise par session (anti-rejeu de 2 min, l.55710-55713)")
        XCTAssertEqual(session.recevoir("654321"), .ignore, "un autre QR après la remise est ignoré aussi")
        XCTAssertEqual(session.remis, "123456")
    }

    func testPayloadIllisibleSignaleUneFoisPuisLaCameraContinue() {
        var session = SessionScanQR()
        XCTAssertEqual(session.recevoir("https://exemple.invalid/qr"), .illisible)
        XCTAssertEqual(session.recevoir("https://exemple.invalid/qr"), .ignore, "même QR étranger : un seul message")
        XCTAssertEqual(session.recevoir("abc123def456"), .illisible, "six chiffres épars : refusé (plus strict que le web, l.186)")
        XCTAssertNil(session.remis)
        XCTAssertEqual(session.recevoir(" 123456\n"), .code("123456"), "bords blancs retirés, puis remise")
    }

    func testScenarioQRDemo() {
        XCTAssertEqual(ScenarioQRDemo(arguments: []), .lecture("123456"), "défaut : QR de la mission a")
        XCTAssertEqual(ScenarioQRDemo(arguments: ["-JOLENE_DEMO_QR", "654321"]), .lecture("654321"))
        XCTAssertEqual(ScenarioQRDemo(arguments: ["-JOLENE_DEMO_QR", "illisible"]), .lecture(ScenarioQRDemo.payloadIllisible))
        XCTAssertNil(PayloadQR.codePointage(depuis: ScenarioQRDemo.payloadIllisible))
        XCTAssertEqual(ScenarioQRDemo(arguments: ["-JOLENE_DEMO_QR", "refus"]), .refus)
        XCTAssertEqual(ScenarioQRDemo.lecture("123456").detections, ["123456", "123456"], "deux détections du même QR")
        XCTAssertEqual(ScenarioQRDemo.refus.detections, [])
    }

    // MARK: - Scénarios de l'appareil démo

    func testScenariosGpsReseauEtPointageDepuisLesArguments() {
        XCTAssertEqual(ScenarioGpsDemo(arguments: []), .accorde)
        XCTAssertEqual(ScenarioGpsDemo(arguments: ["-JOLENE_DEMO_GPS", "refuse"]), .refuse)
        XCTAssertEqual(ScenarioGpsDemo(arguments: ["-JOLENE_DEMO_GPS", "reduite"]), .reduite)
        XCTAssertEqual(ScenarioGpsDemo(arguments: ["-JOLENE_DEMO_GPS", "inconnu"]), .accorde)
        XCTAssertEqual(ScenarioReseauDemo(arguments: []), .enLigne)
        XCTAssertEqual(ScenarioReseauDemo(arguments: ["-JOLENE_DEMO_RESEAU", "horsligne"]), .horsLigne)
        XCTAssertEqual(DemoPointageGateway.Scenario(arguments: []), .normal)
        XCTAssertEqual(DemoPointageGateway.Scenario(arguments: ["-JOLENE_DEMO_SCENARIO", "scan-incertain"]), .scanIncertain)
        XCTAssertEqual(DemoPointageGateway.Scenario(arguments: ["-JOLENE_DEMO_SCENARIO", "upload-incertain"]), .normal,
                       "scénario d'un autre domaine")
    }

    // MARK: - Réseau

    func testEtatReseauSuitLePort() async {
        let hors = EtatReseauModel()
        XCTAssertNil(hors.enLigne)
        XCTAssertFalse(hors.horsLigne, "inconnu : aucun bandeau supposé")
        await hors.suivre(DemoNetworkPathPort(scenario: .horsLigne))
        XCTAssertEqual(hors.enLigne, false)
        XCTAssertTrue(hors.horsLigne)

        let en = EtatReseauModel()
        await en.suivre(DemoNetworkPathPort(scenario: .enLigne))
        XCTAssertEqual(en.enLigne, true)
        XCTAssertFalse(en.horsLigne)
    }

    func testEtatReseauSuitLesChangements() async {
        struct PortChangeant: NetworkPathPort {
            func estEnLigne() async -> Bool { true }
            func changements() -> AsyncStream<Bool> {
                AsyncStream { suite in
                    suite.yield(true)
                    suite.yield(false)
                    suite.finish()
                }
            }
        }
        let modele = EtatReseauModel()
        await modele.suivre(PortChangeant())
        XCTAssertEqual(modele.enLigne, false, "dernier état reçu")
    }

    // MARK: - Relecture des présences après un scan (m1)

    func testPresencesReluesApresUnScanEnregistre() {
        XCTAssertTrue(PointageRules.rechargerPresencesApres(.enregistre(.ouverture)))
        XCTAssertTrue(PointageRules.rechargerPresencesApres(.enregistreSurAutreMission(.fermeture, missionId: "m-2")),
                      "le bloc de la mission pointée change d'état (consigne T4b)")
        for issue: PointageModel.Issue in [.refuse(message: "x", codeInvalide: false), .horsLigne, .verification, .nonRecu,
                                            .recuEnCours, .suiviIllisible, .erreur("x")] {
            XCTAssertFalse(PointageRules.rechargerPresencesApres(issue), "\(issue) : le web ne relit qu'après un succès (l.145-149)")
        }
    }

    // MARK: - Contenu de la zone de pointage (revue fraîche de T4b, M1)

    func testZoneDerivee() {
        let pret = EtatPointage(statut: "ASSIGNEE", prochainTypeScan: .ouverture, nbScans: 0, segmentOuvert: false)
        let termine = EtatPointage(statut: "TERMINEE")
        XCTAssertEqual(AffichageZonePointage(chargement: .chargement, sessionExpiree: false), .chargement)
        XCTAssertEqual(AffichageZonePointage(chargement: .indisponible("Accès interdit"), sessionExpiree: false), .indisponible("Accès interdit"))
        XCTAssertEqual(AffichageZonePointage(chargement: .pret(termine), sessionExpiree: false), .statutIndisponible)
        XCTAssertEqual(AffichageZonePointage(chargement: .pret(pret), sessionExpiree: false), .saisie(pret))
        for chargement: PointageModel.Chargement in [.chargement, .indisponible("Votre session a expiré. Reconnectez-vous."), .pret(pret)] {
            XCTAssertEqual(AffichageZonePointage(chargement: chargement, sessionExpiree: true), .sessionAVerifier,
                           "\(chargement) : session expirée (scan, réconciliation, état ou consentement) → bloc du lot 1")
        }
    }

    // MARK: - Diffusion du dernier état du réseau (revue fraîche de T4b, m5)

    /// Valeurs d'un flux terminé, dans l'ordre.
    private func valeurs(_ flux: AsyncStream<Bool>) async -> [Bool] {
        var vues: [Bool] = []
        for await valeur in flux { vues.append(valeur) }
        return vues
    }

    func testDiffusionRendLEtatCourantPuisChaqueChangement() async {
        let diffusion = DiffusionDernierEtat<Bool>()
        XCTAssertNil(diffusion.lire())
        let avant = diffusion.flux()
        diffusion.recevoir(true)
        let apres = diffusion.flux()
        diffusion.recevoir(true)
        diffusion.recevoir(false)
        XCTAssertEqual(diffusion.lire(), false)
        diffusion.terminer()
        let vuesAvant = await valeurs(avant)
        let vuesApres = await valeurs(apres)
        XCTAssertEqual(vuesAvant, [true, false], "état inconnu : rien d'envoyé à l'abonnement ; doublon ignoré")
        XCTAssertEqual(vuesApres, [true, false], "abonnement après un état connu : cet état d'abord")
    }

    func testDiffusionDesabonneUnFluxAbandonne() async {
        let diffusion = DiffusionDernierEtat<Bool>()
        var flux: AsyncStream<Bool>? = diffusion.flux()
        XCTAssertEqual(diffusion.nombreAbonnes, 1)
        flux = nil
        XCTAssertNil(flux)
        XCTAssertEqual(diffusion.nombreAbonnes, 0, "flux abandonné : désabonné")
    }

    func testDiffusionAbonnementConcurrentNeRendJamaisUnEtatPerime() async {
        // Un abonnement concurrent d'un changement reçoit l'état courant puis les changements, dans l'ordre : son dernier
        // état est toujours le dernier état diffusé (le premier envoi d'un abonné est fait sous le verrou).
        for _ in 0..<200 {
            let diffusion = DiffusionDernierEtat<Bool>()
            diffusion.recevoir(false)
            let boite = BoiteFlux()
            DispatchQueue.concurrentPerform(iterations: 2) { index in
                if index == 0 { boite.poser(diffusion.flux()) } else { diffusion.recevoir(true) }
            }
            diffusion.terminer()
            guard let flux = boite.flux else { return XCTFail("flux absent") }
            let vues = await valeurs(flux)
            XCTAssertEqual(vues.last, true, "état périmé après un changement concurrent : \(vues)")
            XCTAssertTrue(vues == [true] || vues == [false, true], "ordre : \(vues)")
        }
    }
}

/// Flux posé par une file concurrente (test de diffusion).
private final class BoiteFlux: @unchecked Sendable {
    private let verrou = NSLock()
    private var stocke: AsyncStream<Bool>?
    func poser(_ flux: AsyncStream<Bool>) { verrou.lock(); stocke = flux; verrou.unlock() }
    var flux: AsyncStream<Bool>? { verrou.lock(); defer { verrou.unlock() }; return stocke }
}
