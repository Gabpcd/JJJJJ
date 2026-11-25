import Foundation

// Contrats d'échange des ports du lot 4 (`Ports/Lot4Ports.swift`, blueprint `docs/mobile-swift/LOT4_PLAN.md` §2.3,
// tranche T1). Posés par T1 pour que les onze tranches de domaine ne modifient ni `Gateways` ni les protocoles :
// chaque tranche complète ici le contrat de son domaine (champs optionnels, décodage tolérant, sauf les copies de
// bulletins, décodées strictement, §2.4) ou le déplace dans `Models/<Domaine>.swift` (§2.1), comme au lot 1.
// `JoleneError.Kind` n'est pas étendu : les refus métier sont des issues, les erreurs de transport des
// `JoleneError`. Montants, seuils, scores et notes sont des valeurs serveur affichées telles quelles (§2.6).

// MARK: - Swipe (T3a)

// `CarteSwipe`, `DirectionSwipe`, `SwipeOutcome`, `RetraitOutcome` et `PreferencesMatching` : `Models/Swipe.swift`
// (déplacés par T3a avec leur décodage tolérant, comme `Models/Favoris.swift` au lot 1).

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

/// Filleul de `fn_obtenir_mes_parrainages` (`filleuls[]`, lu comme `PageParrainage.tsx` l.70-81) : identifiant
/// `filleul_id`, prénom « Soignant » par défaut, statut `INSCRIT` par défaut. Les champs de progression vers la prime
/// sont lus mais jamais affichés par l'écran natif (bloc de conditions sous HARD STOP n°4, T6-HS).
public struct Filleul: Equatable, Sendable, Identifiable {
    public var id: String
    public var prenom: String
    public var statut: String
    public var creeLe: String?
    public var premiereMissionLe: String?
    public var primeVerseeLe: String?
    public var seuilAtteint: Bool?
    public var resteGmvAvantPrime: Double?

    public init(id: String, prenom: String, statut: String, creeLe: String?, premiereMissionLe: String?,
                primeVerseeLe: String? = nil, seuilAtteint: Bool? = nil, resteGmvAvantPrime: Double? = nil) {
        self.id = id; self.prenom = prenom; self.statut = statut; self.creeLe = creeLe
        self.premiereMissionLe = premiereMissionLe; self.primeVerseeLe = primeVerseeLe; self.seuilAtteint = seuilAtteint
        self.resteGmvAvantPrime = resteGmvAvantPrime
    }
}

/// `mon_parrain` de `fn_obtenir_mes_parrainages` (`{parrain_prenom, statut, prime_versee_le}`, JSON `null` sans parrain).
public struct MonParrain: Equatable, Sendable {
    public var prenom: String?
    public var statut: String?

    public init(prenom: String?, statut: String?) {
        self.prenom = prenom; self.statut = statut
    }
}

/// `soignants.code_parrainage, badge_ambassadeur` + `fn_obtenir_mes_parrainages`. `primeEur` et `seuilGmvEur` (valeurs
/// serveur) sont réservés au bloc de conditions (T6-HS) : jamais affichés par cette tranche.
public struct EtatParrainage: Equatable, Sendable {
    /// Ligne `soignants` présente (texte « à préparer » du web, l.143-145).
    public var profilPresent: Bool
    public var code: String?
    public var badgeAmbassadeur: Bool
    public var filleuls: [Filleul]
    public var primeEur: Double?
    public var seuilGmvEur: Double?
    public var monParrain: MonParrain?

