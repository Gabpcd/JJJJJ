import Foundation

// Missions de l'établissement (lot 5, T5 ; `docs/mobile-swift/LOT5_PLAN.md` §3 T5) : décodage tolérant des
// lignes `missions` et du soignant servi par `fn_soignant_pour_etablissement`, filtres et compteurs de
// `src/pages/ListeMissions.tsx` (l.27-36, l.161-166). Aucun champ monétaire : les colonnes décodées sont
// celles de `EtabMissionResume.clesDecodees`, sans `taux_horaire_base`, `total_brut`, `net_a_payer`,
// `taux_rist_plafonne` ni `rist_plafond_applique` (D15). Le serveur reste l'autorité (RLS `pol_mission_select`).

// MARK: - Décodage des lignes `missions`

extension EtabMissionResume: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case etablissementId = "etablissement_id"
        case intitule, description, service
        case professionRequise = "profession_requise"
        case debutLe = "debut_le"
        case finLe = "fin_le"
        case nbCreneaux = "nb_creneaux"
        case statut
        case estUrgente = "est_urgente"
        case niveauUrgence = "niveau_urgence"
        case soignantAssigneId = "soignant_assigne_id"
        case modeAttribution = "mode_attribution"
        case typeContratRecherche = "type_contrat_recherche"
        case creeLe = "cree_le"
    }

    /// Les seules colonnes lues (ordre du `select` PostgREST de `SupabaseEtabMissionsGateway`).
    public static var clesDecodees: [String] { CodingKeys.allCases.map(\.rawValue) }

    /// `id` exigé, non vide ; toute autre clé tolérante (absente, nulle ou d'un autre type → `nil`,
    /// `intitule` → vide). Un statut inconnu est conservé tel quel (libellé brut à l'affichage).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "identifiant de mission vide")
        }
        func texte(_ cle: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: cle)) ?? nil }
        func entier(_ cle: CodingKeys) -> Int? { (try? c.decodeIfPresent(Int.self, forKey: cle)) ?? nil }
        self.init(id: id, intitule: texte(.intitule) ?? "", statut: texte(.statut), debutLe: texte(.debutLe),
                  finLe: texte(.finLe), nbCreneaux: entier(.nbCreneaux), professionRequise: texte(.professionRequise),
                  typeContratRecherche: texte(.typeContratRecherche),
                  estUrgente: (try? c.decodeIfPresent(Bool.self, forKey: .estUrgente)) ?? nil,
                  etablissementId: texte(.etablissementId), description: texte(.description), service: texte(.service),
                  niveauUrgence: entier(.niveauUrgence), soignantAssigneId: texte(.soignantAssigneId),
                  modeAttribution: texte(.modeAttribution), creeLe: texte(.creeLe))
    }

    /// Mission attendue par la complétude du planning (`CompletudePlanning`) ; bornes absentes → vides
    /// (le planning est alors « à confirmer », jamais un créneau supposé).
    public var planningAttendu: MissionAvecPlanningAttendu {
        MissionAvecPlanningAttendu(id: id, debutLe: debutLe ?? "", finLe: finLe ?? "", nbCreneaux: nbCreneaux)
    }
}

// MARK: - Soignant servi par `fn_soignant_pour_etablissement`

extension SoignantPourEtab: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, prenom, nom, profession, telephone
        case nomAnonymise = "nom_anonymise"
        case numeroRpps = "numero_rpps"
        case scoreFiabilite = "score_fiabilite"
        case totalMissionsTerminees = "total_missions_terminees"
    }

    /// Les seules clés lues dans la réponse (jamais `note_moyenne`, `nb_evaluations`, `type_exercice`, `internat`).
    public static var clesDecodees: [String] { CodingKeys.allCases.map(\.rawValue) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "identifiant de soignant vide")
        }
        func texte(_ cle: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: cle)) ?? nil }
        func entier(_ cle: CodingKeys) -> Int? {
            if let valeur = (try? c.decodeIfPresent(Int.self, forKey: cle)) ?? nil { return valeur }
            // `score_fiabilite` est un numeric : PostgREST peut le servir avec une décimale.
            guard let decimal = (try? c.decodeIfPresent(Double.self, forKey: cle)) ?? nil, decimal.isFinite else { return nil }
            return Int(decimal.rounded())
        }
        self.init(id: id, prenom: texte(.prenom), nom: texte(.nom), profession: texte(.profession),
                  nomAnonymise: (try? c.decodeIfPresent(Bool.self, forKey: .nomAnonymise)) ?? nil,
                  telephone: texte(.telephone), numeroRpps: texte(.numeroRpps), scoreFiabilite: entier(.scoreFiabilite),
                  totalMissionsTerminees: entier(.totalMissionsTerminees))
    }
}

// MARK: - Filtres et compteurs

/// Filtres de la liste du web (`STATUTS_FILTRES`, `ListeMissions.tsx` l.27-36), dans son ordre. `ANNULEE_PAR_SOIGNANT`
/// et `ABSENCE` ne sont visibles que sous « Toutes », comme sur le web.
public enum EtabMissionsFiltre: String, CaseIterable, Sendable, Identifiable {
    case toutes = ""
    case ouvertes = "OUVERTE"
    case assignees = "ASSIGNEE"
    case actives = "EN_COURS"
    case terminees = "TERMINEE"
    case expirees = "EXPIREE"
    case annulees = "ANNULEE_PAR_ETABLISSEMENT"
    case litiges = "LITIGE"

    public var id: String { identifiant }

    /// Statut lu côté serveur ; `nil` = tous les statuts.
    public var statut: String? { self == .toutes ? nil : rawValue }

    public var libelle: String {
        switch self {
        case .toutes: return "Toutes"
        case .ouvertes: return "Ouvertes"
        case .assignees: return "Assignées"
        case .actives: return "Actives"
        case .terminees: return "Terminées"
        case .expirees: return "Expirées"
        case .annulees: return "Annulées"
        case .litiges: return "Litiges"
        }
    }

    /// `etab-missions-filtre-toutes`, `etab-missions-filtre-OUVERTE`…
    public var identifiant: String { "etab-missions-filtre-\(self == .toutes ? "toutes" : rawValue)" }

    /// `?statut=` d'un lien (web l.48-53) : une valeur hors des filtres revient à « Toutes ».
    public init(parametre: String?) {
        self = EtabMissionsFiltre.allCases.first { $0.rawValue == (parametre ?? "") } ?? .toutes
    }

    /// Titre de l'état vide filtré (web l.329-338).
    public var titreVide: String {
        switch self {
        case .toutes: return "Aucune mission trouvée"
        case .ouvertes: return "Aucune mission ouverte"
        case .assignees: return "Aucune mission assignée"
        case .actives: return "Aucune mission active"
        case .terminees: return "Aucune mission terminée"
        case .expirees: return "Aucune mission expirée"
        case .annulees: return "Aucune mission annulée"
        case .litiges: return "Aucun litige"
        }
    }
}

/// Compteurs de la liste (web l.161-166) : « Toutes » = toutes les lignes de l'établissement, chaque filtre = ses
/// lignes. Dérivés des statuts relus, jamais saisis.
public struct EtabMissionsCompteurs: Equatable, Sendable {
    public var total: Int
    public var parStatut: [String: Int]

    public init(statuts: [String?]) {
        total = statuts.count
        var compte: [String: Int] = [:]
        for statut in statuts { if let statut { compte[statut, default: 0] += 1 } }
        parStatut = compte
    }

    public func nombre(_ filtre: EtabMissionsFiltre) -> Int {
        guard let statut = filtre.statut else { return total }
        return parStatut[statut] ?? 0
    }
}
