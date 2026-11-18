import Foundation

// Contrats d'échange de `SwipePort` (lot 4, T3a, `docs/mobile-swift/LOT4_PLAN.md` §2.3-§2.4), déplacés de
// `Models/Lot4Results.swift` par la tranche qui les livre (inits de T1 conservés). Décodage tolérant : seules les
// clés qui conditionnent une action sont requises ; une valeur d'un autre type est ignorée seule. Montants, score et
// distance sont des valeurs serveur affichées telles quelles (§2.6) : aucun barème côté client.

// MARK: - Paquet (`fn_obtenir_missions_swipe`)

/// Montants du payload, servis par le serveur (`COALESCE(m.montant_ifm, 0)`…) et affichés tels quels.
public struct MontantsSwipe: Equatable, Sendable {
    public var ifm: Double?
    public var icp: Double?
    public var majorationNuit: Double?
    public var majorationDimanche: Double?
    public var majorationFerie: Double?

    public init(ifm: Double? = nil, icp: Double? = nil, majorationNuit: Double? = nil, majorationDimanche: Double? = nil,
                majorationFerie: Double? = nil) {
        self.ifm = ifm; self.icp = icp; self.majorationNuit = majorationNuit
        self.majorationDimanche = majorationDimanche; self.majorationFerie = majorationFerie
    }
}

/// Ligne de `fn_obtenir_missions_swipe` (`supabase/schema/public.sql`, `jsonb_build_object` du paquet). Requis :
/// `mission_id`, `intitule`, `etablissement_id`, `debut_le`, `fin_le` (sans eux, la carte ne peut porter aucune
/// action) ; tout le reste est optionnel et toléré seul.
public struct LigneSwipe: Decodable, Equatable, Sendable {
    public var missionId: String
    public var intitule: String
    public var professionRequise: String?
    public var etablissementId: String
    public var etablissementNom: String?
    public var etablissementVille: String?
    public var etablissementCodePostal: String?
    public var etablissementLogoUrl: String?
    public var etablissementScore: Double?
    public var tauxHoraireBase: Double?
    public var dureeHeures: Double?
    public var debutLe: String
    public var finLe: String
    public var estUrgente: Bool
    public var service: String?
    public var typeContratApplique: String?
    public var typeContratRecherche: String?
    public var nbCreneaux: Int?
    public var totalBrut: Double?
    public var netAPayer: Double?
    public var netEstime: Double?
    public var montants: MontantsSwipe
    /// `ms.score_global` : `nil` sans ligne `matching_scores` (migration `20261102204820`, B1) ; jamais fabriqué.
    public var score: Int?
    /// Valeurs numériques du breakdown seulement (contrat de T1). Le breakdown réel porte aussi des `null`
    /// (`distance_km`, `taux_median`) et des textes (`error`, `filtre_dur_ko`) : jamais un échec de décodage.
    public var breakdown: [String: Double]
    /// Breakdown brut, tel que servi (objet `jsonb`, `nil` s'il n'est pas un objet) : source de « Pourquoi N ? »
    /// (`RaisonsScore.raisons(json:)`, revue B8 de #1161, m1).
    public var breakdownBrut: ValeurJSON?
    /// Badge ⚡ : vrai seulement si le serveur sert `true` (drapeau, mission libérale, SEPA actif).
    public var paiementRapide: Bool
    /// Distance serveur (`round(haversine / 1000, 1)`), `nil` sans coordonnées.
    public var distanceKm: Double?

