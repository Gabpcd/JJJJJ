import Foundation

/// « Pourquoi 85 ? » de la carte de swipe : port de `src/lib/raisons-score-matching.ts` (règle extraite de
/// `CardMissionSwipe.tsx` par la PR web W0), vecteurs `raisons-score-matching.json` (L4-T2, `LOT4_PLAN.md` §3 T2).
///
/// Les deux contributeurs les plus parlants, en clair : les raisons épinglées de valeur > 0 d'abord, dans l'ordre de
/// `epinglees` (bonus forts à faible valeur numérique qu'un tri par points enterrerait), puis les autres raisons
/// connues de valeur > 0 par points décroissants. À égalité de points, l'ordre du breakdown départage (tri stable
/// du web). Seul un nombre JSON compte : texte, booléen, tableau ou `null` sont ignorés, comme `typeof v === 'number'`.
///
/// Écart assumé (documenté par W0) : le web lit `RAISON_LABELS[k]` par la chaîne de prototype ; une clé
/// `constructor`, `toString`… de valeur > 0 y passerait le filtre. Le dictionnaire Swift n'a pas de prototype et
/// ignore ces clés, que le breakdown v3 (`fn_calculer_score_matching`) n'émet pas (hors domaine golden).
public enum RaisonsScore {
    /// `RAISON_LABELS` : clés alignées sur le breakdown v3 (`soignant_fiabilite`, jamais l'ancienne `fiabilite`).
    public static let libelles: [String: String] = [
        "distance": "proche de chez toi",
        "tarif": "bien payée vs le marché",
        "horaire": "à tes horaires préférés",
        "etablissement": "établissement bien noté",
        "urgence": "mission urgente",
        "soignant_fiabilite": "ton profil correspond",
        "connaissance_etab": "tu connais cet établissement",
        "paiement_rapide": "paiement rapide ⚡",
    ]

    /// `RAISONS_EPINGLEES`, dans l'ordre d'affichage.
    public static let epinglees = ["connaissance_etab", "paiement_rapide"]

    /// Nombre de raisons affichées et séparateur (`slice(0, 2)`, `join(' · ')`).
    public static let nombreAffiche = 2
    public static let separateur = " · "

    /// Breakdown dans l'ordre du JSON reçu (paires clé, valeur brute). Une clé répétée garde sa première
    /// position et sa dernière valeur, comme `Object.fromEntries`.
    public static func raisons(_ breakdown: [(cle: String, valeur: ValeurJSON)]) -> String {
        var ordre: [String] = []
        var valeurs: [String: ValeurJSON] = [:]
        for (cle, valeur) in breakdown {
            if valeurs.updateValue(valeur, forKey: cle) == nil { ordre.append(cle) }
        }
        func points(_ cle: String) -> Double? {
            guard case .nombre(let nombre)? = valeurs[cle], nombre > 0 else { return nil }
            return nombre
        }
        let epinglees = Self.epinglees.filter { points($0) != nil }
        let autres = ordre.enumerated()
            .compactMap { index, cle -> (index: Int, cle: String, points: Double)? in
                guard libelles[cle] != nil, !Self.epinglees.contains(cle), let valeur = points(cle) else { return nil }
                return (index, cle, valeur)
            }
            // Tri décroissant stable : l'index du breakdown départage les égalités.
            .sorted { $0.points != $1.points ? $0.points > $1.points : $0.index < $1.index }
            .map(\.cle)
        return (epinglees + autres).prefix(nombreAffiche).compactMap { libelles[$0] }.joined(separator: separateur)
    }

    /// Breakdown brut d'une réponse : un objet est relu dans l'ordre `jsonb` (`ordreJsonb`) ; toute autre valeur,
    /// `null` ou une absence ne donne aucune raison (`breakdown || {}` du web, `Object.entries` d'un non-objet sans
    /// clé connue).
    public static func raisons(json: ValeurJSON?) -> String {
        guard case .objet(let objet)? = json else { return "" }
        return raisons(ordreJsonb(Array(objet.keys)).map { (cle: $0, valeur: objet[$0] ?? .null) })
    }

    /// Breakdown décodé par `CarteSwipe` (`[String: Double]`, ordre perdu) : les clés sont remises dans l'ordre où le
    /// serveur les émet. `fn_obtenir_missions_swipe` sert `ms.breakdown` en `jsonb`, dont les clés sortent par longueur
    /// en octets puis par octets (stockage `jsonb` de PostgreSQL) : c'est l'ordre que `JSON.parse` donne au web, donc
    /// celui qui y départage les égalités.
    public static func raisons(breakdownJsonb breakdown: [String: Double]) -> String {
        raisons(ordreJsonb(Array(breakdown.keys)).map { (cle: $0, valeur: .nombre(breakdown[$0] ?? 0)) })
    }

    /// Ordre des clés d'un objet `jsonb` : longueur UTF-8 croissante, puis octets.
    public static func ordreJsonb(_ cles: [String]) -> [String] {
        cles.sorted { a, b in
            let octetsA = Array(a.utf8), octetsB = Array(b.utf8)
            if octetsA.count != octetsB.count { return octetsA.count < octetsB.count }
            return octetsA.lexicographicallyPrecedes(octetsB)
        }
    }
}
