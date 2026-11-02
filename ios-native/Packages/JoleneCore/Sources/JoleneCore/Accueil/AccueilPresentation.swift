import Foundation

/// Textes de l'onglet Accueil, portés de `DashboardSoignant.tsx` (l.459-720) et de
/// `CarteProposition.tsx`. Vouvoiement sobre (décision 9) pour les textes d'interface ; la note
/// « net estimé » est reprise mot pour mot du web (`NoteNetEstime.tsx`, HARD STOP n°4). Horaires
/// en heure de Paris (`DateHeureParis.format`, jetons date-fns) ; montants = valeurs serveur
/// formatées comme `Intl.NumberFormat('fr-FR', { currency: 'EUR' })` (`MissionPresentation.euros`).
/// Exclus (HARD STOP n°4, blueprint T3) : `BandeauAlerte48h` et l'encart « cumul d'activité ».
public enum AccueilPresentation {
    /// Le web affiche les deux premières missions ouvertes (`missionsOuvertes.slice(0, 2)`).
    public static let nombrePourToiAffiches = 2
    public static let planningAConfirmer = "Planning détaillé à confirmer"

    /// Note de bas de page de l'astérisque « net salarié estimé* » (`src/components/NoteNetEstime.tsx`), verbatim.
    public static let noteNetEstime = "* Pour une mission salariée, le net est estimé après cotisations sociales et avant prélèvement à la source. "
        + "Tant que le régime n'est pas choisi, le montant affiché reste une rémunération brute indicative. "
        + "Cette estimation peut différer du net du bulletin officiel établi par l’employeur ou son service paie."

    // MARK: - En-tête

    /// `salutationHeure` : « Bonjour » de 5 h à 17 h 59 (heure locale de l'appareil), sinon « Bonsoir » ;
    /// suivi du prénom quand le tableau de bord le renvoie.
    public static func salutation(prenom: String?, maintenant: Date, fuseau: TimeZone = .current) -> String {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = fuseau
        let heure = calendrier.component(.hour, from: maintenant)
        let formule = heure >= 5 && heure < 18 ? "Bonjour" : "Bonsoir"
        let prenom = prenom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return prenom.isEmpty ? formule : "\(formule), \(prenom)"
    }

    /// Sous-titre de l'en-tête (web l.469-479), au vouvoiement.
    public static func accroche(profil: DashboardProfil?, nombreOuvertes: Int) -> String {
        let pluriel = nombreOuvertes > 1 ? "s" : ""
        if profil?.tousDocumentsValides != true {
            return nombreOuvertes > 0
                ? "\(nombreOuvertes) mission\(pluriel) près de chez vous — vous pouvez déjà postuler."
                : "Vous pouvez déjà postuler — vos documents validés débloquent l'acceptation."
        }
        return nombreOuvertes > 0 ? "\(nombreOuvertes) mission\(pluriel) pour vous 🔥" : "On trouve votre prochaine mission ? 🔥"
    }

    // MARK: - Missions

    /// Libellé de `BadgeStatut` (`BADGES_STATUT` de `constantes.ts`) pour les statuts de l'Accueil.
    public static func statut(_ code: String) -> String {
        switch code {
        case "ASSIGNEE": return "Assignée"
        case "EN_COURS": return "Active"
        default: return code
        }
    }

    /// Pavé de date du prochain créneau (`EEE`, `d`, `MMM`) ; `nil` si le planning n'est pas affichable.
    public struct Jour: Equatable, Sendable {
        public var semaine: String
        public var jour: String
        public var mois: String
    }

    public static func jour(_ planning: PlanningAccueil) -> Jour? {
        guard let intervalle = bornes(planning) else { return nil }
        return Jour(semaine: DateHeureParis.format(intervalle.debut, "EEE"), jour: DateHeureParis.format(intervalle.debut, "d"),
                    mois: DateHeureParis.format(intervalle.debut, "MMM"))
    }

    /// « mardi 3 nov. · 08h00 → 16h00 · créneau 1/2 » (mes prochaines missions, web l.536-542).
    public static func planningProchaine(_ planning: PlanningAccueil) -> String {
        guard let intervalle = bornes(planning), case let .planifie(_, rang, nombre) = planning else { return planningAConfirmer }
        let suffixe = nombre > 1 && rang != nil ? " · créneau \(rang ?? 0)/\(nombre)" : ""
        return plage(intervalle) + suffixe
    }

