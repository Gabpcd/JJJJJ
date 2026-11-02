import Foundation

/// Contrat tel que lu par le choix du contrat de pointage (port de `ContratPointage`).
public protocol ContratPointageRepresentable {
    var id: String { get }
    var statut: String { get }
    var creeLe: String? { get }
}

public struct ContratPointage: Codable, Equatable, Sendable, ContratPointageRepresentable {
    public var id: String
    public var statut: String
    public var creeLe: String?
    public var missionId: String?

    public init(id: String, statut: String, creeLe: String? = nil, missionId: String? = nil) {
        self.id = id; self.statut = statut; self.creeLe = creeLe; self.missionId = missionId
    }

    enum CodingKeys: String, CodingKey {
        case id, statut
        case creeLe = "cree_le"
        case missionId = "mission_id"
    }
}

public protocol AvecStatutMission {
    var statut: String { get }
}

extension MissionRecord: AvecStatutMission {}

/// Plage globale d'une mission, repli des missions ponctuelles sans créneau.
public struct PeriodeMissionPointage: Equatable, Sendable {
    public var id: String?
    public var debutLe: String
    public var finLe: String

    public init(id: String?, debutLe: String, finLe: String) {
        self.id = id; self.debutLe = debutLe; self.finLe = finLe
    }

    public init(_ record: MissionRecord) {
        self.init(id: record.id, debutLe: record.debutLe, finLe: record.finLe)
    }
}

/// Présence legacy : seul le départ enregistré intéresse la terminaison.
public struct PresencePointage: Codable, Equatable, Sendable {
    public var pointageDepartLe: String?

    public init(pointageDepartLe: String?) { self.pointageDepartLe = pointageDepartLe }

    enum CodingKeys: String, CodingKey {
        case pointageDepartLe = "pointage_depart_le"
    }
}

/// Résultat de `evaluerDisponibilitePointage` (port de `DisponibilitePointage`).
public struct EtatDisponibilitePointage: Equatable, Sendable {
    public enum Action: String, Sendable { case ouverture = "OUVERTURE", fermeture = "FERMETURE" }
    public enum Motif: String, Sendable { case contrat = "CONTRAT", horsCreneau = "HORS_CRENEAU", aucunCreneau = "AUCUN_CRENEAU" }

    public var peutPointer: Bool
    public var action: Action?
    public var motif: Motif?
    public var creneauCourant: MissionSlot?
    public var prochainCreneau: MissionSlot?

    public init(peutPointer: Bool, action: Action?, motif: Motif?, creneauCourant: MissionSlot?, prochainCreneau: MissionSlot?) {
        self.peutPointer = peutPointer; self.action = action; self.motif = motif
        self.creneauCourant = creneauCourant; self.prochainCreneau = prochainCreneau
    }
}

/// Résultat de `evaluerTerminaisonMission`. `finReference` est `nil` lorsque la
/// fin de mission est illisible (équivalent d'une `Date` invalide côté web).
public struct EtatTerminaisonMission: Equatable, Sendable {
    public enum Motif: String, Sendable {
        case avantDernierCreneau = "AVANT_DERNIER_CRENEAU"
        case segmentOuvert = "SEGMENT_OUVERT"
        case aucunDepart = "AUCUN_DEPART"
        case planningIncomplet = "PLANNING_INCOMPLET"
    }

    public var peutTerminer: Bool
    public var motif: Motif?
    public var finReference: Date?

    public init(peutTerminer: Bool, motif: Motif?, finReference: Date?) {
        self.peutTerminer = peutTerminer; self.motif = motif; self.finReference = finReference
    }
}

public struct EtatClotureAdminMission: Equatable, Sendable {
    public var peutTerminer: Bool
    public var motif: EtatTerminaisonMission.Motif?
    public var finReference: Date?
    public var clotureAnticipee: Bool

    public init(peutTerminer: Bool, motif: EtatTerminaisonMission.Motif?, finReference: Date?, clotureAnticipee: Bool) {
        self.peutTerminer = peutTerminer; self.motif = motif; self.finReference = finReference; self.clotureAnticipee = clotureAnticipee
    }
}

/// Disponibilité du pointage côté client (port de `src/lib/disponibilite-pointage.ts`).
/// Ces règles n'affichent que ce que le serveur accepterait ; la décision finale
/// reste celle de `fn_pointer_arrivee` / `fn_pointer_depart`.
public enum DisponibilitePointage {
    public static let fenetreOuvertureMinutes = 15
    static let fenetreOuvertureMs: Double = Double(fenetreOuvertureMinutes) * 60_000

