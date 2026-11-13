import Foundation

/// Copies temporaires des justificatifs consultés (lot 2 T6, blueprint §2.7) : dossier dédié du répertoire temporaire,
/// protection `complete` sur iOS, exclu de la sauvegarde, une copie par consultation. Jamais d'URL signée rendue à
/// l'écran. L'écran (T7, QuickLook) appelle `effacerTout()` à la fermeture de la feuille et au changement d'epoch.
public enum ConsultationDocuments {
    /// Taille maximale relue (borne serveur des justificatifs, `fn_remplacer_document_soignant` l.53113).
    public static let tailleMax = RecuDocument.tailleMaxOctets

    public static var dossier: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("jolene-consultation", isDirectory: true)
    }

    /// Écrit une copie protégée et rend son URL locale ; extension déduite de la signature binaire (QuickLook), nom
    /// assaini comme une clé Storage. Lève `JoleneError` avec le message du web si la copie est impossible.
    public static func ecrire(_ octets: Data, nomFichier: String?) throws -> URL {
        guard !octets.isEmpty, octets.count <= tailleMax else {
            throw JoleneError(.contract, MessagesDocuments.consultationImpossible)
        }
        let mime = ClassementDocument.detecterMimeParSignature(Array(octets.prefix(12))) ?? .pdf
        let nom = ClassementDocument.sanitiserNomFichier(nomFichier ?? "document", mime: mime)
        let gestionnaire = FileManager.default
        do {
            var racine = dossier
            if !gestionnaire.fileExists(atPath: racine.path) {
                try gestionnaire.createDirectory(at: racine, withIntermediateDirectories: true, attributes: attributsProteges)
                var valeurs = URLResourceValues()
                valeurs.isExcludedFromBackup = true
                try racine.setResourceValues(valeurs)
            }
            let sousDossier = racine.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try gestionnaire.createDirectory(at: sousDossier, withIntermediateDirectories: false, attributes: attributsProteges)
            let fichier = sousDossier.appendingPathComponent(nom, isDirectory: false)
            try octets.write(to: fichier, options: optionsEcriture)
            return fichier
        } catch {
            throw JoleneError(.environment, MessagesDocuments.consultationImpossible)
        }
    }

    /// Efface toutes les copies (fermeture de la consultation, déconnexion, changement d'epoch). Sans erreur.
    public static func effacerTout() {
        try? FileManager.default.removeItem(at: dossier)
    }

    private static var attributsProteges: [FileAttributeKey: Any]? {
        #if os(iOS)
        return [.protectionKey: FileProtectionType.complete]
        #else
        return nil
        #endif
    }

    private static var optionsEcriture: Data.WritingOptions {
        #if os(iOS)
        return [.atomic, .completeFileProtection]
        #else
        return [.atomic]
        #endif
    }
}
