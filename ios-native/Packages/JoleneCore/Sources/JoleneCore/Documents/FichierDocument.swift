import Foundation

/// Fichier prêt à l'envoi : métadonnées vérifiées (`FichierChoisi`, seules à entrer dans le reçu) et octets, qui ne
/// passent qu'à `DocumentsPort.envoyer(recu:octets:context:)` et ne sont jamais conservés (décision 14).
public struct FichierPret: Equatable, Sendable {
    public let fichier: FichierChoisi
    public let octets: Data

    public init(fichier: FichierChoisi, octets: Data) {
        self.fichier = fichier; self.octets = octets
    }
}

/// Issue de la préparation d'un fichier choisi (caméra, photothèque, Fichiers).
public enum PreparationFichier: Equatable, Sendable {
    case pret(FichierPret)
    /// Refus local, avant tout reçu et tout envoi : message du web (`ClassementDocument`, `documentUpload.ts`).
    case refuse(code: EchecFichierDocument, message: String)
}

/// Provenance d'un fichier choisi (T7 : `TeleversementSheet`).
public enum SourceFichier: String, Sendable {
    /// `UIDocumentPickerViewController` : fichier envoyé tel quel (HEIC/HEIF excepté).
    case fichiers
    /// `UIImagePickerController` `.camera` puis `jpegData(0.8)` : pixels seuls, aucune métadonnée.
    case camera
    /// `PHPickerViewController` : l'original garde ses EXIF (GPS compris), toujours ré-encodé en JPEG sans métadonnée,
    /// comme le web natif (Capacitor, qualité 80, `ModalTeleversement.tsx` l.144-154).
    case phototheque
}

/// Chaîne de préparation d'un justificatif (lot 2 T6, blueprint §2.5) : un HEIC/HEIF (annoncé ou reconnu à sa boîte
/// `ftyp`) et toute image de la photothèque deviennent un JPEG sans métadonnée (`NormalisationImage`), puis tout fichier
/// passe le contrôle du web (`ClassementDocument.verifierFichier` : taille, MIME, extension, signature binaire). Depuis
/// Fichiers ou l'appareil photo, PNG, JPEG, WebP et PDF ne sont jamais ré-encodés.
public enum FichierDocument {
    public static func preparer(nom: String, type: String, octets: Data, source: SourceFichier = .fichiers,
                                tailleMax: Int = ClassementDocument.tailleMaxParDefaut) -> PreparationFichier {
        var nomFinal = nom
        var typeFinal = type
        var contenu = octets
        let heif = !octets.isEmpty
            && (ClassementDocument.classerFormat(nom: nom, type: type) == .heicNonSupporte || NormalisationImage.estHEIF(octets))
        if !heif, source == .phototheque, !octets.isEmpty, !estPDF(octets) {
            // Revue fraîche de T6 (m10) : une image de la photothèque n'est jamais envoyée avec ses métadonnées.
            guard case .valide = ClassementDocument.verifierFichier(nom: nom, type: type, taille: octets.count,
                                                                     entete: Array(octets.prefix(12)), tailleMax: Int.max) else {
                return refus(ClassementDocument.verifierFichier(nom: nom, type: type, taille: octets.count,
                                                                entete: Array(octets.prefix(12)), tailleMax: tailleMax))
            }
            switch NormalisationImage.versJPEG(octets, tailleMax: tailleMax) {
            case let .jpeg(jpeg):
                contenu = jpeg
                nomFinal = renommerEnJPEG(nom)
                typeFinal = MimeDocument.jpeg.rawValue
            case .illisible:
                // Jamais l'original avec ses métadonnées : refus (message générique du web, l.402).
                return .refuse(code: .signatureInvalide, message: MessagesDocuments.enregistrementImpossible)
            case .tropLourd:
                return refus(ClassementDocument.verifierFichier(nom: nom, type: type, taille: tailleMax + 1, entete: nil,
                                                                 tailleMax: tailleMax))
            }
        }
        if heif {
            switch NormalisationImage.versJPEG(octets, tailleMax: tailleMax) {
            case let .jpeg(jpeg):
                contenu = jpeg
                nomFinal = renommerEnJPEG(nom)
                typeFinal = MimeDocument.jpeg.rawValue
            case .illisible:
                // Le contrôle du web refuse un HEIC avec son propre message (documentUpload.ts:147).
                return refus(ClassementDocument.verifierFichier(nom: nom, type: "image/heic", taille: octets.count,
                                                                 entete: Array(octets.prefix(12)), tailleMax: tailleMax))
            case .tropLourd:
                return refus(ClassementDocument.verifierFichier(nom: nom, type: type, taille: tailleMax + 1, entete: nil,
                                                                 tailleMax: tailleMax))
            }
        }
        switch ClassementDocument.verifierFichier(nom: nomFinal, type: typeFinal, taille: contenu.count,
                                                  entete: Array(contenu.prefix(12)), tailleMax: tailleMax) {
        case let .valide(mime):
            return .pret(FichierPret(fichier: FichierChoisi(nom: nomFinal, mime: mime, tailleOctets: contenu.count), octets: contenu))
        case let .refuse(code, message):
            return .refuse(code: code, message: message)
        }
    }

    /// `IMG_0001.HEIC` → `IMG_0001.jpg` : le nom suit le contenu converti (séparateurs de chemin retirés).
    static func renommerEnJPEG(_ nom: String) -> String {
        let feuille = ClassementDocument.dernierSegment(nom)
        let base: String
        if let ext = ClassementDocument.extensionDuNom(feuille) {
            base = String(feuille.unicodeScalars.dropLast(ext.unicodeScalars.count + 1))
        } else {
            base = feuille
        }
        let nette = base.trimmingCharacters(in: .whitespaces)
        return "\(nette.isEmpty ? "photo" : nette).\(MimeDocument.jpeg.extensionCanonique)"
    }

    /// Signature `%PDF` : un PDF n'est jamais une image à ré-encoder.
    static func estPDF(_ octets: Data) -> Bool {
        octets.prefix(4).elementsEqual([0x25, 0x50, 0x44, 0x46])
    }

    private static func refus(_ validation: ValidationFichierDocument) -> PreparationFichier {
        switch validation {
        case let .refuse(code, message): return .refuse(code: code, message: message)
        case .valide: return .refuse(code: .nonSupporte, message: MessagesDocuments.enregistrementImpossible)
        }
    }
}
