import Foundation

// Instantané de la page Présences (blueprint `docs/mobile-swift/LOT2_PLAN.md` §3 T3, §2.7) : décodage tolérant des
// quatre requêtes de `src/pages/PresencesSoignant.tsx` (l.110-152 : missions ASSIGNEE/EN_COURS, présences validées
// depuis 7 jours, historique des présences, missions terminées), puis des créneaux et des contrats (l.172-184).
// Différences assumées avec le web : jamais l'embed `etablissements(...)` (noms par `fn_etablissements_safe`
// seulement, §2.7) ; colonnes réduites à ce que lit l'app (aucun montant : le récapitulatif financier n'est pas
// porté, §1.2 ; aucune colonne `code_pointage_*` : le code rotatif reste lisible par le soignant en PostgREST direct,
// gap « B1-ter » de la migration B1, il n'est jamais demandé). Déplacé ici depuis `Models/Lot2Results.swift` (T1 posait
// le contenant). État dérivé : listes et historique sont recalculés à chaque lecture, jamais stockés.

/// Ligne PostgREST décodée sans faire échouer la liste entière (lecture tolérante) : une ligne sans ses clés
/// obligatoires est écartée, ses voisines sont gardées.
public struct LigneTolerante<Valeur: Decodable>: Decodable {
    public let valeur: Valeur?

    public init(from decoder: Decoder) throws {
        valeur = try? Valeur(from: decoder)
    }

    public static func valeurs(_ lignes: [LigneTolerante<Valeur>]) -> [Valeur] {
        lignes.compactMap(\.valeur)
    }
}

extension LigneTolerante: Sendable where Valeur: Sendable {}

private extension KeyedDecodingContainer {
    /// Valeur absente, nulle ou d'un autre type : nil.
    func lu<T: Decodable>(_ type: T.Type, _ cle: Key) -> T? {
        try? decodeIfPresent(T.self, forKey: cle)
    }
}

/// Mission ASSIGNEE, EN_COURS ou terminée telle que la page Présences la lit (`missions`). `id`, `debut_le` et
/// `fin_le` sont NOT NULL au schéma et exigés ; `statut` est NULLable (`public.sql`) : nul → `""`, qui n'est ni
/// ASSIGNEE ni EN_COURS (consigne T3 de `DECISIONS_LOT2.md`). `profession_requise` n'est pas lue (le web ne la
/// sélectionne pas, l.114-115) : ce type remplace `MissionRecord`, qui l'exige.
public struct MissionPresenceLue: Decodable, Equatable, Sendable, Identifiable, MissionPresenceRepresentable {
    public static let colonnes = ["id", "intitule", "service", "debut_le", "fin_le", "duree_heures", "statut", "etablissement_id"]
    /// Valeur du paramètre PostgREST `select`.
    public static var selection: String { colonnes.joined(separator: ",") }

    public var id: String
    public var intitule: String?
    public var service: String?
    public var debutLe: String
    public var finLe: String
    public var dureeHeures: Double?
    public var statut: String
    public var etablissementId: String?

    public init(id: String, intitule: String? = nil, service: String? = nil, debutLe: String, finLe: String,
                dureeHeures: Double? = nil, statut: String, etablissementId: String? = nil) {
        self.id = id; self.intitule = intitule; self.service = service; self.debutLe = debutLe; self.finLe = finLe
        self.dureeHeures = dureeHeures; self.statut = statut; self.etablissementId = etablissementId
    }

    public var cleEtablissement: String? { etablissementId }

    enum CodingKeys: String, CodingKey {
        case id, intitule, service, statut
        case debutLe = "debut_le"
        case finLe = "fin_le"
        case dureeHeures = "duree_heures"
        case etablissementId = "etablissement_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        debutLe = try c.decode(String.self, forKey: .debutLe)
        finLe = try c.decode(String.self, forKey: .finLe)
        statut = c.lu(String.self, .statut) ?? ""
        intitule = c.lu(String.self, .intitule)
        service = c.lu(String.self, .service)
        dureeHeures = c.lu(Double.self, .dureeHeures)
        etablissementId = c.lu(String.self, .etablissementId)
    }
}

