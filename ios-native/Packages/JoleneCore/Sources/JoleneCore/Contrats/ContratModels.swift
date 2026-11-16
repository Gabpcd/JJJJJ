import Foundation

// Contrats d'échange des contrats (lot 2, T8 ; `docs/mobile-swift/LOT2_PLAN.md` §2.3, §2.7, §3 T8), déplacés de
// `Models/Lot2Results.swift` où T1 les avait posés (inits de T1 conservés). Clés snake_case explicites ; chaque
// lecture PostgREST porte une projection explicite, jamais `select=*` : les images et IP de signature de
// `contrats_mission` ne sont jamais lues, et `signatures_contrats` n'accorde que des colonnes (correction 22).
// Décodage tolérant : une valeur d'un autre type vaut `nil`, `statut` NULLable (`public.sql` l.68786) vaut `""`
// (même effet que le web : contrat « en attente », jamais terminal).

fileprivate extension KeyedDecodingContainer {
    func tolerant<T: Decodable>(_ type: T.Type, _ cle: Key) -> T? {
        guard let valeur = try? decodeIfPresent(T.self, forKey: cle) else { return nil }
        return valeur
    }
}

/// Messages opérationnels des contrats (aucun texte juridique ; `DECISIONS_LOT2.md`, « Textes opérationnels
/// hors web (T8) »).
public enum MessagesContrats {
    /// Lecture impossible ou contrat hors du compte : texte du pilote, repris tel quel
    /// (`mobile-native/src/workflows/contracts/supabaseGateway.ts` l.21, `unavailable()`).
    public static let indisponible = "Les contrats ne peuvent pas être chargés. Réessayez."
}

/// Mission jointe à une carte de contrat (`missions(intitule, debut_le, fin_le)`, `ListeContrats.tsx` l.69).
public struct MissionResumeContrat: Codable, Equatable, Sendable {
    public var intitule: String?
    public var debutLe: String?
    public var finLe: String?

    public init(intitule: String? = nil, debutLe: String? = nil, finLe: String? = nil) {
        self.intitule = intitule; self.debutLe = debutLe; self.finLe = finLe
    }

    enum CodingKeys: String, CodingKey {
        case intitule
        case debutLe = "debut_le"
        case finLe = "fin_le"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intitule = c.tolerant(String.self, .intitule)
        debutLe = c.tolerant(String.self, .debutLe)
        finLe = c.tolerant(String.self, .finLe)
    }
}

/// Carte de la liste des contrats (`contrats_mission`, RLS l.79073), projection du web (`ListeContrats.tsx` l.69).
public struct ContratResume: Codable, Equatable, Sendable, Identifiable {
    public static let colonnes = ["id", "mission_id", "numero_contrat", "type_contrat", "statut", "soignant_id", "etablissement_id",
                                  "signature_soignant", "signature_etablissement", "cree_le"]
    /// Valeur du paramètre PostgREST `select` (embed `missions` many-to-one, objet ou `null`).
    public static var selection: String { colonnes.joined(separator: ",") + ",missions(intitule,debut_le,fin_le)" }

    public var id: String
    public var missionId: String
    public var statut: String
    public var typeContrat: String?
    public var creeLe: String?
    public var numeroContrat: String?
    public var soignantId: String?
    public var etablissementId: String?
    public var signatureSoignant: Bool?
    public var signatureEtablissement: Bool?
    public var mission: MissionResumeContrat?

    public init(id: String, missionId: String, statut: String, typeContrat: String? = nil, creeLe: String? = nil,
                numeroContrat: String? = nil, soignantId: String? = nil, etablissementId: String? = nil,
                signatureSoignant: Bool? = nil, signatureEtablissement: Bool? = nil, mission: MissionResumeContrat? = nil) {
        self.id = id; self.missionId = missionId; self.statut = statut; self.typeContrat = typeContrat; self.creeLe = creeLe
        self.numeroContrat = numeroContrat; self.soignantId = soignantId; self.etablissementId = etablissementId
        self.signatureSoignant = signatureSoignant; self.signatureEtablissement = signatureEtablissement; self.mission = mission
    }

