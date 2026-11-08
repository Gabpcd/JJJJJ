import Foundation

/// Reçu durable d'un scan de pointage, v1 (blueprint lot 2 §2.5-§2.6, décision 2, PRINCIPES §4).
///
/// Écrit AVANT `fn_scanner_code_pointage` (`prepared`), puis `started` juste avant l'unique requête.
/// Le code saisi, les coordonnées et tout jeton du serveur n'y figurent jamais. Aucune file, aucun renvoi :
/// une réponse perdue se réconcilie par relecture de `scans_pointage` (`reconcilier(scans:relueLe:)`) —
/// une preuve absente de la baseline et du même terminal prouve la réception ; son absence ne prouve la
/// non-réception que 8 s après l'envoi. Phases : `prepared` → `started` → `refused` ; `prepared` →
/// `not_sent` (hors ligne). Le journal de T7 (lot 1) le stocke sous le domaine `scan`.
public struct RecuScan: RecuDurable, Codable {
    public static let domaine = "scan"
    public static let versionCourante = 1
    /// Borne de la baseline (pilote `attemptJournal.ts` l.36).
    public static let maxPreuves = 1_000
    /// §2.5 (corrigé v2) : `statement_timeout` du rôle `authenticated` (migration `20260720172000` l.6-7).
    public static let delaiAbsenceProuvee: TimeInterval = 8

    /// Texte opérationnel du pilote (`mobile-native/src/workflows/presence/attemptJournal.ts` l.70), non juridique.
    public static let messageRecuEnCours = "Un autre pointage doit être réconcilié avant de continuer."
    /// Texte opérationnel du pilote (`attemptJournal.ts` l.15) : reçu illisible, aucun nouveau scan (fail-closed).
    public static let messageIllisible = "Le suivi sécurisé du pointage ne peut pas être vérifié. Aucun nouveau scan ne peut être envoyé."

    public enum Phase: String, Codable, Sendable {
        case prepared, started, refused
        case notSent = "not_sent"
    }

    /// État GPS au moment du scan (valeurs du pilote, plus `reduced` pour la précision réduite, décision 5).
    public enum Gps: String, Codable, CaseIterable, Sendable {
        case disponible = "available"
        case refusee = "denied"
        case indisponible = "unavailable"
        case reduite = "reduced"
        case nonDemande = "not_requested"

        /// `observation` nil : position jamais demandée (consentement absent ou refusé).
        public init(observation: ObservationGps?) {
            switch observation {
            case .disponible?: self = .disponible
            case .refusee?: self = .refusee
            case .indisponible?: self = .indisponible
            case .precisionReduite?: self = .reduite
            case nil: self = .nonDemande
            }
        }
    }

