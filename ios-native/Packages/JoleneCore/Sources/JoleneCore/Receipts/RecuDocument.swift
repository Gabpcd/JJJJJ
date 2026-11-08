import Foundation

extension MimeDocument: Codable {}

/// Reçu durable d'un envoi de justificatif, v1 (blueprint lot 2 §2.5-§2.6, décision 14).
///
/// Écrit AVANT l'upload Storage avec la clé déterministe du web (`src/pages/DocumentsSoignant.tsx` l.372 :
/// `<uid>/documents/<TYPE>/<ms>-<nom assaini>`), contrôlée comme `fn_remplacer_document_soignant`
/// (`public.sql` l.53103-53109). Aucun octet de fichier, aucune URL signée. Phases : `prepared` → `started`
/// → `stored` → `registered` (ligne `documents_soignants`) → `verification_demandee` (`verify-document`
/// une seule fois) ; `refused` depuis `started` ou `stored` (le serveur a refusé : `cleanup_orphan`) ;
/// `not_sent` depuis `prepared` ou `started` (relecture : ni objet ni ligne). La réconciliation par `s3_cle`
/// peut sauter de `started` à `stored` (objet présent sans ligne) ou à `registered` (ligne relue).
public struct RecuDocument: RecuDurable, Codable {
    public static let domaine = "document"
    public static let versionCourante = 1
    /// Bornes de `fn_remplacer_document_soignant` (l.53102, l.53110-53113).
    public static let longueurMaxCle = 512
    public static let tailleMaxOctets = 10_485_760

    public enum Phase: String, Codable, Sendable {
        case prepared, started, stored, registered, refused
        case verificationDemandee = "verification_demandee"
        case notSent = "not_sent"
    }

    public internal(set) var version: Int
    public internal(set) var userId: String
    public internal(set) var epoch: Int
    public internal(set) var s3Cle: String
    public internal(set) var typeDocument: String
    public internal(set) var mime: MimeDocument
    public internal(set) var tailleOctets: Int
    public internal(set) var documentId: String?
    public internal(set) var phase: Phase

    enum CodingKeys: String, CodingKey, CaseIterable {
        case version, epoch, mime, phase
        case userId = "user_id"
        case s3Cle = "s3_cle"
        case typeDocument = "type_document"
        case tailleOctets = "taille_octets"
        case documentId = "document_id"
    }

    public var estTermine: Bool { phase == .verificationDemandee || phase == .refused || phase == .notSent }

    // MARK: - Préparation

    /// Prépare l'envoi : clé `<userId>/documents/<typeDocument>/<horodatageMs>-<nom assaini>`
    /// (`ClassementDocument.sanitiserNomFichier`, T2). `existant` encore en vol → `.recuEnCours`.
    public static func preparer(userId: String, epoch: Int, typeDocument: String, fichier: FichierChoisi,
                                horodatageMs: Int64, existant: RecuDocument? = nil) throws -> RecuDocument {
        if let existant {
            guard existant.userId == userId else { throw RecuErreur.utilisateurDifferent }
            guard existant.estTermine else { throw RecuErreur.recuEnCours }
        }
        guard RecuValidation.identifiantValide(userId) else { throw RecuErreur.champInvalide("userId") }
        guard typeDocumentValide(typeDocument) else { throw RecuErreur.champInvalide("typeDocument") }
        guard horodatageMs >= 0 else { throw RecuErreur.champInvalide("horodatageMs") }
        let nom = ClassementDocument.sanitiserNomFichier(fichier.nom, mime: fichier.mime)
        let recu = RecuDocument(version: versionCourante, userId: userId, epoch: epoch,
                                s3Cle: "\(userId)/documents/\(typeDocument)/\(horodatageMs)-\(nom)", typeDocument: typeDocument,
                                mime: fichier.mime, tailleOctets: fichier.tailleOctets, documentId: nil, phase: .prepared)
        try recu.valider()
        return recu
    }