    enum CodingKeys: String, CodingKey {
        case id, statut
        case missionId = "mission_id"
        case typeContrat = "type_contrat"
        case creeLe = "cree_le"
        case numeroContrat = "numero_contrat"
        case soignantId = "soignant_id"
        case etablissementId = "etablissement_id"
        case signatureSoignant = "signature_soignant"
        case signatureEtablissement = "signature_etablissement"
        case mission = "missions"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        missionId = try c.decode(String.self, forKey: .missionId)
        statut = c.tolerant(String.self, .statut) ?? ""
        typeContrat = c.tolerant(String.self, .typeContrat)
        creeLe = c.tolerant(String.self, .creeLe)
        numeroContrat = c.tolerant(String.self, .numeroContrat)
        soignantId = c.tolerant(String.self, .soignantId)
        etablissementId = c.tolerant(String.self, .etablissementId)
        signatureSoignant = c.tolerant(Bool.self, .signatureSoignant)
        signatureEtablissement = c.tolerant(Bool.self, .signatureEtablissement)
        mission = c.tolerant(MissionResumeContrat.self, .mission)
    }
}

/// Mission du contrat (`ContratMission.tsx` l.218-222 : `missions?select=id, intitule, service, debut_le, fin_le,
/// duree_heures, taux_horaire_base`). Valeurs serveur affichées telles quelles, jamais recalculées.
public struct MissionContrat: Codable, Equatable, Sendable, Identifiable {
    public static let colonnes = ["id", "intitule", "service", "debut_le", "fin_le", "duree_heures", "taux_horaire_base"]
    public static var selection: String { colonnes.joined(separator: ",") }

    public var id: String
    public var intitule: String?
    public var service: String?
    public var debutLe: String?
    public var finLe: String?
    public var dureeHeures: Double?
    public var tauxHoraireBase: Double?

    public init(id: String, intitule: String? = nil, service: String? = nil, debutLe: String? = nil, finLe: String? = nil,
                dureeHeures: Double? = nil, tauxHoraireBase: Double? = nil) {
        self.id = id; self.intitule = intitule; self.service = service; self.debutLe = debutLe; self.finLe = finLe
        self.dureeHeures = dureeHeures; self.tauxHoraireBase = tauxHoraireBase
    }

    enum CodingKeys: String, CodingKey {
        case id, intitule, service
        case debutLe = "debut_le"
        case finLe = "fin_le"
        case dureeHeures = "duree_heures"
        case tauxHoraireBase = "taux_horaire_base"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        intitule = c.tolerant(String.self, .intitule)
        service = c.tolerant(String.self, .service)
        debutLe = c.tolerant(String.self, .debutLe)
        finLe = c.tolerant(String.self, .finLe)
        dureeHeures = c.tolerant(Double.self, .dureeHeures)
        tauxHoraireBase = c.tolerant(Double.self, .tauxHoraireBase)
    }
}

/// Contrat relu (`contrats_mission`, colonnes lues par `ContratMission.tsx`). Statut affiché = statut serveur ; le
/// compte à rebours est dérivé de `cree_le` (`CompteARebours72h`), jamais stocké. `mission`, `etablissementNom`
/// (`fn_etablissements_safe` seulement) et `estCompteTest` (`soignants.est_compte_test`, relu à part) ne viennent
/// jamais de la ligne du contrat.
public struct ContratDetail: Codable, Equatable, Sendable, Identifiable {
    public static let colonnes = ["id", "mission_id", "soignant_id", "etablissement_id", "numero_contrat", "type_contrat", "statut",
                                  "mode_signature", "contenu_html", "hash_document", "storage_path", "contenu_html_rendu_le",
                                  "signature_soignant", "signature_soignant_le", "signature_etablissement",
                                  "signature_etablissement_le", "cree_le"]
    public static var selection: String { colonnes.joined(separator: ",") }

    public var id: String
    public var missionId: String
    public var statut: String
    public var typeContrat: String?
    public var contenuHtml: String?
    public var hashDocument: String?
    public var storagePath: String?
    public var contenuHtmlRenduLe: String?
    public var signatureSoignant: Bool?
    public var signatureEtablissement: Bool?
    public var signatureSoignantLe: String?
    public var signatureEtablissementLe: String?
    public var creeLe: String?
    public var numeroContrat: String?
    public var soignantId: String?
    public var etablissementId: String?
    public var modeSignature: String?
    /// Contexte relu à part (jamais décodé de la ligne).
    public var mission: MissionContrat?
    public var etablissementNom: String?
    public var estCompteTest: Bool

