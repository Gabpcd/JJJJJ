import Foundation

/// Mission dont le planning contractuel est attendu (`MissionAvecPlanningAttendu` côté web :
/// période globale et `nb_creneaux` annoncé).
public struct MissionAvecPlanningAttendu: Equatable, Sendable {
    public var id: String?
    public var debutLe: String
    public var finLe: String
    public var nbCreneaux: Int?

    public init(id: String?, debutLe: String, finLe: String, nbCreneaux: Int?) {
        self.id = id; self.debutLe = debutLe; self.finLe = finLe; self.nbCreneaux = nbCreneaux
    }

    public init(_ record: MissionRecord) {
        self.init(id: record.id, debutLe: record.debutLe, finLe: record.finLe, nbCreneaux: record.nbCreneaux)
    }
}

/// Résultat de `analyserCompletudePlanningMission` (src/lib/completude-planning-mission.ts).
/// Un résultat incomplet ne porte aucun créneau : jamais de planning partiel exposé.
public struct CompletudePlanningMission: Equatable, Sendable {
    public var complet: Bool
    public var creneauxPlanifies: [MissionSlot]
    public var nombrePlanifie: Int
    public var dureeTotaleHeures: Double

    public init(complet: Bool, creneauxPlanifies: [MissionSlot], nombrePlanifie: Int, dureeTotaleHeures: Double) {
        self.complet = complet; self.creneauxPlanifies = creneauxPlanifies
        self.nombrePlanifie = nombrePlanifie; self.dureeTotaleHeures = dureeTotaleHeures
    }

    public static let incomplet = CompletudePlanningMission(complet: false, creneauxPlanifies: [], nombrePlanifie: 0, dureeTotaleHeures: 0)
}

/// Port de `analyserCompletudePlanningMission` : vérifie qu'un planning peut servir de
/// source contractuelle. Pour une mission récente, `nb_creneaux` doit correspondre
/// exactement aux lignes PREVISIONNEL de travail reçues ; le seul repli autorisé est
/// l'ancienne mission ponctuelle (24 h maximum) sans aucune ligne détaillée.
public enum CompletudePlanning {
    public static func analyser(_ mission: MissionAvecPlanningAttendu, creneaux: [MissionSlot] = []) -> CompletudePlanningMission {
        let bruts = creneaux.filter { $0.typeCreneau == "PREVISIONNEL" && !$0.estPause }
        // `Number.isInteger(nb) && nb > 0` : `null`, 0 ou négatif ne sont pas vérifiables.
        let nombreAttendu = mission.nbCreneaux ?? 0
        let nombreAttenduVerifiable = nombreAttendu > 0

        var candidats: [MissionSlot] = []
        var complet = false
        if nombreAttenduVerifiable {
            candidats = DisponibilitePointage.creneauxPrevisionnels(bruts)
            complet = bruts.count == nombreAttendu
                && candidats.count == nombreAttendu
                && bruts.allSatisfy(creneauValide)
        } else if bruts.isEmpty {
            candidats = DisponibilitePointage.creneauxPrevisionnels(DisponibilitePointage.ajouterRepliMissionPonctuelle(
                [], mission: PeriodeMissionPointage(id: mission.id, debutLe: mission.debutLe, finLe: mission.finLe)
            ))
            complet = candidats.count == 1 && candidats.allSatisfy(creneauValide)
        }

        guard complet else { return .incomplet }

        // Millisecondes entières (modèle `Date` JavaScript) : `(fin - debut) / 3_600_000`.
        let dureeTotaleHeures = candidats.reduce(0.0) { total, creneau in
            guard let fin = creneau.finRenseignee,
                  let debutDate = PlanningHorlogeParis.instant(creneau.debut),
                  let finDate = PlanningHorlogeParis.instant(fin) else { return total }
            return total + Double(DateHeureParis.millisecondes(finDate) - DateHeureParis.millisecondes(debutDate)) / 3_600_000
        }
        return CompletudePlanningMission(complet: true, creneauxPlanifies: candidats,
                                         nombrePlanifie: candidats.count, dureeTotaleHeures: dureeTotaleHeures)
    }

    /// Port de `creneauValide` : fin renseignée, deux instants lisibles, fin strictement après début.
    /// Une date illisible rend le créneau invalide, jamais une exception.
    static func creneauValide(_ creneau: MissionSlot) -> Bool {
        guard let fin = creneau.finRenseignee,
              let debutDate = PlanningHorlogeParis.instant(creneau.debut),
              let finDate = PlanningHorlogeParis.instant(fin) else { return false }
        return DateHeureParis.millisecondes(finDate) > DateHeureParis.millisecondes(debutDate)
    }
}
