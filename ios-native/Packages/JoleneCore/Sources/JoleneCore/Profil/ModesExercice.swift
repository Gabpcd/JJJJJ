import Foundation

/// Mode d'exercice proposé dans les préférences de recherche (`PreferenceModeExercice`).
/// Codes seulement : les libellés des modes d'exercice restent ceux du web (HARD STOP n°4).
public enum PreferenceModeExercice: String, CaseIterable, Sendable {
    case salarie = "SALARIE"
    case liberal = "LIBERAL"
}

/// Port de `src/lib/preferencesModesExercice.ts` : `types_contrat` du soignant vu comme deux cases
/// (salarié, libéral). CDD et vacation (CDD court) sont des formes d'exercice salarié ; les codes
/// historiques restent inchangés tant que le choix n'est pas retiré, aucun nouveau code n'est créé.
public enum ModesExercice {
    /// `CONTRATS_SALARIES`.
    public static let contratsSalaries: Set<String> = ["CDD", "VACATION", "SALARIE"]

    /// `modeExerciceSelectionne`.
    public static func estSelectionne(_ contrats: [String], mode: PreferenceModeExercice) -> Bool {
        switch mode {
        case .salarie: return contrats.contains { contratsSalaries.contains($0) }
        case .liberal: return contrats.contains("LIBERAL")
        }
    }

    /// `modifierPreferenceModeExercice` : cocher ajoute le code du mode s'il manque (liste inchangée
    /// sinon) ; décocher retire toutes ses variantes, l'ordre des autres codes est conservé.
    public static func modifier(_ contrats: [String], mode: PreferenceModeExercice, selectionne: Bool) -> [String] {
        if selectionne { return estSelectionne(contrats, mode: mode) ? contrats : contrats + [mode.rawValue] }
        return contrats.filter { contrat in
            switch mode {
            case .salarie: return !contratsSalaries.contains(contrat)
            case .liberal: return contrat != "LIBERAL"
            }
        }
    }
}