    enum CodingKeys: String, CodingKey {
        case missionId = "mission_id", intitule, professionRequise = "profession_requise"
        case etablissementId = "etablissement_id", etablissementNom = "etablissement_nom"
        case etablissementVille = "etablissement_ville", etablissementCodePostal = "etablissement_code_postal"
        case etablissementLogoUrl = "etablissement_logo_url", etablissementScore = "etablissement_score"
        case tauxHoraireBase = "taux_horaire_base", dureeHeures = "duree_heures", debutLe = "debut_le", finLe = "fin_le"
        case estUrgente = "est_urgente", service
        case typeContratApplique = "type_contrat_applique", typeContratRecherche = "type_contrat_recherche"
        case nbCreneaux = "nb_creneaux", totalBrut = "total_brut", netAPayer = "net_a_payer", netEstime = "net_estime"
        case montantIfm = "montant_ifm", montantIcp = "montant_icp", montantMajorationNuit = "montant_majoration_nuit"
        case montantMajorationDimanche = "montant_majoration_dimanche", montantMajorationFerie = "montant_majoration_ferie"
        case score, breakdown, paiementRapide = "paiement_rapide", distanceKm = "distance_km"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func texte(_ cle: CodingKeys) -> String? {
            guard case .chaine(let valeur)? = try? c.decodeIfPresent(ValeurJSON.self, forKey: cle) else { return nil }
            return valeur
        }
        func requis(_ cle: CodingKeys) throws -> String {
            guard let valeur = texte(cle), !valeur.isEmpty else {
                throw DecodingError.keyNotFound(cle, .init(codingPath: c.codingPath, debugDescription: "clé requise du paquet"))
            }
            return valeur
        }
        func nombre(_ cle: CodingKeys) -> Double? {
            guard case .nombre(let valeur)? = try? c.decodeIfPresent(ValeurJSON.self, forKey: cle) else { return nil }
            return valeur
        }
        func entier(_ cle: CodingKeys) -> Int? {
            guard let valeur = nombre(cle), valeur.rounded() == valeur, abs(valeur) < 1e15 else { return nil }
            return Int(valeur)
        }
        func vrai(_ cle: CodingKeys) -> Bool {
            if case .booleen(true)? = try? c.decodeIfPresent(ValeurJSON.self, forKey: cle) { return true }
            return false
        }
        missionId = try requis(.missionId)
        intitule = try requis(.intitule)
        etablissementId = try requis(.etablissementId)
        debutLe = try requis(.debutLe)
        finLe = try requis(.finLe)
        professionRequise = texte(.professionRequise)
        etablissementNom = texte(.etablissementNom)
        etablissementVille = texte(.etablissementVille)
        etablissementCodePostal = texte(.etablissementCodePostal)
        etablissementLogoUrl = texte(.etablissementLogoUrl)
        etablissementScore = nombre(.etablissementScore)
        tauxHoraireBase = nombre(.tauxHoraireBase)
        dureeHeures = nombre(.dureeHeures)
        estUrgente = vrai(.estUrgente)
        service = texte(.service)
        typeContratApplique = texte(.typeContratApplique)
        typeContratRecherche = texte(.typeContratRecherche)
        nbCreneaux = entier(.nbCreneaux)
        totalBrut = nombre(.totalBrut)
        netAPayer = nombre(.netAPayer)
        netEstime = nombre(.netEstime)
        montants = MontantsSwipe(ifm: nombre(.montantIfm), icp: nombre(.montantIcp), majorationNuit: nombre(.montantMajorationNuit),
                                 majorationDimanche: nombre(.montantMajorationDimanche),
                                 majorationFerie: nombre(.montantMajorationFerie))
        score = entier(.score)
        if case .objet(let objet)? = try? c.decodeIfPresent(ValeurJSON.self, forKey: .breakdown) {
            breakdownBrut = .objet(objet)
            breakdown = objet.compactMapValues { valeur in
                if case .nombre(let points) = valeur { return points }
                return nil
            }
        } else {
            breakdownBrut = nil
            breakdown = [:]
        }
        paiementRapide = vrai(.paiementRapide)
        distanceKm = nombre(.distanceKm)
    }

    /// Statut servi : le paquet ne contient que des missions `OUVERTE` (`WHERE m.statut = 'OUVERTE'`).
    public static let statutServi = "OUVERTE"

    /// Ligne `missions` reconstituée depuis le payload (aucune colonne absente du payload n'est inventée).
    public var record: MissionRecord {
        MissionRecord(id: missionId, intitule: intitule, description: nil, service: service,
                      professionRequise: professionRequise ?? "", specialiteMedicaleRequise: nil, accepteNonSpecialises: nil,
                      debutLe: debutLe, finLe: finLe, dureeHeures: dureeHeures, nbCreneaux: nbCreneaux,
                      tauxHoraireBase: tauxHoraireBase, tauxRistPlafonne: nil, ristPlafondApplique: nil, totalBrut: totalBrut,
                      netAPayer: netAPayer, estUrgente: estUrgente, niveauUrgence: nil, statut: Self.statutServi,
                      etablissementId: etablissementId, typeContratRecherche: typeContratRecherche, boosteeLe: nil,
                      modeRemuneration: nil, retrocessionPct: nil)
    }

