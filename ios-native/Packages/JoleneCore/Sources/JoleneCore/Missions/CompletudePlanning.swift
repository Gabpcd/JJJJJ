import Foundation

/// Mission dont le planning doit servir de source contractuelle (`MissionAvecPlanningAttendu`).
public struct MissionAvecPlanningAttendu: Equatable, Sendable {
    public var id: String?
    public var debutLe: String
    public var finLe: String
    public var nbCreneaux: Int?

    public init(id: String?, debutLe: String, finLe: String, nbCreneaux: Int?) {
        self.id = id; self.debutLe = debutLe; self.finLe = finLe; self.nbCreneaux = nbCreneaux
    }

    public init(record: MissionRecord) {
        self.init(id: record.id, debutLe: record.debutLe, finLe: record.finLe, nbCreneaux: record.nbCreneaux)
    }
}

/// Résultat de `analyserCompletudePlanningMission` (port de `CompletudePlanningMission`).
public struct CompletudePlanningMission: Equatable, Sendable {
    public var complet: Bool
    public var creneauxPlanifies: [MissionSlot]
    public var nombrePlanifie: Int
    public var dureeTotaleHeures: Double

    public init(complet: Bool, creneauxPlanifies: [MissionSlot], nombrePlanifie: Int, dureeTotaleHeures: Double) {
        self.complet = complet; self.creneauxPlanifies = creneauxPlanifies
        self.nombrePlanifie = nombrePlanifie; self.dureeTotaleHeures = dureeTotaleHeures
    }

    static let incomplet = CompletudePlanningMission(complet: false, creneauxPlanifies: [], nombrePlanifie: 0, dureeTotaleHeures: 0)
}

/// Port de `src/lib/completude-planning-mission.ts` : vérifie qu'un planning peut être utilisé
/// comme source contractuelle.
public enum CompletudePlanning {
    /// Pour une mission récente, `nb_creneaux` doit correspondre exactement aux lignes
    /// PREVISIONNEL de travail reçues, toutes valides. Seul repli : une ancienne mission
    /// ponctuelle (24 h au plus) sans aucune ligne détaillée. Un résultat partiel n'est jamais
    /// exposé comme un planning valide.
    public static func analyser(_ mission: MissionAvecPlanningAttendu, creneaux: [MissionSlot] = []) -> CompletudePlanningMission {
        let bruts = creneaux.filter { $0.typeCreneau == "PREVISIONNEL" && !$0.estPause }
        // `Number.isInteger(n) && n > 0` : `nil` (NaN, null) et 0 ne sont pas vérifiables.
        let nombreAttendu = mission.nbCreneaux ?? 0

        let candidats: [MissionSlot]
        let complet: Bool
        if nombreAttendu > 0 {
            candidats = DisponibilitePointage.creneauxPrevisionnels(bruts)
            complet = bruts.count == nombreAttendu && candidats.count == nombreAttendu && bruts.allSatisfy(creneauValide)
        } else if bruts.isEmpty {
            let periode = PeriodeMissionPointage(id: mission.id, debutLe: mission.debutLe, finLe: mission.finLe)
            candidats = DisponibilitePointage.creneauxPrevisionnels(DisponibilitePointage.ajouterRepliMissionPonctuelle([], mission: periode))
            complet = candidats.count == 1 && candidats.allSatisfy(creneauValide)
        } else {
            candidats = []
            complet = false
        }
        guard complet else { return .incomplet }

        // Millisecondes entières, comme `getTime()` : la somme est identique au web au bit près.
        let dureeTotaleHeures = candidats.reduce(0.0) { total, creneau in
            guard let bornes = bornesMillisecondes(creneau) else { return total }
            return total + Double(bornes.fin - bornes.debut) / 3_600_000
        }
        return CompletudePlanningMission(complet: true, creneauxPlanifies: candidats,
                                         nombrePlanifie: candidats.count, dureeTotaleHeures: dureeTotaleHeures)
    }

    /// `creneauValide` : fin renseignée, bornes lisibles (`instantJolene`), fin strictement après le début.
    static func creneauValide(_ creneau: MissionSlot) -> Bool {
        guard let bornes = bornesMillisecondes(creneau) else { return false }
        return bornes.fin > bornes.debut
    }

    private static func bornesMillisecondes(_ creneau: MissionSlot) -> (debut: Int64, fin: Int64)? {
        guard let fin = creneau.finRenseignee,
              let debutDate = try? DateHeureParis.instantJolene(creneau.debut),
              let finDate = try? DateHeureParis.instantJolene(fin) else { return nil }
        return (DateHeureParis.millisecondes(debutDate), DateHeureParis.millisecondes(finDate))
    }
}
