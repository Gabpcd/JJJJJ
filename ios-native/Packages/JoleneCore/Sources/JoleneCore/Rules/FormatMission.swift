import Foundation

/// Horaires d'une mission tels que formatés par les surfaces soignant
/// (port de `MissionHoraires` dans `src/lib/format-mission.ts`).
public struct MissionHoraires: Equatable, Sendable {
    public var debutLe: String?
    public var finLe: String?
    /// `numeric` Postgres : la valeur peut être absente ou nulle ; `nil`, `0` et
    /// `NaN` sont traités comme « inconnue », comme `Number(x) || 0` côté web.
    public var dureeHeures: Double?
    public var nbCreneaux: Int?

    public init(debutLe: String?, finLe: String?, dureeHeures: Double? = nil, nbCreneaux: Int? = nil) {
        self.debutLe = debutLe; self.finLe = finLe; self.dureeHeures = dureeHeures; self.nbCreneaux = nbCreneaux
    }
}

public extension MissionRecord {
    /// Projection de la ligne `missions` vers les horaires formatables.
    var horaires: MissionHoraires {
        MissionHoraires(debutLe: debutLe, finLe: finLe, dureeHeures: dureeHeures, nbCreneaux: nbCreneaux)
    }
}

/// Formatage unifié des dates, horaires et durées d'une mission
/// (port de `src/lib/format-mission.ts`, Lot 6a.3).
///
/// Règles :
/// - mission d'un jour : « jeudi 3 juillet 2026 » + « 08h00 → 18h00 (10 h) » ;
/// - mission multi-jours : « 13 → 31 juillet 2026 » + « 10 jours · 8 h/j · 13h–21h » ;
/// - le label jour/nuit est toujours dérivé des horaires réels, jamais stocké.
///
/// Toutes les heures sont lues en `Europe/Paris` (le web lit l'heure locale du
/// navigateur, réputée française). Une chaîne de date illisible donne « — »
/// là où le web lèverait une erreur de formatage.
public enum FormatMission {
    static let millisecondesParJour: Int64 = 86_400_000

    private static func instant(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        return try? DateHeureParis.instantJolene(iso)
    }

    private static func renseigne(_ iso: String?) -> Bool {
        guard let iso else { return false }
        return !iso.isEmpty
    }

    /// `Number(x) || 0` : absent, nul ou NaN valent 0.
    static func nombre(_ valeur: Double?) -> Double {
        guard let valeur, !valeur.isNaN else { return 0 }
        return valeur
    }

    /// Nuit dérivée des horaires réels : début à 20 h ou plus, ou avant 7 h.
    public static func estMissionDeNuit(debutISO: String?) -> Bool {
        guard let debut = instant(debutISO) else { return false }
        let heure = DateHeureParis.parties(debut).heure
        return heure >= 20 || heure < 7
    }

    /// Multi-jours : plusieurs créneaux, ou plage début→fin au-delà de 24 h.
    public static func estMultiJours(_ mission: MissionHoraires) -> Bool {
        guard renseigne(mission.debutLe), renseigne(mission.finLe) else { return false }
        if (mission.nbCreneaux ?? 0) > 1 { return true }
        guard let debut = instant(mission.debutLe), let fin = instant(mission.finLe) else { return false }
        return DateHeureParis.millisecondes(fin) - DateHeureParis.millisecondes(debut) > millisecondesParJour
    }

    /// Durée quotidienne (h) dérivée des heures murales — gère la nuit qui passe minuit.
    private static func heuresParJour(_ debut: Date, _ fin: Date) -> Double {
        let pd = DateHeureParis.parties(debut)
        let pf = DateHeureParis.parties(fin)
        var minutes = (pf.heure * 60 + pf.minute) - (pd.heure * 60 + pd.minute)
        if minutes <= 0 { minutes += 24 * 60 }
        return Double(minutes) / 60
    }

    /// Nombre de jours travaillés : créneaux si connus, sinon durée totale / durée quotidienne.
    public static func nbJoursTravailles(_ mission: MissionHoraires) -> Int {
        guard renseigne(mission.debutLe), renseigne(mission.finLe) else { return 1 }
        if let nb = mission.nbCreneaux, nb > 1 { return nb }
        guard let debut = instant(mission.debutLe), let fin = instant(mission.finLe) else { return 1 }
        if !estMultiJours(mission) { return 1 }
        let duree = nombre(mission.dureeHeures)
        let hJour = heuresParJour(debut, fin)
        if duree > 0 && hJour > 0 {
            return max(1, Int(CalendrierCivil.arrondiJS(duree / hJour)))
        }
        let plage = Double(DateHeureParis.millisecondes(fin) - DateHeureParis.millisecondes(debut))
        return max(1, Int((plage / Double(millisecondesParJour)).rounded(.up)))
    }

