import Foundation

// Contrats d'échange des ports du lot 2 (`Ports/Lot2Ports.swift`, blueprint `docs/mobile-swift/LOT2_PLAN.md`
// §2.3-§2.4). Posés par T1 pour que les tranches suivantes ne modifient ni `Gateways` ni les protocoles ;
// chaque tranche (T3 pointage, T5a/T5b, T6 documents, T8 contrats) complète ici le contrat de son domaine
// (champs optionnels, décodage tolérant) ou le déplace dans son dossier (`Pointage/`, `Documents/`,
// `Contrats/`). Clés snake_case explicites (PRINCIPES §2). `JoleneError.Kind` n'est pas étendu : refus
// métier = issues ; erreurs de transport = `JoleneError`. Les sources Swift ne nomment jamais les clés du
// code suivant que renvoie le scan (garde de T0, décision 8) : les décodeurs sont des listes blanches.

/// Décodage d'une valeur inconnue en `nil` plutôt qu'en échec du document entier (lecture tolérante).
private extension KeyedDecodingContainer {
    func tolerant<T: Decodable>(_ type: T.Type, _ cle: Key) -> T? {
        guard let valeur = try? decodeIfPresent(T.self, forKey: cle) else { return nil }
        return valeur
    }

    /// Tableau tolérant ÉLÉMENT par élément : un élément mal formé est écarté, les autres sont gardés ; une valeur
    /// qui n'est pas un tableau donne `[]`.
    func tolerantParElement<T: Decodable>(_ type: T.Type, _ cle: Key) -> [T] {
        guard let elements = try? decodeIfPresent([ElementTolerant<T>].self, forKey: cle) else { return [] }
        return elements.compactMap(\.valeur)
    }
}

/// Élément d'un tableau décodé sans faire échouer ses voisins.
private struct ElementTolerant<T: Decodable>: Decodable {
    let valeur: T?

    init(from decoder: Decoder) throws {
        valeur = try? T(from: decoder)
    }
}

/// Forme `{error}` HTTP 200 des RPC jsonb (`jsonb_build_object('error', …)`) et clés discriminantes d'un succès :
/// une réponse de refus ne se décode jamais en état vide plausible (revue fraîche de T1, blueprint §2.4).
private enum CleRefus: String, CodingKey {
    case error
}

private func exigerSucces<K: CodingKey>(_ decoder: Decoder, cles: [K], type: String) throws {
    if try decoder.container(keyedBy: CleRefus.self).contains(.error) {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                debugDescription: "\(type) : réponse de refus {error}, jamais un état vide"))
    }
    let conteneur = try decoder.container(keyedBy: K.self)
    for cle in cles where !conteneur.contains(cle) {
        throw DecodingError.keyNotFound(cle, .init(codingPath: decoder.codingPath,
                                                    debugDescription: "\(type) : clé discriminante absente"))
    }
}

// MARK: - Pointage (T3)

/// `prochain_type_scan`, `type_scan_effectue`, `scans_pointage.type_scan`.
public enum TypeScan: String, Codable, CaseIterable, Sendable {
    case ouverture = "OUVERTURE"
    case fermeture = "FERMETURE"
}

/// Segment `EFFECTIF` renvoyé par `fn_etat_pointage_mission` (`segments[{id, debut, fin}]`).
public struct SegmentPointage: Codable, Equatable, Sendable {
    public var id: String
    public var debut: String
    public var fin: String?

    public init(id: String, debut: String, fin: String?) { self.id = id; self.debut = debut; self.fin = fin }
}

/// `fn_etat_pointage_mission(p_mission_id)` (`public.sql` l.35180-35190), en liste blanche :
/// `code_pointage_actif` (nul pour le soignant, l.35188) et `est_etab` (nul pour tout compte sans
/// établissement) ne sont jamais décodés. Un refus `{error}` HTTP 200 (l.35162, l.35169) est traité par la
/// gateway (T3, `.refuse` verbatim) ; le décodeur le refuse aussi, comme un objet sans `nb_scans` ni
/// `prochain_type_scan` (clés toujours présentes dans un succès, valeurs nulles comprises). Tolérance par
/// valeur et par segment.
public struct EtatPointage: Codable, Equatable, Sendable {
    public var statut: String?
    public var intitule: String?
    public var prochainTypeScan: TypeScan?
    public var nbScans: Int?
    public var segmentOuvert: Bool?
    public var segments: [SegmentPointage]

