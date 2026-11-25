import Foundation

// Contrats d'échange de `ScorePort` (lot 4, T9, `docs/mobile-swift/LOT4_PLAN.md` §2.3-§2.4), déplacés de
// `Models/Lot4Results.swift` par la tranche qui les livre et complétés du décodage des quatre lectures de « Mon
// score ». Score, niveau, pourcentages, poids, malus, bonus et points sont des valeurs serveur affichées telles
// quelles : aucun barème, aucun défaut fabriqué (le web remplace un score absent par 50 et un niveau absent par
// Bronze, `PageScoreSoignant.tsx` l.75-76 ; l'app n'affiche alors ni score ni niveau).

// MARK: - Détail du calcul (`fn_mon_breakdown_actuel`)

/// Composantes de `scoring_breakdown` : préfixe des colonnes `<cle>_pct` / `<cle>_poids` et valeur de `composante` dans
/// `composantes_inactives_json` (`fn_calculer_score_fiabilite_v2`). Ordre de `COMPOSANTES_DEF` (`BreakdownScore.tsx`
/// l.43-50).
public enum CleComposanteScore: String, Equatable, Sendable, CaseIterable {
    case notationEtabSoignant = "notation_etab_soignant"
    case presentisme
    case ponctualite
    case reactivite
    case ancienneteVolume = "anciennete_volume"
    case notationSoignantEtab = "notation_soignant_etab"
}

/// Composante du dernier calcul : `pct` absent = composante inactive (pas assez de données).
public struct ComposanteScore: Equatable, Sendable, Identifiable {
    public var cle: CleComposanteScore
    public var pct: Double?
    /// Poids effectif après redistribution (`<cle>_poids`).
    public var poids: Double?
    /// Poids initial d'une composante inactive (`composantes_inactives_json[].poids_initial`), sinon `nil`.
    public var poidsInitial: Double?
    public var id: String { cle.rawValue }

    public init(cle: CleComposanteScore, pct: Double?, poids: Double?, poidsInitial: Double? = nil) {
        self.cle = cle; self.pct = pct; self.poids = poids; self.poidsInitial = poidsInitial
    }

    public var estActive: Bool { pct != nil }
}

/// Dernier calcul du score (`fn_mon_breakdown_actuel`) et colonnes du profil lues par la page
/// (`soignants.total_missions_terminees, score_fiabilite, niveau, en_periode_probatoire`, `PageScoreSoignant.tsx` l.62).
public struct BreakdownScore: Equatable, Sendable {
    /// `score_total` du dernier calcul ; sans calcul, `soignants.score_fiabilite` ; `nil` si aucun des deux n'est servi.
    public var score: Double?
    /// `niveau` (`BRONZE`, `ARGENT`, `OR`, `PLATINE`), du calcul sinon du profil ; jamais un niveau par défaut.
    public var niveau: String?
    public var enPeriodeProbatoire: Bool?
    /// Les six composantes du calcul, dans l'ordre du web ; vide sans calcul.
    public var composantes: [ComposanteScore]
    public var litigesMalus: Double?
    public var absenceSansPrevenirMalus: Double?
    public var bonusSuperActif: Double?
    public var totalMissionsTerminees: Int?
    /// Un calcul `scoring_breakdown` existe (réponse non vide portant `score_total`).
    public var calcule: Bool

    public init(score: Double?, niveau: String?, enPeriodeProbatoire: Bool? = nil, composantes: [ComposanteScore] = [],
                litigesMalus: Double? = nil, absenceSansPrevenirMalus: Double? = nil, bonusSuperActif: Double? = nil,
                totalMissionsTerminees: Int? = nil, calcule: Bool = false) {
        self.score = score; self.niveau = niveau; self.enPeriodeProbatoire = enPeriodeProbatoire
        self.composantes = composantes; self.litigesMalus = litigesMalus
        self.absenceSansPrevenirMalus = absenceSansPrevenirMalus; self.bonusSuperActif = bonusSuperActif
        self.totalMissionsTerminees = totalMissionsTerminees; self.calcule = calcule
    }
}

// MARK: - Évolution (`fn_evolution_score_soignant`)

/// Point de `fn_evolution_score_soignant(int)` (`{mois: 'YYYY-MM', score, niveau, cree_le}`).
public struct PointEvolutionScore: Equatable, Sendable, Identifiable {
    public var mois: String
    public var score: Double?
    public var niveau: String?
    public var id: String { mois }

