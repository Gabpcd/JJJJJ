import Foundation

public extension RoleEtab {
    /// Libellé du rôle d'équipe, repris mot pour mot de `ROLE_INFO`
    /// (`src/pages/EquipeEtablissement.tsx` l.45-49, libellés non juridiques ; garde `DemoEspaceTests`).
    /// Une valeur hors des cinq rôles est affichée telle quelle.
    var libelle: String {
        switch self {
        case .proprietaire: return "Propriétaire"
        case .adminGroupe: return "Admin groupe"
        case .rh: return "Ressources humaines"
        case .pointageOnly: return "Pointage uniquement"
        case .lectureSeule: return "Lecture seule"
        case let .inconnu(valeur): return valeur
        }
    }
}