    public init(statut: String? = nil, intitule: String? = nil, prochainTypeScan: TypeScan? = nil, nbScans: Int? = nil,
                segmentOuvert: Bool? = nil, segments: [SegmentPointage] = []) {
        self.statut = statut; self.intitule = intitule; self.prochainTypeScan = prochainTypeScan; self.nbScans = nbScans
        self.segmentOuvert = segmentOuvert; self.segments = segments
    }

    enum CodingKeys: String, CodingKey {
        case statut, intitule, segments
        case prochainTypeScan = "prochain_type_scan"
        case nbScans = "nb_scans"
        case segmentOuvert = "segment_ouvert"
    }

    public init(from decoder: Decoder) throws {
        try exigerSucces(decoder, cles: [CodingKeys.nbScans, .prochainTypeScan], type: "EtatPointage")
        let c = try decoder.container(keyedBy: CodingKeys.self)
        statut = c.tolerant(String.self, .statut)
        intitule = c.tolerant(String.self, .intitule)
        prochainTypeScan = c.tolerant(TypeScan.self, .prochainTypeScan)
        nbScans = c.tolerant(Int.self, .nbScans)
        segmentOuvert = c.tolerant(Bool.self, .segmentOuvert)
        segments = c.tolerantParElement(SegmentPointage.self, .segments)
    }
}

/// Succès de `fn_scanner_code_pointage(p_code, p_metadata)` (`public.sql` l.55871-55885), en liste
/// blanche : le code suivant et sa signature, renvoyés au soignant tant que B1 n'est pas mergée, ne sont
/// ni décodés, ni conservés, ni journalisés (correction 9). `numero_scan` conditionne la relecture.
public struct ScanEnregistre: Codable, Equatable, Sendable {
    public var typeScanEffectue: TypeScan?
    public var prochainTypeScan: TypeScan?
    public var creneauEffectifId: String?
    public var horodatageEffectif: String?
    public var horodatageArrondi: String?
    public var numeroScan: Int
    public var validationEtabRequise: Bool?

    public init(typeScanEffectue: TypeScan?, prochainTypeScan: TypeScan?, creneauEffectifId: String?, horodatageEffectif: String?,
                horodatageArrondi: String?, numeroScan: Int, validationEtabRequise: Bool?) {
        self.typeScanEffectue = typeScanEffectue; self.prochainTypeScan = prochainTypeScan
        self.creneauEffectifId = creneauEffectifId; self.horodatageEffectif = horodatageEffectif
        self.horodatageArrondi = horodatageArrondi; self.numeroScan = numeroScan; self.validationEtabRequise = validationEtabRequise
    }

    enum CodingKeys: String, CodingKey {
        case typeScanEffectue = "type_scan_effectue"
        case prochainTypeScan = "prochain_type_scan"
        case creneauEffectifId = "creneau_effectif_id"
        case horodatageEffectif = "horodatage_effectif"
        case horodatageArrondi = "horodatage_arrondi"
        case numeroScan = "numero_scan"
        case validationEtabRequise = "validation_etab_requise"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        numeroScan = try c.decode(Int.self, forKey: .numeroScan)
        typeScanEffectue = c.tolerant(TypeScan.self, .typeScanEffectue)
        prochainTypeScan = c.tolerant(TypeScan.self, .prochainTypeScan)
        creneauEffectifId = c.tolerant(String.self, .creneauEffectifId)
        horodatageEffectif = c.tolerant(String.self, .horodatageEffectif)
        horodatageArrondi = c.tolerant(String.self, .horodatageArrondi)
        validationEtabRequise = c.tolerant(Bool.self, .validationEtabRequise)
    }
}

/// Ligne `scans_pointage` relue pour la réconciliation (blueprint §3 T3, corrigé v2) : projection
/// imposée, jamais `code_saisi`, `ip_address`, `latitude` ni `longitude` (pourtant lisibles, `sp_select`
/// l.79931). `mission_id` (revue fraîche de T1) : `RecuScan.reconcilier` vérifie lui-même la mission du reçu.
public struct PreuveScan: Codable, Equatable, Sendable {
    public static let colonnes = ["id", "mission_id", "numero_scan", "type_scan", "scanne_le", "id_terminal", "precision_gps_m"]
    /// Valeur du paramètre PostgREST `select`.
    public static var selection: String { colonnes.joined(separator: ",") }

