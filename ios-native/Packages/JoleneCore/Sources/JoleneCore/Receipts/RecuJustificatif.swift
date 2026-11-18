import Foundation

/// Reçu durable du justificatif d'une annulation de candidature, v1 (lot 1, T7 ; PRINCIPES §4 ; consignes « Lot 1 T7 » de
/// `docs/mobile-swift/DECISIONS_LOT2.md` : domaine `justificatif`, journal `ReceiptJournal` repris sans changer son API).
///
/// Écrit AVANT le dépôt Storage avec le chemin déterministe du web (`ModaleAnnulationCandidature.tsx` l.82-83 :
/// `<uid>/annulations-candidature/<candidatureId>/<Date.now()>_<nom assaini>`, bucket `justificatifs`, `upsert: false`).
/// Aucun octet de fichier, aucune URL. Phases :
/// - `prepared` → `started` (juste avant le dépôt) ou `not_sent` ;
/// - `started` → `stored` (dépôt accepté, ou objet relu présent) ou `not_sent` (refus certain, ou objet relu absent) ;
/// - `stored` → `rattache` (annulation relue avec ce chemin) ou `non_rattache` (annulation refusée par le serveur, ou
///   abandonnée pour une autre candidature : l'objet reste, comme sur le web, qui ne le nettoie pas).
/// `rattache`, `non_rattache` et `not_sent` sont terminaux. Un reçu `stored` de la même candidature est repris tel quel
/// par l'essai suivant : l'objet n'est jamais déposé deux fois (pas de doublon à la reprise).
public struct RecuJustificatif: RecuDurable, Codable {
    public static let domaine = "justificatif"
    public static let versionCourante = 1
    /// Borne du web (`verifierFichierDocument(fichier, { maxBytes: 5 * 1024 * 1024 })`, l.72 et l.208).
    public static let tailleMaxOctets = 5 * 1024 * 1024
    public static let longueurMaxChemin = 512
    /// Segment fixe du chemin (l.83).
    public static let segment = "annulations-candidature"

    public enum Phase: String, Codable, Sendable {
        case prepared, started, stored, rattache
        case nonRattache = "non_rattache"
        case notSent = "not_sent"
    }

    public internal(set) var version: Int
    public internal(set) var userId: String
    public internal(set) var candidatureId: String
    public internal(set) var chemin: String
    public internal(set) var mime: MimeDocument
    public internal(set) var tailleOctets: Int
    /// Nom d'origine du fichier (affiché à la reprise) ; le chemin porte le nom assaini.
    public internal(set) var nomFichier: String
    public internal(set) var phase: Phase

    enum CodingKeys: String, CodingKey, CaseIterable {
        case version, chemin, mime, phase
        case userId = "user_id"
        case candidatureId = "candidature_id"
        case tailleOctets = "taille_octets"
        case nomFichier = "nom_fichier"
    }

    public var estTermine: Bool { phase == .rattache || phase == .nonRattache || phase == .notSent }

    /// L'essai est son chemin (horodatage en millisecondes compris) : deux sélections donnent deux essais.
    public var attemptId: String { chemin }

    public func verifierSuccession(apres precedent: RecuJustificatif?) throws {
        guard let precedent else {
            guard phase == .prepared else { throw RecuErreur.premierEnregistrement(vers: phase.rawValue) }
            return
        }
        let immuables: [(String, Bool)] = [
            ("version", version == precedent.version), ("userId", userId == precedent.userId),
            ("candidatureId", candidatureId == precedent.candidatureId), ("chemin", chemin == precedent.chemin),
            ("mime", mime == precedent.mime), ("tailleOctets", tailleOctets == precedent.tailleOctets),
            ("nomFichier", nomFichier == precedent.nomFichier),
        ]
        if let ecart = immuables.first(where: { !$0.1 }) { throw RecuErreur.champInvalide(ecart.0) }
        if phase == precedent.phase { return }
        let admises: [Phase: Set<Phase>] = [
            .prepared: [.started, .notSent],
            .started: [.stored, .notSent],
            .stored: [.rattache, .nonRattache],
        ]
        guard admises[precedent.phase, default: []].contains(phase) else {
            throw RecuErreur.transitionInterdite(de: precedent.phase.rawValue, vers: phase.rawValue)
        }
    }

    // MARK: - Préparation

