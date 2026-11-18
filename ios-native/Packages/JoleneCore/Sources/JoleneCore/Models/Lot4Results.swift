import Foundation

// Contrats d'échange des ports du lot 4 (`Ports/Lot4Ports.swift`, blueprint `docs/mobile-swift/LOT4_PLAN.md` §2.3,
// tranche T1). Posés par T1 pour que les onze tranches de domaine ne modifient ni `Gateways` ni les protocoles :
// chaque tranche complète ici le contrat de son domaine (champs optionnels, décodage tolérant, sauf les copies de
// bulletins, décodées strictement, §2.4) ou le déplace dans `Models/<Domaine>.swift` (§2.1), comme au lot 1.
// `JoleneError.Kind` n'est pas étendu : les refus métier sont des issues, les erreurs de transport des
// `JoleneError`. Montants, seuils, scores et notes sont des valeurs serveur affichées telles quelles (§2.6).

// MARK: - Swipe (T3a)

/// Carte du paquet de `fn_obtenir_missions_swipe`. Complétée par T3a (clés l.46040-46085 du dump).
public struct CarteSwipe: Equatable, Sendable, Identifiable {
    public var id: String
    public var mission: Mission
    /// Valeur serveur : `nil` seulement après B1 (aujourd'hui `COALESCE(score_global, 0)`, correction 13).
    public var score: Int?
    public var breakdown: [String: Double]
    public var etablissementNom: String?

    public init(id: String, mission: Mission, score: Int?, breakdown: [String: Double] = [:], etablissementNom: String? = nil) {
        self.id = id; self.mission = mission; self.score = score; self.breakdown = breakdown
        self.etablissementNom = etablissementNom
    }
}

/// Directions envoyées à `fn_enregistrer_swipe` hors candidature (le ❤️ passe par `CandidaturePort.confirmer(.swipeLike)`).
public enum DirectionSwipe: String, Equatable, Sendable, CaseIterable {
    case passer = "DISLIKE"
    case favori = "FAVORI"
}

/// Issue de ✕ / ⭐ : la carte n'est retirée qu'après `enregistre` (`ok:true`).
public enum SwipeOutcome: Equatable, Sendable {
    case enregistre
    /// `code` technique du serveur (`mission_deja_swipee`, `mission_indisponible`…), traduit par `SwipeRefus` (T3a).
    case refuse(code: String?, message: String)
}

/// Issue du retrait après ❤️ (`fn_retirer_candidature`), prouvée par relecture : candidature absente.
public enum RetraitOutcome: Equatable, Sendable {
    case retiree
    case refuse(message: String)
}

/// Préférences du quiz (`fn_initialiser_preferences_matching(numeric×4)`, bornes [0, 1]).
public struct PreferencesMatching: Equatable, Sendable {
    public var tarif: Double
    public var distance: Double
    public var etablissement: Double
    public var urgence: Double

    public init(tarif: Double, distance: Double, etablissement: Double, urgence: Double) {
        self.tarif = tarif; self.distance = distance; self.etablissement = etablissement; self.urgence = urgence
    }
}

// MARK: - Filtres sauvegardés (T4)

/// Fréquence d'alerte (`filtre_frequence_alerte`).
public enum FrequenceAlerte: String, Equatable, Sendable, CaseIterable {
    case immediate = "IMMEDIATE"
    case quotidienne = "QUOTIDIENNE"
    case hebdomadaire = "HEBDOMADAIRE"
}

/// Critères d'une recherche (`p_filtres`, clés camelCase du validateur serveur, sept clés toujours présentes) :
/// encodés par `FiltresSauvegardesEncodage` (T4).
public struct FiltresAlerte: Equatable, Sendable {
    public var profession: String
    public var rayonKm: Int
    public var tauxMin: Double
    public var typeContrat: String
    public var urgentesOnly: Bool
    public var horaire: String
    public var villeRecherche: String