    public var id: String
    public var missionId: String?
    public var numeroScan: Int?
    public var typeScan: TypeScan?
    public var scanneLe: String?
    public var idTerminal: String?
    public var precisionGpsM: Double?

    public init(id: String, missionId: String? = nil, numeroScan: Int? = nil, typeScan: TypeScan? = nil,
                scanneLe: String? = nil, idTerminal: String? = nil, precisionGpsM: Double? = nil) {
        self.id = id; self.missionId = missionId; self.numeroScan = numeroScan; self.typeScan = typeScan
        self.scanneLe = scanneLe; self.idTerminal = idTerminal; self.precisionGpsM = precisionGpsM
    }

    enum CodingKeys: String, CodingKey {
        case id
        case missionId = "mission_id"
        case numeroScan = "numero_scan"
        case typeScan = "type_scan"
        case scanneLe = "scanne_le"
        case idTerminal = "id_terminal"
        case precisionGpsM = "precision_gps_m"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        missionId = c.tolerant(String.self, .missionId)
        numeroScan = c.tolerant(Int.self, .numeroScan)
        typeScan = c.tolerant(TypeScan.self, .typeScan)
        scanneLe = c.tolerant(String.self, .scanneLe)
        idTerminal = c.tolerant(String.self, .idTerminal)
        precisionGpsM = c.tolerant(Double.self, .precisionGpsM)
    }
}

/// `p_metadata` du scan, clés identiques à `PointageRotatifSoignant.tsx` l.122-126 : `id_terminal`, puis
/// `latitude`, `longitude`, `precision_gps_m` seulement pour une position disponible (P3 ; décision 5 :
/// aucune coordonnée en précision réduite). Jamais journalisé (coordonnées).
public struct MetadonneesScan: Encodable, Equatable, Sendable {
    public let idTerminal: String
    public let latitude: Double?
    public let longitude: Double?
    public let precisionGpsM: Double?
    /// État GPS consigné dans le reçu (`RecuScan.gps`).
    public let gps: RecuScan.Gps

    /// `observation` nil : position jamais demandée (consentement absent ou refusé).
    public init(idTerminal: String, observation: ObservationGps?) {
        self.idTerminal = idTerminal
        gps = RecuScan.Gps(observation: observation)
        if case let .disponible(latitude, longitude, precision)? = observation {
            self.latitude = latitude; self.longitude = longitude; precisionGpsM = precision
        } else {
            latitude = nil; longitude = nil; precisionGpsM = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case latitude, longitude
        case idTerminal = "id_terminal"
        case precisionGpsM = "precision_gps_m"
    }
}

/// Instantané des présences du soignant (T3 : décodage tolérant des quatre requêtes de
/// `PresencesSoignant.tsx`, sans l'embed `etablissements`, regroupement par mission, listes dérivées).
/// T1 pose le contenant ; T3 le complète ou le déplace dans `Pointage/InstantanePresences.swift`.
public struct InstantanePresences: Equatable, Sendable {
    public var missions: [MissionRecord]
    public var creneaux: [MissionSlot]

