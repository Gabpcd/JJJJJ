import Foundation

/// Façade interne du planning candidat et de la présentation des missions sur
/// `DateHeureParis` (port complet de `src/lib/date-heure-paris.ts`, dossier Rules/).
///
/// Il n'existe qu'une seule implémentation du fuseau Europe/Paris dans JoleneCore :
/// chaque fonction ci-dessous délègue à `DateHeureParis` ou à `CalendrierCivil`.
/// L'enum reste interne et préfixé pour que les appelants historiques
/// (`PlanningCandidatRules`, `MissionPresentation`) gardent une API non levante :
/// une chaîne illisible, une heure inexistante ou ambiguë donnent `nil`
/// (choix fail-closed : planning non exact, 0 h, tri en fin).
enum PlanningHorlogeParis {
    typealias Parties = PartiesDateHeureParis

    /// Port de `instantJolene` sans levée : `nil` pour toute chaîne refusée.
    static func instant(_ valeur: String) -> Date? {
        try? DateHeureParis.instantJolene(valeur)
    }

    /// Port de `partiesDateHeureParis`.
    static func parties(_ date: Date) -> Parties {
        DateHeureParis.parties(date)
    }

    /// Port de `instantDateHeureParis` sans levée (heure inexistante ou ambiguë => `nil`).
    static func instant(parties: Parties) -> Date? {
        try? DateHeureParis.instant(parties)
    }

    /// Port de `debutJourParis`.
    static func debutJour(_ date: Date) -> Date {
        DateHeureParis.debutJour(date)
    }

    /// Port de `ajouterJoursCivilsParis`.
    static func ajouterJoursCivils(_ date: Date, _ jours: Int) -> Date {
        DateHeureParis.ajouterJoursCivils(date, jours)
    }

    /// Port de `instantParisDuJour` (planning-candidat.ts) : `heure`:00:00 du jour civil de `jour`.
    /// Les heures employées (07:00, 20:00) n'existent jamais dans une transition DST à Paris ;
    /// par prudence, une heure refusée renvoie `jour` tel quel.
    static func instantDuJour(_ jour: Date, heure: Int) -> Date {
        var parties = parties(jour)
        parties.heure = heure; parties.minute = 0; parties.seconde = 0
        return instant(parties: parties) ?? jour
    }

    /// Jour de semaine civil français : 0 = dimanche … 6 = samedi, comme `getUTCDay()`.
    static func jourSemaine(_ date: Date) -> Int {
        let p = parties(date)
        return CalendrierCivil.jourSemaine(annee: p.annee, mois: p.mois, jour: p.jour)
    }

    /// Équivalent de `formatParis(value, 'dd/MM/yyyy')`.
    static func dateCourte(_ date: Date) -> String {
        DateHeureParis.format(date, "dd/MM/yyyy")
    }

    /// Équivalent de `formatParis(value, 'HH:mm')`.
    static func heureMinute(_ date: Date) -> String {
        DateHeureParis.format(date, "HH:mm")
    }
}

extension MissionSlot {
    /// `fin` telle que le web la considère « renseignée » (`Boolean(creneau.fin)`) : ni nulle ni vide.
    var finRenseignee: String? {
        guard let fin, !fin.isEmpty else { return nil }
        return fin
    }
}
