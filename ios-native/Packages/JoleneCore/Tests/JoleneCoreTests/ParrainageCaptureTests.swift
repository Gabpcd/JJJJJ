import Foundation
import XCTest
@testable import JoleneCore

/// Capture du code de parrainage par lien universel et application après authentification (L4-T6,
/// `docs/mobile-swift/LOT4_PLAN.md` §3 T6, D14) : forme exacte du web (`InscriptionSoignant.tsx` l.113-115, majuscules,
/// `^[A-Z0-9-]{4,16}$`), codes `ETB-` ignorés (`attribution.ts` l.29-31, `useAppliquerParrainage.ts` l.37), fenêtre de
/// 30 jours (`useAppliquerParrainage.ts` l.19, l.43-45), marqueur par userId et code (l.60-61, l.83), refus définitifs
/// (l.20-25) qui posent le marqueur, erreur réseau qui conserve le code (l.71-81).
final class ParrainageCaptureTests: XCTestCase {
    private let debut = Date(timeIntervalSince1970: 1_793_577_600)
    private let jour: TimeInterval = 86_400

    private func url(_ texte: String) throws -> URL { try XCTUnwrap(URL(string: texte)) }

    // MARK: - Forme du code

    func testNormalisationEnMajusculesEtFormeExacteDuWeb() {
        XCTAssertEqual(ParrainageCapture.normaliser("demo-xyz"), "DEMO-XYZ")
        XCTAssertEqual(ParrainageCapture.normaliser("ABCD"), "ABCD", "4 caractères : minimum")
        XCTAssertEqual(ParrainageCapture.normaliser("ABCDEFGHIJKLMNOP"), "ABCDEFGHIJKLMNOP", "16 caractères : maximum")
        for invalide in ["ABC", "ABCDEFGHIJKLMNOPQ", "<script>", "AB CD", " ABCD", "ABCD ", "ABCD\n", "ÉCOLE1", "AB_CD",
                         "AB%20CD", "", "ABCD'--", "ＡＢＣＤ"] {
            XCTAssertNil(ParrainageCapture.normaliser(invalide), "« \(invalide) » hors forme : ignoré")
        }
    }

    func testCodesEtablissementIgnores() {
        XCTAssertNil(ParrainageCapture.normaliser("ETB-1234"))
        XCTAssertNil(ParrainageCapture.normaliser("etb-abcd"), "casse ignorée, comme `/^ETB-/i`")
        XCTAssertEqual(ParrainageCapture.normaliser("ETB1234"), "ETB1234", "sans tiret : code soignant")
    }

    func testCodeDuLienRefParrainEtHotesDeConfiance() throws {
        XCTAssertEqual(ParrainageCapture.code(depuis: try url("https://jolene.app/inscription/soignant?ref=demo-xyz")), "DEMO-XYZ")
        XCTAssertEqual(ParrainageCapture.code(depuis: try url("https://jolene.app/soignant/tableau-de-bord?parrain=XYZ-1234")),
                       "XYZ-1234", "alias `?parrain=` des emails avis-parrainage")
        XCTAssertEqual(ParrainageCapture.code(depuis: try url("https://jolene.app/inscription/soignant?ref=&parrain=ABCD1234")),
                       "ABCD1234", "`ref` vide : `parrain` lu, comme `get('ref') || get('parrain')`")
        XCTAssertEqual(ParrainageCapture.code(depuis: try url("https://jolene.app/inscription/soignant?ref=AAAA&parrain=BBBB")), "AAAA")
        XCTAssertNil(ParrainageCapture.code(depuis: try url("https://jolene.app/inscription/soignant?ref=%3Cscript%3E")))
        XCTAssertNil(ParrainageCapture.code(depuis: try url("https://jolene.app/inscription/soignant?ref=ETB-1234")))
        XCTAssertNil(ParrainageCapture.code(depuis: try url("https://jolene.app/inscription/soignant")))
        XCTAssertNil(ParrainageCapture.code(depuis: try url("https://exemple.invalid/inscription/soignant?ref=ABCD1234")),
                     "hôte hors de confiance : aucun code lu")
        XCTAssertNil(ParrainageCapture.code(depuis: try url("http://jolene.app/inscription/soignant?ref=ABCD1234")),
                     "schéma non sûr : mêmes refus que le routeur des liens")
    }

