import Foundation

/// Mission ouverte d'une série, telle que lue par la sélection (`MissionSerieCandidat` côté web :
/// un `id` et le planning candidat de la mission).
public protocol MissionSerieCandidat {
    var id: String { get }
    var planningCandidat: PlanningCandidatInput { get }
}

extension Mission: MissionSerieCandidat {
    /// Créneaux et erreur de planning issus de l'enrichissement, comme `creneaux_planifies`
    /// et `erreur_planning` côté web.
    public var planningCandidat: PlanningCandidatInput { PlanningCandidatInput(mission: self) }
}

/// Résultat de `analyserSelectionSerie` (port de `AnalyseSelectionSerie`).
public struct AnalyseSelectionSerie<T: MissionSerieCandidat> {
    /// Missions ouvertes sélectionnées, dans l'ordre des missions ouvertes, sans retrait.
    public var missionsSelectionnees: [T]
    /// Missions sélectionnées en conflit, dans le même ordre.
    public var idsEnConflit: [String]
    /// Missions sélectionnées dont le planning exact n'est pas disponible, dans le même ordre.
    public var idsPlanningInexact: [String]
    public var peutAccepter: Bool

    public init(missionsSelectionnees: [T], idsEnConflit: [String], idsPlanningInexact: [String], peutAccepter: Bool) {
        self.missionsSelectionnees = missionsSelectionnees; self.idsEnConflit = idsEnConflit
        self.idsPlanningInexact = idsPlanningInexact; self.peutAccepter = peutAccepter
    }
}

extension AnalyseSelectionSerie: Equatable where T: Equatable {}
extension AnalyseSelectionSerie: Sendable where T: Sendable {}

/// Port de `src/components/planning/selection-serie-candidat.ts`.
public enum SelectionSerieCandidat {
    /// Analyse la sélection sans jamais retirer silencieusement une mission : l'interface laisse
    /// décocher le ou les créneaux responsables d'un conflit, puis accepte exactement le
    /// sous-ensemble vu. Une sélection vide, un conflit ou un planning inexact bloquent.
    public static func analyser<T: MissionSerieCandidat>(
        _ missionsOuvertes: [T], idsSelectionnes: Set<String>, idsConflit: Set<String>
    ) -> AnalyseSelectionSerie<T> {
        let missionsSelectionnees = missionsOuvertes.filter { idsSelectionnes.contains($0.id) }
        let idsEnConflit = missionsSelectionnees.filter { idsConflit.contains($0.id) }.map(\.id)
        let idsPlanningInexact = missionsSelectionnees
            .filter { !PlanningCandidatRules.construirePlanningCandidat($0.planningCandidat).exact }
            .map(\.id)
        return AnalyseSelectionSerie(
            missionsSelectionnees: missionsSelectionnees,
            idsEnConflit: idsEnConflit,
            idsPlanningInexact: idsPlanningInexact,
            peutAccepter: !missionsSelectionnees.isEmpty && idsEnConflit.isEmpty && idsPlanningInexact.isEmpty
        )
    }
}
