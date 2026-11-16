import Foundation
import ImageIO

/// Normalisation d'une photo HEIC/HEIF en JPEG avant l'envoi d'un justificatif (lot 2 T6, décision 13 ; blueprint §2.5).
///
/// Le serveur et l'IA refusent le HEIC (`fn_remplacer_document_soignant` l.53110-53117, `documentUpload.ts` l.142-148) :
/// l'app le convertit avec ImageIO, sans UIKit. Orientation EXIF appliquée aux pixels (`kCGImageSourceCreateThumbnailWithTransform`),
/// image ré-encodée depuis ses seuls pixels : aucune métadonnée de la source n'est recopiée (ni `{GPS}`, ni MakerNote,
/// ni EXIF). Qualité 0,8 ; au-delà de la taille maximale, une seule réduction à 4 096 pixels de côté et qualité 0,6,
/// puis refus (message du web, `ClassementDocument`). Depuis Fichiers ou l'appareil photo, PNG, JPEG, WebP et PDF ne
/// passent jamais ici : ils sont envoyés tels quels ; une image de la photothèque y passe toujours, pour perdre ses EXIF
/// (`FichierDocument.preparer(…, source: .phototheque)`, revue fraîche de T6). Aucun octet n'est écrit sur disque.
public enum NormalisationImage {
    public static let qualite = 0.8
    public static let qualiteReduite = 0.6
    public static let coteReduit = 4_096

    public enum Resultat: Equatable, Sendable {
        case jpeg(Data)
        /// Image non décodable : refus (message HEIC du web).
        case illisible
        /// Encore au-delà de la taille maximale après réduction : refus (message de taille du web).
        case tropLourd
    }

    /// Marques ISO-BMFF d'une image HEIF (`ftyp` à l'octet 4).
    static let marquesHEIF: Set<String> = ["heic", "heix", "hevc", "hevx", "heim", "heis", "hevm", "hevs", "mif1", "msf1", "heif"]

    /// Vrai pour un conteneur HEIF reconnu par sa boîte `ftyp`, quel que soit le nom ou le type annoncé.
    public static func estHEIF(_ octets: Data) -> Bool {
        guard octets.count >= 12 else { return false }
        let entete = Array(octets.prefix(12))
        guard entete[4...7].elementsEqual([0x66, 0x74, 0x79, 0x70]) else { return false } // "ftyp"
        let marque = String(decoding: entete[8...11], as: UTF8.self).lowercased()
        return marquesHEIF.contains(marque)
    }

    /// Image (HEIC, HEIF ou tout format décodable par ImageIO) → JPEG sans métadonnée. `coteReduit` n'est
    /// paramétrable que pour les tests.
    public static func versJPEG(_ octets: Data, tailleMax: Int = ClassementDocument.tailleMaxParDefaut,
                                coteReduit: Int = NormalisationImage.coteReduit) -> Resultat {
        guard !octets.isEmpty,
              let source = CGImageSourceCreateWithData(octets as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let proprietes = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let largeur = proprietes[kCGImagePropertyPixelWidth] as? Int,
              let hauteur = proprietes[kCGImagePropertyPixelHeight] as? Int, largeur > 0, hauteur > 0 else {
            return .illisible
        }
        guard let pleine = encoder(source, coteMax: max(largeur, hauteur), qualite: qualite) else { return .illisible }
        if pleine.count <= tailleMax { return .jpeg(pleine) }
        guard let reduite = encoder(source, coteMax: min(coteReduit, max(largeur, hauteur)), qualite: qualiteReduite) else {
            return .illisible
        }
        return reduite.count <= tailleMax ? .jpeg(reduite) : .tropLourd
    }

    /// Une passe d'encodage : pixels orientés « up », côté borné à `coteMax`, JPEG à `qualite`, aucune métadonnée.
    private static func encoder(_ source: CGImageSource, coteMax: Int, qualite: Double) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: coteMax,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let sortie = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(sortie as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let proprietes: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: qualite, kCGImagePropertyOrientation: 1]
        CGImageDestinationAddImage(destination, image, proprietes as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return sortie as Data
    }
}
