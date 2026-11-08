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

/// Chaîne de préparation d'un justificatif (lot 2 T6, blueprint §2.5) : un HEIC/HEIF (annoncé ou reconnu à sa boîte
/// `ftyp`) devient un JPEG sans métadonnée (`NormalisationImage`), puis tout fichier passe le contrôle du web
/// (`ClassementDocument.verifierFichier` : taille, MIME, extension, signature binaire). PNG, JPEG, WebP et PDF ne sont
/// jamais ré-encodés.
public enum FichierDocument {
    public static func preparer(nom: String, type: String, octets: Data,
                                tailleMax: Int = ClassementDocument.tailleMaxParDefaut) -> PreparationFichier {
        var nomFinal = nom
        var typeFinal = type
        var contenu = octets
        let heif = !octets.isEmpty
            && (ClassementDocument.classerFormat(nom: nom, type: type) == .heicNonSupporte || NormalisationImage.estHEIF(octets))
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

    private static func refus(_ validation: ValidationFichierDocument) -> PreparationFichier {
        switch validation {
        case let .refuse(code, message): return .refuse(code: code, message: message)
        case .valide: return .refuse(code: .nonSupporte, message: MessagesDocuments.enregistrementImpossible)
        }
    }
}