    public init(missions: [MissionRecord] = [], creneaux: [MissionSlot] = []) {
        self.missions = missions; self.creneaux = creneaux
    }
}

/// Issue d'un scan ou de sa réconciliation (blueprint §2.3, §2.5). Jamais de renvoi automatique.
public enum IssueScan: Equatable, Sendable {
    /// Accepté par le serveur ET relu (`fn_etat_pointage_mission` et `scans_pointage`).
    case enregistre(typeScan: TypeScan?, numeroScan: Int)
    /// Exception PostgREST ou refus HTTP 200 : rollback prouvé, message serveur verbatim (décision 6).
    case refuse(sqlstate: String?, message: String)
    /// Réponse perdue, délai dépassé ou relecture trop tôt : reçu `started` gardé, réconciliation par relecture,
    /// jamais un second envoi.
    case incertain
    /// Hors ligne : aucun appel, reçu `not_sent`.
    case nonEnvoye
    /// Relecture ≥ 8 s après l'envoi sans preuve : le serveur n'a rien reçu (nouvelle saisie demandée). Le reçu est
    /// effacé (`ReceiptJournal.effacer`) après cette relecture.
    case nonRecu
    /// Relecture sans preuve datée AVANT le passage `started` (heure de l'appareil reculée,
    /// `RecuScan.VerdictReconciliation.horlogeIncoherente`) : l'écoulement des 8 s n'est pas établi. Reçu `started`
    /// gardé, aucun nouveau scan, aucune relecture en boucle ; affiché comme `RecuScan.messageIllisible`, recours web
    /// (consigne T3 de `DECISIONS_LOT2.md`). Redevient `.nonRecu` dès que l'horloge dépasse `demarreLe + 8 s`.
    case horlogeIncoherente
}

extension IssueScan {
    /// Issue de `PointagePort.reconcilier` pour un verdict de `RecuScan.reconcilier(scans:relueLe:)` : aucune ne
    /// rouvre l'envoi sans preuve. `.recu` → `.enregistre` (numéro et type relus) ; `.aRelire` → `.incertain` (rien
    /// n'est prouvé) ; `.nonRecu` → `.nonRecu` ; `.horlogeIncoherente` → `.horlogeIncoherente`. Une preuve sans
    /// numéro (que `reconcilier` ne rend jamais) ne prouve rien : `.incertain`.
    public init(reconciliation verdict: RecuScan.VerdictReconciliation) {
        switch verdict {
        case let .recu(preuve):
            if let numero = preuve.numeroScan {
                self = .enregistre(typeScan: preuve.typeScan, numeroScan: numero)
            } else {
                self = .incertain
            }
        case .aRelire: self = .incertain
        case .nonRecu: self = .nonRecu
        case .horlogeIncoherente: self = .horlogeIncoherente
        }
    }
}

/// `fn_relancer_validation_presence(p_mission_id)` (l.53013) : `message` serveur verbatim quand il existe.
public enum IssueRelance: Equatable, Sendable {
    case envoyee(message: String?)
    case refusee(message: String)
}

/// Synthèse serveur de `fn_presences_detail_mission` (l.48938-48958) affichée par la carte du détail
/// (`DetailPresencesMission.tsx` l.338-339). `heures_reelles` n'est jamais décodée (le web l'écarte,
/// l.341-344 : les `EFFECTIF` fermés font foi). Un refus `{error}` HTTP 200 (l.48918, l.48922) ou un objet
/// sans le booléen `pointage_effectue` (présent dans les deux formes de succès, l.48928 et l.48939) ne se
/// décode pas : `DetailPresences.resume` reste nil et la carte est masquée (§2.4), jamais affichée vide.
public struct ResumePresencesServeur: Codable, Equatable, Sendable {
    public var pointageEffectue: Bool
    public var dureePauseMin: Double?
    public var distanceM: Double?
    public var alerteTeleportation: Bool?
    public var methodeArrivee: String?
    public var methodeDepart: String?

    public init(pointageEffectue: Bool, dureePauseMin: Double? = nil, distanceM: Double? = nil,
                alerteTeleportation: Bool? = nil, methodeArrivee: String? = nil, methodeDepart: String? = nil) {
        self.pointageEffectue = pointageEffectue; self.dureePauseMin = dureePauseMin; self.distanceM = distanceM
        self.alerteTeleportation = alerteTeleportation; self.methodeArrivee = methodeArrivee; self.methodeDepart = methodeDepart
    }

    enum CodingKeys: String, CodingKey {
        case pointageEffectue = "pointage_effectue"
        case dureePauseMin = "duree_pause_min"
        case distanceM = "distance_m"
        case alerteTeleportation = "alerte_teleportation"
        case methodeArrivee = "methode_arrivee"
        case methodeDepart = "methode_depart"
    }

    public init(from decoder: Decoder) throws {
        try exigerSucces(decoder, cles: [CodingKeys.pointageEffectue], type: "ResumePresencesServeur")
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pointageEffectue = try c.decode(Bool.self, forKey: .pointageEffectue)
        dureePauseMin = c.tolerant(Double.self, .dureePauseMin)
        distanceM = c.tolerant(Double.self, .distanceM)
        alerteTeleportation = c.tolerant(Bool.self, .alerteTeleportation)
        methodeArrivee = c.tolerant(String.self, .methodeArrivee)
        methodeDepart = c.tolerant(String.self, .methodeDepart)
    }
}

/// Détail des présences d'une mission (T3/T5a) : créneaux relus (synthèse par `SynthesePresence`), puis
/// la synthèse serveur, nil si `fn_presences_detail_mission` refuse (`{error}` HTTP 200) : carte masquée,
/// reste de l'écran rendu.
public struct DetailPresences: Equatable, Sendable {
    public var missionId: String
    public var creneaux: [MissionSlot]
    public var resume: ResumePresencesServeur?

