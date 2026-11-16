import Foundation

/// Résultat de `construireSynthesePresenceMission` (port de `SynthesePresenceMission`).
public struct SynthesePresenceMission: Equatable, Sendable {
    public var previsionnels: [MissionSlot]
    public var effectifsFermes: [MissionSlot]
    public var effectifsOuverts: [MissionSlot]
    public var minutesPlanifiees: Double
    public var minutesTravaillees: Double
    /// Fin du dernier créneau prévu (par début) ; `nil` si aucun ou illisible.
    public var dernierPrevisionnelFin: Date?
    public var planningTermine: Bool
    public var validationPossible: Bool

    public init(previsionnels: [MissionSlot], effectifsFermes: [MissionSlot], effectifsOuverts: [MissionSlot],
                minutesPlanifiees: Double, minutesTravaillees: Double, dernierPrevisionnelFin: Date?,
                planningTermine: Bool, validationPossible: Bool) {
        self.previsionnels = previsionnels; self.effectifsFermes = effectifsFermes; self.effectifsOuverts = effectifsOuverts
        self.minutesPlanifiees = minutesPlanifiees; self.minutesTravaillees = minutesTravaillees
        self.dernierPrevisionnelFin = dernierPrevisionnelFin; self.planningTermine = planningTermine
        self.validationPossible = validationPossible
    }
}

/// Port de `src/lib/synthese-presence-mission.ts` : synthèse canonique d'une mission pointée.
///
/// Les champs de `presences` ne représentent que la première arrivée et le dernier départ d'une
/// mission ; ils incluent les jours de repos d'une mission multi-créneaux et ne servent jamais à
/// calculer du temps travaillé. Seuls les créneaux EFFECTIF fermés sont additionnés (état dérivé,
/// une seule source).
public enum SynthesePresence {
    public static func construire(_ creneaux: [MissionSlot], maintenant: Date) -> SynthesePresenceMission {
        let previsionnels = DisponibilitePointage.creneauxPrevisionnels(creneaux)
        let effectifs = triStableCroissant(creneaux.filter { $0.typeCreneau == "EFFECTIF" && !$0.estPause }) {
            DisponibilitePointage.temps($0.debut)
        }
        let effectifsFermes = effectifs.filter { !($0.fin ?? "").isEmpty }
        let effectifsOuverts = effectifs.filter { ($0.fin ?? "").isEmpty }
        let finMs = previsionnels.last.map { DisponibilitePointage.temps($0.fin) } ?? .nan
        let dernierPrevisionnelFin: Date? = finMs.isFinite ? DateHeureParis.date(millisecondes: Int64(finMs)) : nil
        let planningTermine = finMs.isFinite && DisponibilitePointage.temps(maintenant) >= finMs

        return SynthesePresenceMission(
            previsionnels: previsionnels,
            effectifsFermes: effectifsFermes,
            effectifsOuverts: effectifsOuverts,
            minutesPlanifiees: previsionnels.reduce(0) { $0 + dureeMinutes($1) },
            minutesTravaillees: effectifsFermes.reduce(0) { $0 + dureeMinutes($1) },
            dernierPrevisionnelFin: dernierPrevisionnelFin,
            planningTermine: planningTermine,
            validationPossible: planningTermine && effectifsOuverts.isEmpty && !effectifsFermes.isEmpty
        )
    }

    /// `formatDureeMinutes` : heures `Math.floor`, minutes `Math.round` du reste (`%` JavaScript),
    /// complétées à deux chiffres. Comme le web, 119,6 min s'écrit « 1h60 ».
    public static func formatDureeMinutes(_ minutes: Double) -> String {
        let heures = (minutes / 60).rounded(.down)
        let reste = arrondiJS(minutes.truncatingRemainder(dividingBy: 60))
        let texteReste = String(Int(reste))
        return "\(Int(heures))h\(texteReste.count < 2 ? "0" + texteReste : texteReste)"
    }

    /// Durée d'un créneau fermé en minutes (millisecondes entières / 60 000, comme `getTime()`) ;
    /// 0 si une borne manque, est illisible ou si la fin ne suit pas le début.
    static func dureeMinutes(_ creneau: MissionSlot) -> Double {
        guard let fin = creneau.fin, !fin.isEmpty else { return 0 }
        let debutMs = DisponibilitePointage.temps(creneau.debut)
        let finMs = DisponibilitePointage.temps(fin)
        guard debutMs.isFinite, finMs.isFinite, finMs > debutMs else { return 0 }
        return (finMs - debutMs) / 60_000
    }

    /// `Math.round` : entier le plus proche, demi vers +∞ (exact, sans le biais de `floor(x + 0,5)`).
    static func arrondiJS(_ valeur: Double) -> Double {
        let plancher = valeur.rounded(.down)
        return valeur - plancher >= 0.5 ? plancher + 1 : plancher
    }
}

/// Tri stable croissant sur une clé numérique (`Array.prototype.sort` avec `a - b`, stable) ;
/// deux clés incomparables (NaN) gardent leur ordre d'origine.
func triStableCroissant<T>(_ elements: [T], cle: (T) -> Double) -> [T] {
    elements.enumerated().sorted { a, b in
        let ka = cle(a.element), kb = cle(b.element)
        if ka < kb { return true }
        if kb < ka { return false }
        return a.offset < b.offset
    }.map(\.element)
}
