import Foundation

/// Port de `mobile-native/src/data/presentation.ts` et de `getLabelProfession`
/// (constantes.ts). Les chaînes reproduisent `Intl` fr-FR de Node : espace fine
/// insécable (U+202F) pour les milliers, espace insécable (U+00A0) avant le symbole.
public enum MissionPresentation {
    public static let separateurMilliers = "\u{202F}"
    public static let espaceSymbole = "\u{00A0}"

    /// Libellés de `PROFESSIONS` (constantes.ts), dans le même ordre.
    public static let professions: [(valeur: String, label: String)] = [
        ("IDE", "Infirmier(ère) Diplômé(e) d'État (IDE)"),
        ("AS", "Aide-Soignant(e) (AS)"),
        ("AES", "Accompagnant Éducatif et Social (AES)"),
        ("AUXILIAIRE_PUERICULTURE", "Auxiliaire de puériculture"),
        ("IBODE", "Infirmier(ère) de Bloc Opératoire (IBODE)"),
        ("IADE", "Infirmier(ère) Anesthésiste (IADE)"),
        ("SAGE_FEMME", "Sage-Femme"),
        ("KINE", "Kinésithérapeute"),
        ("MEDECIN", "Médecin"),
        ("DENTISTE", "Chirurgien-Dentiste"),
        ("PHARMACIEN", "Pharmacien(ne)"),
        ("MANIPULATEUR_RADIO", "Manipulateur Radio"),
        ("PREPARATEUR_PHARMA", "Préparateur en Pharmacie"),
        ("DIETETICIEN", "Diététicien(ne)"),
        ("ERGOTHERAPEUTE", "Ergothérapeute"),
        ("PSYCHOMOTRICIEN", "Psychomotricien(ne)"),
        ("ORTHOPHONISTE", "Orthophoniste"),
    ]

    /// Port de `getLabelProfession` : le code est rendu tel quel s'il est inconnu.
    public static func professionLabel(_ code: String) -> String {
        professions.first { $0.valeur == code }?.label ?? code
    }

    /// Rendu d'un nombre comme `String(number)` en JavaScript (70 → « 70 », 70.5 → « 70.5 »).
    public static func nombreJavaScript(_ valeur: Double) -> String {
        if valeur.isFinite, valeur == valeur.rounded(), abs(valeur) < 1e15 { return String(Int(valeur)) }
        return String(valeur)
    }

    /// `Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' })`.
    public static func euros(_ valeur: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        formatter.groupingSeparator = separateurMilliers
        formatter.decimalSeparator = ","
        formatter.roundingMode = .halfUp
        let nombre = formatter.string(from: NSNumber(value: valeur)) ?? String(valeur)
        return "\(nombre)\(espaceSymbole)€"
    }

    /// Port de `getMissionRemuneration` : taux horaire serveur, ou rétrocession.
    public static func remuneration(_ mission: Mission) -> String {
        let record = mission.record
        if record.modeRemuneration == "RETROCESSION" {
            let pct = record.retrocessionPct.map(nombreJavaScript) ?? "—"
            return "Rétrocession \(pct) % des honoraires"
        }
        guard let taux = record.tauxHoraireBase else { return "Taux non renseigné" }
        return "\(euros(taux))/h"
    }

    /// Port de `formatMissionPeriod` : dates civiles Paris, horaires du créneau unique,
    /// sinon nombre de créneaux ou « planning à confirmer ».
    public static func periode(_ mission: Mission) -> String {
        let record = mission.record
        let debut = PlanningHorlogeParis.instant(record.debutLe).map(PlanningHorlogeParis.dateCourte) ?? record.debutLe
        let fin = PlanningHorlogeParis.instant(record.finLe).map(PlanningHorlogeParis.dateCourte) ?? record.finLe
        if debut == fin, mission.planningExact, mission.creneauxPlanifies.count == 1 {
            let slot = mission.creneauxPlanifies[0]
            let heureDebut = PlanningHorlogeParis.instant(slot.debut).map(PlanningHorlogeParis.heureMinute) ?? slot.debut
            let heureFin = slot.finRenseignee.flatMap(PlanningHorlogeParis.instant).map(PlanningHorlogeParis.heureMinute) ?? "—"
            return "\(debut) · \(heureDebut)–\(heureFin)"
        }
        let dates = debut == fin ? debut : "\(debut) → \(fin)"
        let nombre = mission.creneauxPlanifies.count
        let detail = mission.planningExact ? "\(nombre) créneau\(nombre > 1 ? "x" : "")" : "planning à confirmer"
        return "\(dates) · \(detail)"
    }

    /// Ligne d'un créneau sur l'écran de détail, en heure de Paris :
    /// « Jeudi 3 juillet · 08:00–18:00 », préfixée « Pause · » pour une pause.
    /// Un début illisible donne « Créneau à confirmer » (ou « Pause ») ; une fin absente ou
    /// illisible donne « — ». Aucune durée n'est calculée ici.
    public static func creneau(_ slot: MissionSlot) -> String {
        guard let debut = PlanningHorlogeParis.instant(slot.debut) else {
            return slot.estPause ? "Pause" : "Créneau à confirmer"
        }
        let fin = slot.finRenseignee.flatMap(PlanningHorlogeParis.instant).map(PlanningHorlogeParis.heureMinute) ?? "—"
        let jour = DateHeureParis.format(debut, "EEEE d MMMM")
        let jourCapitalise = jour.prefix(1).uppercased() + jour.dropFirst()
        let prefixe = slot.estPause ? "Pause · " : ""
        return "\(prefixe)\(jourCapitalise) · \(PlanningHorlogeParis.heureMinute(debut))–\(fin)"
    }
}