    public init(missionId: String, creneaux: [MissionSlot] = [], resume: ResumePresencesServeur? = nil) {
        self.missionId = missionId; self.creneaux = creneaux; self.resume = resume
    }
}

// MARK: - Contestation (T5b)

/// Ligne `litiges` relue par `presence_id` (le serveur rattache la dernière présence, l.46521-46527).
public struct LitigePresence: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var statut: String?
    public var presenceId: String?
    public var missionId: String?
    public var typeLitige: String?
    public var creeLe: String?

    public init(id: String, statut: String? = nil, presenceId: String? = nil, missionId: String? = nil,
                typeLitige: String? = nil, creeLe: String? = nil) {
        self.id = id; self.statut = statut; self.presenceId = presenceId; self.missionId = missionId
        self.typeLitige = typeLitige; self.creeLe = creeLe
    }

    enum CodingKeys: String, CodingKey {
        case id, statut
        case presenceId = "presence_id"
        case missionId = "mission_id"
        case typeLitige = "type_litige"
        case creeLe = "cree_le"
    }
}

public enum IssueContestation: Equatable, Sendable {
    /// Litige créé par `fn_ouvrir_litige_rate_limited` ET relu.
    case ouverte(LitigePresence)
    /// `{error}` serveur verbatim (accès, motif, fenêtre fermée, 3 par heure…).
    case refusee(message: String)
}

// MARK: - Notation (T5a)

/// Les quatre critères de `fn_creer_notation_mission` (`p_critere_1` … `p_critere_4`).
public struct CriteresNotation: Equatable, Sendable {
    public var critere1: Int
    public var critere2: Int
    public var critere3: Int
    public var critere4: Int

    public init(_ critere1: Int, _ critere2: Int, _ critere3: Int, _ critere4: Int) {
        self.critere1 = critere1; self.critere2 = critere2; self.critere3 = critere3; self.critere4 = critere4
    }

    /// Note globale seule : répliquée sur les quatre critères (`NotationRapide.tsx` l.47).
    public static func repliques(note: Int) -> CriteresNotation { CriteresNotation(note, note, note, note) }

    public var valeurs: [Int] { [critere1, critere2, critere3, critere4] }
}

public enum IssueNotation: Equatable, Sendable {
    case enregistree
    /// « Mission déjà notée pour ce sens » : silencieux, comme le web (`NotationRapide.tsx` l.58-61).
    case dejaNotee
    case refusee(message: String)
}

// MARK: - Documents (T6)

/// Ligne de `documents_requis_par_profession` (table paramétrée : aucune règle juridique en dur).
public struct ExigenceDocument: Codable, Equatable, Sendable {
    public var id: String?
    public var profession: String?
    public var typeDocument: String
    public var estCritique: Bool?
    public var aExpiration: Bool?
    public var dureeValiditeMois: Int?
    public var description: String?
    public var typeExerciceRequis: String?

    public init(id: String? = nil, profession: String? = nil, typeDocument: String, estCritique: Bool? = nil,
                aExpiration: Bool? = nil, dureeValiditeMois: Int? = nil, description: String? = nil,
                typeExerciceRequis: String? = nil) {
        self.id = id; self.profession = profession; self.typeDocument = typeDocument; self.estCritique = estCritique
        self.aExpiration = aExpiration; self.dureeValiditeMois = dureeValiditeMois; self.description = description
        self.typeExerciceRequis = typeExerciceRequis
    }

    enum CodingKeys: String, CodingKey {
        case id, profession, description
        case typeDocument = "type_document"
        case estCritique = "est_critique"
        case aExpiration = "a_expiration"
        case dureeValiditeMois = "duree_validite_mois"
        case typeExerciceRequis = "type_exercice_requis"
    }
}

