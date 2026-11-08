import Foundation

public extension MissionPresentation {
    /// Port de `formatHeures` de `src/components/planning/PlanningMissionCandidat.tsx` (l.23-25) :
    /// `heures.toLocaleString('fr-FR', { maximumFractionDigits: 2 })`. Règle unique pour le résumé
    /// « N créneaux · X h au total » (`JoleneDesign.SlotList`) et la durée « · X h » d'une ligne de
    /// créneau du planning candidat (formateur de ligne web, T2/T6a) : aucun autre module ne la recopie.
    ///
    /// Comme `Intl` : décimal le plus court du nombre (celui de JavaScript, donc 1.005 et non
    /// 1.00499…), arrondi au centième « moitié vers l'infini », zéros finaux retirés, virgule décimale,
    /// espace fine insécable U+202F pour les milliers, signe « - » ASCII (« -0 » conservé), « NaN »
    /// et « ∞ » pour les valeurs non finies. Affichage seul : la valeur vient du cœur
    /// (`PlanningCandidat.totalHeures`, durée d'un créneau), jamais d'une heure facturée.
    ///
    /// Ne pas confondre avec `FormatMission.formatHeures` (`src/lib/format-mission.ts`, dixième, sans
    /// séparateur de milliers) : deux règles web distinctes, deux ports distincts.
    static func heuresPlanning(_ heures: Double) -> String {
        if heures.isNaN { return "NaN" }
        let signe = heures.sign == .minus ? "-" : ""
        if heures.isInfinite { return "\(signe)\u{221E}" }
        // `description` de Swift = décimal le plus court qui relit le même Double (algorithme de JavaScript).
        guard var source = Decimal(string: "\(heures.magnitude)", locale: Locale(identifier: "en_US_POSIX")) else {
            return "\(signe)\(heures.magnitude)"
        }
        var arrondi = Decimal()
        NSDecimalRound(&arrondi, &source, 2, .plain)
        let chiffres = NSDecimalNumber(decimal: arrondi).description(withLocale: Locale(identifier: "en_US_POSIX"))
        let parties = chiffres.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let entier = String(parties[0])
        var decimales = parties.count > 1 ? String(parties[1]) : ""
        while decimales.hasSuffix("0") { decimales.removeLast() }
        return signe + groupeParMilliers(entier) + (decimales.isEmpty ? "" : ",\(decimales)")
    }

    /// « 1234567 » → « 1 234 567 » (U+202F), comme `Intl` fr-FR.
    private static func groupeParMilliers(_ entier: String) -> String {
        var groupes: [Substring] = []
        var fin = entier.endIndex
        while fin > entier.startIndex {
            let debut = entier.index(fin, offsetBy: -3, limitedBy: entier.startIndex) ?? entier.startIndex
            groupes.insert(entier[debut..<fin], at: 0)
            fin = debut
        }
        return groupes.joined(separator: separateurMilliers)
    }
}
