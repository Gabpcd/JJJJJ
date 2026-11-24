import Foundation

// Contrats d'échange de `EvaluationsPort` (lot 4, T9, `docs/mobile-swift/LOT4_PLAN.md` §2.3-§2.4), déplacés de
// `Models/Lot4Results.swift` par la tranche qui les livre et complétés du décodage de
// `fn_mes_notations_recues_avec_stats`. `IssueSignalement`, partagée avec la messagerie (T7a), reste dans
// `Lot4Results.swift`.
//
// Filtre de visibilité centralisé (`CLAUDE.md`, « Publication différée ») : une notation n'existe ici que si une des
// deux RPC filtrées l'a servie (`masque = false AND publie_le IS NOT NULL`). Aucun type de ce fichier ne porte de date
// de publication ni d'état « non publiée » : l'app ne peut pas en afficher une, même par erreur. Notes, moyennes et
// pourcentages sont des valeurs serveur affichées telles quelles : rien n'est recalculé (ni moyenne, ni total).

// MARK: - Filtre

/// `p_periode` de `fn_mes_notations_recues_avec_stats` (`EvaluationsSoignant.tsx` l.75).
public enum PeriodeEvaluations: String, Equatable, Sendable, CaseIterable {
    case tout = "TOUT"
    case troisMois = "3M"
    case sixMois = "6M"
    case douzeMois = "12M"
}

/// Filtres de la page Évaluations (`fn_mes_notations_recues_avec_stats(text, int, uuid, int, int)`).
public struct FiltreEvaluations: Equatable, Sendable {
    public var periode: PeriodeEvaluations
    /// `p_note_min` : `nil` (« Toutes notes »), 5, 4 ou 3 (`EvaluationsSoignant.tsx` l.204-207).
    public var noteMin: Int?
    /// `p_etablissement_id` : `nil` (« Tous établissements ») ou un identifiant de `etabs_disponibles`.
    public var etablissementId: String?

    public init(periode: PeriodeEvaluations = .tout, noteMin: Int? = nil, etablissementId: String? = nil) {
        self.periode = periode; self.noteMin = noteMin; self.etablissementId = etablissementId
    }
}

// MARK: - Réponse

/// Notation reçue et PUBLIÉE, servie par `fn_mes_notations_recues_avec_stats` ou `fn_lister_notations_recues`.
public struct NotationRecue: Equatable, Sendable, Identifiable {
    public var id: String
    public var missionId: String?
    public var missionIntitule: String?
    /// `mission_fin_le` (horodatage serveur brut).
    public var missionFinLe: String?
    public var etablissementId: String?
    public var etablissementNom: String?
    /// `critere_1` … `critere_4`, dans l'ordre ; `nil` pour un critère absent ou illisible.
    public var criteres: [Int?]
    /// `note_moyenne` servie par le serveur ; jamais recalculée depuis les critères.
    public var noteMoyenne: Double?
    public var commentaire: String?
    /// `signale` de la page Évaluations ; `nil` quand le serveur ne le sert pas (`fn_lister_notations_recues`) : le
    /// signalement n'est alors pas proposé (l'app ne peut pas relire son effet).
    public var signale: Bool?
    /// `cree_le` (horodatage serveur brut).
    public var creeLe: String?

    public init(id: String, missionId: String? = nil, missionIntitule: String? = nil, missionFinLe: String? = nil,
                etablissementId: String? = nil, etablissementNom: String? = nil, criteres: [Int?] = [nil, nil, nil, nil],
                noteMoyenne: Double? = nil, commentaire: String? = nil, signale: Bool? = nil, creeLe: String? = nil) {
        self.id = id; self.missionId = missionId; self.missionIntitule = missionIntitule; self.missionFinLe = missionFinLe
        self.etablissementId = etablissementId; self.etablissementNom = etablissementNom; self.criteres = criteres
        self.noteMoyenne = noteMoyenne; self.commentaire = commentaire; self.signale = signale; self.creeLe = creeLe
    }
}

/// `stats` : statistiques globales du serveur (toutes périodes, sans filtre), affichées telles quelles.
public struct StatsEvaluations: Equatable, Sendable {
    public var noteMoyenneGlobale: Double?
    public var totalEvaluations: Int?
    public var pct5Etoiles: Double?

    public init(noteMoyenneGlobale: Double?, totalEvaluations: Int?, pct5Etoiles: Double?) {
        self.noteMoyenneGlobale = noteMoyenneGlobale; self.totalEvaluations = totalEvaluations; self.pct5Etoiles = pct5Etoiles
    }
}

/// Point de `evolution_6m` (`{mois: 'YYYY-MM', note_moyenne, nb}`), moyenne mensuelle du serveur.
public struct PointEvolutionNotes: Equatable, Sendable, Identifiable {
    public var mois: String
    public var noteMoyenne: Double?
    public var nb: Int?
    public var id: String { mois }

    public init(mois: String, noteMoyenne: Double?, nb: Int?) { self.mois = mois; self.noteMoyenne = noteMoyenne; self.nb = nb }
}

/// Entrée de `etabs_disponibles` (`{id, nom}`) : établissements ayant noté, pour le filtre.
public struct EtablissementEvaluateur: Equatable, Sendable, Identifiable {
    public var id: String
    public var nom: String

    public init(id: String, nom: String) { self.id = id; self.nom = nom }
}

