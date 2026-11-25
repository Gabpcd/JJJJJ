import Foundation

// Contrats d'échange de `ReclamationsPort` (lot 4, T8, `docs/mobile-swift/LOT4_PLAN.md` §2.3-§2.4), déplacés de
// `Models/Lot4Results.swift` par la tranche qui les livre. Réclamations générales seulement (`reclamations`,
// `fn_soumettre_reclamation`) : la contestation d'un événement de score (`reclamations_score`) relève de T9.

/// Catégories de `reclamations_categorie_check` (liste fermée côté app : hors liste → exception 23514), dans l'ordre
/// du sélecteur web (`MesReclamations.tsx`, `CATEGORIES`).
public enum CategorieReclamation: String, Equatable, Sendable, CaseIterable {
    case mission = "MISSION"
    case paiement = "PAIEMENT"
    case comportement = "COMPORTEMENT"
    case technique = "TECHNIQUE"
    case autre = "AUTRE"
}

/// Ligne de `reclamations` du compte (colonnes du web : `id, categorie, sujet, details, statut, reponse_admin, cree_le,
/// traite_le`). Décodage tolérant : seul l'identifiant est requis.
public struct Reclamation: Equatable, Sendable, Identifiable, Decodable {
    public var id: String
    public var categorie: String
    public var sujet: String
    public var details: String
    /// `EN_ATTENTE`, `EN_COURS`, `RESOLUE` ou `FERMEE` (`reclamations_statut_check`), tel que servi.
    public var statut: String
    /// Réponse de l'équipe Jolene, affichée telle quelle.
    public var reponseAdmin: String?
    public var creeLe: String?
    public var traiteLe: String?

    public init(id: String, categorie: String, sujet: String, details: String = "", statut: String, reponseAdmin: String? = nil,
                creeLe: String? = nil, traiteLe: String? = nil) {
        self.id = id; self.categorie = categorie; self.sujet = sujet; self.details = details; self.statut = statut
        self.reponseAdmin = reponseAdmin; self.creeLe = creeLe; self.traiteLe = traiteLe
    }

    enum CodingKeys: String, CodingKey {
        case id, categorie, sujet, details, statut
        case reponseAdmin = "reponse_admin", creeLe = "cree_le", traiteLe = "traite_le"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        categorie = c.texteTolere(.categorie) ?? ""
        sujet = c.texteTolere(.sujet) ?? ""
        details = c.texteTolere(.details) ?? ""
        statut = c.texteTolere(.statut) ?? ""
        reponseAdmin = c.texteTolere(.reponseAdmin)
        creeLe = c.texteTolere(.creeLe)
        traiteLe = c.texteTolere(.traiteLe)
    }
}

/// Issue de `fn_soumettre_reclamation` (`{id, statut}`, ni `success` ni `ok`) : la ligne relue par `id`.
public enum IssueReclamation: Equatable, Sendable {
    case soumise(Reclamation)
    /// Refus du serveur, mot pour mot (« Rôle non autorisé »), ou libellé générique d'une contrainte (23514).
    case refusee(message: String)
}
