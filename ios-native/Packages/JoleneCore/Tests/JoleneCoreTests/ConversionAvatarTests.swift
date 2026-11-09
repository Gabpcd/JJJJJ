import CoreGraphics
import ImageIO
import XCTest
@testable import JoleneCore

/// Conversion de la photo de profil (lot 3, T10 ; blueprint §3 T10, D14 ; CLAUDE.md « HEIC iPhone → conversion JPEG
/// avant upload ») : HEIC → JPEG valide, plus grand côté 256 px sans agrandissement (`AvatarUpload.tsx` l.39-42),
/// orientation EXIF appliquée, aucune métadonnée recopiée (position GPS comprise), limite de 2 Mo sur le JPEG envoyé.
/// Fixture : `Resources/media/avatar-source.heic`, image de SYNTHÈSE 600 × 400, orientation EXIF 6 (affichée 400 × 600),
/// dictionnaire GPS fictif.
final class ConversionAvatarTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "avatar-source", withExtension: "heic",
                                                  subdirectory: "Resources/media"), "fixture HEIC absente")
        return try Data(contentsOf: url)
    }

    private func proprietes(_ donnees: Data) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(donnees as CFData, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    private func type(_ donnees: Data) -> String? {
        CGImageSourceCreateWithData(donnees as CFData, nil).flatMap { CGImageSourceGetType($0) as String? }
    }

    /// PNG de synthèse `largeur × hauteur`, éventuellement transparent.
    private func png(_ largeur: Int, _ hauteur: Int, transparent: Bool = false) throws -> Data {
        let espace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let contexte = try XCTUnwrap(CGContext(data: nil, width: largeur, height: hauteur, bitsPerComponent: 8, bytesPerRow: 0,
                                               space: espace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        if !transparent {
            contexte.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
            contexte.fill(CGRect(x: 0, y: 0, width: largeur, height: hauteur))
        }
        let image = try XCTUnwrap(contexte.makeImage())
        let sortie = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(sortie, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return sortie as Data
    }

    func testFixtureHeicPorteOrientationEtPositionAvantConversion() throws {
        // Garde de la fixture elle-même : sans orientation ni GPS, les tests suivants ne prouveraient rien.
        let source = try fixture()
        XCTAssertEqual(type(source), "public.heic")
        let avant = try proprietes(source)
        XCTAssertEqual(avant[kCGImagePropertyOrientation] as? Int, 6)
        XCTAssertEqual(avant[kCGImagePropertyPixelWidth] as? Int, 600)
        XCTAssertNotNil(avant[kCGImagePropertyGPSDictionary], "la fixture porte une position GPS fictive")
    }

    func testHeicConvertiEnJpegValideReduitOrienteEtSansMetadonnee() throws {
        let jpeg = try ConversionAvatar.jpeg(depuis: try fixture())
        XCTAssertEqual(type(jpeg), "public.jpeg", "JPEG systématique, jamais de HEIC envoyé")
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xFF, 0xD8], "signature JPEG")
        let apres = try proprietes(jpeg)
        let largeur = try XCTUnwrap(apres[kCGImagePropertyPixelWidth] as? Int)
        let hauteur = try XCTUnwrap(apres[kCGImagePropertyPixelHeight] as? Int)
        // Orientation 6 appliquée : 600 × 400 stocké = 400 × 600 affiché → 171 × 256 (plus grand côté 256).
        XCTAssertEqual(hauteur, 256)
        XCTAssertTrue((170...171).contains(largeur), "largeur proportionnelle, obtenu \(largeur)")
        XCTAssertNil(apres[kCGImagePropertyGPSDictionary], "aucune position GPS recopiée")
        XCTAssertTrue([nil, 1].contains(apres[kCGImagePropertyOrientation] as? Int), "orientation déjà appliquée aux pixels")
        XCTAssertNil(apres[kCGImagePropertyExifDictionary].flatMap { ($0 as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] })
        XCTAssertLessThanOrEqual(jpeg.count, AvatarProfil.tailleMaxOctets)
    }

    func testPetiteImageJamaisAgrandieEtGrandeReduiteA256() throws {
        let petite = try proprietes(try ConversionAvatar.jpeg(depuis: try png(64, 48)))
        XCTAssertEqual(petite[kCGImagePropertyPixelWidth] as? Int, 64, "`if (w > MAX)` : jamais d'agrandissement")
        XCTAssertEqual(petite[kCGImagePropertyPixelHeight] as? Int, 48)
        let grande = try proprietes(try ConversionAvatar.jpeg(depuis: try png(1024, 768)))
        XCTAssertEqual(grande[kCGImagePropertyPixelWidth] as? Int, 256)
        XCTAssertEqual(grande[kCGImagePropertyPixelHeight] as? Int, 192)
    }

    func testTransparenceSurFondBlancPasNoir() throws {
        let jpeg = try ConversionAvatar.jpeg(depuis: try png(32, 32, transparent: true))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixel = [UInt8](repeating: 0, count: 4)
        let espace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let contexte = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                               space: espace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        contexte.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertGreaterThan(Int(pixel[0]), 240, "fond blanc sous la transparence, obtenu \(pixel)")
    }

    func testFichierVideIllisibleOuTropLourdRefusesAvecLesMessagesDuWeb() throws {
        XCTAssertThrowsError(try ConversionAvatar.jpeg(depuis: Data())) {
            XCTAssertEqual($0 as? ConversionAvatar.Erreur, .vide)
        }
        XCTAssertThrowsError(try ConversionAvatar.jpeg(depuis: Data("pas une image".utf8))) {
            XCTAssertEqual($0 as? ConversionAvatar.Erreur, .illisible)
        }
        XCTAssertThrowsError(try ConversionAvatar.jpeg(depuis: try fixture(), tailleMax: 100)) {
            XCTAssertEqual($0 as? ConversionAvatar.Erreur, .tropLourd, "limite appliquée au JPEG envoyé")
        }
        XCTAssertEqual(ConversionAvatar.message(.vide), "Le fichier sélectionné est vide.")
        XCTAssertEqual(ConversionAvatar.message(.illisible), "Impossible de lire le fichier sélectionné.")
        XCTAssertEqual(ConversionAvatar.message(.tropLourd), "Le fichier ne doit pas dépasser 2 Mo.")
    }

    func testReglesDuWeb() {
        XCTAssertEqual(AvatarProfil.dimensionMax, 256)
        XCTAssertEqual(AvatarProfil.qualiteJPEG, 0.8)
        XCTAssertEqual(AvatarProfil.tailleMaxOctets, 2_097_152)
        XCTAssertEqual(AvatarProfil.dureeURLSigneeSecondes, 157_680_000, "5 * 365 * 24 * 60 * 60")
        XCTAssertEqual(AvatarProfil.bucket, "jolene-documents")
        XCTAssertEqual(AvatarProfil.contentType, "image/jpeg")
        XCTAssertEqual(AvatarProfil.chemin(userId: "u-1", instant: Date(timeIntervalSince1970: 1_793_577_600.1239)),
                       "u-1/avatar-1793577600123.jpg", "`${user.id}/avatar-${Date.now()}` en millisecondes, `.jpg`")
    }

    func testUrlSigneeDesigneLeCheminSansLireLeJeton() {
        let chemin = "u-1/avatar-1793577600123.jpg"
        let signee = "https://ref.supabase.co/storage/v1/object/sign/jolene-documents/\(chemin)?token=abc"
        XCTAssertTrue(AvatarProfil.urlDesigne(signee, chemin: chemin))
        XCTAssertFalse(AvatarProfil.urlDesigne(signee, chemin: "u-1/avatar-1.jpg"))
        XCTAssertFalse(AvatarProfil.urlDesigne("https://ref.supabase.co/storage/v1/object/sign/autre/\(chemin)", chemin: chemin))
        XCTAssertFalse(AvatarProfil.urlDesigne(nil, chemin: chemin))
        XCTAssertFalse(AvatarProfil.urlDesigne("https://x.invalid/?p=/jolene-documents/\(chemin)", chemin: chemin),
                       "le chemin est lu dans le chemin de l'URL, jamais dans sa requête")
    }
}
