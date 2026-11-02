import Foundation

/// Créneau confirmé tel que `fn_confirmer_action_planning_v1` le reçoit dans
/// `p_creneaux_confirmes` (clés `debut` / `fin`, instants absolus).
public struct CreneauConfirme: Codable, Equatable, Sendable {
    public var debut: String
    public var fin: String

    public init(debut: String, fin: String) {
        self.debut = debut; self.fin = fin
    }
}

/// Port de `creneauxConfirmesPourAction` (src/components/planning/planning-candidat.ts l.136-147).
///
/// Le serveur compare, sous verrou, les instants confirmés au planning live
/// (`EXCEPT` sur des `timestamptz`) : la sélection reprend les créneaux exacts du
/// planning candidat, et la charge utile RPC sérialise ces mêmes `debut` / `fin`
/// en ISO 8601 UTC `yyyy-MM-dd'T'HH:mm:ss'Z'`, jamais une valeur recalculée.
public enum CreneauxConfirmes {
    /// Les créneaux du planning exact, tels que lus (chaînes PostgREST inchangées), ou
    /// `nil` quand le planning ne peut pas être confirmé (incomplet, erreur, fin absente).
    public static func selectionner(_ mission: PlanningCandidatInput) -> [MissionSlot]? {
        let planning = PlanningCandidatRules.construirePlanningCandidat(mission)
        guard planning.exact, !planning.creneaux.contains(where: { $0.finRenseignee == nil }) else { return nil }
        return planning.creneaux
    }

    /// Charge utile `p_creneaux_confirmes` : mêmes créneaux, mêmes instants, en UTC `Z`.
    /// Un instant illisible rend la sélection impossible (`nil`), jamais un créneau inventé.
    public static func pourAction(_ mission: PlanningCandidatInput) -> [CreneauConfirme]? {
        guard let selection = selectionner(mission) else { return nil }
        var confirmes: [CreneauConfirme] = []
        confirmes.reserveCapacity(selection.count)
        for creneau in selection {
            guard let fin = creneau.finRenseignee,
                  let debutDate = PlanningHorlogeParis.instant(creneau.debut),
                  let finDate = PlanningHorlogeParis.instant(fin) else { return nil }
            confirmes.append(CreneauConfirme(debut: iso8601UTC(debutDate), fin: iso8601UTC(finDate)))
        }
        return confirmes
    }

    /// Port de la mission enrichie (créneaux chargés et erreur de planning inclus).
    public static func pourAction(_ mission: Mission) -> [CreneauConfirme]? {
        pourAction(PlanningCandidatInput(mission: mission))
    }

    /// ISO 8601 UTC sans fraction (`2026-07-06T06:00:00Z`). Une fraction de seconde non
    /// nulle, jamais produite par le formulaire web mais lisible dans un `timestamptz`, est
    /// conservée à la milliseconde : la tronquer ferait diverger la comparaison serveur.
    static func iso8601UTC(_ date: Date) -> String {
        let complet = DateHeureParis.isoUTC(date) // yyyy-MM-ddTHH:mm:ss.SSSZ
        if complet.hasSuffix(".000Z") {
            return String(complet.dropLast(5)) + "Z"
        }
        return complet
    }
}
