import Foundation

// Présences de l'établissement (lot 5, T8 ; `docs/mobile-swift/LOT5_PLAN.md` §3 T8, §2.6) : décodage tolérant des
// lignes `presences` et règles pures de `src/pages/PresencesEtablissement.tsx` (onglets l.190-211, missions terminées
// sans pointage l.119-120). Les colonnes lues sont celles de `PresenceEtab.clesDecodees` : jamais `arrivee_lat/lng`,
// `depart_lat/lng`, `coherence_incidents` ni `duree_heures` ; aucun montant (D15). Le serveur reste l'autorité : ces
// règles ne décident que de l'affichage, la validation est refusée ou acceptée par
// `dec_bloquer_validation_presence_avant_fin_planning` et le trigger RBAC.

// MARK: - Décodage

extension MissionPresenceEtab: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, intitule, service
        case debutLe = "debut_le"
        case finLe = "fin_le"
        case nbCreneaux = "nb_creneaux"
        case etablissementId = "etablissement_id"
    }

    /// Colonnes de l'embed `missions!inner(…)` (web l.77 sans `duree_heures`).
    public static var clesDecodees: [String] { CodingKeys.allCases.map(\.rawValue) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func texte(_ cle: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: cle)) ?? nil }
        self.init(id: try c.decode(String.self, forKey: .id), intitule: texte(.intitule), service: texte(.service),
                  debutLe: texte(.debutLe), finLe: texte(.finLe),
                  nbCreneaux: (try? c.decodeIfPresent(Int.self, forKey: .nbCreneaux)) ?? nil,
                  etablissementId: texte(.etablissementId))
    }
}

extension PresenceEtab: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case missionId = "mission_id"
        case soignantId = "soignant_id"
        case distanceEtablissementM = "distance_etablissement_m"
        case perimetreGpsValide = "perimetre_gps_valide"
        case alerteTeleportation = "alerte_teleportation"
        case arriveeMockDetected = "arrivee_mock_detected"
        case departMockDetected = "depart_mock_detected"
        case valideParEtablissement = "valide_par_etablissement"
        case valideLe = "valide_le"
        case motifLitige = "motif_litige"
        case mission = "missions"
    }

    /// Les seules colonnes lues sur `presences` (l'embed de la mission est `MissionPresenceEtab.clesDecodees`).
    public static var clesDecodees: [String] { CodingKeys.allCases.filter { $0 != .mission }.map(\.rawValue) }

    /// `id` et `mission_id` exigés, non vides ; `valide_par_etablissement` absent ou nul vaut `false` (jamais une
    /// validation supposée) ; toute autre clé tolérante. Les créneaux sont relus à part par la gateway.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        let missionId = try c.decode(String.self, forKey: .missionId)
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !missionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "identifiant de présence ou de mission vide")
        }
        func texte(_ cle: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: cle)) ?? nil }
        func booleen(_ cle: CodingKeys) -> Bool? { (try? c.decodeIfPresent(Bool.self, forKey: cle)) ?? nil }
        let distance = (try? c.decodeIfPresent(Double.self, forKey: .distanceEtablissementM)) ?? nil
        self.init(id: id, missionId: missionId, valideParEtablissement: booleen(.valideParEtablissement) ?? false,
                  valideLe: texte(.valideLe), motifLitige: texte(.motifLitige), soignantId: texte(.soignantId),
                  distanceEtablissementM: distance, perimetreGpsValide: booleen(.perimetreGpsValide),
                  alerteTeleportation: booleen(.alerteTeleportation), arriveeMockDetected: booleen(.arriveeMockDetected),
                  departMockDetected: booleen(.departMockDetected),
                  mission: (try? c.decodeIfPresent(MissionPresenceEtab.self, forKey: .mission)) ?? nil)
    }
}

// MARK: - Onglets

/// Onglets de la page (`PresencesEtablissement.tsx` l.57, valeurs du paramètre `?tab=`).
public enum OngletPresencesEtab: String, CaseIterable, Sendable, Identifiable {
    case aValider = "a_valider"
    case enCours = "en_cours"
    case validees
    case alertes

    public var id: String { rawValue }

    /// `?tab=` d'un lien : toute autre valeur ouvre « À valider » (web l.57).
    public init(parametre: String?) {
        self = parametre.flatMap(OngletPresencesEtab.init(rawValue:)) ?? .aValider
    }
}

// MARK: - Règles

public enum PresencesEtabRules {
    /// Alerte d'une présence (identifiants `etab-presence-alerte-{id}-{cle}`).
    public enum Alerte: String, CaseIterable, Sendable {
        case teleportation
        case horsZone = "hors_zone"
        case gpsTruque = "gps_truque"
    }

