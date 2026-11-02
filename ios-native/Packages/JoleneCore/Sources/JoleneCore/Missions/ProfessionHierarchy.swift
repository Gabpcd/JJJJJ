import Foundation

/// Port de `src/lib/profession-hierarchy.ts` : miroir de `fn_soignant_compatible_mission`.
/// IBODE et IADE peuvent candidater aux missions IDE ; une mission IADE ou IBODE
/// exige la spécialisation exacte. Les autres professions sont en match strict.
public enum ProfessionHierarchy {
    public static let professionsAvecHierarchie: Set<String> = ["IBODE", "IADE"]

    /// Professions requises qu'un soignant de `profession` peut voir sans filtre explicite.
    /// Équivalent du tableau `compatible` de `filterMissions` (business.ts).
    public static func professionsCompatibles(soignant profession: String) -> [String] {
        if professionsAvecHierarchie.contains(profession) { return [profession, "IDE"] }
        return [profession]
    }

    /// Port de `getMissionsCompatiblesFilter` : clause `.or()` PostgREST, ou `nil`
    /// quand un `.eq('profession_requise', X)` suffit.
    public static func missionsCompatiblesFilter(soignant profession: String?) -> String? {
        guard let profession, !profession.isEmpty else { return nil }
        if professionsAvecHierarchie.contains(profession) {
            return "profession_requise.eq.\(profession),profession_requise.eq.IDE"
        }
        return nil
    }

    /// Port de `professionMissionExigeSpecialisationExacte`.
    public static func exigeSpecialisationExacte(professionRequise: String?) -> Bool {
        professionRequise == "IADE" || professionRequise == "IBODE"
    }
}
