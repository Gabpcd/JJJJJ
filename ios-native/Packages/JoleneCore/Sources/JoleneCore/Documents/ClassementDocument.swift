import Foundation

/// Types MIME acceptés pour un justificatif (`DOCUMENT_MIME_TYPES` du web).
public enum MimeDocument: String, CaseIterable, Sendable {
    case pdf = "application/pdf"
    case jpeg = "image/jpeg"
    case png = "image/png"
    case webp = "image/webp"

    /// Sous-ensemble image (`IMAGE_DOCUMENT_MIME_TYPES`).
    public static let images: [MimeDocument] = [.jpeg, .png, .webp]

    /// `EXTENSION_BY_MIME` : extension canonique du fichier téléversé.
    public var extensionCanonique: String {
        switch self {
        case .pdf: return "pdf"
        case .jpeg: return "jpg"
        case .png: return "png"
        case .webp: return "webp"
        }
    }
}

/// Classement préalable (`DocumentUploadFormat`).
public enum FormatDocumentUpload: String, Sendable {
    case supporte = "SUPPORTED"
    case heicNonSupporte = "HEIC_UNSUPPORTED"
    case nonSupporte = "UNSUPPORTED"
}

/// Motif de refus (`DocumentUploadFailure`).
public enum EchecFichierDocument: String, Sendable {
    case vide = "EMPTY"
    case tropLourd = "TOO_LARGE"
    case heicNonSupporte = "HEIC_UNSUPPORTED"
    case nonSupporte = "UNSUPPORTED"
    case signatureInvalide = "INVALID_SIGNATURE"
}

/// Verdict du contrôle avant envoi (`DocumentUploadValidation`) ; l'extension d'un fichier
/// valide est toujours `mime.extensionCanonique`.
public enum ValidationFichierDocument: Equatable, Sendable {
    case valide(mime: MimeDocument)
    case refuse(code: EchecFichierDocument, message: String)
}

/// Port de `src/lib/documentUpload.ts` : contrôle déterministe d'un fichier juste avant son
/// téléversement (taille, MIME déclaré, extension, signature binaire). Le serveur refait le même
/// contrôle (`verify-document`) ; celui-ci donne une erreur immédiate et compréhensible.
/// Messages verbatim du web.
public enum ClassementDocument {
    public static let tailleMaxParDefaut = 10 * 1024 * 1024

    static let mimeParExtension: [String: MimeDocument] = [
        "pdf": .pdf, "jpg": .jpeg, "jpeg": .jpeg, "png": .png, "webp": .webp,
    ]

    /// Classe un fichier par son nom et son type déclaré. Un HEIC/HEIF est isolé (l'API IA ne
    /// l'accepte pas) ; quand une extension est présente, elle doit confirmer le MIME déclaré.
    public static func classerFormat(nom: String, type: String) -> FormatDocumentUpload {
        let mime = mimeDeclare(type)
        let ext = extensionDuNom(nom)
        if mime == "image/heic" || mime == "image/heif" || ext == "heic" || ext == "heif" {
            return .heicNonSupporte
        }
        let mimeExtension = ext.flatMap { mimeParExtension[$0] }
        if mime.isEmpty || mime == "application/octet-stream" {
            return mimeExtension == nil ? .nonSupporte : .supporte
        }
        guard let declare = MimeDocument(rawValue: mime) else { return .nonSupporte }
        if ext != nil, mimeExtension != declare { return .nonSupporte }
        return .supporte
    }

    /// Contrôle complet. `entete` : premiers octets du fichier (au moins les 12 premiers s'il en
    /// a autant), `nil` si sa lecture a échoué ; seuls les 12 premiers sont examinés.
    public static func verifierFichier(nom: String, type: String, taille: Int, entete: [UInt8]?,
                                       tailleMax: Int = tailleMaxParDefaut,
                                       mimesAutorises: [MimeDocument] = MimeDocument.allCases) -> ValidationFichierDocument {
        if taille == 0 {
            // source: src/lib/documentUpload.ts:135
            return .refuse(code: .vide, message: "Le fichier sélectionné est vide.")
        }
        if taille > tailleMax {
            let maxMo = Int((Double(tailleMax) / Double(1024 * 1024)).rounded(.down))
            // source: src/lib/documentUpload.ts:139
            return .refuse(code: .tropLourd, message: "Le fichier ne doit pas dépasser \(maxMo) Mo.")
        }
        switch classerFormat(nom: nom, type: type) {
        case .heicNonSupporte:
            // source: src/lib/documentUpload.ts:147
            return .refuse(code: .heicNonSupporte,
                           message: "Le format HEIC/HEIF ne peut pas être vérifié. Prenez une photo depuis Jolene ou choisissez un PDF, JPEG, PNG ou WebP.")
        case .nonSupporte:
            // source: src/lib/documentUpload.ts:154
            return .refuse(code: .nonSupporte,
                           message: "Format non pris en charge, ou extension et type de fichier incohérents. Utilisez un PDF, JPEG, PNG ou WebP.")
        case .supporte:
            break
        }

        let attendu = MimeDocument(rawValue: mimeDeclare(type)) ?? extensionDuNom(nom).flatMap { mimeParExtension[$0] }
        guard let attendu, mimesAutorises.contains(attendu) else {
            // source: src/lib/documentUpload.ts:166
            return .refuse(code: .nonSupporte, message: "Ce type de fichier n’est pas autorisé ici.")
        }
        guard let entete else {
            // source: src/lib/documentUpload.ts:174
            return .refuse(code: .signatureInvalide, message: "Impossible de lire le fichier sélectionné.")
        }
        guard let detecte = detecterMimeParSignature(Array(entete.prefix(12))), detecte == attendu, mimesAutorises.contains(detecte) else {
            // source: src/lib/documentUpload.ts:180
            return .refuse(code: .signatureInvalide,
                           message: "Le contenu du fichier ne correspond pas au format annoncé. Exportez-le à nouveau en PDF, JPEG, PNG ou WebP.")
        }
        return .valide(mime: detecte)
    }