/// Mission embarquée dans une présence (`missions!inner(…)` des présences validées, `missions(…)` de l'historique,
/// l.124-145) : tout est optionnel, la présence reste lisible sans elle.
public struct MissionDePresence: Decodable, Equatable, Sendable {
    public static let colonnes = ["id", "intitule", "etablissement_id", "debut_le", "fin_le", "statut"]

    public var id: String?
    public var intitule: String?
    public var etablissementId: String?
    public var debutLe: String?
    public var finLe: String?
    public var statut: String?

    public init(id: String? = nil, intitule: String? = nil, etablissementId: String? = nil, debutLe: String? = nil,
                finLe: String? = nil, statut: String? = nil) {
        self.id = id; self.intitule = intitule; self.etablissementId = etablissementId; self.debutLe = debutLe
        self.finLe = finLe; self.statut = statut
    }

    enum CodingKeys: String, CodingKey {
        case id, intitule, statut
        case etablissementId = "etablissement_id"
        case debutLe = "debut_le"
        case finLe = "fin_le"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lu(String.self, .id)
        intitule = c.lu(String.self, .intitule)
        etablissementId = c.lu(String.self, .etablissementId)
        debutLe = c.lu(String.self, .debutLe)
        finLe = c.lu(String.self, .finLe)
        statut = c.lu(String.self, .statut)
    }
}

/// Ligne `presences` lue par la page (l.124-145) ; seul `id` est exigé. Aucune coordonnée n'est lue.
public struct PresenceLue: Decodable, Equatable, Sendable, Identifiable {
    public static let colonnes = ["id", "mission_id", "soignant_id", "pointage_arrivee_le", "pointage_depart_le",
                                  "valide_par_etablissement", "valide_le", "methode_pointage_arrivee", "methode_pointage_depart"]

    public var id: String
    public var missionId: String?
    public var soignantId: String?
    public var pointageArriveeLe: String?
    public var pointageDepartLe: String?
    public var valideParEtablissement: Bool?
    public var valideLe: String?
    public var methodePointageArrivee: String?
    public var methodePointageDepart: String?
    /// Embed `missions` (clé PostgREST au pluriel, comme le web).
    public var mission: MissionDePresence?

    public init(id: String, missionId: String? = nil, soignantId: String? = nil, pointageArriveeLe: String? = nil,
                pointageDepartLe: String? = nil, valideParEtablissement: Bool? = nil, valideLe: String? = nil,
                methodePointageArrivee: String? = nil, methodePointageDepart: String? = nil, mission: MissionDePresence? = nil) {
        self.id = id; self.missionId = missionId; self.soignantId = soignantId; self.pointageArriveeLe = pointageArriveeLe
        self.pointageDepartLe = pointageDepartLe; self.valideParEtablissement = valideParEtablissement; self.valideLe = valideLe
        self.methodePointageArrivee = methodePointageArrivee; self.methodePointageDepart = methodePointageDepart
        self.mission = mission
    }

    enum CodingKeys: String, CodingKey {
        case id
        case missionId = "mission_id"
        case soignantId = "soignant_id"
        case pointageArriveeLe = "pointage_arrivee_le"
        case pointageDepartLe = "pointage_depart_le"
        case valideParEtablissement = "valide_par_etablissement"
        case valideLe = "valide_le"
        case methodePointageArrivee = "methode_pointage_arrivee"
        case methodePointageDepart = "methode_pointage_depart"
        case mission = "missions"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        missionId = c.lu(String.self, .missionId)
        soignantId = c.lu(String.self, .soignantId)
        pointageArriveeLe = c.lu(String.self, .pointageArriveeLe)
        pointageDepartLe = c.lu(String.self, .pointageDepartLe)
        valideParEtablissement = c.lu(Bool.self, .valideParEtablissement)
        valideLe = c.lu(String.self, .valideLe)
        methodePointageArrivee = c.lu(String.self, .methodePointageArrivee)
        methodePointageDepart = c.lu(String.self, .methodePointageDepart)
        mission = c.lu(MissionDePresence.self, .mission)
    }
}

