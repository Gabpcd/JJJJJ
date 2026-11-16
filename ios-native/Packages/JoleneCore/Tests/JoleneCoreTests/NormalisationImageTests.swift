import CoreGraphics
import CryptoKit
import ImageIO
import XCTest
@testable import JoleneCore

/// Normalisation d'image et préparation d'un justificatif (lot 2 T6, blueprint §2.5, décision 13).
///
/// Fixtures `Resources/media/`, produites sur macOS le 8 novembre 2026, sans aucune donnée réelle :
/// - `une-image.heic` : 48 × 32 (moitié gauche rouge, moitié droite bleue), orientation EXIF 6, dictionnaire GPS
///   fictif (48.8566 N, 2.3522 E), écrite par ImageIO (`CGImageDestinationCreateWithURL(…, "public.heic", …)`) :
///   `sips` ne sait pas poser de GPS, or le test doit prouver son retrait ;
/// - `trois-pixels.png` : 3 × 1 sans métadonnée (ImageIO, `public.png`) ;
/// - `minimal.pdf` : PDF 1.4 d'une page vide, écrit à la main.
/// Les empreintes SHA-256 ci-dessous figent ces fichiers : toute régénération doit les mettre à jour.
final class NormalisationImageTests: XCTestCase {
    static let empreintes = [
        "une-image.heic": "5566f854218d17b5cb4dd1f299340879dd80996021636f5ee870cdb308c6c404",
        "trois-pixels.png": "e1bbaea003685a2a13fbeb80099e012e397a12e5c58d0c22544d491ab3248f50",
        "minimal.pdf": "9f1028b2b41823635f8e760d98ff57197c2fb1abd5a3fb2189a8c83c8c2a9d6a",
    ]

    static func media(_ nom: String) throws -> Data {
        let url = URL(fileURLWithPath: nom)
        guard let ressource = Bundle.module.url(forResource: url.deletingPathExtension().lastPathComponent,
                                                withExtension: url.pathExtension, subdirectory: "Resources/media") else {
            throw JoleneError(.contract, "fixture média introuvable : \(nom)")
        }
        return try Data(contentsOf: ressource)
    }

