import Foundation

/// Mission ASSIGNEE ou EN_COURS telle que les listes de présences la lisent (port de
/// `MissionPresenceSoignant`). Les listes sont génériques pour rendre la mission lue entière (T3).
public protocol MissionPresenceRepresentable: AvecStatutMission {
    var id: String { get }
    var debutLe: String { get }
    var finLe: String { get }
    /// `duree_heures` : repli de la durée affichée quand le prochain créneau n'a pas de fin.
    var dureeHeures: Double? { get }
    /// `etablissement_id`, clé de la carte lue par `fn_etablissements_safe` (jamais l'embed
    /// `etablissements(...)`, lot 2 §2.7) ; nul : établissement inconnu.
    var cleEtablissement: String? { get }
}

/// Colonnes de `missions` lues par les listes (`PresencesSoignant.tsx` l.112-115).
public struct MissionPresence: Equatable, Sendable, MissionPresenceRepresentable {
    public var id: String
    public var statut: String
    public var debutLe: String
    public var finLe: String
    public var dureeHeures: Double?
    public var etablissementId: String?

    public init(id: String, statut: String, debutLe: String, finLe: String, dureeHeures: Double?, etablissementId: String?) {
        self.id = id; self.statut = statut; self.debutLe = debutLe; self.finLe = finLe
        self.dureeHeures = dureeHeures; self.etablissementId = etablissementId
    }

    public var cleEtablissement: String? { etablissementId }
}

extension MissionRecord: MissionPresenceRepresentable {
    public var cleEtablissement: String? { etablissementId }
}

/// Mission enrichie de ses créneaux (repli ponctuel compris) et de son établissement résolu
/// (port de `MissionPresenceEnrichie`).
public struct MissionPresenceEnrichie<Mission: MissionPresenceRepresentable, Etablissement>: AvecStatutMission {
    public let mission: Mission
    /// Créneaux lus pour la mission, plus le repli ponctuel quand il s'applique.
    public let creneaux: [MissionSlot]
    /// Valeur lue par `fn_etablissements_safe` ; `nil` si inconnue.
    public let etablissement: Etablissement?

    public var statut: String { mission.statut }
}

extension MissionPresenceEnrichie: Equatable where Mission: Equatable, Etablissement: Equatable {}
extension MissionPresenceEnrichie: Sendable where Mission: Sendable, Etablissement: Sendable {}

/// Ligne de l'onglet « À venir » (port de `MissionPresenceAVenir`).
public struct MissionPresenceAVenir<Mission: MissionPresenceRepresentable, Etablissement> {
    public let mission: Mission
    public let creneaux: [MissionSlot]
    public let etablissement: Etablissement?
    /// Début du prochain créneau prévu à partir de demain (Paris) ; `nil` : planning à confirmer.
    public let dateAffichage: String?
    public let prochainCreneau: MissionSlot?
    /// Durée du prochain créneau, en heures. Jamais non finie : une borne illisible donne `nil`
    /// (le web afficherait « NaN »).
    public let dureeAffichageHeures: Double?
    /// Mission ASSIGNEE sans aucun créneau prévu (fermé, hors pause) : « Planning détaillé à confirmer ».
    public let planningAConfirmer: Bool
}

extension MissionPresenceAVenir: Equatable where Mission: Equatable, Etablissement: Equatable {}
extension MissionPresenceAVenir: Sendable where Mission: Sendable, Etablissement: Sendable {}

/// Listes de la page Présences (port de `ListesPresencesSoignant`). État dérivé : recalculé à
/// chaque lecture, jamais stocké.
public struct ListesPresencesSoignant<Mission: MissionPresenceRepresentable, Etablissement> {
    /// Onglet « Aujourd'hui » : segment EFFECTIF ouvert ou créneau prévu ce jour (Paris).
    public let missionsAujourdhui: [MissionPresenceEnrichie<Mission, Etablissement>]
    /// Onglet « À venir » : prochain créneau dès demain, puis plannings à confirmer (20 au plus).
    public let missionsAVenir: [MissionPresenceAVenir<Mission, Etablissement>]
    /// Onglet « Actives » : missions EN_COURS.
    public let missionsEnCours: [MissionPresenceEnrichie<Mission, Etablissement>]
    /// Contrat retenu pour le pointage, par `mission_id`.
    public let contrats: [String: ContratPointage]
}

extension ListesPresencesSoignant: Equatable where Mission: Equatable, Etablissement: Equatable {}
extension ListesPresencesSoignant: Sendable where Mission: Sendable, Etablissement: Sendable {}

/// Port de `src/lib/presences-soignant-listes.ts` (extrait de `PresencesSoignant.tsx` par la PR
/// web W1, #1112), avec ses vecteurs golden (`presences-soignant-listes.json`). Règle pure :
/// horloge explicite, jour civil de Paris, aucun accès réseau. L'historique reconstruit depuis les
/// segments EFFECTIF reste dans `HistoriquePresences`.
public enum ListesPresences {
    /// `.slice(0, 20)` de l'onglet « À venir ».
    public static let limiteAVenir = 20