    static let statutsContratTerminaux: Set<String> = ["ANNULE", "EXPIRE", "REFUSE", "RUPTURE_ETAB", "RUPTURE_SOIGNANT"]

    /// `new Date(iso).getTime()` : millisecondes, ou NaN si la chaîne est illisible.
    /// Les comparaisons avec NaN sont toutes fausses, comme en JavaScript.
    static func temps(_ iso: String?) -> Double {
        guard let iso, let date = try? DateHeureParis.instantJolene(iso) else { return .nan }
        return Double(DateHeureParis.millisecondes(date))
    }

    static func temps(_ date: Date) -> Double {
        Double(DateHeureParis.millisecondes(date))
    }

    /// Tri stable par clé numérique ; deux clés NaN ou incomparables gardent leur ordre.
    private static func triStable<T>(_ elements: [T], croissant: Bool, cle: (T) -> Double) -> [T] {
        elements.enumerated().sorted { a, b in
            let ka = cle(a.element), kb = cle(b.element)
            if croissant ? ka < kb : ka > kb { return true }
            if croissant ? kb < ka : kb > ka { return false }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Contrat signé en priorité, puis le plus récent ; les contrats terminaux sont ignorés.
    public static func choisirContratPointage<T: ContratPointageRepresentable>(_ contrats: [T]) -> T? {
        let candidats = contrats.filter { !statutsContratTerminaux.contains($0.statut) }
        let tries = candidats.enumerated().sorted { a, b in
            let prioriteA = a.element.statut == "SIGNE_COMPLET" ? 1 : 0
            let prioriteB = b.element.statut == "SIGNE_COMPLET" ? 1 : 0
            if prioriteA != prioriteB { return prioriteA > prioriteB }
            let ta = a.element.creeLe == nil ? 0 : temps(a.element.creeLe)
            let tb = b.element.creeLe == nil ? 0 : temps(b.element.creeLe)
            if ta > tb { return true }
            if tb > ta { return false }
            return a.offset < b.offset
        }
        return tries.first?.element
    }

    /// Une mission longue peut être EN_COURS entre deux créneaux sans présence
    /// ouverte : seul le statut compte, jamais les présences legacy.
    public static func filtrerMissionsEnCours<T: AvecStatutMission>(_ missions: [T]) -> [T] {
        missions.filter { $0.statut == "EN_COURS" }
    }

    /// Créneaux prévisionnels de travail fermés, triés par début.
    public static func creneauxPrevisionnels(_ creneaux: [MissionSlot]) -> [MissionSlot] {
        let filtres = creneaux.filter { $0.typeCreneau == "PREVISIONNEL" && !$0.estPause && !($0.fin ?? "").isEmpty }
        return triStable(filtres, croissant: true) { temps($0.debut) }
    }

    /// Les missions ponctuelles créées par l'ancien RPC n'ont pas toujours de
    /// ligne PREVISIONNEL : leur plage globale (24 h maximum) est alors le seul
    /// horaire contractuel. Une mission longue n'est jamais étalée par défaut.
    public static func ajouterRepliMissionPonctuelle(_ creneaux: [MissionSlot], mission: PeriodeMissionPointage) -> [MissionSlot] {
        if !creneauxPrevisionnels(creneaux).isEmpty { return creneaux }
        let duree = temps(mission.finLe) - temps(mission.debutLe)
        guard duree.isFinite, duree > 0, duree <= 24 * 60 * 60_000 else { return creneaux }
        return creneaux + [MissionSlot(
            id: "mission-ponctuelle-\(mission.id ?? mission.debutLe)",
            debut: mission.debutLe, fin: mission.finLe, estPause: false, typeCreneau: "PREVISIONNEL"
        )]
    }

    public static func creneauChevauchePeriode(_ creneau: MissionSlot, debutPeriode: Date, finPeriode: Date) -> Bool {
        guard creneau.typeCreneau == "PREVISIONNEL", !creneau.estPause, !(creneau.fin ?? "").isEmpty else { return false }
        return temps(creneau.debut) < temps(finPeriode) && temps(creneau.fin) > temps(debutPeriode)
    }

    public static func prochainCreneauPointage(_ creneaux: [MissionSlot], maintenant: Date) -> MissionSlot? {
        let maintenantMs = temps(maintenant)
        return creneauxPrevisionnels(creneaux).first { temps($0.fin) >= maintenantMs }
    }

    public static func evaluerDisponibilitePointage(creneaux: [MissionSlot], contratStatut: String?, maintenant: Date) -> EtatDisponibilitePointage {
        let ouverts = creneaux.filter { $0.typeCreneau == "EFFECTIF" && !$0.estPause && ($0.fin ?? "").isEmpty }
        // Un départ doit toujours rester possible si une arrivée a déjà été enregistrée.
        if let segmentOuvert = triStable(ouverts, croissant: false, cle: { temps($0.debut) }).first {
            return EtatDisponibilitePointage(peutPointer: true, action: .fermeture, motif: nil,
                                             creneauCourant: segmentOuvert, prochainCreneau: nil)
        }

        let planifies = creneauxPrevisionnels(creneaux)
        let maintenantMs = temps(maintenant)
        let creneauCourant = planifies.first { creneau in
            let ouvertureMs = temps(creneau.debut) - fenetreOuvertureMs
            return maintenantMs >= ouvertureMs && maintenantMs <= temps(creneau.fin)
        }
        let prochainCreneau = planifies.first { temps($0.debut) > maintenantMs }

        if contratStatut != "SIGNE_COMPLET" {
            return EtatDisponibilitePointage(peutPointer: false, action: nil, motif: .contrat,
                                             creneauCourant: creneauCourant, prochainCreneau: prochainCreneau)
        }
        if let creneauCourant {
            return EtatDisponibilitePointage(peutPointer: true, action: .ouverture, motif: nil,
                                             creneauCourant: creneauCourant, prochainCreneau: prochainCreneau)
        }
        return EtatDisponibilitePointage(peutPointer: false, action: nil,
                                         motif: planifies.isEmpty ? .aucunCreneau : .horsCreneau,
                                         creneauCourant: nil, prochainCreneau: prochainCreneau)
    }

    public static func evaluerTerminaisonMission(creneaux: [MissionSlot], finMission: String,
                                                 presences: [PresencePointage] = [], maintenant: Date) -> EtatTerminaisonMission {
        let planningIncomplet = creneaux.contains { $0.typeCreneau == "PREVISIONNEL" && !$0.estPause && ($0.fin ?? "").isEmpty }
        let finsPlanifiees = creneauxPrevisionnels(creneaux).map { temps($0.fin) }.filter(\.isFinite)
        let finReferenceMs = finsPlanifiees.max() ?? temps(finMission)
        let finReference: Date? = finReferenceMs.isFinite ? DateHeureParis.date(millisecondes: Int64(finReferenceMs)) : nil

        if planningIncomplet {
            return EtatTerminaisonMission(peutTerminer: false, motif: .planningIncomplet, finReference: finReference)
        }
        let effectifs = creneaux.filter { $0.typeCreneau == "EFFECTIF" && !$0.estPause }
        if effectifs.contains(where: { ($0.fin ?? "").isEmpty }) {
            return EtatTerminaisonMission(peutTerminer: false, motif: .segmentOuvert, finReference: finReference)
        }
        let departEnregistre = effectifs.contains { !($0.fin ?? "").isEmpty }
            || presences.contains { !($0.pointageDepartLe ?? "").isEmpty }
        if !departEnregistre {
            return EtatTerminaisonMission(peutTerminer: false, motif: .aucunDepart, finReference: finReference)
        }
        if !finReferenceMs.isFinite || temps(maintenant) < finReferenceMs {
            return EtatTerminaisonMission(peutTerminer: false, motif: .avantDernierCreneau, finReference: finReference)
        }
        return EtatTerminaisonMission(peutTerminer: true, motif: nil, finReference: finReference)
    }

    /// La clôture anticipée est réservée à un administrateur intervenant sur un litige actif.
    public static func evaluerClotureAdminMission(terminaison: EtatTerminaisonMission, estAdmin: Bool, litigeActif: Bool) -> EtatClotureAdminMission {
        let clotureAnticipee = estAdmin && litigeActif && terminaison.motif == .avantDernierCreneau
        return EtatClotureAdminMission(
            peutTerminer: terminaison.peutTerminer || clotureAnticipee,
            motif: clotureAnticipee ? nil : terminaison.motif,
            finReference: terminaison.finReference,
            clotureAnticipee: clotureAnticipee
        )
    }
}