/// Ligne de l'onglet Historique (l.228-251) : une présence enregistrée, ou une ligne reconstruite depuis les segments
/// EFFECTIF d'une mission terminée sans présence (`HistoriquePresences`).
public enum LigneHistoriquePresence: Equatable, Sendable, Identifiable {
    case presence(PresenceLue, creneaux: [MissionSlot], etablissement: EtablissementSummary?)
    case effectifs(LigneHistoriqueEffectifs<EtablissementSummary>)

    public var id: String {
        switch self {
        case let .presence(presence, _, _): return presence.id
        case let .effectifs(ligne): return ligne.id
        }
    }

    public var missionId: String? {
        switch self {
        case let .presence(presence, _, _): return presence.missionId
        case let .effectifs(ligne): return ligne.missionId
        }
    }

    public var valideParEtablissement: Bool {
        switch self {
        case let .presence(presence, _, _): return presence.valideParEtablissement == true
        case let .effectifs(ligne): return ligne.valideParEtablissement
        }
    }

    public var pointageDepartLe: String? {
        switch self {
        case let .presence(presence, _, _): return presence.pointageDepartLe
        case let .effectifs(ligne): return ligne.pointageDepartLe
        }
    }

    /// Filtre `?filtre=a_valider` (l.284-288) : pointage complet (départ pointé) non encore validé.
    public var aValider: Bool { !valideParEtablissement && !(pointageDepartLe ?? "").isEmpty }

    /// Clé de tri `dateHistorique` (l.243-249) : départ, arrivée, fin puis début de la mission, sinon 0 ; une date
    /// illisible vaut NaN (ordre reçu conservé, comme le tri du web).
    var cleTri: Double {
        let candidats: [String?]
        switch self {
        case let .presence(presence, _, _):
            candidats = [presence.pointageDepartLe, presence.pointageArriveeLe, presence.mission?.finLe, presence.mission?.debutLe]
        case let .effectifs(ligne):
            candidats = [ligne.pointageDepartLe, ligne.pointageArriveeLe]
        }
        guard let premiere = candidats.compactMap({ $0 }).first(where: { !$0.isEmpty }) else { return 0 }
        return DisponibilitePointage.temps(premiere)
    }
}

/// Instantané de la page Présences, lu par `PointagePort.presences(context:)`.
public struct InstantanePresences: Equatable, Sendable {
    /// Missions ASSIGNEE et EN_COURS du soignant, par début croissant (l.110-122).
    public var missions: [MissionPresenceLue]
    /// Présences validées par l'établissement depuis 7 jours civils (l.123-133).
    public var presencesValidees: [PresenceLue]
    /// 100 dernières présences du soignant (l.134-144).
    public var historique: [PresenceLue]
    /// 100 dernières missions TERMINEE, LITIGE ou ABSENCE (l.145-151).
    public var missionsHistorique: [MissionPresenceLue]
    /// Créneaux de toutes ces missions, tous types (PREVISIONNEL, EFFECTIF, pauses), par début croissant.
    public var creneaux: [MissionSlot]
    /// Contrats des missions ASSIGNEE et EN_COURS (`id, mission_id, statut, cree_le`).
    public var contrats: [ContratPointage]
    /// Établissements lus par `fn_etablissements_safe`, par identifiant.
    public var etablissements: [String: EtablissementSummary]
    /// Horloge figée au début du chargement (l.107) : borne « aujourd'hui ».
    public var chargeLe: Date?