/// Ligne `documents_soignants` relue sous RLS. Dates de validité : valeurs serveur, jamais écrites par
/// le client ; statut affiché REJETE avant EXPIRE (T6/T7).
public struct DocumentSoignant: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var typeDocument: String
    public var libelle: String?
    public var s3Cle: String?
    public var nomFichier: String?
    public var typeMime: String?
    public var tailleOctets: Int?
    public var valideJusqua: String?
    public var statutVerification: String?
    public var motifRejet: String?
    public var televerseLe: String?
    public var verificationAttemptId: String?
    // T6 : projection de `DocumentsSoignant.tsx` l.199 (`valide_depuis`, `est_critique`,
    // `profession_certifiee:resultat_ia->>profession_certifiee`), champs additifs.
    public var valideDepuis: String?
    public var estCritique: Bool?
    /// `resultat_ia->>profession_certifiee` seulement : le reste de `resultat_ia` n'est jamais lu.
    public var professionCertifiee: String?
    /// Revue fraîche de T6 (m1) : bucket de l'objet, lu pour la consultation comme le web
    /// (`doc.s3_bucket || 'jolene-documents'`, `DocumentsSoignant.tsx` l.438).
    public var s3Bucket: String?

    public init(id: String, typeDocument: String, libelle: String? = nil, s3Cle: String? = nil, nomFichier: String? = nil,
                typeMime: String? = nil, tailleOctets: Int? = nil, valideJusqua: String? = nil,
                statutVerification: String? = nil, motifRejet: String? = nil, televerseLe: String? = nil,
                verificationAttemptId: String? = nil, valideDepuis: String? = nil, estCritique: Bool? = nil,
                professionCertifiee: String? = nil, s3Bucket: String? = nil) {
        self.id = id; self.typeDocument = typeDocument; self.libelle = libelle; self.s3Cle = s3Cle
        self.nomFichier = nomFichier; self.typeMime = typeMime; self.tailleOctets = tailleOctets
        self.valideJusqua = valideJusqua; self.statutVerification = statutVerification; self.motifRejet = motifRejet
        self.televerseLe = televerseLe; self.verificationAttemptId = verificationAttemptId
        self.valideDepuis = valideDepuis; self.estCritique = estCritique; self.professionCertifiee = professionCertifiee
        self.s3Bucket = s3Bucket
    }

    enum CodingKeys: String, CodingKey {
        case id, libelle
        case typeDocument = "type_document"
        case s3Cle = "s3_cle"
        case nomFichier = "nom_fichier"
        case typeMime = "type_mime"
        case tailleOctets = "taille_octets"
        case valideJusqua = "valide_jusqua"
        case statutVerification = "statut_verification"
        case motifRejet = "motif_rejet"
        case televerseLe = "televerse_le"
        case verificationAttemptId = "verification_attempt_id"
        case valideDepuis = "valide_depuis"
        case estCritique = "est_critique"
        case professionCertifiee = "profession_certifiee"
        case s3Bucket = "s3_bucket"
    }
}

/// Dossier documentaire : exigences paramétrées, documents, attestation santé (valeur serveur). Règles
/// d'affichage dérivées (T6) : `Documents/DossierDocuments.swift`.
public struct DossierDocuments: Equatable, Sendable {
    /// Exigences DÉJÀ filtrées par profession et `type_exercice` (`DossierDocuments.assembler`).
    public var exigences: [ExigenceDocument]
    /// Pièces actives (ni supprimées ni révoquées), les plus récentes d'abord (`televerse_le` décroissant).
    public var documents: [DocumentSoignant]
    public var attestationSanteSigneeLe: String?
    /// T6 : profil documentaire relu (`soignants`) ; nil sans dossier professionnel (web : aucune pièce chargée).
    public var profil: SoignantExigencesDocuments?

    public init(exigences: [ExigenceDocument] = [], documents: [DocumentSoignant] = [], attestationSanteSigneeLe: String? = nil,
                profil: SoignantExigencesDocuments? = nil) {
        self.exigences = exigences; self.documents = documents; self.attestationSanteSigneeLe = attestationSanteSigneeLe
        self.profil = profil
    }
}

/// Fichier choisi puis normalisé (T6/T7 : HEIC/HEIF → JPEG, ≤ 10 Mo, `ClassementDocument`). Les octets
/// ne sont jamais conservés : ils passent seulement à `DocumentsPort.envoyer(recu:octets:context:)`.
public struct FichierChoisi: Equatable, Sendable {
    public var nom: String
    public var mime: MimeDocument
    public var tailleOctets: Int

