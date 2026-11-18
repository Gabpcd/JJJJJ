import Foundation

// Décodage tolérant de `fn_lire_candidatures_mission_habilitee` (lot 5, T6 ; `supabase/schema/public.sql` l.39970,
// fiche `docs/mobile-swift/CONTRATS_RPC_ETABLISSEMENT.md`). Forme : `{mission{…}, creneaux[], candidatures[]}`.
// Seules les clés de `clesDecodees` sont lues : jamais `note_moyenne`, `nb_evaluations` (D8), `internat` (D10),
// `type_exercice`, `etudiant_details`, `specialite_medicale`, `specialite_medicale_requise`, `accepte_internes`.
// Exigé : `mission.id` non vide (sinon refus de contrat). Toléré : toute autre clé absente, nulle ou d'un autre
// type (→ `nil`) ; un créneau illisible est écarté (le planning devient alors inexact et bloque l'acceptation,
// `PlanningExactEtab`), une candidature sans identifiant aussi (aucune action possible sans elle).

extension LectureCandidaturesHabilitee: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable { case mission, creneaux, candidatures }

    enum MissionKeys: String, CodingKey, CaseIterable {
        case id, intitule, statut
        case etablissementId = "etablissement_id"
        case modeAttribution = "mode_attribution"
        case nbCreneaux = "nb_creneaux"
        case professionRequise = "profession_requise"
    }

    /// Clés lues dans `mission` (le reste de l'objet n'est jamais décodé).
    public static var clesMissionDecodees: [String] { MissionKeys.allCases.map(\.rawValue) }

    public init(from decoder: Decoder) throws {
        let racine = try decoder.container(keyedBy: CodingKeys.self)
        let m = try racine.nestedContainer(keyedBy: MissionKeys.self, forKey: .mission)
        let id = try m.decode(String.self, forKey: .id)
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: m, debugDescription: "identifiant de mission vide")
        }
        func texte(_ cle: MissionKeys) -> String? { (try? m.decodeIfPresent(String.self, forKey: cle)) ?? nil }
        let creneaux = ((try? racine.decodeIfPresent([Tolerant<MissionSlot>].self, forKey: .creneaux)) ?? nil) ?? []
        let candidatures = ((try? racine.decodeIfPresent([Tolerant<CandidatureHabilitee>].self, forKey: .candidatures)) ?? nil) ?? []
        self.init(missionId: id, statutMission: texte(.statut),
                  nbCreneaux: (try? m.decodeIfPresent(Int.self, forKey: .nbCreneaux)) ?? nil,
                  creneaux: creneaux.compactMap(\.valeur), candidatures: candidatures.compactMap(\.valeur),
                  intitule: texte(.intitule), etablissementId: texte(.etablissementId),
                  modeAttribution: texte(.modeAttribution), professionRequise: texte(.professionRequise))
    }
}

extension CandidatureHabilitee: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, message, statut, soignant
        case soignantId = "soignant_id"
        case creeLe = "cree_le"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "identifiant de candidature vide")
        }
        func texte(_ cle: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: cle)) ?? nil }
        self.init(id: id, soignantId: texte(.soignantId), statut: texte(.statut), creeLe: texte(.creeLe),
                  message: texte(.message), soignant: (try? c.decodeIfPresent(CandidatHabilite.self, forKey: .soignant)) ?? nil)
    }
}

extension CandidatHabilite: Decodable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, prenom, nom, profession
        case nomAnonymise = "nom_anonymise"
        case estEtudiant = "est_etudiant"
        case scoreFiabilite = "score_fiabilite"
        case totalMissionsTerminees = "total_missions_terminees"
        case tousDocumentsValides = "tous_documents_valides"
    }

    /// Les seules clés lues dans `soignant` (jamais `note_moyenne`, `nb_evaluations`, `internat`, `type_exercice`,
    /// `etudiant_details`, `specialite_medicale`).
    public static var clesDecodees: [String] { CodingKeys.allCases.map(\.rawValue) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        func texte(_ cle: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: cle)) ?? nil }
        func booleen(_ cle: CodingKeys) -> Bool? { (try? c.decodeIfPresent(Bool.self, forKey: cle)) ?? nil }
        func entier(_ cle: CodingKeys) -> Int? {
            if let valeur = (try? c.decodeIfPresent(Int.self, forKey: cle)) ?? nil { return valeur }
            // `score_fiabilite` est un numeric : il peut être servi avec une décimale.
            guard let decimal = (try? c.decodeIfPresent(Double.self, forKey: cle)) ?? nil, decimal.isFinite else { return nil }
            return Int(decimal.rounded())
        }
        self.init(id: id, prenom: texte(.prenom), nom: texte(.nom), nomAnonymise: booleen(.nomAnonymise),
                  profession: texte(.profession), estEtudiant: booleen(.estEtudiant), scoreFiabilite: entier(.scoreFiabilite),
                  totalMissionsTerminees: entier(.totalMissionsTerminees), tousDocumentsValides: booleen(.tousDocumentsValides))
    }
}

/// Élément de tableau décodé sans faire échouer le tableau : `nil` s'il est illisible.
private struct Tolerant<Valeur: Decodable>: Decodable {
    let valeur: Valeur?

    init(from decoder: Decoder) throws {
        valeur = try? Valeur(from: decoder)
    }
}