    public init(profession: String, rayonKm: Int, tauxMin: Double, typeContrat: String, urgentesOnly: Bool,
                horaire: String, villeRecherche: String) {
        self.profession = profession; self.rayonKm = rayonKm; self.tauxMin = tauxMin; self.typeContrat = typeContrat
        self.urgentesOnly = urgentesOnly; self.horaire = horaire; self.villeRecherche = villeRecherche
    }
}

/// Ligne de `fn_lister_mes_filtres_sauvegardes` (audience `SOIGNANT_RECHERCHE_MISSIONS`), lue par
/// `FiltresSauvegardesEncodage.liste` (T4).
public struct FiltreSauvegarde: Equatable, Sendable, Identifiable {
    public var id: String
    public var nom: String
    public var filtres: ValeurJSON
    public var alerteActive: Bool
    public var frequence: FrequenceAlerte?
    /// T4 : `dernier_check_le` (horodatage serveur), `nil` s'il est absent ou n'est pas un texte.
    public var dernierCheckLe: String?
    /// T4 : `nb_resultats_dernier_check` (valeur serveur), 0 s'il est absent ou illisible.
    public var nbResultatsDernierCheck: Int

    public init(id: String, nom: String, filtres: ValeurJSON, alerteActive: Bool, frequence: FrequenceAlerte?,
                dernierCheckLe: String? = nil, nbResultatsDernierCheck: Int = 0) {
        self.id = id; self.nom = nom; self.filtres = filtres; self.alerteActive = alerteActive; self.frequence = frequence
        self.dernierCheckLe = dernierCheckLe; self.nbResultatsDernierCheck = nbResultatsDernierCheck
    }
}

/// Issue d'une mutation de recherche : la liste relue, ou le refus serveur verbatim.
public enum IssueFiltre: Equatable, Sendable {
    case relue([FiltreSauvegarde])
    case refusee(message: String)
}

// MARK: - Disponibilités (T5)

/// Jour civil Europe/Paris (`yyyy-MM-dd`), dérivé de `ClockPort` par `SemainesDisponibilites` (T2).
public struct JourParis: Hashable, Sendable, Comparable {
    public var iso: String
    public init(iso: String) { self.iso = iso }
    public static func < (a: JourParis, b: JourParis) -> Bool { a.iso < b.iso }
}

public enum CreneauDispo: String, Hashable, Sendable, CaseIterable {
    case journee = "JOURNEE"
    case nuit = "NUIT"
}

/// Case de la grille (`disponibilites_soignant`).
public struct DispoCle: Hashable, Sendable {
    public var jour: JourParis
    public var creneau: CreneauDispo
    public init(jour: JourParis, creneau: CreneauDispo) { self.jour = jour; self.creneau = creneau }
}

/// Issue d'une bascule : la semaine relue (aucun état optimiste), ou le refus serveur verbatim.
public enum IssueDisponibilite: Equatable, Sendable {
    case relue(Set<DispoCle>)
    case refusee(message: String)
}

// MARK: - Parrainage (T6)

public struct Filleul: Equatable, Sendable, Identifiable {
    public var id: String
    public var prenom: String?
    public var statut: String?
    public var seuilAtteint: Bool
    public var resteGmvAvantPrime: Double?

    public init(id: String, prenom: String?, statut: String?, seuilAtteint: Bool, resteGmvAvantPrime: Double?) {
        self.id = id; self.prenom = prenom; self.statut = statut; self.seuilAtteint = seuilAtteint
        self.resteGmvAvantPrime = resteGmvAvantPrime
    }
}

/// `soignants.code_parrainage, badge_ambassadeur` + `fn_obtenir_mes_parrainages` (montants et seuils serveur).
public struct EtatParrainage: Equatable, Sendable {
    public var code: String?
    public var badgeAmbassadeur: Bool
    public var filleuls: [Filleul]
    public var primeEur: Double?
    public var seuilGmvEur: Double?
    public var monParrain: String?