    /// Regroupe les lignes `mission_creneaux` par mission, dans l'ordre reçu. Un créneau sans
    /// `mission_id` (hors domaine : colonne NOT NULL, `public.sql` l.70567) n'est rattaché à aucune mission.
    public static func regrouperCreneauxParMission(_ creneaux: [MissionSlot]?) -> [String: [MissionSlot]] {
        var groupes: [String: [MissionSlot]] = [:]
        for creneau in creneaux ?? [] {
            guard let missionId = creneau.missionId else { continue }
            groupes[missionId, default: []].append(creneau)
        }
        return groupes
    }

    /// Construit les onglets Aujourd'hui, À venir et Actives, et choisit le contrat de pointage de
    /// chaque mission (port de `construireListesPresences`). `maintenant` est l'horloge figée au
    /// début du chargement ; `etablissements` vient de `fn_etablissements_safe` uniquement.
    /// Un contrat sans `mission_id` (hors domaine : colonne NOT NULL, `public.sql` l.68776) n'est
    /// retenu pour aucune mission : échec fermé, le pointage reste bloqué par le motif CONTRAT.
    public static func construire<Mission: MissionPresenceRepresentable, Etablissement>(
        missions: [Mission],
        creneauxParMission: [String: [MissionSlot]],
        contrats: [ContratPointage]?,
        maintenant: Date,
        etablissements: [String: Etablissement] = [:]
    ) -> ListesPresencesSoignant<Mission, Etablissement> {
        let aujourdhui = DateHeureParis.debutJour(maintenant)
        let demain = DateHeureParis.ajouterJoursCivils(aujourdhui, 1)

        var contratsParMission: [String: [ContratPointage]] = [:]
        for contrat in contrats ?? [] {
            guard let missionId = contrat.missionId else { continue }
            contratsParMission[missionId, default: []].append(contrat)
        }
        let contratsRetenus = contratsParMission.compactMapValues { DisponibilitePointage.choisirContratPointage($0) }

        let enrichies = missions.map { mission in
            MissionPresenceEnrichie<Mission, Etablissement>(
                mission: mission,
                creneaux: DisponibilitePointage.ajouterRepliMissionPonctuelle(
                    creneauxParMission[mission.id] ?? [],
                    mission: PeriodeMissionPointage(id: mission.id, debutLe: mission.debutLe, finLe: mission.finLe)),
                etablissement: mission.cleEtablissement.flatMap { etablissements[$0] }
            )
        }

        let missionsAujourdhui = enrichies.filter { mission in
            let segmentOuvert = mission.creneaux.contains {
                $0.typeCreneau == "EFFECTIF" && !$0.estPause && ($0.fin ?? "").isEmpty
            }
            let creneauDuJour = DisponibilitePointage.creneauxPrevisionnels(mission.creneaux).contains {
                DisponibilitePointage.creneauChevauchePeriode($0, debutPeriode: aujourdhui, finPeriode: demain)
            }
            return segmentOuvert || creneauDuJour
        }

        let demainMs = DisponibilitePointage.temps(demain)
        let datees: [MissionPresenceAVenir<Mission, Etablissement>] = enrichies.compactMap { enrichie in
            guard let prochain = DisponibilitePointage.creneauxPrevisionnels(enrichie.creneaux)
                .first(where: { DisponibilitePointage.temps($0.debut) >= demainMs }) else { return nil }
            let duree: Double?
            if let fin = prochain.fin, !fin.isEmpty {
                duree = (DisponibilitePointage.temps(fin) - DisponibilitePointage.temps(prochain.debut)) / 3_600_000
            } else {
                duree = enrichie.mission.dureeHeures
            }
            return MissionPresenceAVenir(mission: enrichie.mission, creneaux: enrichie.creneaux, etablissement: enrichie.etablissement,
                                         dateAffichage: prochain.debut, prochainCreneau: prochain,
                                         dureeAffichageHeures: duree.flatMap { $0.isFinite ? $0 : nil }, planningAConfirmer: false)
        }
        let aConfirmer = enrichies
            .filter { $0.statut == "ASSIGNEE" && DisponibilitePointage.creneauxPrevisionnels($0.creneaux).isEmpty }
            .map {
                MissionPresenceAVenir(mission: $0.mission, creneaux: $0.creneaux, etablissement: $0.etablissement,
                                      dateAffichage: nil, prochainCreneau: nil, dureeAffichageHeures: nil, planningAConfirmer: true)
            }
        // Tri stable : missions datées par date croissante, puis plannings à confirmer dans l'ordre reçu.
        let missionsAVenir = (datees + aConfirmer).enumerated().sorted { a, b in
            switch (a.element.dateAffichage, b.element.dateAffichage) {
            case let (dateA?, dateB?):
                let ecart = DisponibilitePointage.temps(dateA) - DisponibilitePointage.temps(dateB)
                if ecart < 0 { return true }
                if ecart > 0 { return false }
                return a.offset < b.offset
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return a.offset < b.offset
            }
        }.prefix(limiteAVenir).map(\.element)

        // Une mission EN_COURS reste visible même sans présence legacy : les créneaux EFFECTIF
        // sont la source de vérité du pointage.
        return ListesPresencesSoignant(
            missionsAujourdhui: missionsAujourdhui,
            missionsAVenir: missionsAVenir,
            missionsEnCours: DisponibilitePointage.filtrerMissionsEnCours(enrichies),
            contrats: contratsRetenus
        )
    }
}
