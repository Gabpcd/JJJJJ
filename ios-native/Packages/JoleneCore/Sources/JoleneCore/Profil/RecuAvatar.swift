import Foundation

// Reçu durable d'un envoi de photo de profil (PRINCIPES §4 : « avant tout upload Storage, un reçu est écrit en
// Keychain avec les phases prepared → started → refused / not_sent / terminé » ; blueprint `LOT3_PLAN.md` §3 T10).
//
// Point d'extension MINIMAL (manque consigné dans `DECISIONS_LOT3.md`, section T10) : le journal générique des reçus
// prévu par le blueprint (« `ReceiptJournal` du lot 1 T7 ») n'existe sur aucune branche du lot 1 ; il est livré par le
// lot 2 (`Receipts/ReceiptJournal.swift`, `RecuDurable.swift`, `KeychainReceiptStore`, sur `feat/ios-lot2`), dont le
// lot 3 ne dépend pas. Ce fichier ne recrée pas ce journal : il décrit le seul reçu d'avatar avec les MÊMES
// exigences que `RecuDurable` (domaine, utilisateur, essai, état terminal, succession, JSON versionné à clés triées,
// relecture stricte), et `RecusAvatarPort` est le seul magasin. À la fusion des lots : `extension RecuAvatar:
// RecuDurable {}` (les membres requis existent déjà sous ces noms), `RecuAvatar.Erreur` remplacé par `RecuErreur`, et
// `RecusAvatarPort` servi par `ReceiptJournal<RecuAvatar>` sur `KeychainReceiptStore` — même service
// (`app.jolene.receipts`) et même compte (`avatar.<userId>`) que l'implémentation provisoire `KeychainRecusAvatar`.

/// Reçu d'un envoi d'avatar : un seul par utilisateur. Ne contient ni octet d'image, ni URL signée, ni jeton.
public struct RecuAvatar: Equatable, Sendable, CustomStringConvertible {
    public enum Phase: String, Codable, Sendable, CaseIterable {
        /// Reçu écrit, aucune requête partie.
        case prepared
        /// Dépôt de l'objet en cours (issue inconnue en cas d'arrêt).
        case started
        /// Objet déposé ; URL signée et `fn_modifier_mon_profil(p_avatar_url)` en cours.
        case stored
        /// Refus certain (stockage 4xx, refus serveur du profil) : rien n'a été lié.
        case refused
        /// Envoi abandonné ou non confirmé à la réconciliation : rien n'a été lié.
        case notSent = "not_sent"
    }

    public enum Erreur: Error, Equatable, Sendable {
        case illisible
        case utilisateurDifferent
        case recuEnCours
        case transitionInterdite(de: String, vers: String)
    }

    public static let domaine = "avatar"
    public static let version = 1

    public let userId: String
    public let attemptId: String
    /// Chemin de l'objet dans le bucket (`<uid>/avatar-<ms>.jpg`).
    public let chemin: String
    public private(set) var phase: Phase

    public init(userId: String, attemptId: String, chemin: String, phase: Phase = .prepared) {
        self.userId = userId; self.attemptId = attemptId; self.chemin = chemin; self.phase = phase
    }

    public var estTermine: Bool { phase == .refused || phase == .notSent }

    /// Graphe des phases, jamais de retour en arrière : prepared → started | not_sent ; started → stored | refused |
    /// not_sent ; stored → refused | not_sent ; refused et not_sent sont terminales.
    public static func transitionPermise(de depart: Phase, vers arrivee: Phase) -> Bool {
        switch (depart, arrivee) {
        case (.prepared, .started), (.prepared, .notSent),
             (.started, .stored), (.started, .refused), (.started, .notSent),
             (.stored, .refused), (.stored, .notSent):
            return true
        default:
            return false
        }
    }

    /// Même essai, phase suivante ; transition hors graphe → `Erreur.transitionInterdite`.
    public func vers(_ arrivee: Phase) throws -> RecuAvatar {
        guard Self.transitionPermise(de: phase, vers: arrivee) else {
            throw Erreur.transitionInterdite(de: phase.rawValue, vers: arrivee.rawValue)
        }
        var suivant = self
        suivant.phase = arrivee
        return suivant
    }

