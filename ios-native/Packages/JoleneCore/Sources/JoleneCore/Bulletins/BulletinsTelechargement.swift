import CryptoKit
import Foundation

/// Refus d'ouverture d'une copie officielle (L4-T10), texte du web (`src/lib/copiesBulletins.ts` l.225-238) :
/// - `retiree` : copie `RETIREE` dans la liste (aucun appel), ou 410 `COPIE_RETIREE` de l'edge (la liste est relue) ;
/// - `integrite` : taille ou SHA-256 des octets reçus différents de la ligne — le PDF n'est jamais affiché ;
/// - `indisponible` : tout autre refus de l'edge (403, 409, 422, 503…), réponse qui n'est pas un PDF (`application/json`
///   en 200, portail captif), corps vide.
/// Aucun octet ni code machine n'est porté par l'erreur : rien du bulletin ne peut partir dans un journal.
public enum RefusCopieBulletin: Error, Equatable, Sendable, LocalizedError {
    case retiree
    case integrite
    case indisponible

    public var message: String {
        switch self {
        case .retiree: return LibellesWeb.CopiesBulletins.copieDejaRetiree
        case .integrite: return LibellesWeb.CopiesBulletins.integriteNonConfirmee
        case .indisponible: return LibellesWeb.CopiesBulletins.pdfIndisponible
        }
    }

    public var errorDescription: String? { message }
}

/// Contrôles côté client des octets d'une copie (port de `ouvrirCopieBulletin`, `copiesBulletins.ts` l.233-238) :
/// type `application/pdf`, corps non vide, taille et SHA-256 (CryptoKit) égaux à ceux de la ligne validée. L'edge
/// contrôle déjà taille et empreinte côté serveur (`handler.ts` l.55-58) : le client ne s'y fie pas.
public enum BulletinsTelechargement {
    public static let typePDF = "application/pdf"
    /// Borne d'un téléchargement, comme le web (`avecDelai(…, 30_000)`, l.232).
    public static let delaiSecondes: TimeInterval = 30
    /// Edge et action (`supabase/functions/copies-bulletins/handler.ts`).
    public static let edge = "copies-bulletins"
    public static let action = "telecharger"

    /// Empreinte SHA-256 en hexadécimal minuscule (format de `sha256` dans la ligne).
    public static func sha256(_ donnees: Data) -> String {
        SHA256.hash(data: donnees).map { String(format: "%02x", $0) }.joined()
    }

    /// `Content-Type` réduit à son type de média (paramètres et casse ignorés).
    public static func estPDF(typeContenu: String?) -> Bool {
        guard let typeContenu else { return false }
        let media = typeContenu.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
        return media.trimmingCharacters(in: .whitespaces).lowercased() == typePDF
    }

    /// Octets reçus pour `copie`, vérifiés ; lève `RefusCopieBulletin` sinon.
    public static func verifier(donnees: Data, typeContenu: String?, copie: CopieBulletin) throws -> PDFVerifie {
        guard estPDF(typeContenu: typeContenu), !donnees.isEmpty else { throw RefusCopieBulletin.indisponible }
        guard donnees.count == copie.tailleOctets else { throw RefusCopieBulletin.integrite }
        let empreinte = sha256(donnees)
        guard empreinte == copie.sha256 else { throw RefusCopieBulletin.integrite }
        return PDFVerifie(donnees: donnees, sha256: empreinte)
    }
}

/// Copie temporaire d'un PDF vérifié, pour la feuille de partage seulement (L4-T10, `LOT4_PLAN.md` §3 T10) : dossier
/// temporaire de l'app, un sous-dossier par copie, protection `complete`, exclue de la sauvegarde ; effacée à la
/// fermeture de la feuille et à la fermeture du lecteur (`effacer`, `effacerTout`). L'affichage lit les octets en
/// mémoire : aucun fichier n'est écrit pour lire un bulletin. Jamais d'URL signée.
public enum FichierCopieBulletinTemporaire {
    /// Nom du fichier partagé : celui que l'edge annonce (`Content-Disposition`, `handler.ts` l.68-70), sans nom ni période.
    public static let nomFichier = "copie-bulletin.pdf"

    public static func dossier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("jolene-copies-bulletins", isDirectory: true)
    }

    /// Écrit les octets vérifiés ; lève `RefusCopieBulletin.indisponible` (aucun chemin ni octet dans l'erreur).
    public static func ecrire(_ pdf: PDFVerifie) throws -> URL {
        let gestionnaire = FileManager.default
        var sousDossier = dossier().appendingPathComponent(UUID().uuidString, isDirectory: true)
        var fichier = sousDossier.appendingPathComponent(nomFichier)
        do {
            try gestionnaire.createDirectory(at: sousDossier, withIntermediateDirectories: true)
            #if os(iOS)
            let options: Data.WritingOptions = [.atomic, .completeFileProtection]
            #else
            let options: Data.WritingOptions = [.atomic] // `swift test` macOS : pas de classe de protection
            #endif
            try pdf.donnees.write(to: fichier, options: options)
            var exclusion = URLResourceValues()
            exclusion.isExcludedFromBackup = true
            try sousDossier.setResourceValues(exclusion)
            try fichier.setResourceValues(exclusion)
            return fichier
        } catch {
            try? gestionnaire.removeItem(at: sousDossier)
            throw RefusCopieBulletin.indisponible
        }
    }

    /// Efface une copie (et son sous-dossier) ; sans effet hors du dossier temporaire des copies.
    public static func effacer(_ url: URL) {
        let racine = dossier().standardizedFileURL.path
        let parent = url.deletingLastPathComponent().standardizedFileURL
        guard parent.path.hasPrefix(racine + "/") else { return }
        try? FileManager.default.removeItem(at: parent)
    }

    /// Efface toutes les copies (fermeture du lecteur, reprise après une interruption).
    public static func effacerTout() {
        try? FileManager.default.removeItem(at: dossier())
    }
}
