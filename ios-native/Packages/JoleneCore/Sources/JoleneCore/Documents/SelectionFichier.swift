import Foundation
import UniformTypeIdentifiers

/// Fichier rendu par un sélecteur (appareil photo, photothèque, Fichiers, ou sa variante démo `DemoMediaPicker`), avant
/// toute préparation (lot 2 T7). Les octets ne vivent qu'en mémoire, le temps de `preparer()` puis de l'unique envoi
/// (décision 14 : aucun octet de document conservé sur disque). `source` décide de la normalisation (`SourceFichier`).
public struct FichierSelectionne: Equatable, Sendable {
    public var nom: String
    /// Type MIME annoncé par le sélecteur ; vide si inconnu (le contrôle du web décide ensuite).
    public var type: String
    public var octets: Data
    public var source: SourceFichier

    public init(nom: String, type: String, octets: Data, source: SourceFichier) {
        self.nom = nom; self.type = type; self.octets = octets; self.source = source
    }

    /// Même chaîne que tout fichier choisi : HEIC/HEIF et photothèque → JPEG sans métadonnée, puis contrôle du web.
    public func preparer() -> PreparationFichier {
        FichierDocument.preparer(nom: nom, type: type, octets: octets, source: source)
    }

    /// Photo de l'appareil (`UIImagePickerController`, `jpegData(0.8)`) : nom `photo_<ms>.jpg` du web natif
    /// (`ModalTeleversement.tsx` l.102).
    public static func photo(jpeg: Data, prisLe: Date) -> FichierSelectionne {
        FichierSelectionne(nom: "photo_" + String(DateHeureParis.millisecondes(prisLe)) + ".jpg",
                           type: MimeDocument.jpeg.rawValue, octets: jpeg, source: .camera)
    }

    /// Image de la photothèque (`PHPickerViewController`) : nom suggéré par le sélecteur, sinon `galerie_<ms>` du web natif
    /// (l.154), extension et MIME du type uniforme choisi (l'image est ré-encodée en JPEG par `preparer()`).
    public static func galerie(octets: Data, typeIdentifier: String, nomSuggere: String?, choisiLe: Date) -> FichierSelectionne {
        let base = nomSuggere.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            ?? "galerie_" + String(DateHeureParis.millisecondes(choisiLe))
        let ext = UTType(typeIdentifier)?.preferredFilenameExtension ?? ""
        return FichierSelectionne(nom: ext.isEmpty ? base : base + "." + ext, type: mime(typeIdentifier: typeIdentifier),
                                  octets: octets, source: .phototheque)
    }

    /// Fichier copié par `UIDocumentPickerViewController` : nom d'origine, MIME déduit de son extension.
    public static func fichier(nom: String, octets: Data) -> FichierSelectionne {
        FichierSelectionne(nom: nom, type: mime(nomFichier: nom), octets: octets, source: .fichiers)
    }

    /// MIME préféré d'un type uniforme, vide si inconnu.
    public static func mime(typeIdentifier: String) -> String {
        UTType(typeIdentifier)?.preferredMIMEType ?? ""
    }

    /// MIME préféré de l'extension d'un nom de fichier (casse ignorée), vide si inconnue ou absente.
    public static func mime(nomFichier: String) -> String {
        let ext = (nomFichier as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return "" }
        return UTType(filenameExtension: ext)?.preferredMIMEType ?? ""
    }
}