    /// Segment de chemin sans séparateur, sans `..`, sans accent, borné à 80 caractères, suivi de
    /// l'extension canonique du MIME vérifié.
    public static func sanitiserNomFichier(_ nom: String, mime: MimeDocument) -> String {
        let segment = dernierSegment(nom)
        let feuille = segment.isEmpty ? "document" : segment
        let scalaires = Array(feuille.unicodeScalars)
        let sansExtension: String
        if let ext = extensionDuNom(feuille) {
            var vue = String.UnicodeScalarView()
            vue.append(contentsOf: scalaires.dropLast(ext.unicodeScalars.count + 1))
            sansExtension = String(vue)
        } else {
            sansExtension = feuille
        }

        // NFD, retrait des diacritiques combinants U+0300–U+036F, puis toute suite d'autres
        // caractères que [a-zA-Z0-9_-] devient un seul tiret.
        var base = ""
        var dansSuite = false
        for scalaire in sansExtension.decomposedStringWithCanonicalMapping.unicodeScalars {
            if (0x0300...0x036F).contains(scalaire.value) { continue }
            if estCaractereDeNom(scalaire) {
                base.unicodeScalars.append(scalaire)
                dansSuite = false
            } else if !dansSuite {
                base.append("-")
                dansSuite = true
            }
        }
        // Les diacritiques retirés ne coupent pas une suite (le web les retire avant de remplacer).
        let rognee = String(base.drop { $0 == "-" }.reversed().drop { $0 == "-" }.reversed())
        let bornee = String(rognee.prefix(80))
        return "\(bornee.isEmpty ? "document" : bornee).\(mime.extensionCanonique)"
    }

    // MARK: - Outils (mêmes définitions que le web)

    /// `type.trim().toLowerCase()` (espaces de bord au sens de `String.prototype.trim`).
    static func mimeDeclare(_ type: String) -> String {
        JSTexte.trim(type).lowercased()
    }

    /// Dernier segment après `/` ou `\`, puis `/\.([a-z0-9]+)$/i` en minuscules.
    static func extensionDuNom(_ nom: String) -> String? {
        var ext = String.UnicodeScalarView()
        let scalaires = Array(dernierSegment(nom).unicodeScalars)
        var index = scalaires.count - 1
        while index >= 0, estAlphanumeriqueASCII(scalaires[index]) { index -= 1 }
        guard index >= 0, index < scalaires.count - 1, scalaires[index] == "." else { return nil }
        ext.append(contentsOf: scalaires[(index + 1)...])
        return String(ext).lowercased()
    }

    static func dernierSegment(_ nom: String) -> String {
        var segment = String.UnicodeScalarView()
        for scalaire in nom.unicodeScalars {
            if scalaire == "/" || scalaire == "\\" { segment = String.UnicodeScalarView() } else { segment.append(scalaire) }
        }
        return String(segment)
    }

    static func detecterMimeParSignature(_ octets: [UInt8]) -> MimeDocument? {
        func commencePar(_ signature: [UInt8]) -> Bool {
            octets.count >= signature.count && zip(octets, signature).allSatisfy { $0 == $1 }
        }
        if commencePar([0x25, 0x50, 0x44, 0x46, 0x2d]) { return .pdf } // %PDF-
        if commencePar([0xff, 0xd8, 0xff]) { return .jpeg }
        if commencePar([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) { return .png }
        if commencePar([0x52, 0x49, 0x46, 0x46]), octets.count >= 12,
           octets[8] == 0x57, octets[9] == 0x45, octets[10] == 0x42, octets[11] == 0x50 { return .webp } // RIFF…WEBP
        return nil
    }

    private static func estAlphanumeriqueASCII(_ scalaire: Unicode.Scalar) -> Bool {
        switch scalaire {
        case "a"..."z", "A"..."Z", "0"..."9": return true
        default: return false
        }
    }

    private static func estCaractereDeNom(_ scalaire: Unicode.Scalar) -> Bool {
        estAlphanumeriqueASCII(scalaire) || scalaire == "_" || scalaire == "-"
    }
}

/// Primitives de chaîne JavaScript reproduites à l'identique pour les ports golden.
enum JSTexte {
    /// Espaces retirés par `String.prototype.trim` : WhiteSpace (dont U+FEFF et la catégorie Zs)
    /// et LineTerminator. Diffère de `CharacterSet.whitespacesAndNewlines` (U+FEFF, U+0085).
    static func estEspaceJS(_ scalaire: Unicode.Scalar) -> Bool {
        switch scalaire.value {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }

    static func trim(_ texte: String) -> String {
        let scalaires = Array(texte.unicodeScalars)
        guard let debut = scalaires.firstIndex(where: { !estEspaceJS($0) }),
              let fin = scalaires.lastIndex(where: { !estEspaceJS($0) }) else { return "" }
        var vue = String.UnicodeScalarView()
        vue.append(contentsOf: scalaires[debut...fin])
        return String(vue)
    }
}