    private func proprietes(_ octets: Data) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(octets as CFData, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    /// Image bruitée (pseudo-aléatoire déterministe) : un JPEG pleine taille lourd, un JPEG réduit léger.
    private func pngBruite(largeur: Int, hauteur: Int) throws -> Data {
        var generateur = SplitMix(graine: 42)
        var pixels = [UInt8](repeating: 255, count: largeur * hauteur * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = UInt8(truncatingIfNeeded: generateur.next())
            pixels[index + 1] = UInt8(truncatingIfNeeded: generateur.next())
            pixels[index + 2] = UInt8(truncatingIfNeeded: generateur.next())
        }
        let espace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let image: CGImage = try pixels.withUnsafeMutableBytes { tampon in
            let ctx = try XCTUnwrap(CGContext(data: tampon.baseAddress, width: largeur, height: hauteur, bitsPerComponent: 8,
                                              bytesPerRow: largeur * 4, space: espace,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            return try XCTUnwrap(ctx.makeImage())
        }
        let sortie = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(sortie as CFMutableData, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return sortie as Data
    }

    /// JPEG 8 × 4 écrit par ImageIO avec des métadonnées fictives : GPS, fabricant et modèle (`{TIFF}`), commentaire et
    /// objectif (`{Exif}`), MakerNote Apple (`{MakerApple}`), ville (`{IPTC}`), orientation 6. Construit en mémoire, comme une
    /// photo de la photothèque.
    private func jpegAvecMetadonnees() throws -> Data {
        var pixels = [UInt8](repeating: 200, count: 8 * 4 * 4)
        let espace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let image: CGImage = try pixels.withUnsafeMutableBytes { tampon in
            let ctx = try XCTUnwrap(CGContext(data: tampon.baseAddress, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 8 * 4,
                                              space: espace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            return try XCTUnwrap(ctx.makeImage())
        }
        let metadonnees: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 48.8566, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 2.3522, kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Fabricant fictif", kCGImagePropertyTIFFModel: "Modele fictif"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "commentaire fictif",
                                             kCGImagePropertyExifLensModel: "objectif fictif"],
            kCGImagePropertyMakerAppleDictionary: ["1": 7, "8": [0.1, 0.2, 0.3]],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCity: "Ville fictive"],
            kCGImagePropertyOrientation: 6,
        ]
        let sortie = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(sortie as CFMutableData, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, metadonnees as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return sortie as Data
    }

    /// Clés de métadonnées identifiantes présentes dans `proprietes` (dictionnaires et champs de `jpegAvecMetadonnees`).
    private func metadonneesIdentifiantes(_ proprietes: [CFString: Any]) -> [String] {
        var presentes: [String] = []
        if proprietes[kCGImagePropertyGPSDictionary] != nil { presentes.append("{GPS}") }
        if proprietes[kCGImagePropertyMakerAppleDictionary] != nil { presentes.append("{MakerApple}") }
        if proprietes[kCGImagePropertyIPTCDictionary] != nil { presentes.append("{IPTC}") }
        let tiff = proprietes[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        if tiff?[kCGImagePropertyTIFFMake] != nil { presentes.append("TIFF.Make") }
        if tiff?[kCGImagePropertyTIFFModel] != nil { presentes.append("TIFF.Model") }
        let exif = proprietes[kCGImagePropertyExifDictionary] as? [CFString: Any]
        if exif?[kCGImagePropertyExifUserComment] != nil { presentes.append("Exif.UserComment") }
        if exif?[kCGImagePropertyExifLensModel] != nil { presentes.append("Exif.LensModel") }
        return presentes
    }

    // MARK: - Fixtures

    func testEmpreintesDesFixtures() throws {
        for (nom, attendue) in Self.empreintes {
            let octets = try Self.media(nom)
            let empreinte = SHA256.hash(data: octets).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(empreinte, attendue, "\(nom) a changé : mettre à jour l'empreinte et l'en-tête de ce fichier")
        }
        let heic = try proprietes(try Self.media("une-image.heic"))
        XCTAssertEqual(heic[kCGImagePropertyOrientation] as? Int, 6, "la fixture HEIC porte une orientation à appliquer")
        XCTAssertNotNil(heic[kCGImagePropertyGPSDictionary], "la fixture HEIC porte un GPS à retirer")
    }

    // MARK: - HEIC → JPEG

    func testHeicDevientUnJpegSansGpsNiMakerNoteOrientationAppliquee() throws {
        let heic = try Self.media("une-image.heic")
        XCTAssertTrue(NormalisationImage.estHEIF(heic))
        guard case let .jpeg(jpeg) = NormalisationImage.versJPEG(heic) else {
            return XCTFail("un HEIC lisible doit devenir un JPEG")
        }
        XCTAssertEqual(Array(jpeg.prefix(3)), [0xFF, 0xD8, 0xFF], "en-tête JPEG")
        XCTAssertFalse(NormalisationImage.estHEIF(jpeg))
        let sortie = try proprietes(jpeg)
        // La fixture ne porte pas de MakerNote : son retrait est prouvé par `testToutesLesMetadonneesRetireesDontMakerNote`.
        XCTAssertNil(sortie[kCGImagePropertyGPSDictionary], "aucune clé {GPS}")
        XCTAssertEqual(sortie[kCGImagePropertyOrientation] as? Int ?? 1, 1, "orientation « up »")
        XCTAssertEqual(sortie[kCGImagePropertyPixelWidth] as? Int, 32, "orientation 6 appliquée aux pixels (48 × 32 → 32 × 48)")
        XCTAssertEqual(sortie[kCGImagePropertyPixelHeight] as? Int, 48)
        XCTAssertLessThanOrEqual(jpeg.count, ClassementDocument.tailleMaxParDefaut)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.jpeg")
    }

    /// m8 (b) : MakerNote, EXIF, IPTC et GPS d'une image qui en porte vraiment sont tous retirés ; orientation appliquée.
    func testToutesLesMetadonneesRetireesDontMakerNote() throws {
        let source = try jpegAvecMetadonnees()
        XCTAssertEqual(metadonneesIdentifiantes(try proprietes(source)),
                       ["{GPS}", "{MakerApple}", "{IPTC}", "TIFF.Make", "TIFF.Model", "Exif.UserComment", "Exif.LensModel"],
                       "l'image de départ porte chaque métadonnée à retirer")
        guard case let .jpeg(jpeg) = NormalisationImage.versJPEG(source) else { return XCTFail("JPEG attendu") }
        let sortie = try proprietes(jpeg)
        XCTAssertEqual(metadonneesIdentifiantes(sortie), [], "aucune métadonnée de la source recopiée")
        XCTAssertEqual(sortie[kCGImagePropertyOrientation] as? Int ?? 1, 1)
        XCTAssertEqual(sortie[kCGImagePropertyPixelWidth] as? Int, 4, "orientation 6 appliquée (8 × 4 → 4 × 8)")
        XCTAssertEqual(sortie[kCGImagePropertyPixelHeight] as? Int, 8)
    }

    /// m10 : une photo de la photothèque est toujours ré-encodée en JPEG sans métadonnée (parité Capacitor, qualité 80,
    /// `ModalTeleversement.tsx` l.144-154) ; depuis Fichiers ou l'appareil photo, PNG/JPEG restent inchangés.
    func testPhotothequeToujoursReencodeeSansMetadonnees() throws {
        let jpeg = try jpegAvecMetadonnees()
        guard case let .pret(photo) = FichierDocument.preparer(nom: "IMG_0002.JPG", type: "image/jpeg", octets: jpeg, source: .phototheque) else {
            return XCTFail("photo de la photothèque acceptée")
        }
        XCTAssertNotEqual(photo.octets, jpeg, "ré-encodée")
        XCTAssertEqual(Array(photo.octets.prefix(3)), [0xFF, 0xD8, 0xFF])
        XCTAssertEqual(photo.fichier, FichierChoisi(nom: "IMG_0002.jpg", mime: .jpeg, tailleOctets: photo.octets.count))
        XCTAssertEqual(metadonneesIdentifiantes(try proprietes(photo.octets)), [], "ni GPS, ni EXIF, ni MakerNote jusqu'à Storage et l'IA")

        let png = try Self.media("trois-pixels.png")
        guard case let .pret(capture) = FichierDocument.preparer(nom: "capture.png", type: "image/png", octets: png, source: .phototheque) else {
            return XCTFail("PNG de la photothèque accepté")
        }
        XCTAssertEqual(capture.fichier.mime, .jpeg)
        XCTAssertEqual(capture.fichier.nom, "capture.jpg")

        let heic = try Self.media("une-image.heic")
        guard case let .pret(heif) = FichierDocument.preparer(nom: "IMG_0003.HEIC", type: "image/heic", octets: heic, source: .phototheque) else {
            return XCTFail("HEIC de la photothèque normalisé")
        }
        XCTAssertEqual(heif.fichier.nom, "IMG_0003.jpg")

        for source in [SourceFichier.fichiers, .camera] {
            guard case let .pret(tel) = FichierDocument.preparer(nom: "IMG_0002.JPG", type: "image/jpeg", octets: jpeg, source: source) else {
                return XCTFail("\(source) : JPEG accepté")
            }
            XCTAssertEqual(tel.octets, jpeg, "\(source) : octets inchangés (« PNG/JPEG/PDF inchangés »)")
        }
        guard case .refuse = FichierDocument.preparer(nom: "photo.jpg", type: "image/jpeg", octets: Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00]),
                                                      source: .phototheque) else {
            return XCTFail("photo illisible : refusée, jamais envoyée telle quelle avec ses métadonnées")
        }
    }

    func testAuDelaDeLaTailleMaxReductionPuisRefus() throws {
        let png = try pngBruite(largeur: 300, hauteur: 200)
        guard case let .jpeg(pleine) = NormalisationImage.versJPEG(png) else { return XCTFail("JPEG pleine taille attendu") }
        // Plafond juste sous la pleine taille : seconde passe à `coteReduit` pixels et qualité 0,6.
        guard case let .jpeg(reduite) = NormalisationImage.versJPEG(png, tailleMax: pleine.count - 1, coteReduit: 16) else {
            return XCTFail("la réduction doit passer sous le plafond")
        }
        XCTAssertLessThan(reduite.count, pleine.count)
        let dimensions = try proprietes(reduite)
        XCTAssertEqual(max(dimensions[kCGImagePropertyPixelWidth] as? Int ?? 0, dimensions[kCGImagePropertyPixelHeight] as? Int ?? 0), 16)
        XCTAssertEqual(NormalisationImage.versJPEG(png, tailleMax: 10, coteReduit: 16), .tropLourd, "encore trop lourd : refus")
        XCTAssertEqual(NormalisationImage.coteReduit, 4_096)
        XCTAssertEqual(NormalisationImage.qualite, 0.8)
        XCTAssertEqual(NormalisationImage.qualiteReduite, 0.6)
    }

    func testHeicIllisibleRefuseAvecLeMessageDuWeb() throws {
        var faux = Data([0x00, 0x00, 0x00, 0x18])
        faux.append(contentsOf: Array("ftypheic".utf8))
        faux.append(Data(repeating: 0xAB, count: 64))
        XCTAssertTrue(NormalisationImage.estHEIF(faux), "signature ftyp/heic reconnue")
        XCTAssertEqual(NormalisationImage.versJPEG(faux), .illisible)
        guard case let .refuse(code, message) = FichierDocument.preparer(nom: "IMG_0001.HEIC", type: "image/heic", octets: faux) else {
            return XCTFail("un HEIC illisible est refusé")
        }
        XCTAssertEqual(code, .heicNonSupporte)
        // source: src/lib/documentUpload.ts:147 (message de ClassementDocument, lot 2 T2)
        XCTAssertEqual(message, "Le format HEIC/HEIF ne peut pas être vérifié. Prenez une photo depuis Jolene ou choisissez un PDF, JPEG, PNG ou WebP.")
    }

    // MARK: - Préparation d'un fichier choisi

    func testHeicPrepareEnJpegRenomme() throws {
        let heic = try Self.media("une-image.heic")
        guard case let .pret(pret) = FichierDocument.preparer(nom: "IMG_0001.HEIC", type: "image/heic", octets: heic) else {
            return XCTFail("un HEIC lisible est normalisé puis accepté")
        }
        XCTAssertEqual(pret.fichier.mime, .jpeg)
        XCTAssertEqual(pret.fichier.nom, "IMG_0001.jpg", "le nom suit le contenu converti")
        XCTAssertEqual(pret.fichier.tailleOctets, pret.octets.count)
        XCTAssertEqual(Array(pret.octets.prefix(3)), [0xFF, 0xD8, 0xFF])
        // Une extension HEIC sans type déclaré suit le même chemin.
        guard case let .pret(sansType) = FichierDocument.preparer(nom: "scan.heif", type: "", octets: heic) else {
            return XCTFail("extension .heif sans type déclaré")
        }
        XCTAssertEqual(sansType.fichier.nom, "scan.jpg")
    }

    func testPngJpegPdfInchanges() throws {
        let png = try Self.media("trois-pixels.png")
        let pdf = try Self.media("minimal.pdf")
        guard case let .jpeg(jpeg) = NormalisationImage.versJPEG(try Self.media("une-image.heic")) else { return XCTFail("JPEG") }
        let cas: [(String, String, Data, MimeDocument)] = [
            ("trois-pixels.png", "image/png", png, .png), ("attestation.pdf", "application/pdf", pdf, .pdf),
            ("photo_1793577600000.jpg", "image/jpeg", jpeg, .jpeg),
        ]
        for (nom, type, octets, mime) in cas {
            guard case let .pret(pret) = FichierDocument.preparer(nom: nom, type: type, octets: octets) else {
                return XCTFail("\(nom) accepté tel quel")
            }
            XCTAssertEqual(pret.octets, octets, "\(nom) : octets inchangés")
            XCTAssertEqual(pret.fichier, FichierChoisi(nom: nom, mime: mime, tailleOctets: octets.count))
        }
    }

    func testRefusDeClassementAvecLesMessagesDuWeb() {
        guard case let .refuse(vide, messageVide) = FichierDocument.preparer(nom: "a.pdf", type: "application/pdf", octets: Data()) else {
            return XCTFail("fichier vide")
        }
        XCTAssertEqual(vide, .vide)
        XCTAssertEqual(messageVide, "Le fichier sélectionné est vide.") // source: src/lib/documentUpload.ts:135
        var lourd = Data(Array("%PDF-1.4\n".utf8))
        lourd.append(Data(repeating: 0x20, count: ClassementDocument.tailleMaxParDefaut))
        guard case let .refuse(trop, messageTrop) = FichierDocument.preparer(nom: "a.pdf", type: "application/pdf", octets: lourd) else {
            return XCTFail("fichier trop lourd")
        }
        XCTAssertEqual(trop, .tropLourd)
        XCTAssertEqual(messageTrop, "Le fichier ne doit pas dépasser 10 Mo.") // source: src/lib/documentUpload.ts:139
        guard case let .refuse(signature, _) = FichierDocument.preparer(nom: "a.pdf", type: "application/pdf",
                                                                        octets: Data([0x89, 0x50, 0x4e, 0x47])) else {
            return XCTFail("contenu contradictoire")
        }
        XCTAssertEqual(signature, .signatureInvalide)
    }

    /// Aucun octet de fichier dans le reçu journalisé (décision 14) : seuls nom, MIME et taille y entrent.
    func testLeRecuNePorteAucunOctetDuFichier() throws {
        let png = try Self.media("trois-pixels.png")
        guard case let .pret(pret) = FichierDocument.preparer(nom: "trois-pixels.png", type: "image/png", octets: png) else {
            return XCTFail("PNG accepté")
        }
        let recu = try RecuDocument.preparer(userId: "demo-soignant", epoch: 1, typeDocument: "DIPLOME", fichier: pret.fichier,
                                             horodatageMs: 1_793_577_600_000)
        let encode = try recu.encoder()
        XCTAssertNil(encode.range(of: png), "aucun octet du fichier")
        XCTAssertNil(encode.range(of: Data(png.base64EncodedString().utf8)), "ni en base64")
        let cles = try XCTUnwrap(JSONSerialization.jsonObject(with: encode) as? [String: Any]).keys
        XCTAssertEqual(Set(cles), ["version", "user_id", "epoch", "s3_cle", "type_document", "mime", "taille_octets",
                                   "nom_fichier", "phase"])
    }
}

/// Générateur déterministe (SplitMix64) pour les images de test.
struct SplitMix: RandomNumberGenerator {
    var etat: UInt64
    init(graine: UInt64) { etat = graine }
    mutating func next() -> UInt64 {
        etat &+= 0x9E37_79B9_7F4A_7C15
        var z = etat
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