    /// Établissement du payload (`etablissement_nom` relu par la jointure serveur, jamais `fn_etablissements_safe`).
    public var etablissement: EtablissementSummary {
        EtablissementSummary(id: etablissementId, nom: etablissementNom ?? "", adresseVille: etablissementVille,
                             adresseCodePostal: etablissementCodePostal, logoUrl: etablissementLogoUrl)
    }
}

/// Corps de `fn_obtenir_missions_swipe` : `{missions:[…]}` (pas de `success`), ou `{missions:[], error:'auth_required'}`
/// sans session. Une ligne illisible (clé requise absente) est écartée seule : elle ne porterait aucune action.
public struct PaquetSwipe: Decodable, Equatable, Sendable {
    /// Refus « non authentifié » du paquet et de `fn_enregistrer_swipe` (HTTP 200) → `.unauthorized`.
    public static let erreurNonAuthentifie = "auth_required"
    /// Taille du paquet demandée, comme le web (`p_limit: 20`, borné 1-100 côté serveur).
    public static let taille = 20

    public var missions: [LigneSwipe]
    public var error: String?
    /// Lignes écartées au décodage (journal de test seulement).
    public var lignesEcartees: Int

    private struct LigneTolerante: Decodable {
        let ligne: LigneSwipe?
        init(from decoder: Decoder) throws { ligne = try? LigneSwipe(from: decoder) }
    }

    enum CodingKeys: String, CodingKey { case missions, error }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let lignes = (try? c.decodeIfPresent([LigneTolerante].self, forKey: .missions)) ?? []
        missions = lignes.compactMap(\.ligne)
        lignesEcartees = lignes.count - missions.count
        if case .chaine(let erreur)? = try? c.decodeIfPresent(ValeurJSON.self, forKey: .error) { error = erreur } else { error = nil }
    }

    public var nonAuthentifie: Bool { error == Self.erreurNonAuthentifie }
}

/// Carte du paquet. Complétée par T3a (clés du payload) ; l'init de T1 est conservé.
public struct CarteSwipe: Equatable, Sendable, Identifiable {
    public var id: String
    public var mission: Mission
    /// Valeur serveur : `nil` sans score calculé (migration `20261102204820`, B1 de LOT4_PLAN) ; jamais « 0/100 » inventé.
    public var score: Int?
    public var breakdown: [String: Double]
    public var etablissementNom: String?
    public var etablissementScore: Double? = nil
    public var netEstime: Double? = nil
    public var paiementRapide: Bool = false
    public var montants: MontantsSwipe = MontantsSwipe()
    public var typeContratApplique: String? = nil
    /// Breakdown brut du serveur (`null` et textes compris), source de `raisons` ; `nil` : `breakdown` seul.
    public var breakdownBrut: ValeurJSON? = nil
    /// Distance servie par le payload (`distance_km`, arrondie par le serveur), seule lue par le filtre du paquet comme
    /// le web (revue B8 de #1161, m2) : jamais une distance recalculée côté client, qui divergerait à la borne du rayon.
    public var distanceServeurKm: Double?

    public init(id: String, mission: Mission, score: Int?, breakdown: [String: Double] = [:], etablissementNom: String? = nil) {
        self.id = id; self.mission = mission; self.score = score; self.breakdown = breakdown
        self.etablissementNom = etablissementNom
        self.distanceServeurKm = mission.distanceKm
    }

    /// Carte d'une ligne du paquet et de ses créneaux PREVISIONNEL hors pauses (`MissionSlotPager`, ou fixture démo),
    /// enrichie comme `MissionBusiness.enrich` (créneaux triés par début puis id, planning candidat dérivé) mais avec la
    /// distance servie par le payload : le paquet ne transmet pas les coordonnées de l'établissement.
    public init(ligne: LigneSwipe, creneaux: [MissionSlot]) {
        let record = ligne.record
        let tries = creneaux.filter { $0.missionId == nil || $0.missionId == ligne.missionId }
            .sorted { ($0.debut, $0.id ?? "") < ($1.debut, $1.id ?? "") }
        let planning = PlanningCandidatRules.construirePlanningCandidat(PlanningCandidatInput(record: record, creneaux: tries))
        let mission = Mission(record: record, etablissement: ligne.etablissement, distanceKm: ligne.distanceKm,
                              creneauxPlanifies: tries.isEmpty ? planning.creneaux : tries, planningExact: planning.exact)
        self.init(id: ligne.missionId, mission: mission, score: ligne.score, breakdown: ligne.breakdown,
                  etablissementNom: ligne.etablissementNom)
        etablissementScore = ligne.etablissementScore
        netEstime = ligne.netEstime
        paiementRapide = ligne.paiementRapide
        montants = ligne.montants
        typeContratApplique = ligne.typeContratApplique
        breakdownBrut = ligne.breakdownBrut
        distanceServeurKm = ligne.distanceKm
    }