    public internal(set) var version: Int
    public internal(set) var userId: String
    /// Epoch d'identité de la session au moment de l'essai (PRINCIPES §5).
    public internal(set) var epoch: Int
    public internal(set) var attemptId: String
    public internal(set) var missionId: String
    public internal(set) var terminalId: String
    public internal(set) var typeAttendu: TypeScan
    /// `nb_scans` relu avant l'envoi.
    public internal(set) var nbScansAvant: Int
    /// Identifiants `scans_pointage` de la mission relus avant l'envoi, triés et uniques.
    public internal(set) var preuvesAvant: [String]
    public internal(set) var gps: Gps
    public internal(set) var phase: Phase
    /// SQLSTATE du refus (`refused` seulement).
    public internal(set) var sqlstate: String?
    /// Passage à `started` : point de départ des 8 s de la réconciliation (ajout au §2.6, requis par le §2.5).
    public internal(set) var demarreLe: Date?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case version, epoch, gps, phase, sqlstate
        case userId = "user_id"
        case attemptId = "attempt_id"
        case missionId = "mission_id"
        case terminalId = "terminal_id"
        case typeAttendu = "type_attendu"
        case nbScansAvant = "nb_scans_avant"
        case preuvesAvant = "preuves_avant"
        case demarreLe = "demarre_le"
    }

    public var estTermine: Bool { phase == .refused || phase == .notSent }

    // MARK: - Préparation

    /// Prépare l'essai. `existant` : reçu du même utilisateur lu dans le journal ; s'il est encore en vol,
    /// refus `.recuEnCours` (« Un autre pointage doit être réconcilié avant de continuer. »).
    public static func preparer(userId: String, epoch: Int, missionId: String, terminalId: String, typeAttendu: TypeScan,
                                nbScansAvant: Int, preuvesAvant: [String], gps: Gps,
                                attemptId: String = UUID().uuidString.lowercased(), existant: RecuScan? = nil) throws -> RecuScan {
        if let existant {
            guard existant.userId == userId else { throw RecuErreur.utilisateurDifferent }
            guard existant.estTermine else { throw RecuErreur.recuEnCours }
        }
        let recu = RecuScan(version: versionCourante, userId: userId, epoch: epoch, attemptId: attemptId, missionId: missionId,
                            terminalId: terminalId, typeAttendu: typeAttendu, nbScansAvant: nbScansAvant,
                            preuvesAvant: Array(Set(preuvesAvant)).sorted(), gps: gps, phase: .prepared, sqlstate: nil,
                            demarreLe: nil)
        if preuvesAvant.contains(where: { !RecuValidation.identifiantValide($0) }) { throw RecuErreur.champInvalide("preuvesAvant") }
        try recu.valider()
        return recu
    }

    // MARK: - Transitions

    /// `prepared` → `started`, juste avant l'unique requête.
    public func demarrer(le date: Date) throws -> RecuScan {
        guard phase == .prepared else { throw transition(vers: .started) }
        var suivant = self
        suivant.phase = .started
        suivant.demarreLe = date
        return suivant
    }

    /// `started` → `refused` : exception PostgREST décodée (rollback prouvé, correction 10).
    public func refuser(sqlstate: String) throws -> RecuScan {
        guard phase == .started else { throw transition(vers: .refused) }
        guard Self.sqlstateValide(sqlstate) else { throw RecuErreur.champInvalide("sqlstate") }
        var suivant = self
        suivant.phase = .refused
        suivant.sqlstate = sqlstate
        return suivant
    }

    /// `prepared` → `not_sent` : hors ligne, aucun appel. Après `started`, seule la relecture prouve l'absence.
    public func marquerNonEnvoye() throws -> RecuScan {
        guard phase == .prepared else { throw transition(vers: .notSent) }
        var suivant = self
        suivant.phase = .notSent
        return suivant
    }

    // MARK: - Réconciliation

    public enum VerdictReconciliation: Equatable, Sendable {
        /// Preuve hors baseline du même terminal : le scan a été reçu (aucun second scan).
        case recu(PreuveScan)
        /// Aucune preuve, relecture trop tôt : relire de nouveau.
        case aRelire
        /// Aucune preuve 8 s ou plus après l'envoi : non reçu (saisie du code courant demandée).
        case nonRecu
    }

    /// Verdict pur sur les lignes `scans_pointage` relues pour la mission (`PreuveScan.colonnes`).
    public func reconcilier(scans: [PreuveScan], relueLe: Date) throws -> VerdictReconciliation {
        guard phase == .started else {
            throw RecuErreur.transitionInterdite(de: phase.rawValue, vers: "reconciled")
        }
        guard let demarreLe, (try? valider()) != nil else { throw RecuErreur.illisible }
        let baseline = Set(preuvesAvant)
        let nouvelles = scans.filter { !baseline.contains($0.id) && $0.idTerminal == terminalId }
        if let preuve = nouvelles.max(by: { ($0.numeroScan ?? 0) < ($1.numeroScan ?? 0) }) {
            return .recu(preuve)
        }
        return relueLe.timeIntervalSince(demarreLe) >= Self.delaiAbsenceProuvee ? .nonRecu : .aRelire
    }

    // MARK: - Encodage durable

    public func encoder() throws -> Data {
        try RecuValidation.encoder(self)
    }

    public static func decoder(_ data: Data, userId: String) throws -> RecuScan {
        let recu = try RecuValidation.decoderStrict(RecuScan.self, data, autorisees: Set(CodingKeys.allCases.map(\.rawValue)))
        do { try recu.valider() } catch { throw RecuErreur.illisible }
        guard recu.preuvesAvant == Array(Set(recu.preuvesAvant)).sorted() else { throw RecuErreur.illisible }
        guard recu.userId == userId else { throw RecuErreur.utilisateurDifferent }
        return recu
    }

    // MARK: - Invariants

    func valider() throws {
        guard version == Self.versionCourante else { throw RecuErreur.champInvalide("version") }
        guard RecuValidation.identifiantValide(userId) else { throw RecuErreur.champInvalide("userId") }
        guard epoch >= 0 else { throw RecuErreur.champInvalide("epoch") }
        guard UUID(uuidString: attemptId) != nil else { throw RecuErreur.champInvalide("attemptId") }
        guard RecuValidation.identifiantValide(missionId) else { throw RecuErreur.champInvalide("missionId") }
        guard IdentifiantTerminal.estValide(terminalId) else { throw RecuErreur.champInvalide("terminalId") }
        guard nbScansAvant >= 0 else { throw RecuErreur.champInvalide("nbScansAvant") }
        guard preuvesAvant.allSatisfy(RecuValidation.identifiantValide) else { throw RecuErreur.champInvalide("preuvesAvant") }
        guard preuvesAvant.count <= Self.maxPreuves else { throw RecuErreur.borneDepassee }
        switch phase {
        case .prepared, .notSent:
            guard sqlstate == nil, demarreLe == nil else { throw RecuErreur.champInvalide("phase") }
        case .started:
            guard sqlstate == nil, demarreLe != nil else { throw RecuErreur.champInvalide("phase") }
        case .refused:
            guard let sqlstate, Self.sqlstateValide(sqlstate), demarreLe != nil else { throw RecuErreur.champInvalide("phase") }
        }
    }

    /// SQLSTATE PostgreSQL : cinq caractères `[0-9A-Z]`.
    static func sqlstateValide(_ valeur: String) -> Bool {
        valeur.count == 5 && valeur.unicodeScalars.allSatisfy { ("0"..."9").contains($0) || ("A"..."Z").contains($0) }
    }

    private func transition(vers: Phase) -> RecuErreur {
        .transitionInterdite(de: phase.rawValue, vers: vers.rawValue)
    }
}