    public init(code: String?, badgeAmbassadeur: Bool, filleuls: [Filleul], primeEur: Double?, seuilGmvEur: Double?,
                monParrain: String?) {
        self.code = code; self.badgeAmbassadeur = badgeAmbassadeur; self.filleuls = filleuls; self.primeEur = primeEur
        self.seuilGmvEur = seuilGmvEur; self.monParrain = monParrain
    }
}

/// Issue de `fn_appliquer_parrainage` : le message serveur de succès n'est jamais affiché (§2.4).
public enum ApplicationParrainage: Equatable, Sendable {
    case appliquee
    /// Refus définitif (`useAppliquerParrainage.ts` l.20-25) : code marqué « appliqué », jamais rejoué.
    case refusDefinitif(message: String)
    /// Refus non définitif ou erreur : code conservé, réessai à la session suivante.
    case aReessayer
}

// MARK: - Litiges et réclamations (T8)

public struct Litige: Equatable, Sendable, Identifiable {
    public var id: String
    public var missionId: String?
    public var statut: String
    public var typeLitige: String?
    public var motif: String?
    public var creeLe: Date?

    public init(id: String, missionId: String?, statut: String, typeLitige: String?, motif: String?, creeLe: Date?) {
        self.id = id; self.missionId = missionId; self.statut = statut; self.typeLitige = typeLitige
        self.motif = motif; self.creeLe = creeLe
    }
}

/// Mission assignée EN_COURS / TERMINEE sans litige ouvert (web `LitigesSoignant.tsx` l.137-146).
public struct MissionContestable: Equatable, Sendable, Identifiable {
    public var id: String
    public var intitule: String?
    public var etablissementId: String?

    public init(id: String, intitule: String?, etablissementId: String?) {
        self.id = id; self.intitule = intitule; self.etablissementId = etablissementId
    }
}

/// Issue de `fn_ouvrir_litige_rate_limited` (3 arguments, `AUTRE`) : `ouvert` après relecture par `litige_id`.
public enum OuvertureLitigeOutcome: Equatable, Sendable {
    case ouvert(id: String, informatif: Bool)
    case refuse(message: String)
}

public struct MessageLitige: Equatable, Sendable, Identifiable {
    public var id: String
    public var auteurId: String?
    public var contenu: String
    public var creeLe: Date?

    public init(id: String, auteurId: String?, contenu: String, creeLe: Date?) {
        self.id = id; self.auteurId = auteurId; self.contenu = contenu; self.creeLe = creeLe
    }
}

/// Issue de `fn_ajouter_message_litige` : le fil relu, ou le refus serveur verbatim.
public enum IssueMessageLitige: Equatable, Sendable {
    case ajoute([MessageLitige])
    case refuse(message: String)
}

/// Catégories de `reclamations_categorie_check` (liste fermée côté app : hors liste → 23514).
public enum CategorieReclamation: String, Equatable, Sendable, CaseIterable {
    case mission = "MISSION"
    case paiement = "PAIEMENT"
    case technique = "TECHNIQUE"
    case comportement = "COMPORTEMENT"
    case autre = "AUTRE"
}

public struct Reclamation: Equatable, Sendable, Identifiable {
    public var id: String
    public var categorie: String
    public var sujet: String
    public var statut: String
    public var creeLe: Date?

    public init(id: String, categorie: String, sujet: String, statut: String, creeLe: Date?) {
        self.id = id; self.categorie = categorie; self.sujet = sujet; self.statut = statut; self.creeLe = creeLe
    }
}

/// Issue de `fn_soumettre_reclamation` (`{id, statut}`, ni `success` ni `ok`) : la ligne relue par `id`.
public enum IssueReclamation: Equatable, Sendable {
    case soumise(Reclamation)
    case refusee(message: String)
}

// MARK: - Score et évaluations (T9)

/// `fn_mon_breakdown_actuel` : composantes telles que servies.
public struct BreakdownScore: Equatable, Sendable {
    public var score: Double?
    public var niveau: String?
    public var composantes: [String: Double]

