import Foundation

/// Points d'entrée vers les présences (lot 2, T5a, décision 24 : pas de sixième onglet) : boutons du détail d'une
/// mission (`DetailMissionSoignant.tsx` l.638-645, l.1477-1494) et widget « Aller pointer » de l'Accueil
/// (`DashboardSoignant.tsx` l.282-317, `WidgetAllerPointer.tsx`). Règles pures ; textes : `LibellesWeb.DetailMission`,
/// `LibellesWeb.AllerPointer` (verbatim), assemblés comme le rendu React.
public enum PointsEntreePresences {
    /// Bouton du détail d'une mission.
    public enum EntreeMission: Equatable, Sendable {
        /// « 🕐 Présences et pointage » (ASSIGNEE, EN_COURS) → page Présences sur l'onglet calculé.
        case presences(onglet: PointageRules.OngletPresences)
        /// « 🕐 Voir mes heures pointées et mes pauses » (TERMINEE) → détail des présences.
        case heures
    }

    /// `ongletPresences` (l.638-645) : Aujourd'hui si un créneau planifié chevauche le jour de Paris, sinon Actives pour
    /// une mission EN_COURS, sinon À venir.
    public static func entreeMission(statut: String, creneaux: [MissionSlot], maintenant: Date) -> EntreeMission? {
        switch statut {
        case "ASSIGNEE", "EN_COURS":
            let debut = DateHeureParis.debutJour(maintenant)
            let fin = DateHeureParis.ajouterJoursCivils(debut, 1)
            let aujourdhui = creneaux.contains { DisponibilitePointage.creneauChevauchePeriode($0, debutPeriode: debut, finPeriode: fin) }
            return .presences(onglet: aujourdhui ? .aujourdhui : (statut == "EN_COURS" ? .encours : .avenir))
        case "TERMINEE":
            return .heures
        default:
            return nil
        }
    }

    /// Widget « Aller pointer » affiché.
    public struct AllerPointer: Equatable, Sendable {
        public var missionId: String
        public var titre: String
        /// « intitulé — établissement » (l.38).
        public var mission: String
        public var horaire: String?
        /// « Aller pointer → » ou « Voir horaires et présences → » (l.50).
        public var bouton: String
        /// `?tab=` de la destination (l.47).
        public var onglet: PointageRules.OngletPresences
    }

    /// `missionProchaine` (l.282-317) puis le rendu de `WidgetAllerPointer` (l.11-52), sur les prochaines missions de
    /// l'Accueil (`mes_missions`, ordre serveur) dont le planning est vérifié. Le prochain créneau est celui de
    /// l'assemblage de l'Accueil (`PlanningAccueil.planifie`) ; « créneau actuel » : `maintenant` dans
    /// [début − 15 min, fin] de ce créneau (les créneaux PREVISIONNEL ne se chevauchent pas : c'est le seul candidat).
    public static func allerPointer(_ missions: [AccueilMission], maintenant: Date) -> AllerPointer? {
        let candidates = missions.compactMap { mission -> Candidate? in
            guard case let .planifie(prochain, _, _) = mission.planning else { return nil }
            return Candidate(mission: mission, prochain: prochain, maintenant: maintenant)
        }
        let retenue = candidates.first(where: \.creneauActuel)
            ?? candidates.first { candidate in
                guard let debut = candidate.debutProchain else { return false }
                let minutes = (DisponibilitePointage.temps(debut) - DisponibilitePointage.temps(maintenant)) / 60_000
                return minutes > -30 && minutes <= 60
            }
            ?? triStableCroissant(candidates.filter { $0.estEnCours && $0.debutProchain != nil }) {
                DisponibilitePointage.temps($0.debutProchain ?? Date.distantFuture)
            }.first
        guard let retenue else { return nil }
        return retenue.widget(maintenant: maintenant)
    }

    private struct Candidate {
        let mission: AccueilMission
        let prochain: MissionSlot?
        let debutProchain: Date?
        let finProchain: Date?
        let creneauActuel: Bool
        let estEnCours: Bool

        init(mission: AccueilMission, prochain: MissionSlot?, maintenant: Date) {
            self.mission = mission
            self.prochain = prochain
            debutProchain = prochain.flatMap { try? DateHeureParis.instantJolene($0.debut) }
            finProchain = prochain?.finRenseignee.flatMap { try? DateHeureParis.instantJolene($0) }
            if let debutProchain, let finProchain {
                let ouverture = debutProchain.addingTimeInterval(-Double(DisponibilitePointage.fenetreOuvertureMinutes) * 60)
                creneauActuel = maintenant >= ouverture && maintenant <= finProchain
            } else {
                creneauActuel = false
            }
            estEnCours = mission.ligne.statut == "EN_COURS"
        }

        func widget(maintenant: Date) -> AllerPointer? {
            typealias Web = LibellesWeb.AllerPointer
            let reference = debutProchain ?? mission.ligne.debutLe.flatMap { try? DateHeureParis.instantJolene($0) }
            let minutes = reference.map { PresentationDetailPresences.minutes($0, maintenant) }
            if !creneauActuel, !estEnCours, minutes.map({ $0 > 60 || $0 < -30 }) ?? true { return nil }
            let titre: String
            if creneauActuel {
                titre = Web.creneauActuel
            } else if estEnCours {
                titre = debutProchain != nil ? Web.missionActiveProchain : Web.missionActivePlanning
            } else {
                let delai = minutes ?? 0
                titre = Web.missionDans + " " + (delai > 0 ? String(delai) + " " + Web.minutes : Web.maintenant)
            }
            return AllerPointer(missionId: mission.id, titre: titre,
                                mission: mission.ligne.intitule + " " + Web.tiret + " " + mission.etablissementNom,
                                horaire: horaire(),
                                bouton: (creneauActuel ? Web.allerPointer : Web.voirHoraires) + " " + Web.flecheBouton,
                                onglet: creneauActuel || !estEnCours ? .aujourdhui : .encours)
        }

        /// Ligne horaire (l.39-45).
        private func horaire() -> String? {
            typealias Web = LibellesWeb.AllerPointer
            if let debutProchain, let finProchain {
                return DateHeureParis.format(debutProchain, "EEEE d MMMM") + " " + Web.point + " " + DateHeureParis.format(debutProchain, "HH:mm")
                    + " " + Web.flecheProchain + " " + DateHeureParis.format(finProchain, "HH:mm")
            }
            guard let debut = mission.ligne.debutLe.flatMap({ try? DateHeureParis.instantJolene($0) }),
                  let fin = mission.ligne.finLe.flatMap({ try? DateHeureParis.instantJolene($0) }) else { return nil }
            if DateHeureParis.memeJour(debut, fin) {
                return DateHeureParis.format(debut, "HH:mm") + " " + Web.flecheMemeJour + " " + DateHeureParis.format(fin, "HH:mm")
            }
            return DateHeureParis.format(debut, "d MMM") + " " + Web.flecheJours + " " + DateHeureParis.format(fin, "d MMM yyyy")
        }
    }
}
