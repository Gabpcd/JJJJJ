import Foundation

/// Jour de la grille des disponibilités : clé `yyyy-MM-dd` Europe/Paris, jour passé (boutons désactivés), jour
/// courant (« aujourd'hui ») et libellé `EEEE d MMM` de date-fns `fr` (« lundi 2 nov. », mis en capitales par l'écran
/// comme la classe CSS `capitalize`).
public struct JourGrilleDisponibilites: Equatable, Sendable {
    public var jour: JourParis
    public var passe: Bool
    public var estAujourdhui: Bool
    public var libelle: String

    public init(jour: JourParis, passe: Bool, estAujourdhui: Bool, libelle: String) {
        self.jour = jour; self.passe = passe; self.estAujourdhui = estAujourdhui; self.libelle = libelle
    }
}

/// Semaine de sept jours à partir du lundi, avec son en-tête « Semaine du 2 novembre ».
public struct SemaineDisponibilites: Equatable, Sendable {
    public var entete: String
    public var jours: [JourGrilleDisponibilites]

    public init(entete: String, jours: [JourGrilleDisponibilites]) { self.entete = entete; self.jours = jours }
}

public struct GrilleDisponibilites: Equatable, Sendable {
    /// Jour Paris de l'horloge : borne de lecture `.gte("jour", …)` et seuil des jours passés.
    public var aujourdhui: JourParis
    public var semaines: [SemaineDisponibilites]

    public init(aujourdhui: JourParis, semaines: [SemaineDisponibilites]) { self.aujourdhui = aujourdhui; self.semaines = semaines }
}

/// Grille de `/soignant/disponibilites` (`src/pages/MesDisponibilites.tsx`, calcul dans la page) : quatre semaines
/// complètes à partir du lundi de la semaine courante, en jours civils Europe/Paris (date-fns `startOfWeek`
/// `weekStartsOn: 1` puis `addDays`, dans le fuseau de l'appareil web). Vecteurs `semaines-disponibilites.json`
/// (L4-T2, `LOT4_PLAN.md` §3 T2), dont les semaines des changements d'heure du 25 octobre 2026 et du 28 mars 2027
/// vérifiées à la main par l'exporteur. État dérivé (`CLAUDE.md`) : la grille vient de l'horloge (`ClockPort`), jamais
/// d'un défaut figé.
public enum SemainesDisponibilites {
    public static let nombreSemaines = 4
    public static let joursParSemaine = 7

    public static func grille(maintenant: Date) -> GrilleDisponibilites {
        let aujourdhui = JourParis(iso: DateHeureParis.cleJour(maintenant))
        let lundi = DateHeureParis.debutSemaine(maintenant)
        let semaines = (0..<nombreSemaines).map { semaine -> SemaineDisponibilites in
            let jours = (0..<joursParSemaine).map { rang -> JourGrilleDisponibilites in
                let date = DateHeureParis.ajouterJoursCivils(lundi, semaine * joursParSemaine + rang)
                let jour = JourParis(iso: DateHeureParis.cleJour(date))
                return JourGrilleDisponibilites(jour: jour, passe: jour < aujourdhui, estAujourdhui: jour == aujourdhui,
                                                libelle: DateHeureParis.format(date, "EEEE d MMM"))
            }
            let premier = DateHeureParis.ajouterJoursCivils(lundi, semaine * joursParSemaine)
            return SemaineDisponibilites(entete: "Semaine du " + DateHeureParis.format(premier, "d MMMM"), jours: jours)
        }
        return GrilleDisponibilites(aujourdhui: aujourdhui, semaines: semaines)
    }
}