    /// Lecture d'une présence à un instant (web l.146-169, l.190-193) : planning contractuel complet ou non, synthèse
    /// des créneaux, validation possible. Dérivée à chaque affichage, jamais mémorisée.
    public struct Analyse: Equatable, Sendable {
        /// `missions.planning_indisponible` du web : planning détaillé non vérifiable.
        public var planningIndisponible: Bool
        public var synthese: SynthesePresenceMission
        /// `!planning_indisponible && synthese.validationPossible` (web l.194-198, `CarteValidation.tsx` l.62).
        public var validationPossible: Bool { !planningIndisponible && synthese.validationPossible }
    }

    public static func analyser(_ presence: PresenceEtab, maintenant: Date) -> Analyse {
        analyser(mission: presence.mission, missionId: presence.missionId, creneaux: presence.creneaux, maintenant: maintenant)
    }

    /// Planning complet : créneaux planifiés retenus par `CompletudePlanning` puis EFFECTIF ; sinon créneaux bruts et
    /// planning indisponible (web l.149-158). Sans mission lue, rien n'est vérifiable (fail-closed).
    public static func analyser(mission: MissionPresenceEtab?, missionId: String, creneaux: [MissionSlot],
                                maintenant: Date) -> Analyse {
        guard let mission else {
            return Analyse(planningIndisponible: true, synthese: SynthesePresence.construire(creneaux, maintenant: maintenant))
        }
        let attendu = MissionAvecPlanningAttendu(id: missionId, debutLe: mission.debutLe ?? "", finLe: mission.finLe ?? "",
                                                 nbCreneaux: mission.nbCreneaux)
        let planning = CompletudePlanning.analyser(attendu, creneaux: creneaux)
        let effectifs = creneaux.filter { $0.typeCreneau == "EFFECTIF" }
        let retenus = planning.complet ? planning.creneauxPlanifies + effectifs : creneaux
        return Analyse(planningIndisponible: !planning.complet, synthese: SynthesePresence.construire(retenus, maintenant: maintenant))
    }

    /// `alerte_teleportation || perimetre_gps_valide === false` (web l.206).
    public static func aAlerte(_ presence: PresenceEtab) -> Bool {
        presence.alerteTeleportation == true || presence.perimetreGpsValide == false
    }

    /// Présence « sans alerte » de la validation en lot (web l.209-211) : périmètre **confirmé** et aucune téléportation,
    /// le prédicat de `fn_valider_presences_lot` (`perimetre_gps_valide = true AND NOT alerte_teleportation`).
    public static func sansAlerte(_ presence: PresenceEtab) -> Bool {
        presence.perimetreGpsValide == true && presence.alerteTeleportation != true
    }

    /// Pastilles d'alerte (web l.456-458), dans l'ordre du web.
    public static func alertes(_ presence: PresenceEtab) -> [Alerte] {
        var alertes: [Alerte] = []
        if presence.alerteTeleportation == true { alertes.append(.teleportation) }
        if presence.perimetreGpsValide == false { alertes.append(.horsZone) }
        if presence.arriveeMockDetected == true || presence.departMockDetected == true { alertes.append(.gpsTruque) }
        return alertes
    }

    /// Présences par onglet (web l.194-211). Une présence en alerte figure aussi dans son onglet d'état.
    public struct Repartition: Equatable, Sendable {
        public var aValider: [PresenceEtab] = []
        public var enCours: [PresenceEtab] = []
        public var validees: [PresenceEtab] = []
        public var alertes: [PresenceEtab] = []

        /// Présences à valider sans alerte : celles que la validation en lot propose (web l.209-211).
        public var sansAlerte: [PresenceEtab] { aValider.filter(PresencesEtabRules.sansAlerte) }

        public func presences(_ onglet: OngletPresencesEtab) -> [PresenceEtab] {
            switch onglet {
            case .aValider: return aValider
            case .enCours: return enCours
            case .validees: return validees
            case .alertes: return alertes
            }
        }
    }

    public static func repartir(_ presences: [PresenceEtab], maintenant: Date) -> Repartition {
        var repartition = Repartition()
        for presence in presences {
            if presence.valideParEtablissement {
                repartition.validees.append(presence)
            } else if analyser(presence, maintenant: maintenant).validationPossible {
                repartition.aValider.append(presence)
            } else {
                // Une mission multi-jours reste « en cours » entre deux journées (web l.200-205).
                repartition.enCours.append(presence)
            }
            if aAlerte(presence) { repartition.alertes.append(presence) }
        }
        return repartition
    }

    /// Missions terminées sans aucune présence pointée (web l.119-120) : `terminees` = missions `TERMINEE` salariées
    /// attribuées, `presences` = présences dont l'arrivée est pointée.
    public static func missionsSansPointage(terminees: [EtabMissionResume], presences: [PresenceEtab]) -> [EtabMissionResume] {
        let pointees = Set(presences.map(\.missionId))
        return terminees.filter { !pointees.contains($0.id) }
    }
}