    /// Contrôles de `fn_remplacer_document_soignant` (l.53103-53109) et de `cleanup_orphan`, en plus strict :
    /// exactement quatre segments (le serveur ne contrôle que le quatrième).
    public static func cleValide(_ cle: String, userId: String, typeDocument: String) -> Bool {
        guard cle.count <= longueurMaxCle, cle.hasPrefix("\(userId)/documents/\(typeDocument)/"),
              !cle.contains(".."), !cle.contains("\\") else { return false }
        let segments = cle.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count == 4, let feuille = segments.last, !feuille.isEmpty else { return false }
        return feuille.unicodeScalars.allSatisfy { scalaire in
            switch scalaire {
            case "a"..."z", "A"..."Z", "0"..."9", ".", "_", "-": return true
            default: return false
            }
        }
    }

    // MARK: - Transitions

    /// `prepared` → `started`, juste avant l'upload Storage (`upsert: false`).
    public func demarrer() throws -> RecuDocument {
        try passer(vers: .started, depuis: [.prepared])
    }

    /// `started` → `stored` : upload accepté, ou objet relu présent (`exists(path:)`) sans ligne.
    public func stocker() throws -> RecuDocument {
        try passer(vers: .stored, depuis: [.started])
    }

    /// `started` ou `stored` → `registered` : `fn_remplacer_document_soignant` accepté ou ligne relue par `s3_cle`.
    public func enregistrer(documentId: String) throws -> RecuDocument {
        var suivant = try passer(vers: .registered, depuis: [.started, .stored])
        guard RecuValidation.identifiantValide(documentId) else { throw RecuErreur.champInvalide("documentId") }
        suivant.documentId = documentId
        return suivant
    }

    /// `registered` → `verification_demandee` : `verify-document` appelée une seule fois pour ce document.
    public func demanderVerification() throws -> RecuDocument {
        try passer(vers: .verificationDemandee, depuis: [.registered])
    }

    /// `started` ou `stored` → `refused` : refus serveur, l'objet orphelin est nettoyé (`cleanup_orphan`).
    public func refuser() throws -> RecuDocument {
        try passer(vers: .refused, depuis: [.started, .stored])
    }

    /// `prepared` (hors ligne) ou `started` (relecture : ni objet ni ligne) → `not_sent` ; nouvelle sélection.
    public func marquerNonEnvoye() throws -> RecuDocument {
        try passer(vers: .notSent, depuis: [.prepared, .started])
    }

    private func passer(vers cible: Phase, depuis admises: Set<Phase>) throws -> RecuDocument {
        guard admises.contains(phase) else { throw RecuErreur.transitionInterdite(de: phase.rawValue, vers: cible.rawValue) }
        var suivant = self
        suivant.phase = cible
        return suivant
    }

    // MARK: - Encodage durable

    public func encoder() throws -> Data {
        try RecuValidation.encoder(self)
    }

    public static func decoder(_ data: Data, userId: String) throws -> RecuDocument {
        let recu = try RecuValidation.decoderStrict(RecuDocument.self, data, autorisees: Set(CodingKeys.allCases.map(\.rawValue)))
        do { try recu.valider() } catch { throw RecuErreur.illisible }
        guard recu.userId == userId else { throw RecuErreur.utilisateurDifferent }
        return recu
    }

    // MARK: - Invariants

    func valider() throws {
        guard version == Self.versionCourante else { throw RecuErreur.champInvalide("version") }
        guard RecuValidation.identifiantValide(userId) else { throw RecuErreur.champInvalide("userId") }
        guard epoch >= 0 else { throw RecuErreur.champInvalide("epoch") }
        guard Self.typeDocumentValide(typeDocument) else { throw RecuErreur.champInvalide("typeDocument") }
        guard (1...Self.tailleMaxOctets).contains(tailleOctets) else { throw RecuErreur.champInvalide("tailleOctets") }
        guard Self.cleValide(s3Cle, userId: userId, typeDocument: typeDocument) else { throw RecuErreur.champInvalide("s3Cle") }
        switch phase {
        case .registered, .verificationDemandee:
            guard let documentId, RecuValidation.identifiantValide(documentId) else { throw RecuErreur.champInvalide("documentId") }
        case .prepared, .started, .stored, .refused, .notSent:
            guard documentId == nil else { throw RecuErreur.champInvalide("documentId") }
        }
    }

    /// Libellé de l'énumération `type_document` : `^[A-Z][A-Z0-9_]*$` (jamais de séparateur de chemin).
    static func typeDocumentValide(_ valeur: String) -> Bool {
        guard let premier = valeur.unicodeScalars.first, ("A"..."Z").contains(premier) else { return false }
        return valeur.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
    }
}