/// Page de notations publiées, statistiques et évolution serveur (aucune moyenne recalculée).
public struct PageEvaluations: Equatable, Sendable {
    /// `total` filtré (pagination).
    public var total: Int
    public var notations: [NotationRecue]
    public var stats: StatsEvaluations?
    public var evolution: [PointEvolutionNotes]
    public var etablissements: [EtablissementEvaluateur]

    public init(total: Int, notations: [NotationRecue], stats: StatsEvaluations?, evolution: [PointEvolutionNotes],
                etablissements: [EtablissementEvaluateur]) {
        self.total = total; self.notations = notations; self.stats = stats; self.evolution = evolution
        self.etablissements = etablissements
    }
}

// MARK: - Décodage

/// Lecture tolérante des réponses des deux RPC filtrées, partagée par la gateway Supabase et le monde démo (la
/// fixture a la forme exacte de la RPC). Requis : `success: true`, `total` entier, `notations` tableau, `id` de chaque
/// notation — sans eux la réponse est illisible (`nil`, erreur de contrat), jamais une page vide plausible. Le reste
/// est optionnel et toléré seul.
public enum EvaluationsDecodage {
    /// Taille de page du web (`PAR_PAGE`, `EvaluationsSoignant.tsx` l.41).
    public static let parPage = 20
    /// Limite de « Mon score » (`NotationsRecues.tsx` l.49, `p_limit: 20`).
    public static let limiteScore = 20

    /// `{success:true, total, limit, offset, notations, stats, evolution_6m, etabs_disponibles}`.
    public static func page(_ reponse: ValeurJSON) -> PageEvaluations? {
        guard case .objet = reponse, case .booleen(true)? = reponse["success"],
              let total = entier(reponse["total"]), total >= 0,
              case .tableau(let lignes)? = reponse["notations"] else { return nil }
        var notations: [NotationRecue] = []
        for ligne in lignes {
            guard let notation = notation(ligne) else { return nil }
            notations.append(notation)
        }
        return PageEvaluations(total: total, notations: notations, stats: stats(reponse["stats"]),
                               evolution: evolution(reponse["evolution_6m"]),
                               etablissements: etablissements(reponse["etabs_disponibles"]))
    }

    /// Tableau de `fn_lister_notations_recues` (`[{id, mission_id, …, note_moyenne, commentaire, cree_le}]`, sans
    /// `signale`) ; `nil` si la réponse n'est pas un tableau de notations lisibles.
    public static func liste(_ reponse: ValeurJSON) -> [NotationRecue]? {
        guard case .tableau(let lignes) = reponse else { return nil }
        var notations: [NotationRecue] = []
        for ligne in lignes {
            guard let notation = notation(ligne) else { return nil }
            notations.append(notation)
        }
        return notations
    }

    static func notation(_ ligne: ValeurJSON) -> NotationRecue? {
        guard case .objet = ligne, let id = texte(ligne["id"]), !id.isEmpty else { return nil }
        var signale: Bool?
        if case .booleen(let valeur)? = ligne["signale"] { signale = valeur }
        return NotationRecue(id: id, missionId: texte(ligne["mission_id"]), missionIntitule: texte(ligne["mission_intitule"]),
                             missionFinLe: texte(ligne["mission_fin_le"]), etablissementId: texte(ligne["etablissement_id"]),
                             etablissementNom: texte(ligne["etablissement_nom"]),
                             criteres: ["critere_1", "critere_2", "critere_3", "critere_4"].map { entier(ligne[$0]) },
                             noteMoyenne: nombre(ligne["note_moyenne"]), commentaire: texte(ligne["commentaire"]),
                             signale: signale, creeLe: texte(ligne["cree_le"]))
    }

    static func stats(_ valeur: ValeurJSON?) -> StatsEvaluations? {
        guard let valeur, case .objet = valeur else { return nil }
        return StatsEvaluations(noteMoyenneGlobale: nombre(valeur["note_moyenne_globale"]),
                                totalEvaluations: entier(valeur["total_evaluations"]),
                                pct5Etoiles: nombre(valeur["pct_5_etoiles"]))
    }

    static func evolution(_ valeur: ValeurJSON?) -> [PointEvolutionNotes] {
        guard case .tableau(let points)? = valeur else { return [] }
        return points.compactMap { point in
            guard let mois = texte(point["mois"]), !mois.isEmpty else { return nil }
            return PointEvolutionNotes(mois: mois, noteMoyenne: nombre(point["note_moyenne"]), nb: entier(point["nb"]))
        }
    }

    static func etablissements(_ valeur: ValeurJSON?) -> [EtablissementEvaluateur] {
        guard case .tableau(let lignes)? = valeur else { return [] }
        return lignes.compactMap { ligne in
            guard let id = texte(ligne["id"]), !id.isEmpty, let nom = texte(ligne["nom"]) else { return nil }
            return EtablissementEvaluateur(id: id, nom: nom)
        }
    }

    // MARK: Valeurs

    static func texte(_ valeur: ValeurJSON?) -> String? {
        if case .chaine(let texte)? = valeur { return texte }
        return nil
    }

    static func nombre(_ valeur: ValeurJSON?) -> Double? {
        if case .nombre(let nombre)? = valeur, nombre.isFinite { return nombre }
        return nil
    }

    static func entier(_ valeur: ValeurJSON?) -> Int? {
        guard let nombre = nombre(valeur), nombre.rounded() == nombre, abs(nombre) < 1e15 else { return nil }
        return Int(nombre)
    }
}