    /// Prépare le dépôt : chemin `<userId>/annulations-candidature/<candidatureId>/<horodatageMs>_<nom assaini>`
    /// (`ClassementDocument.sanitiserNomFichier`, même assainissement que le web). `existant` encore en vol →
    /// `.recuEnCours` ; fichier hors des bornes du web → `.champInvalide`.
    public static func preparer(userId: String, candidatureId: String, fichier: FichierChoisi, horodatageMs: Int64,
                                existant: RecuJustificatif? = nil) throws -> RecuJustificatif {
        if let existant {
            guard existant.userId == userId else { throw RecuErreur.utilisateurDifferent }
            guard existant.estTermine else { throw RecuErreur.recuEnCours }
        }
        guard RecuValidation.identifiantValide(userId) else { throw RecuErreur.champInvalide("userId") }
        guard RecuValidation.identifiantValide(candidatureId) else { throw RecuErreur.champInvalide("candidatureId") }
        guard horodatageMs >= 0 else { throw RecuErreur.champInvalide("horodatageMs") }
        let nom = ClassementDocument.sanitiserNomFichier(fichier.nom, mime: fichier.mime)
        let recu = RecuJustificatif(version: versionCourante, userId: userId, candidatureId: candidatureId,
                                    chemin: "\(userId)/\(segment)/\(candidatureId)/\(horodatageMs)_\(nom)",
                                    mime: fichier.mime, tailleOctets: fichier.tailleOctets, nomFichier: fichier.nom,
                                    phase: .prepared)
        try recu.valider()
        return recu
    }

    /// Chemin admis : quatre segments `<userId>/annulations-candidature/<candidatureId>/<feuille>`, sans `..` ni `\`,
    /// feuille `[A-Za-z0-9._-]` (plus strict que `fn_peut_deposer_justificatif`, qui ne contrôle que le premier segment).
    public static func cheminValide(_ chemin: String, userId: String, candidatureId: String) -> Bool {
        guard chemin.count <= longueurMaxChemin, chemin.hasPrefix("\(userId)/\(segment)/\(candidatureId)/"),
              !chemin.contains(".."), !chemin.contains("\\") else { return false }
        let segments = chemin.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count == 4, let feuille = segments.last, !feuille.isEmpty else { return false }
        return feuille.unicodeScalars.allSatisfy { scalaire in
            switch scalaire {
            case "a"..."z", "A"..."Z", "0"..."9", ".", "_", "-": return true
            default: return false
            }
        }
    }

    // MARK: - Transitions

    /// `prepared` → `started`, juste avant le dépôt.
    public func demarrer() throws -> RecuJustificatif { try passer(vers: .started, depuis: [.prepared]) }

    /// `started` → `stored` : dépôt accepté, ou objet relu présent.
    public func stocker() throws -> RecuJustificatif { try passer(vers: .stored, depuis: [.started]) }

    /// `prepared` ou `started` → `not_sent` : rien n'est déposé (refus certain, hôte injoignable, objet relu absent).
    public func marquerNonEnvoye() throws -> RecuJustificatif { try passer(vers: .notSent, depuis: [.prepared, .started]) }

    /// `stored` → `rattache` : annulation acceptée et relue avec ce chemin.
    public func rattacher() throws -> RecuJustificatif { try passer(vers: .rattache, depuis: [.stored]) }

    /// `stored` → `non_rattache` : annulation refusée par le serveur, ou abandonnée pour une autre candidature.
    public func abandonner() throws -> RecuJustificatif { try passer(vers: .nonRattache, depuis: [.stored]) }

    private func passer(vers cible: Phase, depuis admises: Set<Phase>) throws -> RecuJustificatif {
        guard admises.contains(phase) else { throw RecuErreur.transitionInterdite(de: phase.rawValue, vers: cible.rawValue) }
        var suivant = self
        suivant.phase = cible
        return suivant
    }

    // MARK: - Encodage durable

    public func encoder() throws -> Data {
        try RecuValidation.encoder(self)
    }

    public static func decoder(_ data: Data, userId: String) throws -> RecuJustificatif {
        let recu = try RecuValidation.decoderStrict(RecuJustificatif.self, data,
                                                    autorisees: Set(CodingKeys.allCases.map(\.rawValue)))
        do { try recu.valider() } catch { throw RecuErreur.illisible }
        guard recu.userId == userId else { throw RecuErreur.utilisateurDifferent }
        return recu
    }

    // MARK: - Invariants

    func valider() throws {
        guard version == Self.versionCourante else { throw RecuErreur.champInvalide("version") }
        guard RecuValidation.identifiantValide(userId) else { throw RecuErreur.champInvalide("userId") }
        guard RecuValidation.identifiantValide(candidatureId) else { throw RecuErreur.champInvalide("candidatureId") }
        guard (1...Self.tailleMaxOctets).contains(tailleOctets) else { throw RecuErreur.champInvalide("tailleOctets") }
        guard Self.cheminValide(chemin, userId: userId, candidatureId: candidatureId) else { throw RecuErreur.champInvalide("chemin") }
        guard nomFichier.unicodeScalars.contains(where: { $0 != " " }), nomFichier.unicodeScalars.count <= 255 else {
            throw RecuErreur.champInvalide("nomFichier")
        }
    }
}