    // MARK: - Fenêtre de 30 jours

    func testFenetreDeTrenteJours() {
        let capture = ParrainageCapture.Capture(code: "ABCD1234", captureLe: debut)
        XCTAssertTrue(ParrainageCapture.estApplicable(capture, maintenant: debut))
        XCTAssertTrue(ParrainageCapture.estApplicable(capture, maintenant: debut + 30 * jour - 1))
        XCTAssertFalse(ParrainageCapture.estApplicable(capture, maintenant: debut + 30 * jour), "30 jours révolus")
        XCTAssertFalse(ParrainageCapture.estApplicable(capture, maintenant: debut - 1), "capture dans le futur : jamais")
    }

    // MARK: - Stockage

    func testCaptureMemoriseeEtCodeAAppliquerParCompte() {
        let stockage = ParrainageStockage(MemoireStockageAppareil())
        XCTAssertNil(stockage.codeAAppliquer(userId: "u1", maintenant: debut))
        stockage.capturer("ABCD1234", le: debut)
        XCTAssertEqual(stockage.capture(), ParrainageCapture.Capture(code: "ABCD1234", captureLe: debut))
        XCTAssertEqual(stockage.codeAAppliquer(userId: "u1", maintenant: debut + jour), "ABCD1234")
        stockage.marquer(userId: "u1", code: "ABCD1234")
        XCTAssertNil(stockage.codeAAppliquer(userId: "u1", maintenant: debut + jour), "marqueur : plus jamais rejoué")
        XCTAssertNil(stockage.capture(), "capture du même code retirée au marquage")
    }

    func testCaptureExpireeRetireeSansApplication() {
        let stockage = ParrainageStockage(MemoireStockageAppareil())
        stockage.capturer("ABCD1234", le: debut)
        XCTAssertNil(stockage.codeAAppliquer(userId: "u1", maintenant: debut + 31 * jour))
        XCTAssertNil(stockage.capture(), "capture hors fenêtre effacée")
    }

    func testDoubleCapture() {
        let stockage = ParrainageStockage(MemoireStockageAppareil())
        stockage.capturer("ABCD1234", le: debut)
        stockage.capturer("ABCD1234", le: debut + 10 * jour)
        XCTAssertEqual(stockage.capture()?.captureLe, debut, "même code : la fenêtre n'est pas prolongée")
        stockage.capturer("WXYZ5678", le: debut + 12 * jour)
        XCTAssertEqual(stockage.capture(), ParrainageCapture.Capture(code: "WXYZ5678", captureLe: debut + 12 * jour),
                       "autre code : le dernier lien reçu remplace la capture (page d'inscription du web)")
        stockage.marquer(userId: "u1", code: "ABCD1234")
        XCTAssertEqual(stockage.capture()?.code, "WXYZ5678", "un autre code reçu n'est jamais retiré par le marquage")
    }

    func testMarqueurParCompteEtParCode() {
        let stockage = ParrainageStockage(MemoireStockageAppareil())
        stockage.capturer("ABCD1234", le: debut)
        stockage.marquer(userId: "u1", code: "AUTRE123")
        XCTAssertEqual(stockage.codeAAppliquer(userId: "u1", maintenant: debut), "ABCD1234", "marqueur d'un autre code")
        XCTAssertEqual(stockage.codeAAppliquer(userId: "u2", maintenant: debut), "ABCD1234", "autre compte : marqueur propre")
    }

    func testStockageIllisibleEstIgnore() {
        let memoire = MemoireStockageAppareil([ParrainageStockage.cleCapture: "{pas du json"])
        let stockage = ParrainageStockage(memoire)
        XCTAssertNil(stockage.capture())
        XCTAssertNil(stockage.codeAAppliquer(userId: "u1", maintenant: debut))
        let horsForme = try? String(data: JSONEncoder().encode(ParrainageCapture.Capture(code: "<script>", captureLe: debut)),
                                    encoding: .utf8)
        memoire.ecrire(ParrainageStockage.cleCapture, horsForme)
        XCTAssertNil(stockage.codeAAppliquer(userId: "u1", maintenant: debut), "un code stocké hors forme n'est jamais envoyé")
    }

