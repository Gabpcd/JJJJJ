import Foundation

// Accueil de l'espace établissement (lot 5, T4 ; `docs/mobile-swift/LOT5_PLAN.md` §1.1, §2.4, §2.8, §3 T4) : contrat
// d'échange de `EtabDashboardPort` (déplacé de `Models/EtablissementResults.swift`, où T1 l'avait posé minimal) et
// dérivation du planning à venir. Compteurs seulement : aucun montant, aucun nom de soignant, aucune note (D15, §2.8).

/// Compteurs de `fn_stats_dashboard_etablissement()` (`supabase/schema/public.sql` l.58066, 18 clés) que le natif
/// décode. **Jamais décodés** : `commissions_cumulees`, `commissions_impayees` (montants), `candidatures_recentes` et
/// `missions_assignees_detail` (noms complets de soignants), et les compteurs que l'Accueil n'affiche pas. Décodage
/// tolérant : une clé absente, nulle, négative ou d'un autre type vaut `nil` — jamais un zéro supposé qui masquerait
/// une action, jamais une valeur qui en ouvrirait une.
public struct EtabDashboardStats: Equatable, Sendable {
    public var candidaturesEnAttente: Int?
    public var messagesNonLus: Int?
    public var litigesOuverts: Int?
    /// Compteur seul (aucun montant), affiché sous `lecture_paiement` ∨ `paiement` (§2.7, D15).
    public var nbFacturesImpayees: Int?
    public var aDejaPublie: Bool?

    public init(candidaturesEnAttente: Int? = nil, messagesNonLus: Int? = nil, litigesOuverts: Int? = nil,
                nbFacturesImpayees: Int? = nil, aDejaPublie: Bool? = nil) {
        self.candidaturesEnAttente = candidaturesEnAttente; self.messagesNonLus = messagesNonLus
        self.litigesOuverts = litigesOuverts; self.nbFacturesImpayees = nbFacturesImpayees; self.aDejaPublie = aDejaPublie
    }
}

extension EtabDashboardStats: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case candidaturesEnAttente = "candidatures_en_attente"
        case messagesNonLus = "messages_non_lus"
        case litigesOuverts = "litiges_ouverts"
        case nbFacturesImpayees = "nb_factures_impayees"
        case aDejaPublie = "a_deja_publie"
    }

    /// Les seules clés lues dans la réponse serveur.
    public static var clesDecodees: [String] { CodingKeys.allCases.map(\.rawValue) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func compteur(_ cle: CodingKeys) -> Int? {
            guard let valeur = (try? c.decodeIfPresent(Int.self, forKey: cle)) ?? nil, valeur >= 0 else { return nil }
            return valeur
        }
        self.init(candidaturesEnAttente: compteur(.candidaturesEnAttente), messagesNonLus: compteur(.messagesNonLus),
                  litigesOuverts: compteur(.litigesOuverts), nbFacturesImpayees: compteur(.nbFacturesImpayees),
                  aDejaPublie: (try? c.decodeIfPresent(Bool.self, forKey: .aDejaPublie)) ?? nil)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(candidaturesEnAttente, forKey: .candidaturesEnAttente)
        try c.encode(messagesNonLus, forKey: .messagesNonLus)
        try c.encode(litigesOuverts, forKey: .litigesOuverts)
        try c.encode(nbFacturesImpayees, forKey: .nbFacturesImpayees)
        try c.encode(aDejaPublie, forKey: .aDejaPublie)
    }
}

/// Tableau de bord de l'Accueil : compteurs (lecture principale, `fn_stats_dashboard_etablissement`) et planning à
/// venir (lecture secondaire PostgREST). `planning == nil` : la lecture secondaire a échoué, l'Accueil s'affiche
/// quand même avec le bandeau « partiel » (parité `erreurPartielle` du web, `DashboardEtablissement.tsx` l.711-713).
public struct EtabDashboardSnapshot: Equatable, Sendable {
    public var stats: EtabDashboardStats
    public var planning: EtabPlanningAVenir?

    public init(stats: EtabDashboardStats = EtabDashboardStats(), planning: EtabPlanningAVenir? = EtabPlanningAVenir()) {
        self.stats = stats; self.planning = planning
    }

    public var lecturePartielle: Bool { planning == nil }
}

// MARK: - Planning à venir

/// Ligne `missions` lue pour le planning à venir (`DashboardEtablissement.tsx` l.293-300, sans `duree_heures` ni
/// soignant : aucun nom n'est chargé par l'Accueil natif).
public struct EtabMissionPlanifiee: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var intitule: String
    public var statut: String
    public var debutLe: String
    public var finLe: String
    public var nbCreneaux: Int?

    public init(id: String, intitule: String, statut: String, debutLe: String, finLe: String, nbCreneaux: Int?) {
        self.id = id; self.intitule = intitule; self.statut = statut; self.debutLe = debutLe; self.finLe = finLe
        self.nbCreneaux = nbCreneaux
    }

    enum CodingKeys: String, CodingKey {
        case id, intitule, statut
        case debutLe = "debut_le"
        case finLe = "fin_le"
        case nbCreneaux = "nb_creneaux"
    }
}

