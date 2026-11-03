import Foundation

// Contrats d'échange des ports de l'espace établissement (`Ports/Lot5Ports.swift`, lot 5 T1 ;
// `docs/mobile-swift/LOT5_PLAN.md` §2.4-§2.5). Posés par T1 pour que les tranches suivantes ne
// modifient ni `EtablissementGateways` ni les signatures des protocoles : chaque tranche complète ici
// le contrat de son domaine (champs optionnels, décodage tolérant) ou le déplace dans son dossier
// `Etablissement/<Domaine>/`. `JoleneError.Kind` n'est pas étendu : les refus métier structurés sont
// des issues, les erreurs de transport des `JoleneError`. Aucun champ monétaire (D15), aucune note
// lue (§2.8) : un modèle de lecture n'en déclare jamais.

// MARK: - Candidatures (T6)

/// Décision de `fn_traiter_candidature_planning_v1` (`p_decision`).
public enum DecisionCandidature: String, CaseIterable, Sendable {
    case acceptee = "ACCEPTEE"
    case refusee = "REFUSEE"
}

/// Cas d'acceptation renvoyés au web avant tout appel (D10, D25 ; correction 19).
public enum MotifRenvoiWebCandidature: String, CaseIterable, Sendable {
    /// Mission `TOUS` ou `LIBERAL` : escrow et mandat de facturation possibles.
    case contratNonSalarie = "CONTRAT_NON_SALARIE"
    /// Mission `MEDECIN` : statuts d'internat non portés.
    case medecin = "MEDECIN"
    /// Étudiant aide-soignant (cadre étudiant) : aucune case juridique en natif.
    case cadreEtudiant = "CADRE_ETUDIANT"
}

/// Issue d'un traitement de candidature par l'établissement. Messages serveur verbatim (HARD STOP
/// n°4). `acceptee` et `refusEnregistre` ne disent que ce que le serveur a répondu : l'écran relit
/// `fn_lire_candidatures_mission_habilitee` avant d'annoncer un succès (PRINCIPES §3).
public enum TraitementCandidatureOutcome: Equatable, Sendable {
    /// Acceptation répondue `success:true` (contrat éventuel servi par `fn_finaliser_attribution_mission`).
    case acceptee(contratId: String?)
    /// Refus de la candidature répondu `success:true` (l.61782).
    case refusEnregistre
    /// Refus serveur de l'action : jsonb (`code` serveur), choix de contrat ou documents requis
    /// relayés tels quels, exception `[CODE DU TRAVAIL]` (`CandidatureOutcome.codeRefusCodeDuTravail`).
    case refusee(code: String?, message: String, documentsRequisPour: String?)
    /// `PLANNING_A_RECONFIRMER` / `PLANNING_MODIFIE_RECONFIRMER` : relire puis reconfirmer, jamais renvoyer.
    case planningAReconfirmer(code: String, message: String)
    /// `CADRE_ETUDIANT_A_CONFIRMER` seul (l.61929-61935) → renvoi web ; les autres `CADRE_ETUDIANT_*`
    /// sont des `.refusee` verbatim (correction 19).
    case cadreEtudiant(code: String, message: String)
    /// 42501 en liste blanche (`Mission indisponible ou accès refusé`, trigger RBAC) : jamais « session expirée ».
    case accesRefuse(message: String)
    /// P0001 de `fn_trg_gate_assignation_paiement` (l.63314, l.63317) → message verbatim + Safari facturation.
    case paiementNonConfigure(message: String)
    /// Acceptation hors périmètre natif, refusée localement avant tout appel.
    case renvoiWeb(motif: MotifRenvoiWebCandidature)

    /// Seul code du cadre étudiant qui renvoie au web (le web peut confirmer, le natif non).
    public static let codeCadreEtudiantAConfirmer = "CADRE_ETUDIANT_A_CONFIRMER"
    /// Préfixe des refus du cadre étudiant (`fn_traiter_candidature_planning_v1`, l.61904-61935).
    public static let prefixeCadreEtudiant = "CADRE_ETUDIANT_"
}

/// Lecture habilitée `fn_lire_candidatures_mission_habilitee` (l.39524) : contrat minimal posé par T1,
/// complété par T6 (soignant à l'initiale, `nom_anonymise`, étudiant ; jamais `note_moyenne`).
public struct LectureCandidaturesHabilitee: Equatable, Sendable {
    public var missionId: String
    public var statutMission: String?
    public var nbCreneaux: Int?
    /// Créneaux PREVISIONNEL hors pause, chaînes `debut`/`fin` telles que servies (D26).
    public var creneaux: [MissionSlot]
    public var candidatures: [CandidatureHabilitee]

