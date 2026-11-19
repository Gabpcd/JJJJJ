import Foundation

/// Textes et formats de l'Accueil établissement (lot 5, T4), repris du web quand il en existe un (libellés non
/// juridiques) : `DashboardEtablissement.tsx` et `src/components/dashboard/SectionPlanning.tsx`. La vue n'ajoute
/// aucun texte ni aucun calcul.
public enum EtabAccueilPresentation {
    public static let titreActions = "À faire maintenant"                   // DashboardEtablissement.tsx l.751
    public static let aucuneAction = "Rien à faire pour le moment."
    public static let noteRenvoiWeb = "Certaines actions s'ouvrent sur jolene.app, où une nouvelle connexion peut vous être demandée."
    public static let publier = "Publier une mission"                       // DashboardEtablissement.tsx l.780
    public static let lecturePartielle = "Certaines données n'ont pas pu être chargées." // DashboardEtablissement.tsx l.713
    public static let titrePlanning = "Planning missions à venir"           // SectionPlanning.tsx l.224
    public static let planningErreur = "Le planning n'a pas pu être chargé. Réessayez dans un instant." // DashboardEtablissement.tsx l.375
    public static let planningVide = "Aucun créneau planifié dans les 31 prochains jours." // SectionPlanning.tsx l.288
    public static let sansPlanningTitre = "Planning détaillé à confirmer"   // SectionPlanning.tsx l.262
    public static let sansPlanningDetail = "Ces missions restent visibles mais aucun créneau prévisionnel complet n’est enregistré." // l.265
    public static let reessayer = "Réessayer"
    /// Occurrences affichées par l'Accueil ; le compteur de l'en-tête garde le total.
    public static let occurrencesAffichees = 10

    /// `({n} créneau{x} · {m} à confirmer)` (`SectionPlanning.tsx` l.226-227).
    public static func compteurPlanning(_ planning: EtabPlanningAVenir) -> String {
        let n = planning.occurrences.count
        let aConfirmer = planning.missionsSansPlanning.count
        return "(\(n) créneau\(n > 1 ? "x" : "")\(aConfirmer > 0 ? " · \(aConfirmer) à confirmer" : ""))"
    }

    /// Libellé de statut du planning (`STATUT_STYLE`, `SectionPlanning.tsx` l.119-123 ; statut inconnu → « Ouverte »,
    /// comme `styleFor`).
    public static func statut(_ code: String) -> String {
        switch code {
        case "ASSIGNEE": return "Assignée"
        case "EN_COURS": return "Active"
        default: return "Ouverte"
        }
    }

    /// `EEE d MMM · HH:mm → <fin> · <durée>h` (`VueListe`, `SectionPlanning.tsx` l.543-544, `formatFinAvecDate`
    /// l.129-133). Chaîne vide si le créneau est illisible.
    public static func horaire(_ occurrence: EtabOccurrencePlanning) -> String {
        guard let debut = try? DateHeureParis.instantJolene(occurrence.debut),
              let fin = try? DateHeureParis.instantJolene(occurrence.fin) else { return "" }
        let finTexte: String
        if DateHeureParis.memeJour(debut, fin) {
            finTexte = DateHeureParis.format(fin, "HH:mm")
        } else {
            let lendemain = DateHeureParis.memeJour(DateHeureParis.ajouterJoursCivils(debut, 1), fin)
            finTexte = DateHeureParis.format(fin, "EEE d MMM · HH:mm") + (lendemain ? " (lendemain)" : "")
        }
        let heures = max(0, fin.timeIntervalSince(debut) / 3600)
        return "\(DateHeureParis.format(debut, "EEE d MMM")) · \(DateHeureParis.format(debut, "HH:mm")) → \(finTexte) · \(duree(heures))h"
    }

    /// `Période prévue : d MMM yyyy → d MMM yyyy` (`SectionPlanning.tsx` l.274).
    public static func periodePrevue(_ mission: EtabMissionPlanifiee) -> String {
        guard let debut = try? DateHeureParis.instantJolene(mission.debutLe),
              let fin = try? DateHeureParis.instantJolene(mission.finLe) else { return "" }
        return "Période prévue : \(DateHeureParis.format(debut, "d MMM yyyy")) → \(DateHeureParis.format(fin, "d MMM yyyy"))"
    }

    /// `toLocaleString('fr-FR', { maximumFractionDigits: 2 })` d'une durée positive.
    static func duree(_ heures: Double) -> String {
        let centiemes = (heures * 100).rounded()
        let entier = Int(centiemes / 100)
        let reste = Int(centiemes.truncatingRemainder(dividingBy: 100))
        guard reste != 0 else { return "\(entier)" }
        let decimales = reste % 10 == 0 ? "\(reste / 10)" : String(format: "%02d", reste)
        return "\(entier),\(decimales)"
    }
}
