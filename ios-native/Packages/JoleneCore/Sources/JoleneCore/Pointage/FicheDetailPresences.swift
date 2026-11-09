import Foundation

/// Première présence d'une mission par arrivée (`DetailPresencesMission.tsx` l.135-139, `presences[0]`) : support de la
/// validation (`valide_par_etablissement`, `valide_le`), des heures retenues après litige et des « Contrôles du
/// pointage » (l.658-692). Les champs de durée de `presences` ne servent jamais au temps travaillé (seuls les créneaux
/// EFFECTIF fermés font foi, `SynthesePresence`). Projection imposée (`colonnes`) : le web lit `select('*')`, le natif
/// ne lit que ce qu'il affiche (aucune coordonnée, aucun code). Lecture tolérante : une valeur illisible vaut nil.
public struct PresenceControlee: Decodable, Equatable, Sendable {
    public static let colonnes = ["id", "pointage_arrivee_le", "valide_par_etablissement", "valide_le",
                                  "distance_etablissement_m", "perimetre_gps_valide", "arrivee_precision_gps_m",
                                  "depart_precision_gps_m", "alerte_teleportation", "heures_ajustees_litige"]
    public static var selection: String { colonnes.joined(separator: ",") }

    public var id: String
    public var pointageArriveeLe: String?
    public var valideParEtablissement: Bool?
    public var valideLe: String?
    public var distanceEtablissementM: Double?
    public var perimetreGpsValide: Bool?
    public var arriveePrecisionGpsM: Double?
    public var departPrecisionGpsM: Double?
    public var alerteTeleportation: Bool?
    public var heuresAjusteesLitige: Double?

    public init(id: String, pointageArriveeLe: String? = nil, valideParEtablissement: Bool? = nil, valideLe: String? = nil,
                distanceEtablissementM: Double? = nil, perimetreGpsValide: Bool? = nil, arriveePrecisionGpsM: Double? = nil,
                departPrecisionGpsM: Double? = nil, alerteTeleportation: Bool? = nil, heuresAjusteesLitige: Double? = nil) {
        self.id = id; self.pointageArriveeLe = pointageArriveeLe; self.valideParEtablissement = valideParEtablissement
        self.valideLe = valideLe; self.distanceEtablissementM = distanceEtablissementM; self.perimetreGpsValide = perimetreGpsValide
        self.arriveePrecisionGpsM = arriveePrecisionGpsM; self.departPrecisionGpsM = departPrecisionGpsM
        self.alerteTeleportation = alerteTeleportation; self.heuresAjusteesLitige = heuresAjusteesLitige
    }

    enum CodingKeys: String, CodingKey {
        case id
        case pointageArriveeLe = "pointage_arrivee_le"
        case valideParEtablissement = "valide_par_etablissement"
        case valideLe = "valide_le"
        case distanceEtablissementM = "distance_etablissement_m"
        case perimetreGpsValide = "perimetre_gps_valide"
        case arriveePrecisionGpsM = "arrivee_precision_gps_m"
        case departPrecisionGpsM = "depart_precision_gps_m"
        case alerteTeleportation = "alerte_teleportation"
        case heuresAjusteesLitige = "heures_ajustees_litige"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        pointageArriveeLe = try? c.decodeIfPresent(String.self, forKey: .pointageArriveeLe)
        valideParEtablissement = try? c.decodeIfPresent(Bool.self, forKey: .valideParEtablissement)
        valideLe = try? c.decodeIfPresent(String.self, forKey: .valideLe)
        distanceEtablissementM = Self.nombre(c, .distanceEtablissementM)
        perimetreGpsValide = try? c.decodeIfPresent(Bool.self, forKey: .perimetreGpsValide)
        arriveePrecisionGpsM = Self.nombre(c, .arriveePrecisionGpsM)
        departPrecisionGpsM = Self.nombre(c, .departPrecisionGpsM)
        alerteTeleportation = try? c.decodeIfPresent(Bool.self, forKey: .alerteTeleportation)
        heuresAjusteesLitige = Self.nombre(c, .heuresAjusteesLitige)
    }

    /// `numeric` PostgREST : nombre JSON, ou chaîne décimale (`toNumberOrNull` du web, l.37-41) ; sinon nil.
    private static func nombre(_ c: KeyedDecodingContainer<CodingKeys>, _ cle: CodingKeys) -> Double? {
        if let valeur = try? c.decodeIfPresent(Double.self, forKey: cle) { return valeur.isFinite ? valeur : nil }
        guard let texte = try? c.decodeIfPresent(String.self, forKey: cle), let valeur = Double(texte), valeur.isFinite else { return nil }
        return valeur
    }
}

/// Fiche lue pour le détail des présences (port `PointagePort.ficheDetail`, tranche T5a) : `mission` nil = mission non
/// lisible (« Mission introuvable », l.184-191) ; `presence` nil = aucune présence (ligne reconstruite, mission non
/// pointée) : ni validation ni contrôles affichés.
public struct FicheDetailPresences: Equatable, Sendable {
    public var mission: MissionPresenceLue?
    public var presence: PresenceControlee?

    public init(mission: MissionPresenceLue?, presence: PresenceControlee?) {
        self.mission = mission; self.presence = presence
    }
}
