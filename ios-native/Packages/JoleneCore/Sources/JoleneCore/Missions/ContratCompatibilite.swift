import Foundation

/// Port de la partie « contrat » de `src/lib/constantes.ts` :
/// `extraireContratPreference`, `getTypesContratSoignant`, `missionCompatibleContrat`.
public enum ContratCompatibilite {
    public static let preferences: [String] = ["TOUS", "SALARIE", "LIBERAL"]
    public static let tousTypesContrat: [String] = ["CDD", "VACATION", "LIBERAL", "SALARIE"]

    /// Tag legacy `[CONTRAT:TOUS|SALARIE|LIBERAL]` dans la description ; `TOUS` par défaut.
    public static func extraireContratPreference(_ description: String?) -> String {
        guard let description, !description.isEmpty else { return "TOUS" }
        let ouverture = "[CONTRAT:"
        var recherche = description[...]
        while let debut = recherche.range(of: ouverture) {
            let reste = recherche[debut.upperBound...]
            if let fin = reste.firstIndex(of: "]") {
                let valeur = String(reste[..<fin])
                if preferences.contains(valeur) { return valeur }
                recherche = reste[fin...]
            } else {
                break
            }
        }
        return "TOUS"
    }

    /// Contrat effectif d'une mission : `type_contrat_recherche` sinon le tag legacy.
    public static func contratEffectif(_ record: MissionRecord) -> String {
        if let type = record.typeContratRecherche, !type.isEmpty { return type }
        return extraireContratPreference(record.description)
    }

    /// Port de `missionCompatibleContrat`. Un profil libéral reste éligible à une
    /// mission salariée (Lot 21 / D4) : `types_contrat_acceptes` est une préférence,
    /// pas une interdiction juridique.
    public static func missionCompatible(preference: String?, typesContratSoignant: [String]) -> Bool {
        guard let preference, !preference.isEmpty, preference != "TOUS" else { return true }
        if preference == "LIBERAL" { return typesContratSoignant.contains("LIBERAL") }
        return true
    }

    /// Port de `getTypesContratSoignant` : JSON array ou liste séparée par des virgules,
    /// repli sur `type_exercice` puis `type_contrat`, sinon tous les types (profil incomplet).
    public static func typesContratSoignant(_ profile: SoignantProfile?) -> [String] {
        guard let profile else { return tousTypesContrat }
        if let brut = profile.typesContratAcceptes, !brut.isEmpty {
            let raw = brut.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.hasPrefix("["),
               let data = raw.data(using: .utf8),
               let tableau = try? JSONSerialization.jsonObject(with: data) as? [Any],
               !tableau.isEmpty {
                // Comme `JSON.parse` : le tableau est renvoyé tel quel ; seules les
                // chaînes sont exploitables côté Swift, les autres valeurs sont décrites.
                return tableau.map { ($0 as? String) ?? String(describing: $0) }
            }
            let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parts.isEmpty { return parts }
        }
        if profile.typeExercice == "MIXTE" { return ["CDD", "LIBERAL"] }
        if profile.typeExercice == "LIBERAL" { return ["LIBERAL"] }
        if let type = profile.typeContrat, !type.isEmpty { return [type] }
        return tousTypesContrat
    }
}
