import Foundation

/// Élément de `p_creneaux_confirmes` envoyé à `fn_confirmer_action_planning_v1` : les bornes
/// d'un créneau PREVISIONNEL de travail que le soignant a vues dans le récapitulatif.
/// Le serveur relit `element->>'debut'` et `element->>'fin'` en `timestamptz` et les compare,
/// sous verrou, au planning live (`supabase/schema/public.sql`, fonction l.24141).
public struct CreneauConfirme: Codable, Hashable, Sendable {
    public var debut: String
    public var fin: String

    public init(debut: String, fin: String) {
        self.debut = debut; self.fin = fin
    }
}

/// Port de `creneauxConfirmesPourAction` (src/components/planning/planning-candidat.ts l.136-147)
/// et format filaire natif de la charge utile.
///
/// - `lus` : parité web exacte, les chaînes PostgREST telles que lues (récapitulatif, golden).
/// - `pourAction` : ce que l'app envoie. Mêmes créneaux, dans le même ordre, chaque borne
///   réécrite en UTC `yyyy-MM-dd'T'HH:mm:ss'Z'` sans fraction, depuis les mêmes `debut`/`fin`
///   lus : `fn_valider_creneaux_mission_json` exige un suffixe `Z` ou un décalage, et la
///   comparaison serveur porte sur l'instant, jamais sur la chaîne.
///
/// Fail-closed : `nil` dès que le planning n'est pas exact (compteur, ligne sans fin, erreur de
/// chargement, date illisible) ou qu'une borne porte une fraction de seconde non nulle (non
/// représentable sans changer l'instant comparé). `nil` bloque l'action ; on relit la mission,
/// on ne renvoie jamais une charge approximative.
public enum CreneauxConfirmes {
    /// Port exact de `creneauxConfirmesPourAction`. Écart assumé du lot 0 : là où le web lève sur
    /// une date illisible, le port renvoie `nil` (planning non exact).
    public static func lus(_ mission: PlanningCandidatInput) -> [CreneauConfirme]? {
        let planning = PlanningCandidatRules.construirePlanningCandidat(mission)
        guard planning.exact, !planning.creneaux.contains(where: { $0.finRenseignee == nil }) else { return nil }
        return planning.creneaux.compactMap { creneau in
            creneau.finRenseignee.map { CreneauConfirme(debut: creneau.debut, fin: $0) }
        }
    }

    /// Charge utile native de `p_creneaux_confirmes`.
    public static func pourAction(_ mission: PlanningCandidatInput) -> [CreneauConfirme]? {
        guard let lus = lus(mission) else { return nil }
        var filaires: [CreneauConfirme] = []
        filaires.reserveCapacity(lus.count)
        for creneau in lus {
            guard let debut = isoUTCSansFraction(creneau.debut), let fin = isoUTCSansFraction(creneau.fin) else { return nil }
            filaires.append(CreneauConfirme(debut: debut, fin: fin))
        }
        return filaires
    }

    /// Instant de `valeur` (règles de `instantJolene` : décalage explicite, ou heure murale
    /// française pour un ISO legacy sans offset) au format `yyyy-MM-dd'T'HH:mm:ss'Z'`.
    /// `nil` si la chaîne est illisible ou si sa fraction de seconde n'est pas nulle, y compris
    /// au-delà de la milliseconde (`instantJolene` tronque comme `Date`, le serveur non).
    public static func isoUTCSansFraction(_ valeur: String) -> String? {
        guard fractionNulle(valeur), let instant = try? DateHeureParis.instantJolene(valeur) else { return nil }
        let iso = DateHeureParis.isoUTC(instant)
        guard iso.hasSuffix(".000Z") else { return nil }
        return String(iso.dropLast(5)) + "Z"
    }

    /// Vrai si la chaîne n'a pas de fraction de seconde, ou une fraction faite de zéros.
    private static func fractionNulle(_ valeur: String) -> Bool {
        guard let point = valeur.firstIndex(of: ".") else { return true }
        let chiffres = valeur[valeur.index(after: point)...].prefix { $0.isASCII && $0.isNumber }
        return chiffres.allSatisfy { $0 == "0" }
    }
}