    public init(mois: String, score: Double?, niveau: String?) { self.mois = mois; self.score = score; self.niveau = niveau }
}

// MARK: - Événements (`fn_mes_evenements_score`)

/// Événement de `fn_mes_evenements_score` (clé **`events`**, correction 16). `contestable` est calculé par le serveur
/// (`contestable AND decision_admin IS NULL AND reclamation_id IS NULL`) : l'app ne le déduit jamais.
public struct EvenementScore: Equatable, Sendable, Identifiable {
    public var id: String
    public var typeEvenement: String
    public var points: Double?
    /// `points_corriges` : points après décision de l'admin, affichés à la place de `points` quand ils sont servis.
    public var pointsCorriges: Double?
    public var motif: String?
    public var contestable: Bool
    public var decisionAdmin: String?
    /// `cree_le` (horodatage serveur brut).
    public var creeLe: String?
    public var missionId: String?

    public init(id: String, typeEvenement: String, points: Double?, pointsCorriges: Double? = nil, motif: String?,
                contestable: Bool, decisionAdmin: String? = nil, creeLe: String? = nil, missionId: String? = nil) {
        self.id = id; self.typeEvenement = typeEvenement; self.points = points; self.pointsCorriges = pointsCorriges
        self.motif = motif; self.contestable = contestable; self.decisionAdmin = decisionAdmin; self.creeLe = creeLe
        self.missionId = missionId
    }

    /// `Number(ev.points_corriges ?? ev.points)` (`PageScoreSoignant.tsx` l.185) : valeur serveur, jamais calculée.
    public var pointsAffiches: Double? { pointsCorriges ?? points }
}

// MARK: - Contestation (`fn_creer_reclamation_score`)

/// `p_motif_categorie` : valeurs de `MOTIFS` (`ModaleReclamationScore.tsx` l.22-29), les seules que le serveur accepte.
public enum MotifContestationScore: String, Equatable, Sendable, CaseIterable, Identifiable {
    case urgenceMedicale = "URGENCE_MEDICALE"
    case deuil = "DEUIL"
    case forceMajeure = "FORCE_MAJEURE"
    case erreurJolene = "ERREUR_JOLENE"
    case contexteParticulier = "CONTEXTE_PARTICULIER"
    case autre = "AUTRE"

    public var id: String { rawValue }
}

/// Issue de `fn_creer_reclamation_score` (`p_justificatif_storage_path` jamais envoyé, D10).
public enum ReclamationScoreOutcome: Equatable, Sendable {
    case enregistree(reclamationId: String)
    /// `error_code` serveur (`TEXTE_REQUIS`, `NON_CONTESTABLE`…) et message verbatim.
    case refusee(code: String?, message: String)
}

// MARK: - Décodage

/// Lecture tolérante des réponses de « Mon score », partagée par la gateway Supabase et le monde démo (les fixtures
/// ont la forme exacte du serveur). `nil` = réponse illisible (erreur de contrat), jamais un état vide plausible. Les
/// refus (`{error}`, `{success:false, …}`) sont lus avant, par la gateway.
public enum ScoreDecodage {
    /// `p_limit` des événements et de l'évolution, comme le web (`PageScoreSoignant.tsx` l.48, `GraphiqueEvolutionScore.tsx` l.27).
    public static let limiteEvenements = 20
    public static let moisEvolution = 6
    /// `p_evenement_type` d'un soignant (`PageScoreSoignant.tsx` l.250).
    public static let typeSoignant = "SOIGNANT"

