import Foundation

/// Contrats de données du parcours soignant, dérivés de
/// `mobile-native/src/data/types.ts` et de `src/integrations/supabase/types.ts`.
/// Les clés JSON sont celles de PostgREST (snake_case) : décodage par `JSONDecoder`
/// sans stratégie de conversion, pour que le contrat soit lisible ligne à ligne.
public struct RoleResult: Codable, Equatable, Sendable {
    public var role: String
    public var etablissementId: String?

    public init(role: String, etablissementId: String? = nil) {
        self.role = role
        self.etablissementId = etablissementId
    }

    enum CodingKeys: String, CodingKey {
        case role
        case etablissementId = "etablissement_id"
    }
}

/// Valeurs exactes de `UserRole` côté web (CLAUDE.md) plus le repli legacy `ETABLISSEMENT`.
public enum UserRole: String, Codable, Sendable, CaseIterable {
    case soignant = "SOIGNANT"
    case adminEtablissement = "ADMIN_ETABLISSEMENT"
    case adminPlateforme = "ADMIN_PLATEFORME"
    case adminGroupe = "ADMIN_GROUPE"
    case etablissementLegacy = "ETABLISSEMENT"

    /// Rôles que l'app native sert ; les autres reçoivent un écran de renvoi vers jolene.app.
    public var isNativelyServed: Bool {
        switch self {
        case .soignant: return true
        case .adminEtablissement, .etablissementLegacy: return false // lot 5
        case .adminPlateforme, .adminGroupe: return false
        }
    }
}

public struct SoignantProfile: Codable, Equatable, Sendable {
    public var id: String
    public var profession: String
    public var adresseLat: Double?
    public var adresseLng: Double?
    public var rayonDeplacementKm: Double?
    public var tousDocumentsValides: Bool
    public var typeContrat: String?
    public var typesContratAcceptes: String?
    public var typeExercice: String?
    public var tauxHoraireMinimum: Double?

    public init(id: String, profession: String, adresseLat: Double? = nil, adresseLng: Double? = nil,
                rayonDeplacementKm: Double? = nil, tousDocumentsValides: Bool = false, typeContrat: String? = nil,
                typesContratAcceptes: String? = nil, typeExercice: String? = nil, tauxHoraireMinimum: Double? = nil) {
        self.id = id; self.profession = profession; self.adresseLat = adresseLat; self.adresseLng = adresseLng
        self.rayonDeplacementKm = rayonDeplacementKm; self.tousDocumentsValides = tousDocumentsValides
        self.typeContrat = typeContrat; self.typesContratAcceptes = typesContratAcceptes
        self.typeExercice = typeExercice; self.tauxHoraireMinimum = tauxHoraireMinimum
    }

    enum CodingKeys: String, CodingKey {
        case id, profession
        case adresseLat = "adresse_lat"
        case adresseLng = "adresse_lng"
        case rayonDeplacementKm = "rayon_deplacement_km"
        case tousDocumentsValides = "tous_documents_valides"
        case typeContrat = "type_contrat"
        case typesContratAcceptes = "types_contrat_acceptes"
        case typeExercice = "type_exercice"
        case tauxHoraireMinimum = "taux_horaire_minimum"
    }

    /// Nullabilité réelle du schéma (`soignants.profession` et `tous_documents_valides` sont
    /// NULLables, `types.ts`) : un NULL PostgREST devient `""` / `false`, comme `!profile.profession`
    /// côté pilote, au lieu de faire échouer tout le décodage (`valueNotFound`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        profession = try c.decodeIfPresent(String.self, forKey: .profession) ?? ""
        adresseLat = try c.decodeIfPresent(Double.self, forKey: .adresseLat)
        adresseLng = try c.decodeIfPresent(Double.self, forKey: .adresseLng)
        rayonDeplacementKm = try c.decodeIfPresent(Double.self, forKey: .rayonDeplacementKm)
        tousDocumentsValides = try c.decodeIfPresent(Bool.self, forKey: .tousDocumentsValides) ?? false
        typeContrat = try c.decodeIfPresent(String.self, forKey: .typeContrat)
        typesContratAcceptes = try c.decodeIfPresent(String.self, forKey: .typesContratAcceptes)
        typeExercice = try c.decodeIfPresent(String.self, forKey: .typeExercice)
        tauxHoraireMinimum = try c.decodeIfPresent(Double.self, forKey: .tauxHoraireMinimum)
    }
}