    public init(score: Double?, niveau: String?, composantes: [String: Double]) {
        self.score = score; self.niveau = niveau; self.composantes = composantes
    }
}

/// Point de `fn_evolution_score_soignant(int)` (`{mois, score, niveau, cree_le}`).
public struct PointEvolutionScore: Equatable, Sendable {
    public var mois: String
    public var score: Double?
    public var niveau: String?

    public init(mois: String, score: Double?, niveau: String?) { self.mois = mois; self.score = score; self.niveau = niveau }
}

/// Événement de `fn_mes_evenements_score` (clé **`events`**, correction 16) ; `contestable` calculé serveur.
public struct EvenementScore: Equatable, Sendable, Identifiable {
    public var id: String
    public var typeEvenement: String
    public var points: Double?
    public var motif: String?
    public var contestable: Bool
    public var creeLe: Date?

    public init(id: String, typeEvenement: String, points: Double?, motif: String?, contestable: Bool, creeLe: Date?) {
        self.id = id; self.typeEvenement = typeEvenement; self.points = points; self.motif = motif
        self.contestable = contestable; self.creeLe = creeLe
    }
}

/// Notation reçue et PUBLIÉE, lue seulement par `fn_lister_notations_recues` ou
/// `fn_mes_notations_recues_avec_stats` (filtre de visibilité centralisé, garde-fou 18).
public struct NotationRecue: Equatable, Sendable, Identifiable {
    public var id: String
    public var note: Double?
    public var commentaire: String?
    public var etablissementNom: String?
    public var signale: Bool
    public var publieLe: Date?

    public init(id: String, note: Double?, commentaire: String?, etablissementNom: String?, signale: Bool, publieLe: Date?) {
        self.id = id; self.note = note; self.commentaire = commentaire; self.etablissementNom = etablissementNom
        self.signale = signale; self.publieLe = publieLe
    }
}

/// Issue de `fn_creer_reclamation_score` (`p_justificatif_storage_path` jamais envoyé, D10).
public enum ReclamationScoreOutcome: Equatable, Sendable {
    case enregistree(reclamationId: String)
    /// `error_code` serveur (`TEXTE_REQUIS`, `NON_CONTESTABLE`…) et message verbatim.
    case refusee(code: String?, message: String)
}

/// Filtres de la page Évaluations (`fn_mes_notations_recues_avec_stats(text, int, uuid, int, int)`).
public struct FiltreEvaluations: Equatable, Sendable {
    public var periode: String?
    public var noteMin: Int?
    public var etablissementId: String?

    public init(periode: String? = nil, noteMin: Int? = nil, etablissementId: String? = nil) {
        self.periode = periode; self.noteMin = noteMin; self.etablissementId = etablissementId
    }
}

/// Page de 20 notations publiées, statistiques et évolution serveur (aucune moyenne recalculée).
public struct PageEvaluations: Equatable, Sendable {
    public var total: Int
    public var notations: [NotationRecue]
    public var noteMoyenne: Double?
    public var evolution: [PointEvolutionScore]

    public init(total: Int, notations: [NotationRecue], noteMoyenne: Double?, evolution: [PointEvolutionScore]) {
        self.total = total; self.notations = notations; self.noteMoyenne = noteMoyenne; self.evolution = evolution
    }
}

/// Issue d'un signalement (notation, utilisateur) : relu, ou refus verbatim.
public enum IssueSignalement: Equatable, Sendable {
    case signale
    case refuse(message: String)
}

// MARK: - Messagerie et Realtime (T7a)

/// Curseur keyset `(ordre_le, id)` de `fn_lister_conversations_messagerie`.
public struct CurseurConversations: Equatable, Sendable {
    public var ordreLe: String
    public var id: String
    public init(ordreLe: String, id: String) { self.ordreLe = ordreLe; self.id = id }
}