    public init(missionId: String, statutMission: String?, nbCreneaux: Int?, creneaux: [MissionSlot],
                candidatures: [CandidatureHabilitee]) {
        self.missionId = missionId; self.statutMission = statutMission; self.nbCreneaux = nbCreneaux
        self.creneaux = creneaux; self.candidatures = candidatures
    }
}

/// Élément `candidatures[]` de la lecture habilitée (contrat minimal, complété par T6).
public struct CandidatureHabilitee: Equatable, Sendable, Identifiable {
    public var id: String
    public var soignantId: String?
    public var statut: String?
    public var creeLe: String?

    public init(id: String, soignantId: String?, statut: String?, creeLe: String?) {
        self.id = id; self.soignantId = soignantId; self.statut = statut; self.creeLe = creeLe
    }
}

// MARK: - Présences (T8, B9)

/// Issue d'une validation unitaire : `valide_le` relu (valeur serveur, jamais posée localement).
public enum ValidationPresenceOutcome: Equatable, Sendable {
    case validee(valideLe: String)
    case refusee(message: String)
    case accesRefuse(message: String)
}

/// Issue d'une validation en lot : comptes **relus** par identifiant, jamais déduits de `nb_validees`.
public enum ValidationLotOutcome: Equatable, Sendable {
    case traitee(validees: Int, selectionnees: Int)
    case refusee(message: String)
    case accesRefuse(message: String)
}

/// Issue d'une contestation : `motif_litige` relu.
public enum ContestationOutcome: Equatable, Sendable {
    case contestee(motifLitige: String)
    case refusee(message: String)
    case accesRefuse(message: String)
}

/// Note 1-5 envoyée après une validation relue (D6) : best-effort, jamais bloquante ; « déjà notée »
/// est un succès (`NotationRapide.tsx` l.61).
public enum NotationOutcome: Equatable, Sendable {
    case enregistree
    case nonEnregistree(message: String?)
}

/// Issue d'une clôture rétroactive : `segment_ouvert == false` relu ; `nouveau_code` jamais décodé
/// (correction 17).
public enum ClotureOutcome: Equatable, Sendable {
    case cloturee
    case refusee(message: String)
    case accesRefuse(message: String)
}

/// Ligne `presences` d'une mission de l'établissement (contrat minimal, complété par T8 ; jamais de
/// coordonnées GPS).
public struct PresenceEtab: Equatable, Sendable, Identifiable {
    public var id: String
    public var missionId: String
    public var valideParEtablissement: Bool
    public var valideLe: String?
    public var motifLitige: String?

    public init(id: String, missionId: String, valideParEtablissement: Bool, valideLe: String?, motifLitige: String?) {
        self.id = id; self.missionId = missionId; self.valideParEtablissement = valideParEtablissement
        self.valideLe = valideLe; self.motifLitige = motifLitige
    }
}

// MARK: - Publication (T9)

/// Brouillon d'une mission simple ou urgente, salariée, au taux horaire (D8). Contrat minimal posé par
/// T1, complété par T9 ; `creneaux` = instants matérialisés par `PlanningDerive`, envoyés tels quels.
public struct PublicationMission: Equatable, Sendable {
    public var intitule: String
    public var description: String?
    public var professionRequise: String
    public var service: String?
    /// Seul montant du lot 5 : le taux saisi, renvoyé dans le récapitulatif (§2.8).
    public var tauxHoraireBase: Double
    public var estUrgente: Bool
    public var creneaux: [CreneauConfirme]

    public init(intitule: String, description: String?, professionRequise: String, service: String?,
                tauxHoraireBase: Double, estUrgente: Bool, creneaux: [CreneauConfirme]) {
        self.intitule = intitule; self.description = description; self.professionRequise = professionRequise
        self.service = service; self.tauxHoraireBase = tauxHoraireBase; self.estUrgente = estUrgente; self.creneaux = creneaux
    }
}

/// Issue d'une publication : `publiee` seulement après relecture `missions` + `mission_creneaux` (T9).
public enum PublicationOutcome: Equatable, Sendable {
    case publiee(missionId: String)
    /// Refus serveur verbatim (`{success:false, error}`, `CREATION_MISSION_INDISPONIBLE`, `PLAFOND_48H_HEBDO`…).
    case refusee(code: String?, message: String)
    /// `{error: CODE, message}` de `fn_blocage_publication_etab` (correction 8) → renvoi web.
    case blocageEtablissement(code: String, message: String)
}

// MARK: - Tableau de bord (T4)