    /// Ligne `scoring_breakdown` (`to_jsonb(b.*)`) ou `{}` sans calcul, complétée des colonnes du profil. `calcul` doit
    /// être un objet ; `profil` est la ligne `soignants` (`nil` si elle n'est pas servie).
    public static func breakdown(calcul: ValeurJSON, profil: ValeurJSON?) -> BreakdownScore? {
        guard case .objet = calcul else { return nil }
        switch profil {
        case nil, .null?, .objet?: break
        default: return nil
        }
        let total = EvaluationsDecodage.entier(profil?["total_missions_terminees"])
        guard let score = EvaluationsDecodage.nombre(calcul["score_total"]) else {
            // Aucun calcul : valeurs du profil seulement, sans défaut (ni 50, ni Bronze).
            return BreakdownScore(score: EvaluationsDecodage.nombre(profil?["score_fiabilite"]),
                                  niveau: EvaluationsDecodage.texte(profil?["niveau"]),
                                  enPeriodeProbatoire: booleen(profil?["en_periode_probatoire"]),
                                  totalMissionsTerminees: total, calcule: false)
        }
        var initiaux: [String: Double] = [:]
        if case .tableau(let inactives)? = calcul["composantes_inactives_json"] {
            for inactive in inactives {
                guard let cle = EvaluationsDecodage.texte(inactive["composante"]),
                      let poids = EvaluationsDecodage.nombre(inactive["poids_initial"]) else { continue }
                initiaux[cle] = poids
            }
        }
        let composantes = CleComposanteScore.allCases.map { cle in
            ComposanteScore(cle: cle, pct: EvaluationsDecodage.nombre(calcul["\(cle.rawValue)_pct"]),
                            poids: EvaluationsDecodage.nombre(calcul["\(cle.rawValue)_poids"]),
                            poidsInitial: initiaux[cle.rawValue])
        }
        return BreakdownScore(score: score, niveau: EvaluationsDecodage.texte(calcul["niveau"]),
                              enPeriodeProbatoire: booleen(calcul["en_periode_probatoire"]), composantes: composantes,
                              litigesMalus: EvaluationsDecodage.nombre(calcul["litiges_malus"]),
                              absenceSansPrevenirMalus: EvaluationsDecodage.nombre(calcul["absence_sans_prevenir_malus"]),
                              bonusSuperActif: EvaluationsDecodage.nombre(calcul["bonus_super_actif"]),
                              totalMissionsTerminees: total, calcule: true)
    }

    /// Tableau `[{mois, score, niveau, cree_le}]` trié par mois ; `nil` si la réponse n'est pas un tableau.
    public static func evolution(_ reponse: ValeurJSON) -> [PointEvolutionScore]? {
        guard case .tableau(let points) = reponse else { return nil }
        var lus: [PointEvolutionScore] = []
        for point in points {
            guard let mois = EvaluationsDecodage.texte(point["mois"]), !mois.isEmpty else { return nil }
            lus.append(PointEvolutionScore(mois: mois, score: EvaluationsDecodage.nombre(point["score"]),
                                           niveau: EvaluationsDecodage.texte(point["niveau"])))
        }
        return lus
    }

    /// `{success:true, type:'SOIGNANT', events:[…]}`. Illisible (`nil`) : `success` absent ou faux, `type` autre que
    /// `SOIGNANT` (réponse d'un établissement), clé `events` absente — dont la clé `evenements` que lit le web
    /// (correction 16) —, événement sans `id`. `contestable` absent ou non booléen vaut `false` (aucune contestation
    /// proposée sans l'accord du serveur).
    public static func evenements(_ reponse: ValeurJSON) -> [EvenementScore]? {
        guard case .objet = reponse, case .booleen(true)? = reponse["success"],
              EvaluationsDecodage.texte(reponse["type"]) == typeSoignant,
              case .tableau(let lignes)? = reponse["events"] else { return nil }
        var evenements: [EvenementScore] = []
        for ligne in lignes {
            guard case .objet = ligne, let id = EvaluationsDecodage.texte(ligne["id"]), !id.isEmpty,
                  let type = EvaluationsDecodage.texte(ligne["type_evenement"]) else { return nil }
            evenements.append(EvenementScore(id: id, typeEvenement: type, points: EvaluationsDecodage.nombre(ligne["points"]),
                                             pointsCorriges: EvaluationsDecodage.nombre(ligne["points_corriges"]),
                                             motif: EvaluationsDecodage.texte(ligne["motif"]),
                                             contestable: booleen(ligne["contestable"]) == true,
                                             decisionAdmin: EvaluationsDecodage.texte(ligne["decision_admin"]),
                                             creeLe: EvaluationsDecodage.texte(ligne["cree_le"]),
                                             missionId: EvaluationsDecodage.texte(ligne["mission_id"])))
        }
        return evenements
    }

    static func booleen(_ valeur: ValeurJSON?) -> Bool? {
        if case .booleen(let booleen)? = valeur { return booleen }
        return nil
    }
}