public struct ConversationApercu: Equatable, Sendable, Identifiable {
    public var id: String
    public var autreId: String?
    public var missionId: String?
    public var etablissementId: String?
    public var dernierContenu: String?
    public var nonLus: Int
    public var archivee: Bool

    public init(id: String, autreId: String?, missionId: String?, etablissementId: String?, dernierContenu: String?,
                nonLus: Int, archivee: Bool) {
        self.id = id; self.autreId = autreId; self.missionId = missionId; self.etablissementId = etablissementId
        self.dernierContenu = dernierContenu; self.nonLus = nonLus; self.archivee = archivee
    }
}

/// Page de 100 conversations ; `suivant` nil quand le curseur ne change plus (arrêt de la pagination).
public struct PageConversations: Equatable, Sendable {
    public var conversations: [ConversationApercu]
    public var suivant: CurseurConversations?
    public init(conversations: [ConversationApercu], suivant: CurseurConversations?) {
        self.conversations = conversations; self.suivant = suivant
    }
}

public struct Interlocuteur: Equatable, Sendable, Identifiable {
    public var id: String
    public var nom: String?
    public var estJolene: Bool
    public init(id: String, nom: String?, estJolene: Bool) { self.id = id; self.nom = nom; self.estJolene = estJolene }
}

/// Ligne de `messages_chat` (contenu jamais journalisé, §2.6).
public struct MessageChat: Equatable, Sendable, Identifiable {
    public var id: String
    public var conversationId: String
    public var expediteurId: String?
    public var contenu: String
    public var creeLe: Date?

    public init(id: String, conversationId: String, expediteurId: String?, contenu: String, creeLe: Date?) {
        self.id = id; self.conversationId = conversationId; self.expediteurId = expediteurId; self.contenu = contenu
        self.creeLe = creeLe
    }
}

/// `DetectedType` de `supabase/functions/_shared/anti-leak.ts` l.15.
public enum DetectedType: String, Equatable, Sendable, CaseIterable {
    case telephone = "TELEPHONE"
    case email = "EMAIL"
    case url = "URL"
    case handle = "HANDLE"
    case keyword = "KEYWORD"
}

/// Issue de l'envoi par l'edge `messagerie-validate` : jamais un écho Realtime supposé.
public enum EnvoiOutcome: Equatable, Sendable {
    case envoye(messageId: String)
    case antiFuite(DetectedType?)
    case refuse(code: String?, message: String)
    /// Délai dépassé ou 200 sans `message_id` : relecture du fil, aucun renvoi automatique.
    case nonConfirme
}

/// Issue de `fn_marquer_messages_lus` : `42501 Accès refusé` est un refus métier, jamais « session expirée ».
public enum IssueLecture: Equatable, Sendable {
    case lus
    case accesRefuse
}

/// Issue de « Écrire à l'établissement » (`fn_user_id_pour_etablissement` puis `fn_obtenir_conversation`).
public enum IssueConversationMission: Equatable, Sendable {
    case conversation(id: String)
    case indisponible(message: String)
}

/// Cible d'un signalement (`fn_signaler_utilisateur`, `p_cible_type`).
public enum TypeCibleSignalement: String, Equatable, Sendable, CaseIterable {
    case etablissement = "ETABLISSEMENT"
    case soignant = "SOIGNANT"
}

public struct EtatSaisie: Equatable, Sendable {
    public var userId: String
    public var enTrain: Bool
    public init(userId: String, enTrain: Bool) { self.userId = userId; self.enTrain = enTrain }
}

public struct EtatPresence: Equatable, Sendable {
    public var userId: String
    public var enLigne: Bool
    public var vuLe: Date?
    public init(userId: String, enLigne: Bool, vuLe: Date?) { self.userId = userId; self.enLigne = enLigne; self.vuLe = vuLe }
}

/// État d'un canal Realtime : à chaque `rejoint` après coupure, relecture du fil (§2.5).
public enum EtatCanal: Equatable, Sendable {
    case connexion
    case rejoint
    case coupe
    case ferme
}