    /// « 10 » ou « 7,5 » — entier si rond, sinon 1 décimale (virgule FR).
    static func formatHeures(_ heures: Double) -> String {
        let arrondi = CalendrierCivil.arrondiJS(heures * 10) / 10
        if arrondi.isFinite && arrondi == arrondi.rounded(.towardZero) {
            return String(Int(arrondi))
        }
        return "\(arrondi)".replacingOccurrences(of: ".", with: ",")
    }

    /// « 08h » ou « 08h30 » — minutes seulement si non nulles.
    private static func heureCompacte(_ date: Date) -> String {
        DateHeureParis.format(date, DateHeureParis.parties(date).minute == 0 ? "HH'h'" : "HH'h'mm")
    }

    /// Ligne date : « jeudi 3 juillet 2026 » (1 jour)
    /// ou « 13 → 31 juillet 2026 » / « 28 juil. → 3 août 2026 » (multi-jours).
    public static func formatDateMission(_ mission: MissionHoraires) -> String {
        guard renseigne(mission.debutLe), let debut = instant(mission.debutLe) else { return "—" }
        if !estMultiJours(mission) || !renseigne(mission.finLe) {
            return DateHeureParis.format(debut, "EEEE d MMMM yyyy")
        }
        guard let fin = instant(mission.finLe) else { return "—" }
        let pd = DateHeureParis.parties(debut)
        let pf = DateHeureParis.parties(fin)
        let memeMois = pd.mois == pf.mois && pd.annee == pf.annee
        return memeMois
            ? "\(DateHeureParis.format(debut, "d")) → \(DateHeureParis.format(fin, "d MMMM yyyy"))"
            : "\(DateHeureParis.format(debut, "d MMM")) → \(DateHeureParis.format(fin, "d MMM yyyy"))"
    }

    /// Ligne horaires : « 08h00 → 18h00 (10 h) » (1 jour)
    /// ou « 20 jours · 8 h/j · 13h–21h » (multi-jours).
    public static func formatHorairesMission(_ mission: MissionHoraires) -> String {
        guard renseigne(mission.debutLe), renseigne(mission.finLe),
              let debut = instant(mission.debutLe), let fin = instant(mission.finLe) else { return "—" }
        let brut = nombre(mission.dureeHeures)
        let duree = brut != 0
            ? brut
            : Double(DateHeureParis.millisecondes(fin) - DateHeureParis.millisecondes(debut)) / 3_600_000

        if !estMultiJours(mission) {
            return "\(DateHeureParis.format(debut, "HH'h'mm")) → \(DateHeureParis.format(fin, "HH'h'mm")) (\(formatHeures(duree)) h)"
        }

        let jours = nbJoursTravailles(mission)
        let hJour = heuresParJour(debut, fin)
        return "\(jours) jours · \(formatHeures(hJour)) h/j · \(heureCompacte(debut))–\(heureCompacte(fin))"
    }

    /// Résumé une ligne (carte swipe) : « 10h » ou « 2 créneaux · 13 h au total ».
    public static func formatDureeCompacte(_ mission: MissionHoraires) -> String {
        guard renseigne(mission.debutLe), renseigne(mission.finLe) else { return "—" }
        let duree = nombre(mission.dureeHeures)
        if !estMultiJours(mission) { return duree > 0 ? "\(formatHeures(duree))h" : "—" }

        // `debut_le` et `fin_le` bornent toute la période, repos compris : leur
        // différence ne vaut jamais une durée quotidienne. Le nombre de créneaux,
        // quand il est connu, est l'unité exacte et non ambiguë.
        let nbCreneaux = mission.nbCreneaux ?? 0
        if nbCreneaux > 1 {
            return duree > 0 ? "\(nbCreneaux) créneaux · \(formatHeures(duree)) h au total" : "\(nbCreneaux) créneaux"
        }

        let jours = nbJoursTravailles(mission)
        return duree > 0 ? "\(jours) jours · \(formatHeures(duree)) h au total" : "\(jours) jours"
    }
}