    public init(profilPresent: Bool, code: String?, badgeAmbassadeur: Bool, filleuls: [Filleul], primeEur: Double?,
                seuilGmvEur: Double?, monParrain: MonParrain?) {
        self.profilPresent = profilPresent; self.code = code; self.badgeAmbassadeur = badgeAmbassadeur
        self.filleuls = filleuls; self.primeEur = primeEur; self.seuilGmvEur = seuilGmvEur; self.monParrain = monParrain
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

// `Litige`, `MissionContestable`, `OuvertureLitigeOutcome`, `MessageLitige`, `IssueMessageLitige` : `Models/Litiges.swift` ;
// `CategorieReclamation`, `Reclamation`, `IssueReclamation` : `Models/Reclamations.swift` (déplacés par T8 avec leur
// décodage tolérant, comme `Models/Swipe.swift` par T3a).

// MARK: - Score et évaluations (T9)

// `BreakdownScore`, `PointEvolutionScore`, `EvenementScore`, `MotifContestationScore` et `ReclamationScoreOutcome` :
// `Models/Score.swift` ; `NotationRecue`, `FiltreEvaluations` et `PageEvaluations` : `Models/Evaluations.swift`
// (déplacés par T9 avec leur décodage tolérant, comme `Models/Swipe.swift`).

/// Issue d'un signalement (notation, utilisateur) : relu, ou refus verbatim.
public enum IssueSignalement: Equatable, Sendable {
    case signale
    case refuse(message: String)
}

// MARK: - Messagerie et Realtime (T7a)

// `CurseurConversations`, `ConversationApercu`, `PageConversations`, `Interlocuteur`, `MessageChat`, `DetectedType`,
// `EnvoiOutcome`, `IssueLecture`, `IssueConversationMission`, `TypeCibleSignalement`, `EtatSaisie`, `EtatPresence` et
// `EtatCanal` : `Models/Messagerie.swift` (déplacés par T7a avec leur décodage tolérant, comme `Models/Swipe.swift`).

// MARK: - Bulletins (T10)

public enum StatutCopieBulletin: String, Equatable, Sendable, CaseIterable {
    case publiee = "PUBLIEE"
    case remplacee = "REMPLACEE"
    case retiree = "RETIREE"
}

/// `motif_remplacement` d'une version qui en remplace une autre (`MotifRemplacementCopie`, `copiesBulletins.ts` l.11).
public enum MotifRemplacementCopie: String, Equatable, Sendable, CaseIterable {
    case contenu = "CONTENU"
    case autre = "AUTRE"
}

/// Ligne de `fn_lister_copies_bulletins`, validée STRICTEMENT (exception assumée au décodage tolérant, §2.4).
/// T10 : `etablissementId` (clé du filtre « Employeur »), `version`, `publieLe` et `motifRemplacement`, affichés tels
/// que le serveur les rend ; les champs que l'écran du soignant n'affiche pas (`soignant_*`, `remplace_id`) sont
/// contrôlés par la validation mais ne sont pas gardés.
public struct CopieBulletin: Equatable, Sendable, Identifiable {
    public var id: String
    public var etablissementId: String
    public var employeurNom: String?
    public var periodeDebut: String
    public var periodeFin: String
    public var statut: StatutCopieBulletin
    public var version: Int
    public var publieLe: String
    public var motifRemplacement: MotifRemplacementCopie?
    public var tailleOctets: Int
    public var sha256: String
    public var missionIds: [String]
    public var signalee: Bool

    public init(id: String, etablissementId: String, employeurNom: String?, periodeDebut: String, periodeFin: String,
                statut: StatutCopieBulletin, version: Int, publieLe: String, motifRemplacement: MotifRemplacementCopie?,
                tailleOctets: Int, sha256: String, missionIds: [String], signalee: Bool) {
        self.id = id; self.etablissementId = etablissementId; self.employeurNom = employeurNom
        self.periodeDebut = periodeDebut; self.periodeFin = periodeFin; self.statut = statut; self.version = version
        self.publieLe = publieLe; self.motifRemplacement = motifRemplacement; self.tailleOctets = tailleOctets
        self.sha256 = sha256; self.missionIds = missionIds; self.signalee = signalee
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
    /// `deja_candidate` du serveur (T11) : une candidature existe, même sans statut lisible (« Tu as déjà candidaté »).
    public var dejaCandidate: Bool = false
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