    public init(nom: String, mime: MimeDocument, tailleOctets: Int) {
        self.nom = nom; self.mime = mime; self.tailleOctets = tailleOctets
    }
}

/// Verdict de l'edge `verify-document` (`{success:true, verdict}`).
public enum VerdictDocument: String, Codable, CaseIterable, Sendable {
    case verifie = "VERIFIE"
    case rejete = "REJETE"
    case enAttente = "EN_ATTENTE"
    case revueManuelleRequise = "REVUE_MANUELLE_REQUISE"
}

/// Issue d'un envoi de justificatif ou de sa réconciliation (§2.5). Jamais de renvoi automatique.
public enum IssueEnvoiDocument: Equatable, Sendable {
    /// Ligne enregistrée et `verify-document` demandée une fois, ou relue `EN_ATTENTE` avec une tentative en cours :
    /// verdict attendu en ligne.
    case verificationDemandee(documentId: String)
    /// Ligne enregistrée sans vérification en cours : revue manuelle relue (`REVUE_MANUELLE_REQUISE`), aucune tentative
    /// relue, ou `verify-document` en erreur. « Revérifier » reste un geste manuel, jamais automatique.
    case enregistre(documentId: String)
    /// Ligne relue dont le verdict est déjà rendu (`VERIFIE`, `REJETE`, `EXPIRE`…), après un relancement : ni
    /// vérification ni suivi, le badge de la pièce porte le verdict (revue fraîche de T6, m-c).
    case verdictRendu(documentId: String)
    /// Refus serveur (`error_code` de `fn_remplacer_document_soignant`, Storage) ; message du web (T7).
    case refuse(code: String)
    case incertain
    case nonEnvoye
}

/// `fn_verifier_coherence_documents()` (l.65809) : `problemes` est un tableau de textes (l.65853-65872).
public struct CoherenceDocuments: Codable, Equatable, Sendable {
    public var coherent: Bool
    public var problemes: [String]
    public var message: String?

    public init(coherent: Bool, problemes: [String] = [], message: String? = nil) {
        self.coherent = coherent; self.problemes = problemes; self.message = message
    }

    enum CodingKeys: String, CodingKey { case coherent, problemes, message }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        coherent = try c.decode(Bool.self, forKey: .coherent)
        problemes = c.tolerant([String].self, .problemes) ?? []
        message = c.tolerant(String.self, .message)
    }
}

// MARK: - Contrats (T8)

/// Carte de la liste des contrats (`contrats_mission`, RLS l.79073).
public struct ContratResume: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var missionId: String
    public var statut: String
    public var typeContrat: String?
    public var creeLe: String?

    public init(id: String, missionId: String, statut: String, typeContrat: String? = nil, creeLe: String? = nil) {
        self.id = id; self.missionId = missionId; self.statut = statut; self.typeContrat = typeContrat; self.creeLe = creeLe
    }

    enum CodingKeys: String, CodingKey {
        case id, statut
        case missionId = "mission_id"
        case typeContrat = "type_contrat"
        case creeLe = "cree_le"
    }
}

/// Contrat relu (`contrats_mission`). Statut affiché = statut serveur ; le compte à rebours est dérivé
/// de `cree_le` (`CompteARebours72h`), jamais stocké.
public struct ContratDetail: Codable, Equatable, Sendable, Identifiable {
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

    public init(id: String, missionId: String, statut: String, typeContrat: String? = nil, contenuHtml: String? = nil,
                hashDocument: String? = nil, storagePath: String? = nil, contenuHtmlRenduLe: String? = nil,
                signatureSoignant: Bool? = nil, signatureEtablissement: Bool? = nil, signatureSoignantLe: String? = nil,
                signatureEtablissementLe: String? = nil, creeLe: String? = nil) {
        self.id = id; self.missionId = missionId; self.statut = statut; self.typeContrat = typeContrat
        self.contenuHtml = contenuHtml; self.hashDocument = hashDocument; self.storagePath = storagePath
        self.contenuHtmlRenduLe = contenuHtmlRenduLe; self.signatureSoignant = signatureSoignant
        self.signatureEtablissement = signatureEtablissement; self.signatureSoignantLe = signatureSoignantLe
        self.signatureEtablissementLe = signatureEtablissementLe; self.creeLe = creeLe
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
    }