/// Tableau de bord établissement (`fn_stats_dashboard_etablissement`, l.57610) : contrat minimal posé
/// par T1, complété par T4. Compteurs seulement, montants jamais décodés.
public struct EtabDashboardSnapshot: Equatable, Sendable {
    public var candidaturesEnAttente: Int?
    public var messagesNonLus: Int?
    public var litigesOuverts: Int?

    public init(candidaturesEnAttente: Int? = nil, messagesNonLus: Int? = nil, litigesOuverts: Int? = nil) {
        self.candidaturesEnAttente = candidaturesEnAttente; self.messagesNonLus = messagesNonLus
        self.litigesOuverts = litigesOuverts
    }
}

// MARK: - Missions (T5)

/// Mission de l'établissement, colonnes sans montant (§2.8 : ni `taux_horaire_base`, ni `total_brut`,
/// ni `net_a_payer`). Contrat minimal posé par T1, complété par T5.
public struct EtabMissionResume: Equatable, Sendable, Identifiable {
    public var id: String
    public var intitule: String
    public var statut: String?
    public var debutLe: String?
    public var finLe: String?
    public var nbCreneaux: Int?
    public var professionRequise: String?
    /// Lu avant toute acceptation (D25).
    public var typeContratRecherche: String?
    public var estUrgente: Bool?

    public init(id: String, intitule: String, statut: String? = nil, debutLe: String? = nil, finLe: String? = nil,
                nbCreneaux: Int? = nil, professionRequise: String? = nil, typeContratRecherche: String? = nil,
                estUrgente: Bool? = nil) {
        self.id = id; self.intitule = intitule; self.statut = statut; self.debutLe = debutLe; self.finLe = finLe
        self.nbCreneaux = nbCreneaux; self.professionRequise = professionRequise
        self.typeContratRecherche = typeContratRecherche; self.estUrgente = estUrgente
    }
}

/// Page de missions de l'établissement (pages de 50, comme `MissionsPage`).
public struct EtabMissionsPage: Equatable, Sendable {
    public static let taille = 50

    public var missions: [EtabMissionResume]
    public var page: Int
    public var aSuivre: Bool

    public init(missions: [EtabMissionResume], page: Int, aSuivre: Bool) {
        self.missions = missions; self.page = page; self.aSuivre = aSuivre
    }
}

/// Détail d'une mission de l'établissement (contrat minimal, complété par T5).
public struct EtabMissionDetail: Equatable, Sendable {
    public var mission: EtabMissionResume
    public var creneaux: [MissionSlot]
    public var soignantAssigneId: String?

    public init(mission: EtabMissionResume, creneaux: [MissionSlot], soignantAssigneId: String?) {
        self.mission = mission; self.creneaux = creneaux; self.soignantAssigneId = soignantAssigneId
    }
}

/// `fn_soignant_pour_etablissement` (l.57155), tel que servi : un `null` SQL (soignant supprimé) est
/// rendu `nil` par le port (« Soignant indisponible »), jamais un profil vide. Contrat minimal (T5).
public struct SoignantPourEtab: Equatable, Sendable, Identifiable {
    public var id: String
    public var prenom: String?
    public var nom: String?
    public var profession: String?

    public init(id: String, prenom: String?, nom: String?, profession: String?) {
        self.id = id; self.prenom = prenom; self.nom = nom; self.profession = profession
    }
}

// MARK: - Pointage terrain (T7)

/// Réponse de `fn_etat_pointage_mission` utile à l'affichage : le type des règles pures de T3.
public typealias EtatPointageEtab = CodeRotatifRules.Etat

/// Planning lu pour le pointage (web l.100-112) : mission (`id`, `debut_le`, `fin_le`, `nb_creneaux`)
/// et créneaux PREVISIONNEL hors pause, analysés par `CodeRotatifRules.Planning.depuis`.
public struct PlanningMission: Equatable, Sendable {
    public var mission: MissionAvecPlanningAttendu
    public var creneaux: [MissionSlot]

    public init(mission: MissionAvecPlanningAttendu, creneaux: [MissionSlot]) {
        self.mission = mission; self.creneaux = creneaux
    }
}

// MARK: - Audit (T1, consommé par T4)

/// Pages auditées en consultation (`DONNEES_PERSO_CONSULTATION`, D19), valeurs du web.
public enum PageAuditEtab: String, CaseIterable, Sendable {
    /// `DashboardEtablissement.tsx` l.424 : `p_details: { page: 'dashboard_etablissement' }`.
    case tableauDeBord = "dashboard_etablissement"
}