    public init(id: String, missionId: String, statut: String, typeContrat: String? = nil, contenuHtml: String? = nil,
                hashDocument: String? = nil, storagePath: String? = nil, contenuHtmlRenduLe: String? = nil,
                signatureSoignant: Bool? = nil, signatureEtablissement: Bool? = nil, signatureSoignantLe: String? = nil,
                signatureEtablissementLe: String? = nil, creeLe: String? = nil, numeroContrat: String? = nil,
                soignantId: String? = nil, etablissementId: String? = nil, modeSignature: String? = nil,
                mission: MissionContrat? = nil, etablissementNom: String? = nil, estCompteTest: Bool = false) {
        self.id = id; self.missionId = missionId; self.statut = statut; self.typeContrat = typeContrat
        self.contenuHtml = contenuHtml; self.hashDocument = hashDocument; self.storagePath = storagePath
        self.contenuHtmlRenduLe = contenuHtmlRenduLe; self.signatureSoignant = signatureSoignant
        self.signatureEtablissement = signatureEtablissement; self.signatureSoignantLe = signatureSoignantLe
        self.signatureEtablissementLe = signatureEtablissementLe; self.creeLe = creeLe; self.numeroContrat = numeroContrat
        self.soignantId = soignantId; self.etablissementId = etablissementId; self.modeSignature = modeSignature
        self.mission = mission; self.etablissementNom = etablissementNom; self.estCompteTest = estCompteTest
    }

    enum CodingKeys: String, CodingKey {
        case id, statut
        case missionId = "mission_id"
        case typeContrat = "type_contrat"
        case contenuHtml = "contenu_html"
        case hashDocument = "hash_document"
        case storagePath = "storage_path"
        case contenuHtmlRenduLe = "contenu_html_rendu_le"
        case signatureSoignant = "signature_soignant"
        case signatureEtablissement = "signature_etablissement"
        case signatureSoignantLe = "signature_soignant_le"
        case signatureEtablissementLe = "signature_etablissement_le"
        case creeLe = "cree_le"
        case numeroContrat = "numero_contrat"
        case soignantId = "soignant_id"
        case etablissementId = "etablissement_id"
        case modeSignature = "mode_signature"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        missionId = try c.decode(String.self, forKey: .missionId)
        statut = c.tolerant(String.self, .statut) ?? ""
        typeContrat = c.tolerant(String.self, .typeContrat)
        contenuHtml = c.tolerant(String.self, .contenuHtml)
        hashDocument = c.tolerant(String.self, .hashDocument)
        storagePath = c.tolerant(String.self, .storagePath)
        contenuHtmlRenduLe = c.tolerant(String.self, .contenuHtmlRenduLe)
        signatureSoignant = c.tolerant(Bool.self, .signatureSoignant)
        signatureEtablissement = c.tolerant(Bool.self, .signatureEtablissement)
        signatureSoignantLe = c.tolerant(String.self, .signatureSoignantLe)
        signatureEtablissementLe = c.tolerant(String.self, .signatureEtablissementLe)
        creeLe = c.tolerant(String.self, .creeLe)
        numeroContrat = c.tolerant(String.self, .numeroContrat)
        soignantId = c.tolerant(String.self, .soignantId)
        etablissementId = c.tolerant(String.self, .etablissementId)
        modeSignature = c.tolerant(String.self, .modeSignature)
        mission = nil
        etablissementNom = nil
        estCompteTest = false
    }

    /// Preuves de signature lues par les règles de `ContratMissionUi` (T2).
    public var preuve: PreuveSignatureContrat {
        PreuveSignatureContrat(statut: statut, signatureSoignant: signatureSoignant, signatureEtablissement: signatureEtablissement,
                               signatureSoignantLe: signatureSoignantLe, signatureEtablissementLe: signatureEtablissementLe)
    }
}

/// Original contrôlé (§2.5) : SHA-256 du HTML UTF-8 = `hash_document` = SHA-256 des octets Storage
/// (`VerificationOriginal`). Seul ce type est affiché, partagé ou signé ; `empreinte` est l'empreinte affichée et
/// signée ; `numeroContrat` nomme le fichier partagé (`FichierContratTemporaire`).
public struct OriginalContrat: Equatable, Sendable {
    public var contratId: String
    public var html: String
    public var empreinte: String
    public var numeroContrat: String?

    public init(contratId: String, html: String, empreinte: String, numeroContrat: String? = nil) {
        self.contratId = contratId; self.html = html; self.empreinte = empreinte; self.numeroContrat = numeroContrat
    }
}