    // MARK: - Application

    private actor Appels {
        var codes: [String] = []
        func ajouter(_ code: String) { codes.append(code) }
    }

    func testSuccesAfficheLeTexteDuWebEtPoseLeMarqueur() async {
        let stockage = ParrainageStockage(MemoireStockageAppareil())
        stockage.capturer("DEMO-XYZ", le: debut)
        let appels = Appels()
        let avis = await ParrainageApplication.appliquer(stockage: stockage, userId: "u1", maintenant: debut) { code in
            await appels.ajouter(code)
            return .appliquee
        }
        XCTAssertEqual(avis, .enregistre)
        XCTAssertEqual(avis?.texte, "Code de parrainage enregistré.", "useAppliquerParrainage.ts l.89")
        let codes = await appels.codes
        XCTAssertEqual(codes, ["DEMO-XYZ"])
        let rejoue = await ParrainageApplication.appliquer(stockage: stockage, userId: "u1", maintenant: debut) { code in
            await appels.ajouter(code)
            return .appliquee
        }
        XCTAssertNil(rejoue, "marqueur posé : aucun second appel")
        let total = await appels.codes.count
        XCTAssertEqual(total, 1)
    }

    func testRefusDefinitifsPosentLeMarqueurSansMessage() async {
        XCTAssertEqual(ParrainageApplication.refusDefinitifs, [
            "Code de parrainage invalide",
            "Vous ne pouvez pas vous parrainer vous-même",
            "Le parrain a atteint la limite de 20 filleuls validés",
            "Vous avez déjà appliqué un code de parrainage",
        ], "useAppliquerParrainage.ts l.20-25")
        for message in ParrainageApplication.refusDefinitifs.sorted() {
            let stockage = ParrainageStockage(MemoireStockageAppareil())
            stockage.capturer("ABCD1234", le: debut)
            let avis = await ParrainageApplication.appliquer(stockage: stockage, userId: "u1", maintenant: debut) { _ in
                .refusDefinitif(message: message)
            }
            XCTAssertNil(avis, "\(message) : refus silencieux, comme le web")
            XCTAssertNil(stockage.codeAAppliquer(userId: "u1", maintenant: debut), "\(message) : marqueur posé")
        }
    }

    func testErreurReseauOuRefusNonDefinitifConserveLeCode() async {
        struct Coupure: Error {}
        let cas: [@Sendable (String) async throws -> ApplicationParrainage] = [
            { _ in throw Coupure() },
            { _ in throw JoleneError(.network, "Connexion impossible.") },
            { _ in .aReessayer },
        ]
        for appel in cas {
            let stockage = ParrainageStockage(MemoireStockageAppareil())
            stockage.capturer("ABCD1234", le: debut)
            let avis = await ParrainageApplication.appliquer(stockage: stockage, userId: "u1", maintenant: debut, appel: appel)
            XCTAssertEqual(avis, .nonEnregistre)
            XCTAssertEqual(avis?.texte, "Le parrainage n’a pas pu être enregistré. Nous réessaierons à votre prochaine connexion.",
                           "useAppliquerParrainage.ts l.74")
            XCTAssertEqual(stockage.codeAAppliquer(userId: "u1", maintenant: debut), "ABCD1234", "code conservé")
        }
    }

    func testAnnulationNiMessageNiMarqueur() async {
        let stockage = ParrainageStockage(MemoireStockageAppareil())
        stockage.capturer("ABCD1234", le: debut)
        let avis = await ParrainageApplication.appliquer(stockage: stockage, userId: "u1", maintenant: debut) { _ in
            throw CancellationError()
        }
        XCTAssertNil(avis)
        XCTAssertEqual(stockage.codeAAppliquer(userId: "u1", maintenant: debut), "ABCD1234")
    }

    func testSansCaptureAucunAppel() async {
        let stockage = ParrainageStockage(MemoireStockageAppareil())
        let avis = await ParrainageApplication.appliquer(stockage: stockage, userId: "u1", maintenant: debut) { _ in
            XCTFail("aucun appel sans capture")
            return .appliquee
        }
        XCTAssertNil(avis)
    }
}
