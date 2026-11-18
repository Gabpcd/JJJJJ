import Foundation

/// Groupe d'un statut de litige (`GroupeStatut` du web) : filtres de la liste des litiges (T8).
public enum GroupeStatutLitige: String, Equatable, Sendable, CaseIterable {
    case ouvert = "OUVERT"
    case mediation = "MEDIATION"
    case actionAttendue = "ACTION_ATTENDUE"
    case resoluAccord = "RESOLU_ACCORD"
    case resoluDecision = "RESOLU_DECISION"
    case ferme = "FERME"
}

/// Icône nommée du badge (`IconeStatutLitige` du web, noms lucide) ; l'écran choisit son symbole (T8).
public enum IconeStatutLitige: String, Equatable, Sendable, CaseIterable {
    case scale = "Scale"
    case messageSquare = "MessageSquare"
    case alertTriangle = "AlertTriangle"
    case users = "Users"
    case gavel = "Gavel"
    case checkCircle2 = "CheckCircle2"
    case xCircle = "XCircle"
}

/// Libellé, icône et groupe d'un statut (`StatutLitigeRegle` du web, sans les classes Tailwind).
public struct RegleStatutLitige: Equatable, Sendable {
    public var libelle: String
    public var icone: IconeStatutLitige
    public var groupe: GroupeStatutLitige

    public init(libelle: String, icone: IconeStatutLitige, groupe: GroupeStatutLitige) {
        self.libelle = libelle; self.icone = icone; self.groupe = groupe
    }
}

/// Statuts de litige : port de `src/lib/statut-litige-regles.ts` (partie pure de `statutLitige.ts`, source unique de
/// `statutBadgeV2`, extraite par la PR web W0), vecteurs `statut-litige.json` (L4-T2, `LOT4_PLAN.md` §3 T2).
/// Périmètre du web : `FilDiscussionLitige.tsx` et `PanneauContestation.tsx` gardent leurs propres libellés, sans
/// parité visée. Un statut inconnu garde son code pour libellé, dans le groupe `OUVERT`.
public enum StatutLitige {
    public static func regle(_ statut: String) -> RegleStatutLitige {
        switch statut {
        case "OUVERT": return RegleStatutLitige(libelle: "Ouvert", icone: .scale, groupe: .ouvert)
        case "EN_DISCUSSION": return RegleStatutLitige(libelle: "En discussion", icone: .messageSquare, groupe: .ouvert)
        case "EN_MEDIATION": return RegleStatutLitige(libelle: "Médiation", icone: .alertTriangle, groupe: .mediation)
        case "MEDIATION_EN_COURS": return RegleStatutLitige(libelle: "Médiation en cours", icone: .users, groupe: .mediation)
        case "REVUE_ADMIN": return RegleStatutLitige(libelle: "Revue admin", icone: .gavel, groupe: .actionAttendue)
        case "RESOLU_ACCORD_PARTIES": return RegleStatutLitige(libelle: "Accord mutuel ✅", icone: .checkCircle2, groupe: .resoluAccord)
        case "RESOLU_FAVEUR_SOIGNANT":
            return RegleStatutLitige(libelle: "Tranché en faveur soignant", icone: .gavel, groupe: .resoluDecision)
        case "RESOLU_FAVEUR_ETAB": return RegleStatutLitige(libelle: "Tranché en faveur étab", icone: .gavel, groupe: .resoluDecision)
        case "RESOLU_PARTAGE": return RegleStatutLitige(libelle: "Tranché : décision partagée", icone: .gavel, groupe: .resoluDecision)
        case "RESOLU_SOIGNANT": return RegleStatutLitige(libelle: "Résolu (soignant)", icone: .checkCircle2, groupe: .resoluDecision)
        case "RESOLU_ETABLISSEMENT": return RegleStatutLitige(libelle: "Résolu (étab)", icone: .checkCircle2, groupe: .resoluDecision)
        case "RESOLU_ADMIN": return RegleStatutLitige(libelle: "Résolu admin", icone: .gavel, groupe: .ferme)
        case "FERME": return RegleStatutLitige(libelle: "Fermé", icone: .xCircle, groupe: .ferme)
        default: return RegleStatutLitige(libelle: statut, icone: .scale, groupe: .ouvert)
        }
    }

    /// `STATUTS_RESOLUS` : statuts résolus et fermés.
    public static let statutsResolus: Set<String> = [
        "RESOLU_ACCORD_PARTIES", "RESOLU_FAVEUR_SOIGNANT", "RESOLU_FAVEUR_ETAB", "RESOLU_PARTAGE",
        "RESOLU_SOIGNANT", "RESOLU_ETABLISSEMENT", "RESOLU_ADMIN", "FERME",
    ]
    /// `STATUTS_PROPOSER_MEDIATION`.
    public static let statutsProposerMediation: Set<String> = ["OUVERT", "EN_DISCUSSION", "EN_MEDIATION"]
    /// `STATUTS_CONFIRMER_ACCORD`.
    public static let statutsConfirmerAccord: Set<String> = ["OUVERT", "EN_DISCUSSION", "EN_MEDIATION", "MEDIATION_EN_COURS"]

    // Codes ASCII sans « K » (seule lettre ASCII à équivalent canonique, U+212A) : l'égalité canonique des
    // `String` Swift (switch, `Set`) y coïncide avec `===`.
    public static func estResolu(_ statut: String) -> Bool { statutsResolus.contains(statut) }
    public static func peutProposerMediation(_ statut: String) -> Bool { statutsProposerMediation.contains(statut) }
    public static func peutConfirmerAccord(_ statut: String) -> Bool { statutsConfirmerAccord.contains(statut) }
}