    /// « mardi 3 nov. · 08h00 → 16h00 · 2 créneaux au total » (missions pour vous, web l.623-626).
    public static func planningPourToi(_ planning: PlanningAccueil) -> String {
        guard let intervalle = bornes(planning), case let .planifie(_, _, nombre) = planning else { return planningAConfirmer }
        return plage(intervalle) + (nombre > 1 ? " · \(nombre) créneaux au total" : "")
    }

    /// Taux horaire serveur, formaté comme Explorer et le détail ; `nil` sans taux.
    public static func remuneration(_ taux: Double?) -> String? {
        taux.map { "\(MissionPresentation.euros($0))/h" }
    }

    // MARK: - Propositions

    /// Temps restant avant expiration, comme `CarteProposition` : « 1h 30min » ; `nil` une fois
    /// l'échéance atteinte (la carte disparaît).
    public static func tempsRestant(expireLe: Date, maintenant: Date) -> String? {
        let secondes = Int(expireLe.timeIntervalSince(maintenant).rounded(.towardZero))
        guard secondes > 0 else { return nil }
        let minutes = (secondes % 3600) / 60
        return "\(secondes / 3600)h \(minutes < 10 ? "0" : "")\(minutes)min"
    }

    // MARK: - Gains et compteurs

    /// « 💰 Ce mois : 162,40 € net salarié estimé* sur 1 mission » (web l.664-678) ; `nil` sans
    /// mission relue porteuse d'un montant (carte masquée).
    public static func texteGains(_ gains: GainsDuMois) -> String? {
        guard gains.nombreMissions > 0 else { return nil }
        let parties = [
            gains.honoraires > 0 ? "\(MissionPresentation.euros(gains.honoraires)) d’honoraires" : nil,
            gains.netSalarie > 0 ? "\(MissionPresentation.euros(gains.netSalarie)) net salarié estimé*" : nil,
            gains.brutIndicatif > 0 ? "\(MissionPresentation.euros(gains.brutIndicatif)) brut indicatif" : nil,
        ].compactMap { $0 }
        let n = gains.nombreMissions
        return "💰 Ce mois : \(parties.joined(separator: " + ")) sur \(n) mission\(n > 1 ? "s" : "")"
    }

    /// La note « net estimé » accompagne un net salarié estimé ou un brut indicatif (web l.681).
    public static func afficheNoteNetEstime(_ gains: GainsDuMois) -> Bool {
        gains.netSalarie > 0 || gains.brutIndicatif > 0
    }

    /// Compteur de notifications non lues (centre de notifications : renvoi web au lot 1).
    public static func texteNotifications(_ nombre: Int) -> String? {
        guard nombre > 0 else { return nil }
        return nombre > 1 ? "\(nombre) notifications non lues" : "1 notification non lue"
    }

    /// `BandeauOubliDepart` sans mission nommée (le compteur seul est renvoyé), au vouvoiement ;
    /// le pointage est au lot 2 (renvoi web vers `/soignant/presences`).
    public static func texteOubliPointage(_ nombre: Int) -> String? {
        guard nombre > 0 else { return nil }
        return nombre > 1
            ? "\(nombre) missions semblent attendre un pointage de départ. Vérifiez vos présences."
            : "1 mission semble attendre un pointage de départ. Vérifiez vos présences."
    }

    // MARK: - Interne

    /// Début et fin du prochain créneau, lisibles et fin renseignée ; sinon `nil` (« à confirmer »).
    private struct Bornes { var debut: Date; var fin: Date }

    private static func bornes(_ planning: PlanningAccueil) -> Bornes? {
        guard case let .planifie(prochain?, _, _) = planning, let fin = prochain.finRenseignee,
              let debutDate = PlanningHorlogeParis.instant(prochain.debut), let finDate = PlanningHorlogeParis.instant(fin) else { return nil }
        return Bornes(debut: debutDate, fin: finDate)
    }

    private static func plage(_ intervalle: Bornes) -> String {
        "\(DateHeureParis.format(intervalle.debut, "EEEE d MMM · HH'h'mm")) → \(DateHeureParis.format(intervalle.fin, "HH'h'mm"))"
    }
}
