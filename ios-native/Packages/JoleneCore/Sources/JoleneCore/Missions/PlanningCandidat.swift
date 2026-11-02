import Foundation

/// Résultat de `construirePlanningCandidat` (src/components/planning/planning-candidat.ts).
public struct PlanningCandidat: Equatable, Sendable {
    public var creneaux: [MissionSlot]
    public var exact: Bool
    public var totalHeures: Double
    public var periodeEtendue: Bool
    public var messageBlocage: String?

    public init(creneaux: [MissionSlot], exact: Bool, totalHeures: Double, periodeEtendue: Bool, messageBlocage: String?) {
        self.creneaux = creneaux; self.exact = exact; self.totalHeures = totalHeures
        self.periodeEtendue = periodeEtendue; self.messageBlocage = messageBlocage
    }
}

/// Entrée minimale du planning candidat (`MissionPlanningCandidat` côté web).
public struct PlanningCandidatInput: Equatable, Sendable {
    public var id: String?
    public var debutLe: String?
    public var finLe: String?
    public var nbCreneaux: Int?
    public var creneauxPlanifies: [MissionSlot]
    public var erreurPlanning: Bool

    public init(id: String?, debutLe: String?, finLe: String?, nbCreneaux: Int?, creneauxPlanifies: [MissionSlot] = [], erreurPlanning: Bool = false) {
        self.id = id; self.debutLe = debutLe; self.finLe = finLe; self.nbCreneaux = nbCreneaux
        self.creneauxPlanifies = creneauxPlanifies; self.erreurPlanning = erreurPlanning
    }

    /// Ligne `missions` brute, sans créneaux chargés.
    public init(record: MissionRecord, creneaux: [MissionSlot] = [], erreurPlanning: Bool = false) {
        self.init(id: record.id, debutLe: record.debutLe, finLe: record.finLe, nbCreneaux: record.nbCreneaux,
                  creneauxPlanifies: creneaux, erreurPlanning: erreurPlanning)
    }

    /// Mission enrichie : les créneaux et l'erreur de planning proviennent de l'enrichissement.
    public init(mission: Mission) {
        self.init(record: mission.record, creneaux: mission.creneauxPlanifies, erreurPlanning: mission.erreurPlanning)
    }
}

/// Port des règles pures de `planning-candidat.ts` utilisées par l'exploration des missions.
public enum PlanningCandidatRules {
    public static let messageErreurChargement = "Le planning détaillé ne peut pas être vérifié. La candidature est bloquée jusqu’à son chargement."
    public static let messagePlanningIncomplet = "Les dates et horaires détaillés ne sont pas tous confirmés. La candidature est bloquée jusqu’à confirmation du planning."

    /// `creneauxPrevisionnels` de disponibilite-pointage.ts : comme `planning-candidat.ts`
    /// qui importe la fonction, une seule implémentation dans l'app, celle couverte par les
    /// vecteurs golden (`DisponibilitePointage`, tri stable, date illisible = ordre conservé).
    public static func creneauxPrevisionnels(_ creneaux: [MissionSlot]) -> [MissionSlot] {
        DisponibilitePointage.creneauxPrevisionnels(creneaux)
    }

    /// `ajouterRepliMissionPonctuelle` de disponibilite-pointage.ts, même délégation.
    public static func ajouterRepliMissionPonctuelle(_ creneaux: [MissionSlot], id: String?, debutLe: String, finLe: String) -> [MissionSlot] {
        DisponibilitePointage.ajouterRepliMissionPonctuelle(
            creneaux, mission: PeriodeMissionPointage(id: id, debutLe: debutLe, finLe: finLe)
        )
    }

