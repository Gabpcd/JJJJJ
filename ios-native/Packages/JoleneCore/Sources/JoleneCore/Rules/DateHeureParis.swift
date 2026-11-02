import Foundation

/// Composantes civiles françaises d'un instant (port de `PartiesDateHeureParis`).
public struct PartiesDateHeureParis: Codable, Equatable, Sendable {
    public var annee: Int
    public var mois: Int
    public var jour: Int
    public var heure: Int
    public var minute: Int
    public var seconde: Int

    public init(annee: Int, mois: Int, jour: Int, heure: Int, minute: Int, seconde: Int) {
        self.annee = annee; self.mois = mois; self.jour = jour
        self.heure = heure; self.minute = minute; self.seconde = seconde
    }

    /// `YYYY-MM-DDTHH:mm:ss`, utilisé par les messages d'erreur du web.
    var libelle: String {
        String(format: "%04d-%02d-%02dT%02d:%02d:%02d", annee, mois, jour, heure, minute, seconde)
    }
}

/// Erreurs du port de `date-heure-paris.ts`. `code` est la clé stable comparée
/// par les vecteurs golden ; `message` reprend le wording du web.
public enum DateHeureParisError: Error, Equatable, Sendable, LocalizedError {
    /// Chaîne non reconnue (équivalent d'une `Date` JavaScript invalide).
    case invalide(String)
    /// Heure murale absente du fuseau (passage à l'heure d'été).
    case inexistante(String)
    /// Heure murale répétée sans offset (retour à l'heure d'hiver).
    case ambigue(String)

    public var code: String {
        switch self {
        case .invalide: return "INVALIDE"
        case .inexistante: return "INEXISTANTE"
        case .ambigue: return "AMBIGUE"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalide(let valeur):
            return "Date Jolene invalide: \(valeur)"
        case .inexistante(let libelle):
            return "Date/heure inexistante dans le fuseau \(DateHeureParis.identifiantFuseau): \(libelle)"
        case .ambigue(let libelle):
            return "Date/heure ambiguë dans le fuseau \(DateHeureParis.identifiantFuseau): \(libelle)"
        }
    }
}

/// Fuseau métier unique de Jolene, port de `src/lib/date-heure-paris.ts`.
///
/// Les instants stockés par Supabase sont absolus ; un horaire de mission, un
/// jour de planning ou une saisie « locale » sont toujours lus dans le fuseau de
/// la France, quel que soit le fuseau de l'appareil. Aucune fonction ici ne lit
/// `TimeZone.current` ni `Locale.current` : seul `Europe/Paris` est consulté,
/// via `TimeZone.secondsFromGMT(for:)`, et le reste est de l'arithmétique pure.
public enum DateHeureParis {
    public static let identifiantFuseau = "Europe/Paris"
    public static let fuseau = TimeZone(identifier: identifiantFuseau)!

