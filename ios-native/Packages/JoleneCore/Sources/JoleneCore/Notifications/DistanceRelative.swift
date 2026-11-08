import Foundation

/// Port de `formatDistanceToNow(date, { addSuffix: true, locale: fr })` de date-fns 3.6.0 (date des lignes du
/// centre de notifications, `src/pages/PageNotifications.tsx` l.161) : `formatDistance` (`date-fns/formatDistance.js`),
/// `differenceInMonths` et la locale `fr` (`date-fns/locale/fr/_lib/formatDistance.js`), libellés verbatim.
///
/// Comme le web, le calcul dépend du fuseau de l'appareil (`fuseau`) : l'écart de décalage horaire entre les deux
/// instants (changement d'heure) est retranché avant l'arrondi aux minutes, et les mois sont comptés en dates
/// locales. Les instants sont ramenés à la milliseconde entière (`DateHeureParis.millisecondes`, `Date` JavaScript). Les valeurs attendues des tests
/// (`DistanceRelativeTests`) sont celles de date-fns exécuté sous Node (`TZ=Europe/Paris`), y compris ses
/// bizarreries (« il y a -10 minutes » à la reprise de l'heure d'hiver).
public enum DistanceRelative {
    static let minutesParJour: Double = 1_440
    static let minutesParMois: Double = 43_200
    static let minutesPresqueDeuxJours: Double = 2_520

    /// « il y a environ 2 heures », « dans 3 jours »…
    public static func depuis(_ date: Date, maintenant: Date, fuseau: TimeZone = .current) -> String {
        let instantDate = DateHeureParis.millisecondes(date)
        let instantMaintenant = DateHeureParis.millisecondes(maintenant)
        let futur = instantDate > instantMaintenant
        let (gauche, droite) = futur ? (instantMaintenant, instantDate) : (instantDate, instantMaintenant)
        let suffixe = { (texte: String) in futur ? "dans " + texte : "il y a " + texte }

        let secondes = Double((droite - gauche) / 1000)       // `differenceInSeconds`, tronqué (écart positif)
        let decalage = Double(decalageGMT(gauche, fuseau) - decalageGMT(droite, fuseau))
        let minutes = arrondiJS((secondes - decalage) / 60)

        if minutes < 2 {
            return suffixe(minutes == 0 ? "moins d’une minute" : pluriel(Int(minutes), un: "1 minute", autre: "minutes"))
        } else if minutes < 45 {
            return suffixe("\(Int(minutes)) minutes")
        } else if minutes < 90 {
            return suffixe("environ 1 heure")
        } else if minutes < minutesParJour {
            let heures = Int(arrondiJS(minutes / 60))
            return suffixe(pluriel(heures, un: "environ 1 heure", autre: "heures", prefixe: "environ "))
        } else if minutes < minutesPresqueDeuxJours {
            return suffixe("1 jour")
        } else if minutes < minutesParMois {
            let jours = Int(arrondiJS(minutes / minutesParJour))
            return suffixe(pluriel(jours, un: "1 jour", autre: "jours"))
        } else if minutes < minutesParMois * 2 {
            let mois = Int(arrondiJS(minutes / minutesParMois))
            return suffixe(pluriel(mois, un: "environ 1 mois", autre: "mois", prefixe: "environ "))
        }

        let mois = differenceEnMois(plusTard: droite, plusTot: gauche, fuseau: fuseau)
        if mois < 12 {
            let moisProches = Int(arrondiJS(minutes / minutesParMois))
            return suffixe(pluriel(moisProches, un: "1 mois", autre: "mois"))
        }
        let moisDansLAnnee = mois % 12
        let annees = mois / 12
        if moisDansLAnnee < 3 {
            return suffixe(pluriel(annees, un: "environ 1 an", autre: "ans", prefixe: "environ "))
        } else if moisDansLAnnee < 9 {
            return suffixe(pluriel(annees, un: "plus d’un an", autre: "ans", prefixe: "plus de "))
        }
        return suffixe(pluriel(annees + 1, un: "presqu’un an", autre: "ans", prefixe: "presque "))
    }

    // MARK: - Interne

    /// Forme `one` pour 1, sinon `{{count}}` remplacé (`formatDistance` de la locale).
    private static func pluriel(_ nombre: Int, un: String, autre: String, prefixe: String = "") -> String {
        nombre == 1 ? un : "\(prefixe)\(nombre) \(autre)"
    }

    /// `Math.round` : demi vers +∞.
    static func arrondiJS(_ valeur: Double) -> Double {
        (valeur + 0.5).rounded(.down)
    }

    /// Décalage du fuseau en secondes (positif à l'est) ; `getTimezoneOffsetInMilliseconds` en est l'opposé.
    private static func decalageGMT(_ ms: Int64, _ fuseau: TimeZone) -> Int {
        fuseau.secondsFromGMT(for: Date(timeIntervalSince1970: Double(ms) / 1000))
    }

    /// `differenceInMonths(plusTard, plusTot)` avec `plusTard > plusTot` (signe 1) : écart en mois calendaires
    /// locaux, diminué de 1 si le dernier mois n'est pas plein ; fin février et dernier jour du mois traités
    /// comme date-fns (`setDate(30)` puis `setMonth`, débordements normalisés comme un `Date` JavaScript).
    static func differenceEnMois(plusTard: Int64, plusTot: Int64, fuseau: TimeZone) -> Int {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = fuseau
        let dateTard = Date(timeIntervalSince1970: Double(plusTard) / 1000)
        let dateTot = Date(timeIntervalSince1970: Double(plusTot) / 1000)
        let unites: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second, .nanosecond]
        let tard = calendrier.dateComponents(unites, from: dateTard)
        let tot = calendrier.dateComponents(unites, from: dateTot)
        guard let anneeTard = tard.year, let moisTard = tard.month, let anneeTot = tot.year, let moisTot = tot.month else {
            return 0
        }
        let difference = abs((anneeTard - anneeTot) * 12 + (moisTard - moisTot))
        guard difference >= 1 else { return 0 }

        var travail = tard
        if moisTard == 2, let jour = tard.day, jour > 27 {
            // `setDate(30)` : débordement sur mars, normalisé avant `setMonth`.
            travail.day = 30
            travail = calendrier.dateComponents(unites, from: calendrier.date(from: travail) ?? dateTard)
        }
        travail.month = (travail.month ?? moisTard) - difference
        let recule = calendrier.date(from: travail) ?? dateTard
        var dernierMoisIncomplet = DateHeureParis.millisecondes(recule) < plusTot
        if estDernierJourDuMois(dateTard, calendrier), difference == 1, plusTard > plusTot {
            dernierMoisIncomplet = false
        }
        return difference - (dernierMoisIncomplet ? 1 : 0)
    }

    private static func estDernierJourDuMois(_ date: Date, _ calendrier: Calendar) -> Bool {
        guard let jour = calendrier.dateComponents([.day], from: date).day,
              let jours = calendrier.range(of: .day, in: .month, for: date)?.count else { return false }
        return jour == jours
    }
}