    /// Port de `construirePlanningCandidat`. Écart assumé : là où le web lève (`instantJolene`)
    /// sur un créneau PREVISIONNEL à date illisible, le port marque le planning non exact
    /// (fail-closed, message « ne peut pas être vérifié ») au lieu de le compter à 0 h.
    public static func construirePlanningCandidat(_ mission: PlanningCandidatInput, creneaux: [MissionSlot]? = nil, erreur: Bool? = nil) -> PlanningCandidat {
        let creneaux = creneaux ?? mission.creneauxPlanifies
        let erreur = erreur ?? mission.erreurPlanning
        let tousLesPrevisionnels = creneaux.filter { $0.typeCreneau == "PREVISIONNEL" }
        let creneauxTravail = tousLesPrevisionnels.filter { !$0.estPause }
        let attendus = mission.nbCreneaux ?? 0
        let avecRepliPonctuel: [MissionSlot]
        if attendus <= 1, let debutLe = mission.debutLe, !debutLe.isEmpty, let finLe = mission.finLe, !finLe.isEmpty {
            avecRepliPonctuel = ajouterRepliMissionPonctuelle(creneauxTravail, id: mission.id, debutLe: debutLe, finLe: finLe)
        } else {
            avecRepliPonctuel = creneauxTravail
        }
        let planifies = creneauxPrevisionnels(avecRepliPonctuel)
        let planningIncomplet = creneauxTravail.contains { $0.finRenseignee == nil }
            || (attendus > 0 && attendus != planifies.count)
        let illisible = planifies.contains { creneau in
            PlanningHorlogeParis.instant(creneau.debut) == nil
                || creneau.finRenseignee.flatMap(PlanningHorlogeParis.instant) == nil
        }
        let exact = !erreur && !planifies.isEmpty && !planningIncomplet && !illisible
        let totalHeures = planifies.reduce(0.0) { total, creneau in
            guard let fin = creneau.finRenseignee,
                  let debutDate = PlanningHorlogeParis.instant(creneau.debut),
                  let finDate = PlanningHorlogeParis.instant(fin) else { return total }
            return total + max(0, finDate.timeIntervalSince(debutDate) / 3600)
        }
        var periodeEtendue = planifies.count > 1
        if !periodeEtendue, let premier = planifies.first, let fin = premier.finRenseignee,
           let debutDate = PlanningHorlogeParis.instant(premier.debut), let finDate = PlanningHorlogeParis.instant(fin) {
            periodeEtendue = PlanningHorlogeParis.debutJour(debutDate) != PlanningHorlogeParis.debutJour(finDate)
        }
        let message: String? = exact ? nil : ((erreur || illisible) ? messageErreurChargement : messagePlanningIncomplet)
        return PlanningCandidat(creneaux: planifies, exact: exact, totalHeures: totalHeures,
                                periodeEtendue: periodeEtendue, messageBlocage: message)
    }

    /// Port de `creneauContientNuit` : nuit = 20:00 → 07:00 Paris, jour civil par jour civil.
    public static func creneauContientNuit(_ creneau: MissionSlot) -> Bool {
        guard let fin = creneau.finRenseignee,
              let debut = PlanningHorlogeParis.instant(creneau.debut),
              let finDate = PlanningHorlogeParis.instant(fin) else { return false }
        var jour = PlanningHorlogeParis.debutJour(debut)
        while jour < finDate {
            let lendemain = PlanningHorlogeParis.ajouterJoursCivils(jour, 1)
            let finNuitMatin = PlanningHorlogeParis.instantDuJour(jour, heure: 7)
            let debutNuitSoir = PlanningHorlogeParis.instantDuJour(jour, heure: 20)
            if chevauchement(debut, finDate, jour, finNuitMatin) || chevauchement(debut, finDate, debutNuitSoir, lendemain) {
                return true
            }
            jour = lendemain
        }
        return false
    }

    /// Port de `creneauChevaucheWeekend` : samedi ou dimanche civil français.
    public static func creneauChevaucheWeekend(_ creneau: MissionSlot) -> Bool {
        guard let fin = creneau.finRenseignee,
              let debut = PlanningHorlogeParis.instant(creneau.debut),
              let finDate = PlanningHorlogeParis.instant(fin) else { return false }
        var jour = PlanningHorlogeParis.debutJour(debut)
        while jour < finDate {
            let jourSemaine = PlanningHorlogeParis.jourSemaine(jour)
            let lendemain = PlanningHorlogeParis.ajouterJoursCivils(jour, 1)
            if (jourSemaine == 0 || jourSemaine == 6) && chevauchement(debut, finDate, jour, lendemain) {
                return true
            }
            jour = lendemain
        }
        return false
    }

    /// Port de `planningCorrespondAuFiltre` : un planning non exact ne correspond à aucun
    /// filtre horaire autre que TOUS.
    public static func planningCorrespondAuFiltre(_ mission: PlanningCandidatInput, filtre: MissionFilters.Horaire) -> Bool {
        if filtre == .tous { return true }
        let planning = construirePlanningCandidat(mission)
        guard planning.exact else { return false }
        switch filtre {
        case .nuit: return planning.creneaux.contains(where: creneauContientNuit)
        case .jour: return planning.creneaux.contains { !creneauContientNuit($0) }
        case .weekend: return planning.creneaux.contains(where: creneauChevaucheWeekend)
        case .tous: return true
        }
    }

    private static func chevauchement(_ debutA: Date, _ finA: Date, _ debutB: Date, _ finB: Date) -> Bool {
        debutA < finB && finA > debutB
    }
}