    /// « Pourquoi N ? » : deux raisons au plus (`RaisonsScore.raisons(json:)`, golden T2) sur le breakdown brut, dont les
    /// valeurs non numériques sont ignorées comme par le web (revue B8 de #1161, m1).
    public var raisons: String {
        RaisonsScore.raisons(json: breakdownBrut ?? .objet(breakdown.mapValues { .nombre($0) }))
    }

    /// Champs lus par le filtre du paquet (chips rapides, golden T2), distance du serveur comprise (m2).
    public var missionPaquet: MissionPaquetSwipe {
        var champs = MissionPaquetSwipe(mission: mission)
        champs.distanceKm = distanceServeurKm
        return champs
    }
}

// MARK: - Actions

/// Directions envoyées à `fn_enregistrer_swipe` hors candidature (le ❤️ passe par `CandidaturePort.confirmer(.swipeLike)`).
public enum DirectionSwipe: String, Equatable, Sendable, CaseIterable {
    case passer = "DISLIKE"
    case favori = "FAVORI"
}

/// Issue de ✕ / ⭐ : la carte n'est retirée qu'après `enregistre` (`ok:true`, ⭐ relu dans `missions_sauvegardees`).
public enum SwipeOutcome: Equatable, Sendable {
    case enregistre
    /// `code` technique du serveur (`mission_deja_swipee`, `mission_indisponible`…), traduit par `SwipeRefus` ; `nil`
    /// pour un message rédigé du serveur, restitué verbatim.
    case refuse(code: String?, message: String)
}

/// Issue du retrait après ❤️ (`fn_retirer_candidature`), prouvée par relecture : candidature absente.
public enum RetraitOutcome: Equatable, Sendable {
    case retiree
    case refuse(message: String)
}

/// Préférences horaires du quiz (`fn_initialiser_preferences_matching(p_pref_nuit, p_pref_jour, p_pref_weekend,
/// p_pref_semaine)`, bornes [0, 1]). Corrigé par T3a : T1 nommait quatre poids de scoring (tarif, distance,
/// établissement, urgence) que la RPC ne reçoit pas.
public struct PreferencesMatching: Equatable, Sendable {
    public var nuit: Double
    public var jour: Double
    public var weekend: Double
    public var semaine: Double

    public init(nuit: Double, jour: Double, weekend: Double, semaine: Double) {
        self.nuit = nuit; self.jour = jour; self.weekend = weekend; self.semaine = semaine
    }

    /// Réponses « horaire » et « rythme » du quiz (`QuizPreferencesSwipe.tsx`, `ReponsesQuiz`).
    public enum Horaire: String, Equatable, Sendable, CaseIterable { case jour = "JOUR", nuit = "NUIT", tous = "TOUS" }
    public enum Rythme: String, Equatable, Sendable, CaseIterable { case semaine = "SEMAINE", weekend = "WEEKEND", tous = "TOUS" }

    /// Amorçage du web (`QuizPreferencesSwipe.tsx`, `valider`) : la tranche choisie démarre à 0,8, l'autre à 0,3,
    /// « Les deux » à 0,5 / 0,5.
    public static func depuisQuiz(horaire: Horaire, rythme: Rythme) -> PreferencesMatching {
        let (nuit, jour): (Double, Double) = horaire == .nuit ? (0.8, 0.3) : horaire == .jour ? (0.3, 0.8) : (0.5, 0.5)
        let (weekend, semaine): (Double, Double) = rythme == .weekend ? (0.8, 0.3) : rythme == .semaine ? (0.3, 0.8) : (0.5, 0.5)
        return PreferencesMatching(nuit: nuit, jour: jour, weekend: weekend, semaine: semaine)
    }

    /// Bornes serveur (`NOT BETWEEN 0 AND 1` → « Préférences hors bornes [0,1] ») : contrôle avant tout envoi.
    public var dansLesBornes: Bool { [nuit, jour, weekend, semaine].allSatisfy { (0...1).contains($0) } }
}
