import Foundation

/// Mission ouverte d'une série, telle que `analyserSelectionSerie` la lit
/// (`MissionSerieCandidat` côté web : un `id` obligatoire et un planning candidat).
public protocol MissionSerieCandidatRepresentable: Sendable {
    var id: String { get }
    var planningCandidat: PlanningCandidatInput { get }
}

/// Forme minimale d'une mission de série, pour les lignes `missions` sans enrichissement.
public struct MissionSerieCandidat: Equatable, Sendable, MissionSerieCandidatRepresentable {
    public var id: String
    public var planningCandidat: PlanningCandidatInput

    public init(id: String, planning: PlanningCandidatInput) {
        self.id = id
        self.planningCandidat = planning
    }
}

extension Mission: MissionSerieCandidatRepresentable {
    public var planningCandidat: PlanningCandidatInput { PlanningCandidatInput(mission: self) }
}

/// Résultat de `analyserSelectionSerie` (src/components/planning/selection-serie-candidat.ts).
public struct AnalyseSelectionSerie<T: MissionSerieCandidatRepresentable>: Sendable {
    public var missionsSelectionnees: [T]
    public var idsEnConflit: [String]
    public var idsPlanningInexact: [String]
    public var peutAccepter: Bool

    public init(missionsSelectionnees: [T], idsEnConflit: [String], idsPlanningInexact: [String], peutAccepter: Bool) {
        self.missionsSelectionnees = missionsSelectionnees; self.idsEnConflit = idsEnConflit
        self.idsPlanningInexact = idsPlanningInexact; self.peutAccepter = peutAccepter
    }
}

extension AnalyseSelectionSerie: Equatable where T: Equatable {}

/// Port de `analyserSelectionSerie` : l'analyse ne retire jamais silencieusement une
/// mission ; l'interface laisse décocher les créneaux en conflit puis accepte exactement le
/// sous-ensemble vu. L'ordre est celui des missions ouvertes, pas celui de la sélection.
public enum SelectionSerieCandidat {
    public static func analyser<T: MissionSerieCandidatRepresentable>(
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