    /// Preuves de signature lues par les règles de `ContratMissionUi` (T2).
    public var preuve: PreuveSignatureContrat {
        PreuveSignatureContrat(statut: statut, signatureSoignant: signatureSoignant, signatureEtablissement: signatureEtablissement,
                               signatureSoignantLe: signatureSoignantLe, signatureEtablissementLe: signatureEtablissementLe)
    }
}

/// Original contrôlé (§2.5) : SHA-256 du HTML UTF-8 = `hash_document` = SHA-256 des octets Storage.
/// Seul ce type est affiché, partagé ou signé ; `empreinte` est l'empreinte affichée et signée.
public struct OriginalContrat: Equatable, Sendable {
    public var contratId: String
    public var html: String
    public var empreinte: String

    public init(contratId: String, html: String, empreinte: String) {
        self.contratId = contratId; self.html = html; self.empreinte = empreinte
    }
}

/// Succès de `fn_envoyer_otp_signature` (l.33286-33293). Ne prouve pas l'envoi réel du SMS ; seul
/// `telephone_masked` serveur s'affiche.
public struct OtpEnvoye: Equatable, Sendable {
    public var role: String?
    public var telephoneMasque: String?
    public var expireDansMinutes: Int?
    public var smsEnvoyes: Int?
    public var smsRestants: Int?

    public init(role: String? = nil, telephoneMasque: String? = nil, expireDansMinutes: Int? = nil,
                smsEnvoyes: Int? = nil, smsRestants: Int? = nil) {
        self.role = role; self.telephoneMasque = telephoneMasque; self.expireDansMinutes = expireDansMinutes
        self.smsEnvoyes = smsEnvoyes; self.smsRestants = smsRestants
    }
}

public enum IssueEnvoiOtp: Equatable, Sendable {
    case envoye(OtpEnvoye)
    /// `MESSAGES_ERREUR` du web ou `error` serveur verbatim (T9b) ; `bloquant` : plus aucun envoi possible.
    case refuse(code: String?, message: String, bloquant: Bool)
}

public enum IssueSignature: Equatable, Sendable {
    /// `fn_signer_contrat_otp` accepté ET relu (`signature_soignant`, `statut_signature = 'signe'`).
    case signee(contratComplet: Bool)
    case refuse(code: String?, message: String, tentativesRestantes: Int?)
}

/// Ligne `signatures_contrats` du certificat. Projection imposée (correction 22) : `authenticated` n'a
/// que des GRANT colonne par colonne (l.86518-86570) ; un `select=*` lève 42501.
public struct SignatureCertificat: Codable, Equatable, Sendable, Identifiable {
    public static let colonnes = ["id", "contrat_id", "signataire_user_id", "signataire_role", "signe_a", "ip_signature",
                                  "user_agent", "hash_document", "otp_valide_a", "psc_session_active", "rpps_verifie",
                                  "traits_identite_verifies", "statut_signature", "cree_le"]
    /// Valeur du paramètre PostgREST `select`.
    public static var selection: String { colonnes.joined(separator: ",") }

    public var id: String
    public var contratId: String?
    public var signataireUserId: String?
    public var signataireRole: String?
    public var signeA: String?
    public var ipSignature: String?
    public var userAgent: String?
    public var hashDocument: String?
    public var otpValideA: String?
    public var pscSessionActive: Bool?
    public var rppsVerifie: Bool?
    public var traitsIdentiteVerifies: Bool?
    public var statutSignature: String?
    public var creeLe: String?

    enum CodingKeys: String, CodingKey {
        case id
        case contratId = "contrat_id"
        case signataireUserId = "signataire_user_id"
        case signataireRole = "signataire_role"
        case signeA = "signe_a"
        case ipSignature = "ip_signature"
        case userAgent = "user_agent"
        case hashDocument = "hash_document"
        case otpValideA = "otp_valide_a"
        case pscSessionActive = "psc_session_active"
        case rppsVerifie = "rpps_verifie"
        case traitsIdentiteVerifies = "traits_identite_verifies"
        case statutSignature = "statut_signature"
        case creeLe = "cree_le"
    }
}