    static let joursCourts = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]
    static let joursLongs = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
    static let moisCourts = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]
    static let moisLongs = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]

    static let millisecondesParHeure: Int64 = 3_600_000
    static let millisecondesParJour: Int64 = 86_400_000

    // MARK: - Millisecondes (modèle `Date` JavaScript)

    /// Millisecondes entières depuis l'époque, comme `Date.prototype.getTime`.
    public static func millisecondes(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    public static func date(millisecondes: Int64) -> Date {
        Date(timeIntervalSince1970: Double(millisecondes) / 1000)
    }

    /// Équivalent de `Date.prototype.toISOString` (UTC, millisecondes, suffixe Z).
    public static func isoUTC(_ date: Date) -> String {
        let ms = millisecondes(date)
        let secondes = CalendrierCivil.divisionEntiere(ms, 1000)
        let partieMs = Int(ms - secondes * 1000)
        let jours = CalendrierCivil.divisionEntiere(secondes, 86_400)
        let reste = Int(secondes - jours * 86_400)
        let civil = CalendrierCivil.civilDepuisJours(Int(jours))
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
            civil.annee, civil.mois, civil.jour, reste / 3600, (reste % 3600) / 60, reste % 60, partieMs
        )
    }

    // MARK: - Analyse des chaînes ISO

    /// Convertit toute date Jolene en instant, y compris les ISO legacy sans
    /// offset, qui désignent une heure murale française (port de `instantJolene`).
    public static func instantJolene(_ valeur: String) throws -> Date {
        var scanner = ScannerISO(valeur)
        guard let annee = scanner.chiffres(4), scanner.consomme("-"),
              let mois = scanner.chiffres(2), scanner.consomme("-"),
              let jour = scanner.chiffres(2) else {
            throw DateHeureParisError.invalide(valeur)
        }
        if scanner.termine {
            // Forme « date seule » : minuit UTC, comme en JavaScript.
            return date(millisecondes: Int64(CalendrierCivil.joursDepuisCivil(annee: annee, mois: mois, jour: jour)) * millisecondesParJour)
        }
        guard scanner.consomme("T") || scanner.consomme(" "),
              let heure = scanner.chiffres(2), scanner.consomme(":"),
              let minute = scanner.chiffres(2) else {
            throw DateHeureParisError.invalide(valeur)
        }
        var seconde = 0
        var fraction = ""
        if scanner.consomme(":") {
            guard let s = scanner.chiffres(2) else { throw DateHeureParisError.invalide(valeur) }
            seconde = s
            if scanner.consomme(".") {
                guard let f = scanner.chiffresVariables() else { throw DateHeureParisError.invalide(valeur) }
                fraction = f
            }
        }
        // JavaScript tronque la fraction à la milliseconde (`.123456` → 123 ms).
        let fractionMs = Int(String(fraction.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0

        let parties = PartiesDateHeureParis(annee: annee, mois: mois, jour: jour, heure: heure, minute: minute, seconde: seconde)
        if scanner.termine {
            // ISO sans suffixe : heure murale française (fixtures et anciennes données).
            let instant = try self.instant(parties)
            return fractionMs > 0 ? date(millisecondes: millisecondes(instant) + Int64(fractionMs)) : instant
        }
        guard let decalageSecondes = scanner.decalage(), scanner.termine else {
            throw DateHeureParisError.invalide(valeur)
        }
        guard (1...12).contains(mois), (1...31).contains(jour), (0...24).contains(heure),
              (0...59).contains(minute), (0...59).contains(seconde),
              heure < 24 || (minute == 0 && seconde == 0 && fractionMs == 0) else {
            throw DateHeureParisError.invalide(valeur)
        }
        let utc = millisecondesUTC(parties) - Int64(decalageSecondes) * 1000 + Int64(fractionMs)
        return date(millisecondes: utc)
    }

    /// Interprète une valeur de saisie « locale » (`YYYY-MM-DDTHH:mm[:ss]`)
    /// comme une heure de Paris (port de `instantDepuisSaisieParis`).
    public static func instantDepuisSaisie(_ valeur: String) throws -> Date {
        var scanner = ScannerISO(valeur)
        guard let annee = scanner.chiffres(4), scanner.consomme("-"),
              let mois = scanner.chiffres(2), scanner.consomme("-"),
              let jour = scanner.chiffres(2), scanner.consomme("T"),
              let heure = scanner.chiffres(2), scanner.consomme(":"),
              let minute = scanner.chiffres(2) else {
            throw DateHeureParisError.invalide("Date/heure locale invalide: \(valeur)")
        }
        var seconde = 0
        if scanner.consomme(":") {
            guard let s = scanner.chiffres(2) else { throw DateHeureParisError.invalide("Date/heure locale invalide: \(valeur)") }
            seconde = s
        }
        guard scanner.termine else { throw DateHeureParisError.invalide("Date/heure locale invalide: \(valeur)") }
        return try instant(PartiesDateHeureParis(annee: annee, mois: mois, jour: jour, heure: heure, minute: minute, seconde: seconde))
    }

    // MARK: - Composantes civiles

    /// Composantes civiles françaises d'un instant absolu.
    public static func parties(_ date: Date) -> PartiesDateHeureParis {
        let ms = millisecondes(date)
        let secondesUTC = CalendrierCivil.divisionEntiere(ms, 1000)
        let local = secondesUTC + Int64(fuseau.secondsFromGMT(for: date))
        let jours = CalendrierCivil.divisionEntiere(local, 86_400)
        let reste = Int(local - jours * 86_400)
        let civil = CalendrierCivil.civilDepuisJours(Int(jours))
        return PartiesDateHeureParis(
            annee: civil.annee, mois: civil.mois, jour: civil.jour,
            heure: reste / 3600, minute: (reste % 3600) / 60, seconde: reste % 60
        )
    }

    /// Décalage du fuseau en minutes à un instant donné (port de `decalageParisMinutes`).
    static func decalageMinutes(_ date: Date) -> Int {
        Int(CalendrierCivil.arrondiJS(Double(fuseau.secondsFromGMT(for: date)) / 60))
    }

    /// `Date.UTC(...)` : millisecondes comme si les composantes étaient UTC.
    static func millisecondesUTC(_ p: PartiesDateHeureParis) -> Int64 {
        let jours = Int64(CalendrierCivil.joursDepuisCivil(annee: p.annee, mois: p.mois, jour: p.jour))
        return jours * millisecondesParJour
            + Int64(p.heure) * millisecondesParHeure
            + Int64(p.minute) * 60_000
            + Int64(p.seconde) * 1000
    }

    /// Instant correspondant à une heure murale, sans vérification. Réservé aux
    /// minuits civils : Paris ne change jamais d'heure à minuit, le résultat est
    /// donc toujours unique et existant.
    static func instantMural(_ p: PartiesDateHeureParis) -> Date {
        let cible = millisecondesUTC(p)
        var instant = cible
        for _ in 0..<3 {
            instant = cible - Int64(decalageMinutes(date(millisecondes: instant))) * 60_000
        }
        return date(millisecondes: instant)
    }

    /// Convertit une date/heure murale française en instant absolu, DST compris.
    /// Refuse explicitement une heure inexistante (printemps) ou ambiguë (automne) :
    /// un planning contractuel conserve exactement l'heure saisie ou la refuse.
    public static func instant(_ p: PartiesDateHeureParis) throws -> Date {
        let resultat = instantMural(p)
        guard parties(resultat) == p else {
            throw DateHeureParisError.inexistante(p.libelle)
        }
        let ms = millisecondes(resultat)
        if parties(date(millisecondes: ms - millisecondesParHeure)) == p
            || parties(date(millisecondes: ms + millisecondesParHeure)) == p {
            throw DateHeureParisError.ambigue(p.libelle)
        }
        return resultat
    }

    // MARK: - Bornes de jours, semaines, mois

    private static func dateCivile(_ date: Date) -> (annee: Int, mois: Int, jour: Int) {
        let p = parties(date)
        return (p.annee, p.mois, p.jour)
    }

    private static func minuit(annee: Int, mois: Int, jour: Int) -> Date {
        instantMural(PartiesDateHeureParis(annee: annee, mois: mois, jour: jour, heure: 0, minute: 0, seconde: 0))
    }

    private static func ajouterJoursCivil(_ civil: (annee: Int, mois: Int, jour: Int), _ jours: Int) -> (annee: Int, mois: Int, jour: Int) {
        CalendrierCivil.civilDepuisJours(
            CalendrierCivil.joursDepuisCivil(annee: civil.annee, mois: civil.mois, jour: civil.jour) + jours
        )
    }

    private static func lundiCivil(_ civil: (annee: Int, mois: Int, jour: Int)) -> (annee: Int, mois: Int, jour: Int) {
        let jourSemaine = CalendrierCivil.jourSemaine(annee: civil.annee, mois: civil.mois, jour: civil.jour)
        return ajouterJoursCivil(civil, -(jourSemaine == 0 ? 6 : jourSemaine - 1))
    }

    /// Début (00:00 Paris) du jour civil français contenant `date`.
    public static func debutJour(_ date: Date) -> Date {
        let c = dateCivile(date)
        return minuit(annee: c.annee, mois: c.mois, jour: c.jour)
    }

    /// Début du jour civil français situé `jours` jours après celui de `date`.
    public static func ajouterJoursCivils(_ date: Date, _ jours: Int) -> Date {
        let c = ajouterJoursCivil(dateCivile(date), jours)
        return minuit(annee: c.annee, mois: c.mois, jour: c.jour)
    }

    /// Premier jour à 00:00 du mois civil français contenant `date`.
    public static func debutMois(_ date: Date) -> Date {
        let c = dateCivile(date)
        return minuit(annee: c.annee, mois: c.mois, jour: 1)
    }

    /// Premier jour à 00:00 du mois français situé `mois` mois plus loin.
    public static func ajouterMoisCivils(_ date: Date, _ mois: Int) -> Date {
        let c = dateCivile(date)
        let total = c.annee * 12 + (c.mois - 1) + mois
        return minuit(annee: CalendrierCivil.divisionEntiere(total, 12), mois: CalendrierCivil.modulo(total, 12) + 1, jour: 1)
    }

    /// Dernière milliseconde du mois civil français contenant `date`.
    public static func finMois(_ date: Date) -> Date {
        self.date(millisecondes: millisecondes(ajouterMoisCivils(date, 1)) - 1)
    }

    /// Lundi 00:00 français de la semaine de `date`.
    public static func debutSemaine(_ date: Date) -> Date {
        let lundi = lundiCivil(dateCivile(date))
        return minuit(annee: lundi.annee, mois: lundi.mois, jour: lundi.jour)
    }

    /// Lundi 00:00 français de la semaine suivante.
    public static func semaineSuivante(_ date: Date) -> Date {
        ajouterJoursCivils(debutSemaine(date), 7)
    }

    // MARK: - Clés et comparaisons

    public static func cleJour(_ date: Date) -> String {
        let c = dateCivile(date)
        return String(format: "%04d-%02d-%02d", c.annee, c.mois, c.jour)
    }

    public static func cleMois(_ date: Date) -> String {
        let c = dateCivile(date)
        return String(format: "%04d-%02d", c.annee, c.mois)
    }

    public static func cleSemaine(_ date: Date) -> String {
        cleJour(debutSemaine(date))
    }

    public static func memeJour(_ a: Date, _ b: Date) -> Bool {
        cleJour(a) == cleJour(b)
    }

    public static func memeMois(_ a: Date, _ b: Date) -> Bool {
        let ca = dateCivile(a), cb = dateCivile(b)
        return ca.annee == cb.annee && ca.mois == cb.mois
    }

    /// Heure décimale française (8h30 = 8.5), utile aux grilles horaires.
    public static func heureDecimale(_ date: Date) -> Double {
        let p = parties(date)
        return Double(p.heure) + Double(p.minute) / 60
    }

    // MARK: - Formatage

    private static let jetons = ["MMMM", "EEEE", "yyyy", "MMM", "EEE", "dd", "MM", "HH", "mm", "ss", "d", "M", "H", "m", "s"]

    /// Formate les composantes Europe/Paris selon le sous-ensemble de jetons
    /// date-fns utilisé par les plannings Jolene. Les textes entre apostrophes
    /// sont des littéraux ; `''` produit une apostrophe.
    public static func format(_ date: Date, _ masque: String) -> String {
        let p = parties(date)
        let jourSemaine = CalendrierCivil.jourSemaine(annee: p.annee, mois: p.mois, jour: p.jour)
        let pad2 = { (n: Int) in String(format: "%02d", n) }
        let valeurs: [String: String] = [
            "MMMM": moisLongs[CalendrierCivil.modulo(p.mois - 1, 12)],
            "EEEE": joursLongs[jourSemaine],
            "EEE": joursCourts[jourSemaine],
            "MMM": moisCourts[CalendrierCivil.modulo(p.mois - 1, 12)],
            "yyyy": String(format: "%04d", p.annee),
            "dd": pad2(p.jour), "MM": pad2(p.mois), "HH": pad2(p.heure), "mm": pad2(p.minute), "ss": pad2(p.seconde),
            "d": String(p.jour), "M": String(p.mois), "H": String(p.heure), "m": String(p.minute), "s": String(p.seconde),
        ]
        let caracteres = Array(masque)
        var resultat = ""
        var index = 0
        while index < caracteres.count {
            if caracteres[index] == "'" {
                index += 1
                while index < caracteres.count {
                    if caracteres[index] != "'" {
                        resultat.append(caracteres[index])
                        index += 1
                        continue
                    }
                    if index + 1 < caracteres.count && caracteres[index + 1] == "'" {
                        resultat.append("'")
                        index += 2
                        continue
                    }
                    index += 1
                    break
                }
                continue
            }
            if let jeton = jetons.first(where: { commence(caracteres, par: $0, a: index) }) {
                resultat += valeurs[jeton] ?? ""
                index += jeton.count
            } else {
                resultat.append(caracteres[index])
                index += 1
            }
        }
        return resultat
    }

    private static func commence(_ caracteres: [Character], par jeton: String, a index: Int) -> Bool {
        let attendu = Array(jeton)
        guard index + attendu.count <= caracteres.count else { return false }
        return Array(caracteres[index..<(index + attendu.count)]) == attendu
    }

    /// Valeur compatible avec un champ de saisie `datetime-local`, en heure de Paris.
    public static func valeurSaisie(_ date: Date) -> String {
        format(date, "yyyy-MM-dd'T'HH:mm")
    }
}

/// Lecteur minimal de chaînes ISO 8601 (sous-ensemble accepté par `new Date` en
/// JavaScript : date seule, date-heure, fraction, suffixe `Z` ou `±HH:MM`).
struct ScannerISO {
    private let octets: [UInt8]
    private var index = 0

    init(_ valeur: String) { octets = Array(valeur.utf8) }

    var termine: Bool { index >= octets.count }

    mutating func consomme(_ caractere: Character) -> Bool {
        guard index < octets.count, octets[index] == caractere.asciiValue else { return false }
        index += 1
        return true
    }

    /// Exactement `n` chiffres.
    mutating func chiffres(_ n: Int) -> Int? {
        guard index + n <= octets.count else { return nil }
        var valeur = 0
        for i in index..<(index + n) {
            let c = octets[i]
            guard c >= 48 && c <= 57 else { return nil }
            valeur = valeur * 10 + Int(c - 48)
        }
        index += n
        return valeur
    }

    /// Un chiffre ou plus, renvoyés tels quels.
    mutating func chiffresVariables() -> String? {
        let debut = index
        while index < octets.count, octets[index] >= 48, octets[index] <= 57 { index += 1 }
        guard index > debut else { return nil }
        return String(decoding: octets[debut..<index], as: UTF8.self)
    }

    /// Décalage en secondes : `Z`, `±HH`, `±HHMM` ou `±HH:MM`.
    mutating func decalage() -> Int? {
        if consomme("Z") || consomme("z") { return 0 }
        let signe: Int
        if consomme("+") { signe = 1 } else if consomme("-") { signe = -1 } else { return nil }
        guard let heures = chiffres(2) else { return nil }
        var minutes = 0
        if consomme(":") {
            guard let m = chiffres(2) else { return nil }
            minutes = m
        } else if let m = chiffres(2) {
            minutes = m
        }
        return signe * (heures * 3600 + minutes * 60)
    }
}
