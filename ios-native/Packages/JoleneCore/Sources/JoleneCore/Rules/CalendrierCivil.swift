import Foundation

/// Arithmétique grégorienne proleptique pure (algorithmes de Howard Hinnant),
/// sans `Calendar` ni locale. Elle reproduit la normalisation de `Date.UTC` en
/// JavaScript, sur laquelle repose `src/lib/date-heure-paris.ts` : un mois 13
/// glisse en janvier de l'année suivante, un 30 février au 2 mars, une heure 24
/// au lendemain. Les règles portées doivent donner exactement les mêmes
/// résultats que le web, y compris sur ces entrées hors plage.
enum CalendrierCivil {
    /// Division entière arrondie vers moins l'infini (comme `Math.floor(a / b)`).
    static func divisionEntiere(_ a: Int, _ b: Int) -> Int {
        let quotient = a / b
        let reste = a % b
        return (reste != 0 && ((reste < 0) != (b < 0))) ? quotient - 1 : quotient
    }

    static func divisionEntiere(_ a: Int64, _ b: Int64) -> Int64 {
        let quotient = a / b
        let reste = a % b
        return (reste != 0 && ((reste < 0) != (b < 0))) ? quotient - 1 : quotient
    }

    static func modulo(_ a: Int, _ b: Int) -> Int {
        a - divisionEntiere(a, b) * b
    }

    /// Nombre de jours écoulés depuis le 1er janvier 1970 pour une date civile.
    /// Le mois est d'abord normalisé (13 → janvier suivant), puis le jour est
    /// ajouté linéairement, ce qui reproduit `Date.UTC`.
    static func joursDepuisCivil(annee: Int, mois: Int, jour: Int) -> Int {
        let moisTotal = annee * 12 + (mois - 1)
        var y = divisionEntiere(moisTotal, 12)
        let m = modulo(moisTotal, 12) + 1
        if m <= 2 { y -= 1 }
        let era = divisionEntiere(y, 400)
        let yoe = y - era * 400
        let mp = m > 2 ? m - 3 : m + 9
        let doy = (153 * mp + 2) / 5 + (jour - 1)
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// Date civile correspondant à un nombre de jours depuis le 1er janvier 1970.
    static func civilDepuisJours(_ jours: Int) -> (annee: Int, mois: Int, jour: Int) {
        let z = jours + 719_468
        let era = divisionEntiere(z, 146_097)
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }

    /// Jour de la semaine, 0 = dimanche … 6 = samedi (convention `getUTCDay`).
    static func jourSemaine(annee: Int, mois: Int, jour: Int) -> Int {
        // Le 1er janvier 1970 était un jeudi (4).
        modulo(joursDepuisCivil(annee: annee, mois: mois, jour: jour) + 4, 7)
    }

    /// Arrondi JavaScript (`Math.round`) : au plus proche, les demis vers +∞.
    static func arrondiJS(_ valeur: Double) -> Double {
        guard valeur.isFinite else { return valeur }
        let plancher = valeur.rounded(.down)
        return (valeur - plancher) >= 0.5 ? plancher + 1 : plancher
    }
}
