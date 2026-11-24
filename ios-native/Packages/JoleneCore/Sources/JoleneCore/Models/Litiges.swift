import Foundation

// Contrats d'échange de `LitigesPort` (lot 4, T8, `docs/mobile-swift/LOT4_PLAN.md` §2.3-§2.4), déplacés de
// `Models/Lot4Results.swift` par la tranche qui les livre. Décodage tolérant : seul l'identifiant est requis ; une
// valeur absente ou d'un autre type est ignorée seule. Aucun montant n'est lu ni calculé ici : la ligne `litiges` est
// lue par colonnes explicites (jamais `*`), sans `montant_tresorerie_bloquee` ni `payload_modifications`.

/// Lecture tolérante d'un conteneur à clés : une valeur absente, nulle ou d'un autre type rend `nil`.
extension KeyedDecodingContainer {
    func texteTolere(_ cle: Key) -> String? {
        guard let valeur = try? decodeIfPresent(String.self, forKey: cle) else { return nil }
        return valeur
    }
}

/// Ligne de `litiges` du soignant, avec la mission jointe (`missions(id,intitule,debut_le)`, comme le web
/// `LitigesSoignant.tsx` l.68) ; le nom de l'établissement vient de `fn_etablissements_safe`, jamais d'un embed
/// `etablissements` (refusé au soignant, lot 1 §2.6).
public struct Litige: Equatable, Sendable, Identifiable, Decodable {
    public var id: String
    public var missionId: String?
    public var etablissementId: String?
    /// Statut serveur tel que servi ; libellé, groupe et prédicats par `StatutLitige` (golden T2).
    public var statut: String
    public var typeLitige: String?
    public var motif: String?
    /// Texte de clôture écrit par le serveur (`litiges.resolution`), affiché tel quel.
    public var resolution: String?
    /// `cree_le` serveur (ISO 8601), affiché « d MMM yyyy » à l'heure de Paris (`LitigesPresentation.jour`).
    public var creeLe: String?
    public var missionIntitule: String?
    public var missionDebutLe: String?
    public var etablissementNom: String?

    public init(id: String, missionId: String? = nil, etablissementId: String? = nil, statut: String, typeLitige: String? = nil,
                motif: String? = nil, resolution: String? = nil, creeLe: String? = nil, missionIntitule: String? = nil,
                missionDebutLe: String? = nil, etablissementNom: String? = nil) {
        self.id = id; self.missionId = missionId; self.etablissementId = etablissementId; self.statut = statut
        self.typeLitige = typeLitige; self.motif = motif; self.resolution = resolution; self.creeLe = creeLe
        self.missionIntitule = missionIntitule; self.missionDebutLe = missionDebutLe; self.etablissementNom = etablissementNom
    }

    enum CodingKeys: String, CodingKey {
        case id, statut, motif, resolution, missions
        case missionId = "mission_id", etablissementId = "etablissement_id", typeLitige = "type_litige", creeLe = "cree_le"
        case etablissementNom = "etablissement_nom"
    }

    enum MissionKeys: String, CodingKey { case intitule, debutLe = "debut_le" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        missionId = c.texteTolere(.missionId)
        etablissementId = c.texteTolere(.etablissementId)
        statut = c.texteTolere(.statut) ?? ""
        typeLitige = c.texteTolere(.typeLitige)
        motif = c.texteTolere(.motif)
        resolution = c.texteTolere(.resolution)
        creeLe = c.texteTolere(.creeLe)
        etablissementNom = c.texteTolere(.etablissementNom)
        // Jointure plusieurs-à-un : un objet, ou `null` si la mission n'est pas lisible sous RLS.
        let mission = try? c.nestedContainer(keyedBy: MissionKeys.self, forKey: .missions)
        missionIntitule = mission?.texteTolere(.intitule)
        missionDebutLe = mission?.texteTolere(.debutLe)
    }
}

/// Mission assignée `EN_COURS` ou `TERMINEE` sans litige (web `LitigesSoignant.tsx` l.134-153), proposée à l'ouverture.
public struct MissionContestable: Equatable, Sendable, Identifiable, Decodable {
    public var id: String
    public var intitule: String?
    public var debutLe: String?
    public var etablissementId: String?
    public var etablissementNom: String?

    public init(id: String, intitule: String?, debutLe: String? = nil, etablissementId: String?, etablissementNom: String? = nil) {
        self.id = id; self.intitule = intitule; self.debutLe = debutLe; self.etablissementId = etablissementId
        self.etablissementNom = etablissementNom
    }

    enum CodingKeys: String, CodingKey {
        case id, intitule
        case debutLe = "debut_le", etablissementId = "etablissement_id", etablissementNom = "etablissement_nom"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        intitule = c.texteTolere(.intitule)
        debutLe = c.texteTolere(.debutLe)
        etablissementId = c.texteTolere(.etablissementId)
        etablissementNom = c.texteTolere(.etablissementNom)
    }
}

/// Issue de `fn_ouvrir_litige_rate_limited` (3 arguments, `AUTRE`) : `ouvert` après relecture par `litige_id`.
public enum OuvertureLitigeOutcome: Equatable, Sendable {
    case ouvert(id: String, informatif: Bool)
    /// Refus du serveur, mot pour mot (motif, doublon, plafond horaire, fenêtre…).
    case refuse(message: String)
}

/// Ligne de `messages_litige` (contenu jamais journalisé).
public struct MessageLitige: Equatable, Sendable, Identifiable, Decodable {
    public var id: String
    public var litigeId: String?
    public var auteurId: String?
    /// `SOIGNANT`, `ETABLISSEMENT` ou `ADMIN` (`messages_litige_type_auteur_check`).
    public var typeAuteur: String?
    public var contenu: String
    public var creeLe: String?

    public init(id: String, litigeId: String? = nil, auteurId: String?, typeAuteur: String? = nil, contenu: String,
                creeLe: String? = nil) {
        self.id = id; self.litigeId = litigeId; self.auteurId = auteurId; self.typeAuteur = typeAuteur
        self.contenu = contenu; self.creeLe = creeLe
    }

    enum CodingKeys: String, CodingKey {
        case id, contenu
        case litigeId = "litige_id", auteurId = "auteur_id", typeAuteur = "type_auteur", creeLe = "cree_le"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        litigeId = c.texteTolere(.litigeId)
        auteurId = c.texteTolere(.auteurId)
        typeAuteur = c.texteTolere(.typeAuteur)
        contenu = c.texteTolere(.contenu) ?? ""
        creeLe = c.texteTolere(.creeLe)
    }
}

/// Issue de `fn_ajouter_message_litige` : le fil relu, ou le refus serveur verbatim.
public enum IssueMessageLitige: Equatable, Sendable {
    case ajoute([MessageLitige])
    case refuse(message: String)
}
