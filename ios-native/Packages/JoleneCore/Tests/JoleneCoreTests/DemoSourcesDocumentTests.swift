import CryptoKit
import XCTest
@testable import JoleneCore

/// Sources de fichiers du monde démo (lot 2 T7, blueprint §2.8 « Justificatifs ») : `-JOLENE_DEMO_SOURCE_DOC png / heic /
/// pdf / trop-gros / annule`, rendues par `DemoMediaPicker` à la place de la caméra, de la photothèque et de Fichiers.
/// Fichiers fictifs (trois pixels du pilote `mobile-native/src/workflows/documents/demoFixture.ts`, HEIC de T6, PDF vide),
/// aucune donnée réelle ; chacun passe par la même préparation que les vrais sélecteurs (`FichierSelectionne.preparer`).
final class DemoSourcesDocumentTests: XCTestCase {
    func testArgumentDeLancement() {
        XCTAssertEqual(SourceDocumentDemo(arguments: ["Jolene", "-JOLENE_DEMO_SOURCE_DOC", "heic"]), .heic)
        XCTAssertEqual(SourceDocumentDemo(arguments: ["-JOLENE_DEMO_SOURCE_DOC", "trop-gros"]), .tropGros)
        XCTAssertEqual(SourceDocumentDemo(arguments: ["-JOLENE_DEMO_SOURCE_DOC", "annule"]), .annule)
        XCTAssertEqual(SourceDocumentDemo(arguments: ["-JOLENE_DEMO_SOURCE_DOC", "pdf"]), .pdf)
        XCTAssertEqual(SourceDocumentDemo(arguments: []), .png, "défaut : l'image de trois pixels")
        XCTAssertEqual(SourceDocumentDemo(arguments: ["-JOLENE_DEMO_SOURCE_DOC"]), .png, "valeur absente")
        XCTAssertEqual(SourceDocumentDemo(arguments: ["-JOLENE_DEMO_SOURCE_DOC", "inconnue"]), .png)
        XCTAssertEqual(ScenarioDocumentsDemo(arguments: ["-JOLENE_DEMO_SCENARIO", "upload-incertain"]), .uploadIncertain)
        XCTAssertEqual(ScenarioDocumentsDemo(arguments: ["-JOLENE_DEMO_SCENARIO", "otp-expire"]), .normal, "scénario d'un autre domaine")
        XCTAssertEqual(ScenarioDocumentsDemo(arguments: []), .normal)
    }