/// Créneau travaillé d'une mission dans la fenêtre (une occurrence de `construireOccurrencesPlanning`,
/// `src/components/dashboard/SectionPlanning.tsx` l.65-104).
public struct EtabOccurrencePlanning: Equatable, Sendable, Identifiable {
    public var id: String
    public var missionId: String
    public var intitule: String
    public var statut: String
    /// Chaînes serveur telles que lues (jamais réécrites).
    public var debut: String
    public var fin: String

    public init(id: String, missionId: String, intitule: String, statut: String, debut: String, fin: String) {
        self.id = id; self.missionId = missionId; self.intitule = intitule; self.statut = statut
        self.debut = debut; self.fin = fin
    }
}

/// Planning des 31 prochains jours (`SectionPlanning`, web) : occurrences triées par début et missions dont le
/// planning détaillé n'est pas exact au sens de `CompletudePlanning` (« à confirmer », `DashboardEtablissement.tsx`
/// l.354-363 ; même prédicat que la liste et le détail des missions).
public struct EtabPlanningAVenir: Equatable, Sendable {
    public var occurrences: [EtabOccurrencePlanning]
    public var missionsSansPlanning: [EtabMissionPlanifiee]

    public init(occurrences: [EtabOccurrencePlanning] = [], missionsSansPlanning: [EtabMissionPlanifiee] = []) {
        self.occurrences = occurrences; self.missionsSansPlanning = missionsSansPlanning
    }
}

/// Dérivation pure du planning à venir, port de `DashboardEtablissement.tsx` l.288-369 et de
/// `construireOccurrencesPlanning` / `finFenetrePlanningParis` (`SectionPlanning.tsx` l.52-104) : la période globale
/// `debut_le`/`fin_le` d'une mission n'est jamais étalée sur chaque jour, seul le repli ponctuel (≤ 24 h, missions
/// legacy sans PREVISIONNEL) en tient lieu (`DisponibilitePointage.ajouterRepliMissionPonctuelle`).
public enum EtabPlanningAccueil {
    /// Fenêtre du web (`finFenetrePlanningParis(now, 31)`).
    public static let fenetreJours = 31
    /// Statuts lus (`DashboardEtablissement.tsx` l.297).
    public static let statuts = ["OUVERTE", "ASSIGNEE", "EN_COURS"]

    /// Dernière milliseconde du jour civil de Paris situé `jours` jours plus loin.
    public static func finFenetre(_ debut: Date, jours: Int = fenetreJours) -> Date {
        let lendemain = DateHeureParis.ajouterJoursCivils(debut, jours + 1)
        return DateHeureParis.date(millisecondes: DateHeureParis.millisecondes(lendemain) - 1)
    }

    public static func construire(missions: [EtabMissionPlanifiee], creneaux: [MissionSlot], maintenant: Date) -> EtabPlanningAVenir {
        var parMission: [String: [MissionSlot]] = [:]
        for creneau in creneaux {
            guard let missionId = creneau.missionId else { continue }
            parMission[missionId, default: []].append(creneau)
        }
        let debutMs = DisponibilitePointage.temps(maintenant)
        let finMs = DisponibilitePointage.temps(finFenetre(maintenant))

        // Planning « à confirmer » : un seul prédicat, `CompletudePlanning` (source contractuelle), le même que la liste et
        // le détail des missions et que l'espace soignant (principe « État dérivé » ; intégration de la vague C, revue B8
        // de #1160, m4). Écart au critère local du web (`DashboardEtablissement.tsx` l.354-363, nombre reçu égal à
        // `nb_creneaux` et fin renseignée) : bornes lisibles et `fin > debut` exigées, repli ponctuel accepté quand
        // `nb_creneaux` vaut 0 ou manque, comme `analyserCompletudePlanningMission`.
        let sansPlanning = missions.filter { !planningExact($0, creneaux: parMission[$0.id] ?? []) }

        var occurrences: [EtabOccurrencePlanning] = []
        for mission in missions {
            let periode = PeriodeMissionPointage(id: mission.id, debutLe: mission.debutLe, finLe: mission.finLe)
            let planifies = DisponibilitePointage.creneauxPrevisionnels(
                DisponibilitePointage.ajouterRepliMissionPonctuelle(parMission[mission.id] ?? [], mission: periode))
            for creneau in planifies {
                guard let fin = creneau.fin, !fin.isEmpty,
                      DisponibilitePointage.temps(fin) >= debutMs, DisponibilitePointage.temps(creneau.debut) <= finMs
                else { continue }
                occurrences.append(EtabOccurrencePlanning(id: "\(mission.id):\(creneau.id ?? creneau.debut)", missionId: mission.id,
                                                          intitule: mission.intitule, statut: mission.statut,
                                                          debut: creneau.debut, fin: fin))
            }
        }
        let triees = DisponibilitePointage.triStable(occurrences, croissant: true) { DisponibilitePointage.temps($0.debut) }
        return EtabPlanningAVenir(occurrences: triees, missionsSansPlanning: sansPlanning)
    }

    /// Planning exact d'une mission de l'Accueil : `CompletudePlanning.analyser`, sans autre critère.
    public static func planningExact(_ mission: EtabMissionPlanifiee, creneaux: [MissionSlot]) -> Bool {
        CompletudePlanning.analyser(MissionAvecPlanningAttendu(id: mission.id, debutLe: mission.debutLe, finLe: mission.finLe,
                                                               nbCreneaux: mission.nbCreneaux),
                                    creneaux: creneaux).complet
    }
}
