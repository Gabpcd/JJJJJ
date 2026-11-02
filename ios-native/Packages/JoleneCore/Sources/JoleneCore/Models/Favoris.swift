import Foundation

// Contrats d'échange de `FavorisPort` (lot 1, T4b), déplacés de `Models/Lot1Results.swift` par la
// tranche qui les livre (inits de T1 conservés). Décodage tolérant : seules les clés qui conditionnent
// une action sont requises (`mission_id` pour l'étoile, `etablissement_id` pour le retrait).

/// Ligne `missions_sauvegardees` relue sous RLS (`soignant_id = auth.uid()`), avec la mission jointe
/// (`missions(...)`, `SupabaseFavorisGateway.selectSauvegardees`) quand la RLS des missions la laisse lire.
public struct MissionSauvegardee: Codable, Equatable, Sendable, Identifiable {
    /// Mission jointe : colonnes lues par `MesFavorisSoignant.tsx` (l.42-44) pour l'affichage et pour le
    /// filtre `OUVERTE` + début futur (`FavorisRegles.missionsAffichees`), hors montants (non affichés
    /// par la page web). Seul `id` est requis ; une valeur d'un autre type est ignorée seule.
    public struct Apercu: Codable, Equatable, Sendable {
        public var id: String
        public var intitule: String?
        public var debutLe: String?
        public var finLe: String?
        public var dureeHeures: Double?
        public var nbCreneaux: Int?
        public var statut: String?

        public init(id: String, intitule: String?, debutLe: String?, finLe: String?, dureeHeures: Double?,
                    nbCreneaux: Int?, statut: String?) {
            self.id = id; self.intitule = intitule; self.debutLe = debutLe; self.finLe = finLe
            self.dureeHeures = dureeHeures; self.nbCreneaux = nbCreneaux; self.statut = statut
        }

        /// Aperçu d'une ligne `missions` déjà lue (monde démo : jointure reconstituée à l'ajout).
        public init(_ record: MissionRecord) {
            self.init(id: record.id, intitule: record.intitule, debutLe: record.debutLe, finLe: record.finLe,
                      dureeHeures: record.dureeHeures, nbCreneaux: record.nbCreneaux, statut: record.statut)
        }

        enum CodingKeys: String, CodingKey {
            case id, intitule, statut
            case debutLe = "debut_le"
            case finLe = "fin_le"
            case dureeHeures = "duree_heures"
            case nbCreneaux = "nb_creneaux"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            intitule = try? c.decodeIfPresent(String.self, forKey: .intitule)
            debutLe = try? c.decodeIfPresent(String.self, forKey: .debutLe)
            finLe = try? c.decodeIfPresent(String.self, forKey: .finLe)
            dureeHeures = try? c.decodeIfPresent(Double.self, forKey: .dureeHeures)
            nbCreneaux = FavorisDecodage.entier(c, .nbCreneaux)
            statut = try? c.decodeIfPresent(String.self, forKey: .statut)
        }

        /// Horaires formatables (`FormatMission`), comme `MissionRecord.horaires`.
        public var horaires: MissionHoraires {
            MissionHoraires(debutLe: debutLe, finLe: finLe, dureeHeures: dureeHeures, nbCreneaux: nbCreneaux)
        }
    }

    public var id: String
    public var missionId: String
    public var creeLe: String?
    /// `nil` : jointure absente, masquée par la RLS (`null`) ou illisible — la ligne garde l'étoile
    /// allumée, la mission n'est pas listée dans « Mes favoris ».
    public var mission: Apercu?

    public init(id: String, missionId: String, creeLe: String?, mission: Apercu? = nil) {
        self.id = id; self.missionId = missionId; self.creeLe = creeLe; self.mission = mission
    }

    enum CodingKeys: String, CodingKey {
        case id
        case missionId = "mission_id"
        case creeLe = "cree_le"
        case mission = "missions"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        missionId = try c.decode(String.self, forKey: .missionId)
        creeLe = try? c.decodeIfPresent(String.self, forKey: .creeLe)
        mission = try? c.decodeIfPresent(Apercu.self, forKey: .mission)
    }
}

/// Élément de `fn_mes_favoris_etablissements` (jsonb_agg, l.41844-41852 du dump). Seul
/// `etablissement_id` conditionne une action (retrait) ; `nom` est remplacé par celui de
/// `fn_etablissements_safe` quand la ligne existe (`SupabaseFavorisGateway`).
public struct EtablissementFavori: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var nom: String?
    public var ville: String?
    public var logoUrl: String?
    public var typeEtablissement: String?
    public var nbMissionsOuvertes: Int?
    public var creeLe: String?

    public init(id: String, nom: String?, ville: String?, logoUrl: String?, typeEtablissement: String?,
                nbMissionsOuvertes: Int?, creeLe: String?) {
        self.id = id; self.nom = nom; self.ville = ville; self.logoUrl = logoUrl
        self.typeEtablissement = typeEtablissement; self.nbMissionsOuvertes = nbMissionsOuvertes; self.creeLe = creeLe
    }

    enum CodingKeys: String, CodingKey {
        case id = "etablissement_id"
        case nom, ville
        case logoUrl = "logo_url"
        case typeEtablissement = "type_etablissement"
        case nbMissionsOuvertes = "nb_missions_ouvertes"
        case creeLe = "cree_le"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        nom = try? c.decodeIfPresent(String.self, forKey: .nom)
        ville = try? c.decodeIfPresent(String.self, forKey: .ville)
        logoUrl = try? c.decodeIfPresent(String.self, forKey: .logoUrl)
        typeEtablissement = try? c.decodeIfPresent(String.self, forKey: .typeEtablissement)
        nbMissionsOuvertes = FavorisDecodage.entier(c, .nbMissionsOuvertes)
        creeLe = try? c.decodeIfPresent(String.self, forKey: .creeLe)
    }
}

/// Lecture tolérante d'un entier JSON : `count(*)` ou `nb_creneaux` relayés en nombre réel (`3.0`) sont
/// acceptés s'ils sont entiers ; tout autre type est ignoré.
enum FavorisDecodage {
    static func entier<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ cle: K) -> Int? {
        if let entier = try? c.decodeIfPresent(Int.self, forKey: cle) { return entier }
        guard let reel = try? c.decodeIfPresent(Double.self, forKey: cle), reel.isFinite, reel.rounded() == reel,
              abs(reel) < 9_007_199_254_740_992 else { return nil }
        return Int(reel)
    }
}