    /// Contrôle de succession (même contrat que `RecuDurable.verifierSuccession`) : premier enregistrement d'un essai en
    /// `prepared` seulement ; ensuite, mêmes champs immuables et réécriture identique ou transition du graphe.
    public func verifierSuccession(apres precedent: RecuAvatar?) throws {
        guard let precedent else {
            guard phase == .prepared else { throw Erreur.transitionInterdite(de: "absent", vers: phase.rawValue) }
            return
        }
        guard precedent.userId == userId, precedent.attemptId == attemptId, precedent.chemin == chemin else {
            throw Erreur.illisible
        }
        guard precedent.phase == phase || Self.transitionPermise(de: precedent.phase, vers: phase) else {
            throw Erreur.transitionInterdite(de: precedent.phase.rawValue, vers: phase.rawValue)
        }
    }

    // MARK: - Encodage versionné

    private struct Forme: Codable {
        let v: Int
        let userId: String
        let attemptId: String
        let chemin: String
        let phase: Phase
        enum CodingKeys: String, CodingKey {
            case v, userId = "user_id", attemptId = "attempt_id", chemin, phase
        }
    }

    private static let clesAutorisees: Set<String> = ["v", "user_id", "attempt_id", "chemin", "phase"]

    /// JSON versionné à clés triées.
    public func encoder() throws -> Data {
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = [.sortedKeys]
        return try encodeur.encode(Forme(v: Self.version, userId: userId, attemptId: attemptId, chemin: chemin, phase: phase))
    }

    /// Relecture stricte : clé inattendue, version inconnue, champ vide, chemin hors du dossier de l'utilisateur →
    /// `.illisible` ; reçu d'un autre utilisateur → `.utilisateurDifferent`. Jamais de réparation silencieuse.
    public static func decoder(_ donnees: Data, userId: String) throws -> RecuAvatar {
        guard let objet = (try? JSONSerialization.jsonObject(with: donnees)) as? [String: Any],
              Set(objet.keys).isSubset(of: clesAutorisees),
              let forme = try? JSONDecoder().decode(Forme.self, from: donnees),
              forme.v == version, !forme.attemptId.isEmpty, !forme.userId.isEmpty else {
            throw Erreur.illisible
        }
        guard forme.userId == userId else { throw Erreur.utilisateurDifferent }
        guard forme.chemin.hasPrefix("\(userId)/avatar-"), forme.chemin.hasSuffix(".jpg"),
              !forme.chemin.contains("..") else { throw Erreur.illisible }
        return RecuAvatar(userId: forme.userId, attemptId: forme.attemptId, chemin: forme.chemin, phase: forme.phase)
    }

    /// Description masquée : ni identifiant d'utilisateur ni chemin.
    public var description: String { "RecuAvatar(phase: \(phase.rawValue))" }
}

/// Magasin des reçus d'avatar, un par utilisateur. Une erreur de stockage est levée, jamais traduite en « aucun reçu »
/// (fail-closed : aucun envoi sans reçu durable). Réel : `KeychainRecusAvatar` (JoleneSupabase, provisoire jusqu'à la
/// fusion avec le journal du lot 2) ; démo et tests : `RecusAvatarEnMemoire`.
public protocol RecusAvatarPort: Sendable {
    func lire(userId: String) async throws -> RecuAvatar?
    func ecrire(_ recu: RecuAvatar) async throws
    /// Effacer un reçu absent n'est pas une erreur.
    func effacer(userId: String) async throws
}

/// Reçus d'avatar en mémoire : mode démo et tests. Aucun disque, aucun réseau ; vierge à chaque instance.
public actor RecusAvatarEnMemoire: RecusAvatarPort {
    private var octets: [String: Data] = [:]
    /// Erreur scriptée (tests) : toute opération la lève.
    private var panne: Error?

    public init() {}

    public func lire(userId: String) throws -> RecuAvatar? {
        if let panne { throw panne }
        guard let donnees = octets[userId] else { return nil }
        return try RecuAvatar.decoder(donnees, userId: userId)
    }

    public func ecrire(_ recu: RecuAvatar) throws {
        if let panne { throw panne }
        octets[recu.userId] = try recu.encoder()
    }

    public func effacer(userId: String) throws {
        if let panne { throw panne }
        octets[userId] = nil
    }

    /// Octets stockés (tests : aucune URL ni octet d'image dans un reçu).
    public func brut(userId: String) -> Data? { octets[userId] }

    /// Dépose des octets bruts (tests : reçu laissé par un arrêt, reçu altéré).
    public func deposer(_ donnees: Data?, userId: String) { octets[userId] = donnees }

    public func tomberEnPanne(_ erreur: Error?) { panne = erreur }
}