// MARK: - Bulletins (T10)

public enum StatutCopieBulletin: String, Equatable, Sendable, CaseIterable {
    case publiee = "PUBLIEE"
    case remplacee = "REMPLACEE"
    case retiree = "RETIREE"
}

/// Ligne de `fn_lister_copies_bulletins`, validée STRICTEMENT (exception assumée au décodage tolérant, §2.4).
public struct CopieBulletin: Equatable, Sendable, Identifiable {
    public var id: String
    public var employeurNom: String?
    public var periodeDebut: String
    public var periodeFin: String
    public var statut: StatutCopieBulletin
    public var tailleOctets: Int
    public var sha256: String
    public var missionIds: [String]
    public var signalee: Bool

    public init(id: String, employeurNom: String?, periodeDebut: String, periodeFin: String, statut: StatutCopieBulletin,
                tailleOctets: Int, sha256: String, missionIds: [String], signalee: Bool) {
        self.id = id; self.employeurNom = employeurNom; self.periodeDebut = periodeDebut; self.periodeFin = periodeFin
        self.statut = statut; self.tailleOctets = tailleOctets; self.sha256 = sha256; self.missionIds = missionIds
        self.signalee = signalee
    }
}

/// PDF reçu de l'edge `copies-bulletins`, type, taille et SHA-256 vérifiés contre la ligne.
public struct PDFVerifie: Equatable, Sendable {
    public var donnees: Data
    public var sha256: String
    public init(donnees: Data, sha256: String) { self.donnees = donnees; self.sha256 = sha256 }
}

/// Motifs de `fn_signaler_copie_bulletin` (`copiesBulletins.ts` l.10) ; `DESTINATAIRE` retire la copie (correction 18).
public enum MotifSignalementCopie: String, Equatable, Sendable, CaseIterable {
    case destinataire = "DESTINATAIRE"
    case contenu = "CONTENU"
    case autre = "AUTRE"
}

// MARK: - Pool urgence et exclusions (T11)

public struct MissionUrgente: Equatable, Sendable, Identifiable {
    public var id: String
    public var mission: Mission
    public var statutCandidature: String?
    public init(id: String, mission: Mission, statutCandidature: String?) {
        self.id = id; self.mission = mission; self.statutCandidature = statutCandidature
    }
}

/// `fn_pool_urgence_missions_pour_soignant` : `{missions, pool_actif, rayon_km, sms_opt_in}`.
public struct EtatPool: Equatable, Sendable {
    public var actif: Bool
    public var rayonKm: Int?
    public var smsOptIn: Bool
    public var missions: [MissionUrgente]

    public init(actif: Bool, rayonKm: Int?, smsOptIn: Bool, missions: [MissionUrgente]) {
        self.actif = actif; self.rayonKm = rayonKm; self.smsOptIn = smsOptIn; self.missions = missions
    }
}

/// Issue d'une bascule du pool : l'état relu, ou le refus serveur verbatim (documents, rayon).
public enum IssuePool: Equatable, Sendable {
    case relu(EtatPool)
    case refuse(message: String)
}

public struct Exclusion: Equatable, Sendable, Identifiable {
    public var id: String
    /// Identifiant de l'exclu (paramètre de `fn_retirer_exclusion`, pas l'id de ligne, l.54888-54891).
    public var excluId: String
    public var etablissementNom: String?
    public var motif: String?
    public var creeLe: Date?

    public init(id: String, excluId: String, etablissementNom: String?, motif: String?, creeLe: Date?) {
        self.id = id; self.excluId = excluId; self.etablissementNom = etablissementNom; self.motif = motif
        self.creeLe = creeLe
    }
}

/// Issue d'une exclusion ou de son retrait : exclusions envoyées relues, ou refus verbatim.
public enum IssueExclusion: Equatable, Sendable {
    case relues([Exclusion])
    case refusee(message: String)
}