public struct EtablissementSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var nom: String
    public var adresseVille: String?
    public var adresseCodePostal: String?
    public var adresseLat: Double?
    public var adresseLng: Double?
    public var type: String?
    public var logoUrl: String?

    public init(id: String, nom: String, adresseVille: String? = nil, adresseCodePostal: String? = nil,
                adresseLat: Double? = nil, adresseLng: Double? = nil, type: String? = nil, logoUrl: String? = nil) {
        self.id = id; self.nom = nom; self.adresseVille = adresseVille; self.adresseCodePostal = adresseCodePostal
        self.adresseLat = adresseLat; self.adresseLng = adresseLng; self.type = type; self.logoUrl = logoUrl
    }

    enum CodingKeys: String, CodingKey {
        case id, nom, type
        case adresseVille = "adresse_ville"
        case adresseCodePostal = "adresse_code_postal"
        case adresseLat = "adresse_lat"
        case adresseLng = "adresse_lng"
        case logoUrl = "logo_url"
    }
}

public struct MissionSlot: Codable, Equatable, Sendable, Identifiable {
    public var id: String?
    public var missionId: String?
    /// ISO 8601 tel que renvoyé par PostgREST ; la conversion en `Date` passe par `DateHeureParis`.
    public var debut: String
    public var fin: String?
    public var estPause: Bool
    public var typeCreneau: String

    public init(id: String? = nil, missionId: String? = nil, debut: String, fin: String?, estPause: Bool, typeCreneau: String) {
        self.id = id; self.missionId = missionId; self.debut = debut; self.fin = fin; self.estPause = estPause; self.typeCreneau = typeCreneau
    }

    enum CodingKeys: String, CodingKey {
        case id, debut, fin
        case missionId = "mission_id"
        case estPause = "est_pause"
        case typeCreneau = "type_creneau"
    }
}

/// Ligne `missions` telle que sélectionnée par `MISSION_SELECT` du pilote.
/// Montants et plafond RIST sont des valeurs serveur, jamais recalculées.
public struct MissionRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var intitule: String
    public var description: String?
    public var service: String?
    public var professionRequise: String
    public var specialiteMedicaleRequise: String?
    public var accepteNonSpecialises: Bool?
    public var debutLe: String
    public var finLe: String
    public var dureeHeures: Double?
    public var nbCreneaux: Int?
    public var tauxHoraireBase: Double?
    public var tauxRistPlafonne: Double?
    public var ristPlafondApplique: Bool?
    public var totalBrut: Double?
    public var netAPayer: Double?
    public var estUrgente: Bool
    public var niveauUrgence: Int?
    public var statut: String
    public var etablissementId: String
    public var typeContratRecherche: String?
    public var boosteeLe: String?
    public var modeRemuneration: String?
    public var retrocessionPct: Double?

    enum CodingKeys: String, CodingKey {
        case id, intitule, description, service, statut
        case professionRequise = "profession_requise"
        case specialiteMedicaleRequise = "specialite_medicale_requise"
        case accepteNonSpecialises = "accepte_non_specialises"
        case debutLe = "debut_le"
        case finLe = "fin_le"
        case dureeHeures = "duree_heures"
        case nbCreneaux = "nb_creneaux"
        case tauxHoraireBase = "taux_horaire_base"
        case tauxRistPlafonne = "taux_rist_plafonne"
        case ristPlafondApplique = "rist_plafond_applique"
        case totalBrut = "total_brut"
        case netAPayer = "net_a_payer"
        case estUrgente = "est_urgente"
        case niveauUrgence = "niveau_urgence"
        case etablissementId = "etablissement_id"
        case typeContratRecherche = "type_contrat_recherche"
        case boosteeLe = "boostee_le"
        case modeRemuneration = "mode_remuneration"
        case retrocessionPct = "retrocession_pct"
    }

    /// Nullabilité réelle du schéma (`missions.est_urgente` et `statut` NULLables, `types.ts`) :
    /// `est_urgente: null` vaut `false`, `statut: null` vaut `""` (jamais `OUVERTE`). Une seule
    /// ligne à NULL ne fait plus échouer la lecture des 500 missions de la page.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        intitule = try c.decode(String.self, forKey: .intitule)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        service = try c.decodeIfPresent(String.self, forKey: .service)
        professionRequise = try c.decode(String.self, forKey: .professionRequise)
        specialiteMedicaleRequise = try c.decodeIfPresent(String.self, forKey: .specialiteMedicaleRequise)
        accepteNonSpecialises = try c.decodeIfPresent(Bool.self, forKey: .accepteNonSpecialises)
        debutLe = try c.decode(String.self, forKey: .debutLe)
        finLe = try c.decode(String.self, forKey: .finLe)
        dureeHeures = try c.decodeIfPresent(Double.self, forKey: .dureeHeures)
        nbCreneaux = try c.decodeIfPresent(Int.self, forKey: .nbCreneaux)
        tauxHoraireBase = try c.decodeIfPresent(Double.self, forKey: .tauxHoraireBase)
        tauxRistPlafonne = try c.decodeIfPresent(Double.self, forKey: .tauxRistPlafonne)
        ristPlafondApplique = try c.decodeIfPresent(Bool.self, forKey: .ristPlafondApplique)
        totalBrut = try c.decodeIfPresent(Double.self, forKey: .totalBrut)
        netAPayer = try c.decodeIfPresent(Double.self, forKey: .netAPayer)
        estUrgente = try c.decodeIfPresent(Bool.self, forKey: .estUrgente) ?? false
        niveauUrgence = try c.decodeIfPresent(Int.self, forKey: .niveauUrgence)
        statut = try c.decodeIfPresent(String.self, forKey: .statut) ?? ""
        etablissementId = try c.decode(String.self, forKey: .etablissementId)
        typeContratRecherche = try c.decodeIfPresent(String.self, forKey: .typeContratRecherche)
        boosteeLe = try c.decodeIfPresent(String.self, forKey: .boosteeLe)
        modeRemuneration = try c.decodeIfPresent(String.self, forKey: .modeRemuneration)
        retrocessionPct = try c.decodeIfPresent(Double.self, forKey: .retrocessionPct)
    }

    public init(id: String, intitule: String, description: String?, service: String?, professionRequise: String,
                specialiteMedicaleRequise: String?, accepteNonSpecialises: Bool?, debutLe: String, finLe: String,
                dureeHeures: Double?, nbCreneaux: Int?, tauxHoraireBase: Double?, tauxRistPlafonne: Double?,
                ristPlafondApplique: Bool?, totalBrut: Double?, netAPayer: Double?, estUrgente: Bool, niveauUrgence: Int?,
                statut: String, etablissementId: String, typeContratRecherche: String?, boosteeLe: String?,
                modeRemuneration: String?, retrocessionPct: Double?) {
        self.id = id; self.intitule = intitule; self.description = description; self.service = service
        self.professionRequise = professionRequise; self.specialiteMedicaleRequise = specialiteMedicaleRequise
        self.accepteNonSpecialises = accepteNonSpecialises; self.debutLe = debutLe; self.finLe = finLe
        self.dureeHeures = dureeHeures; self.nbCreneaux = nbCreneaux; self.tauxHoraireBase = tauxHoraireBase
        self.tauxRistPlafonne = tauxRistPlafonne; self.ristPlafondApplique = ristPlafondApplique
        self.totalBrut = totalBrut; self.netAPayer = netAPayer; self.estUrgente = estUrgente
        self.niveauUrgence = niveauUrgence; self.statut = statut; self.etablissementId = etablissementId
        self.typeContratRecherche = typeContratRecherche; self.boosteeLe = boosteeLe
        self.modeRemuneration = modeRemuneration; self.retrocessionPct = retrocessionPct
    }
}