    func testChaqueSourcePasseParLaPreparationDesVraisSelecteurs() throws {
        // PNG de trois pixels : tel quel depuis Fichiers, ré-encodé en JPEG sans métadonnée depuis la photothèque.
        let png = try XCTUnwrap(SourceDocumentDemo.png.fichier(origine: .fichiers))
        XCTAssertEqual(png.source, .fichiers)
        XCTAssertEqual(Array(png.octets.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        guard case let .pret(pret) = png.preparer() else { return XCTFail("PNG démo refusé") }
        XCTAssertEqual(pret.fichier.mime, .png)
        XCTAssertEqual(pret.octets, png.octets, "Fichiers : octets inchangés")
        let galerie = try XCTUnwrap(SourceDocumentDemo.png.fichier(origine: .phototheque))
        guard case let .pret(jpeg) = galerie.preparer() else { return XCTFail("photothèque démo refusée") }
        XCTAssertEqual(jpeg.fichier.mime, .jpeg)
        XCTAssertEqual(jpeg.fichier.nom, "justificatif-demo.jpg")

        // HEIC (fixture de T6, GPS fictif) → JPEG, quelle que soit l'origine.
        let heic = try XCTUnwrap(SourceDocumentDemo.heic.fichier(origine: .phototheque))
        XCTAssertEqual(heic.type, "image/heic")
        guard case let .pret(converti) = heic.preparer() else { return XCTFail("HEIC démo refusé") }
        XCTAssertEqual(converti.fichier.mime, .jpeg)
        XCTAssertEqual(Array(converti.octets.prefix(3)), [0xFF, 0xD8, 0xFF])
        XCTAssertEqual(converti.fichier.nom, "justificatif-demo.jpg")

        let pdf = try XCTUnwrap(SourceDocumentDemo.pdf.fichier(origine: .fichiers))
        guard case let .pret(document) = pdf.preparer() else { return XCTFail("PDF démo refusé") }
        XCTAssertEqual(document.fichier.mime, .pdf)

        // Plus de 10 Mo : refus local avec le message du web, avant tout reçu.
        let lourd = try XCTUnwrap(SourceDocumentDemo.tropGros.fichier(origine: .fichiers))
        XCTAssertGreaterThan(lourd.octets.count, ClassementDocument.tailleMaxParDefaut)
        XCTAssertEqual(lourd.preparer(), .refuse(code: .tropLourd, message: "Le fichier ne doit pas dépasser 10 Mo."))

        XCTAssertNil(SourceDocumentDemo.annule.fichier(origine: .camera), "annulé : aucun fichier, aucun envoi")
        XCTAssertNil(SourceDocumentDemo.annule.fichier(origine: .phototheque))
    }

    /// Le HEIC démo est la fixture de T6 (empreinte figée par `NormalisationImageTests`), copiée dans les ressources du
    /// paquet pour l'app : mêmes octets.
    func testHeicDemoIdentiqueALaFixtureDeT6() throws {
        let demo = try XCTUnwrap(SourceDocumentDemo.heic.fichier(origine: .fichiers))
        let fixture = try NormalisationImageTests.media("une-image.heic")
        XCTAssertEqual(SHA256.hash(data: demo.octets).description, SHA256.hash(data: fixture).description)
        XCTAssertEqual(demo.octets, fixture)
    }

    /// Type MIME d'un fichier choisi : type uniforme du sélecteur, sinon extension du nom ; vide si inconnu (le contrôle du
    /// web refuse ensuite).
    func testTypeMimeDesSelecteurs() {
        XCTAssertEqual(FichierSelectionne.mime(typeIdentifier: "public.heic"), "image/heic")
        XCTAssertEqual(FichierSelectionne.mime(typeIdentifier: "public.jpeg"), "image/jpeg")
        XCTAssertEqual(FichierSelectionne.mime(typeIdentifier: "public.png"), "image/png")
        XCTAssertEqual(FichierSelectionne.mime(typeIdentifier: "com.adobe.pdf"), "application/pdf")
        XCTAssertEqual(FichierSelectionne.mime(typeIdentifier: "type.inconnu.jolene"), "")
        XCTAssertEqual(FichierSelectionne.mime(nomFichier: "Scan.PDF"), "application/pdf")
        XCTAssertEqual(FichierSelectionne.mime(nomFichier: "photo.jpg"), "image/jpeg")
        XCTAssertEqual(FichierSelectionne.mime(nomFichier: "sans-extension"), "")
    }

    /// Photo de l'appareil : `jpegData(0.8)`, nom `photo_<ms>.jpg` comme le web natif (`ModalTeleversement.tsx` l.102).
    func testPhotoDeLAppareil() {
        let photo = FichierSelectionne.photo(jpeg: Data([0xFF, 0xD8, 0xFF, 0xE0]), prisLe: DemoWorld.fixedNow)
        XCTAssertEqual(photo.nom, "photo_1793577600000.jpg")
        XCTAssertEqual(photo.type, "image/jpeg")
        XCTAssertEqual(photo.source, .camera)
        let galerie = FichierSelectionne.galerie(octets: Data([1]), typeIdentifier: "public.heic", nomSuggere: nil,
                                                 choisiLe: DemoWorld.fixedNow)
        XCTAssertEqual(galerie.nom, "galerie_1793577600000.heic", "nom du web natif (l.154), extension du type choisi")
        XCTAssertEqual(galerie.type, "image/heic")
        XCTAssertEqual(galerie.source, .phototheque)
        let nomme = FichierSelectionne.galerie(octets: Data([1]), typeIdentifier: "public.jpeg", nomSuggere: "IMG_0001",
                                               choisiLe: DemoWorld.fixedNow)
        XCTAssertEqual(nomme.nom, "IMG_0001.jpeg")
    }
}
