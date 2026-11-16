import Foundation

/// État du compte à rebours de signature, dérivé de `contrats_mission.cree_le` à chaque seconde
/// et jamais stocké (lot 2, correction 13).
public struct EtatCompteARebours72h: Equatable, Sendable {
    /// Tons du web (`Countdown72hSignature.tsx`) : vert au-delà de 48 h restantes, orange de 24 à
    /// 48 h, rouge en deçà et à l'expiration. Le libellé affiché relève des textes web (tranche TL).
    public enum Ton: String, Sendable {
        case confortable = "success"
        case attention = "warning"
        case urgent = "destructive"
    }

    public var restantSecondes: Int
    public var heures: Int
    public var minutes: Int
    public var secondes: Int
    public var ton: Ton

    public var expire: Bool { restantSecondes <= 0 }

    public init(restantSecondes: Int) {
        self.restantSecondes = max(0, restantSecondes)
        heures = self.restantSecondes / 3600
        minutes = (self.restantSecondes % 3600) / 60
        secondes = self.restantSecondes % 60
        ton = heures >= 48 ? .confortable : heures >= 24 ? .attention : .urgent
    }
}

/// Miroir de `calculerRestant` (`Countdown72hSignature.tsx` l.79-82) et du cron d'expiration des
/// contrats non signés sous 72 h après leur création. Le serveur fait foi : ce décompte n'autorise
/// ni ne refuse aucune signature, il l'annonce.
public enum CompteARebours72h {
    public static let dureeSecondes = 72 * 3600

    /// Secondes restantes `max(0, floor((cree_le + 72 h − maintenant) / 1 000))`. Un `cree_le`
    /// absent ou illisible vaut délai expiré (échec fermé ; le web afficherait « NaNh »).
    public static func etat(creeLe: String?, maintenant: Date) -> EtatCompteARebours72h {
        guard let creeLe, let cree = try? DateHeureParis.instantJolene(creeLe) else {
            return EtatCompteARebours72h(restantSecondes: 0)
        }
        let restantMs = DateHeureParis.millisecondes(cree) + Int64(dureeSecondes) * 1000 - DateHeureParis.millisecondes(maintenant)
        return EtatCompteARebours72h(restantSecondes: Int(CalendrierCivil.divisionEntiere(restantMs, 1000)))
    }
}