/// Mission enrichie pour l'affichage : établissement, distance et planning dérivé.
public struct Mission: Equatable, Sendable, Identifiable {
    public var record: MissionRecord
    public var etablissement: EtablissementSummary?
    public var distanceKm: Double?
    public var creneauxPlanifies: [MissionSlot]
    public var planningExact: Bool
    public var erreurPlanning: Bool

    public var id: String { record.id }

    public init(record: MissionRecord, etablissement: EtablissementSummary?, distanceKm: Double?,
                creneauxPlanifies: [MissionSlot], planningExact: Bool, erreurPlanning: Bool = false) {
        self.record = record; self.etablissement = etablissement; self.distanceKm = distanceKm
        self.creneauxPlanifies = creneauxPlanifies; self.planningExact = planningExact; self.erreurPlanning = erreurPlanning
    }
}

public struct MissionReadContext: Equatable, Sendable {
    public var userId: String
    public var email: String?
    public var profile: SoignantProfile

    public init(userId: String, email: String?, profile: SoignantProfile) {
        self.userId = userId; self.email = email; self.profile = profile
    }
}

public struct MissionFilters: Equatable, Sendable {
    public enum TypeContrat: String, Sendable { case tous = "TOUS", cdd = "CDD", liberal = "LIBERAL" }
    public enum Horaire: String, Sendable { case tous = "TOUS", jour = "JOUR", nuit = "NUIT", weekend = "WEEKEND" }

    public var ville: String?
    public var rayonKm: Double?
    public var tauxMin: Double?
    public var profession: String?
    public var urgentesOnly: Bool?
    public var typeContrat: TypeContrat?
    public var horaire: Horaire?
    public var etablissementId: String?

    public init(ville: String? = nil, rayonKm: Double? = nil, tauxMin: Double? = nil, profession: String? = nil,
                urgentesOnly: Bool? = nil, typeContrat: TypeContrat? = nil, horaire: Horaire? = nil, etablissementId: String? = nil) {
        self.ville = ville; self.rayonKm = rayonKm; self.tauxMin = tauxMin; self.profession = profession
        self.urgentesOnly = urgentesOnly; self.typeContrat = typeContrat; self.horaire = horaire; self.etablissementId = etablissementId
    }
}