    public init(missions: [MissionPresenceLue] = [], presencesValidees: [PresenceLue] = [], historique: [PresenceLue] = [],
                missionsHistorique: [MissionPresenceLue] = [], creneaux: [MissionSlot] = [], contrats: [ContratPointage] = [],
                etablissements: [String: EtablissementSummary] = [:], chargeLe: Date? = nil) {
        self.missions = missions; self.presencesValidees = presencesValidees; self.historique = historique
        self.missionsHistorique = missionsHistorique; self.creneaux = creneaux; self.contrats = contrats
        self.etablissements = etablissements; self.chargeLe = chargeLe
    }

    /// Missions dont les créneaux sont lus (`tousMissionIds`, l.165-170) : actives, présences validées, historique,
    /// missions terminées, dans cet ordre, dédoublonnées, vides écartées.
    public static func identifiantsMissions(missions: [MissionPresenceLue], presencesValidees: [PresenceLue],
                                            historique: [PresenceLue], missionsHistorique: [MissionPresenceLue]) -> [String] {
        uniques(missions.map(\.id) + presencesValidees.map(\.missionId) + historique.map(\.missionId) + missionsHistorique.map(\.id))
    }

    /// Établissements à résoudre par `fn_etablissements_safe` (l.185-196), dans le même ordre.
    public static func identifiantsEtablissements(missions: [MissionPresenceLue], presencesValidees: [PresenceLue],
                                                  historique: [PresenceLue], missionsHistorique: [MissionPresenceLue]) -> [String] {
        uniques(missions.map(\.etablissementId) + presencesValidees.map { $0.mission?.etablissementId }
                + historique.map { $0.mission?.etablissementId } + missionsHistorique.map(\.etablissementId))
    }

    public var identifiantsMissions: [String] {
        Self.identifiantsMissions(missions: missions, presencesValidees: presencesValidees, historique: historique,
                                  missionsHistorique: missionsHistorique)
    }

    public var creneauxParMission: [String: [MissionSlot]] {
        ListesPresences.regrouperCreneauxParMission(creneaux)
    }

    /// Onglets Aujourd'hui, À venir et Actives, et contrat de pointage par mission (`ListesPresences`, golden W1).
    public func listes(maintenant: Date) -> ListesPresencesSoignant<MissionPresenceLue, EtablissementSummary> {
        ListesPresences.construire(missions: missions, creneauxParMission: creneauxParMission, contrats: contrats,
                                   maintenant: maintenant, etablissements: etablissements)
    }

    /// Lignes reconstruites depuis les segments EFFECTIF (l.236-242).
    public func historiqueEffectifs(soignantId: String) -> [LigneHistoriqueEffectifs<EtablissementSummary>] {
        HistoriquePresences.construireEffectifsSansPresence(
            missions: missionsHistorique.map { MissionHistorique(id: $0.id, etablissementId: $0.etablissementId) },
            missionsAvecPresence: historique.map(\.missionId),
            creneauxParMission: creneauxParMission,
            etablissements: etablissements,
            soignantId: soignantId)
    }

    /// Onglet Historique (l.228-251) : présences puis lignes reconstruites, triées par date décroissante (tri stable).
    public func lignesHistorique(soignantId: String) -> [LigneHistoriquePresence] {
        let parMission = creneauxParMission
        let presences = historique.map { presence -> LigneHistoriquePresence in
            .presence(presence, creneaux: presence.missionId.flatMap { parMission[$0] } ?? [],
                      etablissement: presence.mission?.etablissementId.flatMap { etablissements[$0] })
        }
        let lignes = presences + historiqueEffectifs(soignantId: soignantId).map(LigneHistoriquePresence.effectifs)
        return DisponibilitePointage.triStable(lignes, croissant: false, cle: \.cleTri)
    }

    private static func uniques(_ valeurs: [String?]) -> [String] {
        var vus = Set<String>()
        return valeurs.compactMap { $0 }.filter { !$0.isEmpty && vus.insert($0).inserted }
    }
}
