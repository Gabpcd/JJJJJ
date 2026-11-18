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

/// Lecture habilitée `fn_lire_candidatures_mission_habilitee` (`supabase/schema/public.sql` l.39970) : contrat
/// posé par T1, complété par T6 (intitulé, établissement, mode d'attribution, profession requise ; candidat à
/// l'initiale). Décodage tolérant dans `Etablissement/Candidatures/LectureCandidaturesHabilitee+Decodage.swift`.
/// **Jamais décodés** : `note_moyenne`, `nb_evaluations` (D8), `internat` (D10), `type_exercice` (le régime vient de
/// la mission), `etudiant_details`, `specialite_medicale`, `specialite_medicale_requise`, `accepte_internes`.
/// `type_contrat_recherche` n'y figure pas : lu par T5 (`EtabMissionsPort.mission`, D25).
public struct LectureCandidaturesHabilitee: Equatable, Sendable {
    public var missionId: String
    public var statutMission: String?
    public var nbCreneaux: Int?
    /// Créneaux PREVISIONNEL hors pause, chaînes `debut`/`fin` telles que servies (D26), ordre serveur `debut, id`.
    public var creneaux: [MissionSlot]
    public var candidatures: [CandidatureHabilitee]
    public var intitule: String?
    /// Établissement de la mission relue : comparé au contexte confirmé, jamais une valeur de filtre.
    public var etablissementId: String?
    public var modeAttribution: String?
    public var professionRequise: String?

    public init(missionId: String, statutMission: String?, nbCreneaux: Int?, creneaux: [MissionSlot],
                candidatures: [CandidatureHabilitee], intitule: String? = nil, etablissementId: String? = nil,
                modeAttribution: String? = nil, professionRequise: String? = nil) {
        self.missionId = missionId; self.statutMission = statutMission; self.nbCreneaux = nbCreneaux
        self.creneaux = creneaux; self.candidatures = candidatures; self.intitule = intitule
        self.etablissementId = etablissementId; self.modeAttribution = modeAttribution
        self.professionRequise = professionRequise
    }
}

/// Élément `candidatures[]` de la lecture habilitée (ordre serveur `cree_le, id`).
public struct CandidatureHabilitee: Equatable, Sendable, Identifiable {
    public var id: String
    public var soignantId: String?
    public var statut: String?
    public var creeLe: String?
    /// Message du candidat, affiché tel quel.
    public var message: String?
    /// Soignant tel que servi (nom à l'initiale, `nom_anonymise:true`).
    public var soignant: CandidatHabilite?

    public init(id: String, soignantId: String?, statut: String?, creeLe: String?, message: String? = nil,
                soignant: CandidatHabilite? = nil) {
        self.id = id; self.soignantId = soignantId; self.statut = statut; self.creeLe = creeLe
        self.message = message; self.soignant = soignant
    }
}

/// Objet `soignant` d'une candidature de la lecture habilitée (l.40017-40025), réduit à ce que l'écran affiche et à
/// l'aiguillage du cadre étudiant (`est_etudiant`, `profession` : aiguillage seulement, le serveur décide,
/// correction 19). Aucune note, aucun statut d'internat, aucun mode d'exercice.
public struct CandidatHabilite: Equatable, Sendable, Identifiable {
    public var id: String
    public var prenom: String?
    /// Initiale servie par le serveur (« D. »).
    public var nom: String?
    public var nomAnonymise: Bool?
    public var profession: String?
    public var estEtudiant: Bool?
    public var scoreFiabilite: Int?
    public var totalMissionsTerminees: Int?
    public var tousDocumentsValides: Bool?

    public init(id: String, prenom: String?, nom: String?, nomAnonymise: Bool? = nil, profession: String? = nil,
                estEtudiant: Bool? = nil, scoreFiabilite: Int? = nil, totalMissionsTerminees: Int? = nil,
                tousDocumentsValides: Bool? = nil) {
        self.id = id; self.prenom = prenom; self.nom = nom; self.nomAnonymise = nomAnonymise
        self.profession = profession; self.estEtudiant = estEtudiant; self.scoreFiabilite = scoreFiabilite
        self.totalMissionsTerminees = totalMissionsTerminees; self.tousDocumentsValides = tousDocumentsValides
    }
}

/// Refus de **droit** d'une lecture de l'espace établissement (42501 en liste blanche, D12 ; correction 5) :
/// jamais « session expirée », jamais une déconnexion. `message` = texte serveur verbatim (ou message neutre du
/// trigger RBAC). L'écran l'affiche puis relit les permissions une fois (`SessionStore.refreshEtablissementScope`).
/// Les mutations rendent l'issue `.accesRefuse` de leur domaine ; cette erreur sert aux lectures (T6).
public struct RefusAccesEtablissement: Error, Equatable, Sendable {
    public var message: String

    public init(message: String) { self.message = message }
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

/// Issue d'une clôture rétroactive : `segment_ouvert == false` relu ; le code de pointage suivant de la réponse jamais décodé
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

// MARK: - Tableau de bord (T4) : `Etablissement/Accueil/EtabDashboardSnapshot.swift`.

// MARK: - Missions (T5)

/// Mission de l'établissement, colonnes sans montant (§2.8 : ni `taux_horaire_base`, ni `total_brut`,
/// ni `net_a_payer`, ni `taux_rist_plafonne`, ni `rist_plafond_applique`). Contrat posé par T1, complété
/// par T5 (colonnes de `ListeMissions.tsx` l.85 moins les montants, plus `type_contrat_recherche` et
/// `mode_attribution`) ; décodage tolérant dans `Etablissement/Missions/EtabMission.swift`.
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
    /// Établissement de la ligne relue : comparé au contexte confirmé, jamais une valeur de filtre (T5).
    public var etablissementId: String?
    public var description: String?
    public var service: String?
    public var niveauUrgence: Int?
    public var soignantAssigneId: String?
    /// `CANDIDATURE` ou `PREMIER_ARRIVE` (aiguillage des candidatures, T5/T6).
    public var modeAttribution: String?
    public var creeLe: String?

    public init(id: String, intitule: String, statut: String? = nil, debutLe: String? = nil, finLe: String? = nil,
                nbCreneaux: Int? = nil, professionRequise: String? = nil, typeContratRecherche: String? = nil,
                estUrgente: Bool? = nil, etablissementId: String? = nil, description: String? = nil, service: String? = nil,
                niveauUrgence: Int? = nil, soignantAssigneId: String? = nil, modeAttribution: String? = nil,
                creeLe: String? = nil) {
        self.id = id; self.intitule = intitule; self.statut = statut; self.debutLe = debutLe; self.finLe = finLe
        self.nbCreneaux = nbCreneaux; self.professionRequise = professionRequise
        self.typeContratRecherche = typeContratRecherche; self.estUrgente = estUrgente
        self.etablissementId = etablissementId; self.description = description; self.service = service
        self.niveauUrgence = niveauUrgence; self.soignantAssigneId = soignantAssigneId
        self.modeAttribution = modeAttribution; self.creeLe = creeLe
    }
}

/// Page de missions de l'établissement (pages de 50, comme `MissionsPage`). Lecture **cumulative** comme
/// « Mes missions » (T5) : la page `n` rend les missions 0…(n + 1) × 50 − 1 d'un seul tenant, la liste est
/// remplacée, jamais complétée localement.
public struct EtabMissionsPage: Equatable, Sendable {
    public static let taille = 50

    public var missions: [EtabMissionResume]
    public var page: Int
    public var aSuivre: Bool
    /// Compteurs par statut de tout l'établissement (web l.161-166) ; `nil` si leur lecture a échoué
    /// (rendu partiel : les pastilles s'affichent sans nombre, comme le web qui retombe à 0).
    public var compteurs: EtabMissionsCompteurs?
    /// Candidatures `EN_ATTENTE` par mission `OUVERTE` de la page (web l.120-138) ; vide sans la
    /// permission `candidatures` (jamais lue) ou si la lecture a échoué.
    public var candidaturesEnAttente: [String: Int]
    /// Créneaux PREVISIONNEL hors pause relus par mission (pager exact du lot 0).
    public var creneaux: [String: [MissionSlot]]

    public init(missions: [EtabMissionResume], page: Int, aSuivre: Bool, compteurs: EtabMissionsCompteurs? = nil,
                candidaturesEnAttente: [String: Int] = [:], creneaux: [String: [MissionSlot]] = [:]) {
        self.missions = missions; self.page = page; self.aSuivre = aSuivre; self.compteurs = compteurs
        self.candidaturesEnAttente = candidaturesEnAttente; self.creneaux = creneaux
    }
}

/// Détail d'une mission de l'établissement (T5). Le planning est une lecture secondaire : son échec est
/// porté par `erreurPlanning` (le web affiche « Planning détaillé momentanément indisponible »), la mission reste lue.
public struct EtabMissionDetail: Equatable, Sendable {
    public var mission: EtabMissionResume
    public var creneaux: [MissionSlot]
    public var soignantAssigneId: String?
    /// Candidatures `EN_ATTENTE` d'une mission `OUVERTE` en mode `CANDIDATURE` (web l.590-596) ; `nil`
    /// sans la permission `candidatures`, hors de ce cas, ou si la lecture a échoué.
    public var candidaturesEnAttente: Int?
    /// Message de l'échec de lecture du planning, verbatim ; `nil` si le planning a été relu.
    public var erreurPlanning: String?

    public init(mission: EtabMissionResume, creneaux: [MissionSlot], soignantAssigneId: String?,
                candidaturesEnAttente: Int? = nil, erreurPlanning: String? = nil) {
        self.mission = mission; self.creneaux = creneaux; self.soignantAssigneId = soignantAssigneId
        self.candidaturesEnAttente = candidaturesEnAttente; self.erreurPlanning = erreurPlanning
    }
}

/// `fn_soignant_pour_etablissement` (l.57155), tel que servi : un `null` SQL (soignant supprimé) est
/// rendu `nil` par le port (« Soignant indisponible »), jamais un profil vide. Complété par T5 avec ce
/// que le détail du web affiche (l.1070-1130). **Jamais décodés** : `note_moyenne`, `nb_evaluations`
/// (D8), `type_exercice` (le régime vient de la mission), `internat` (D10), `etudiant_details`, `bio`.
public struct SoignantPourEtab: Equatable, Sendable, Identifiable {
    public var id: String
    public var prenom: String?
    public var nom: String?
    public var profession: String?
    /// Vrai hors relation contractuelle : `nom` est alors l'initiale (« D. »).
    public var nomAnonymise: Bool?
    /// Servi seulement pour une mission du jour ou du lendemain (l.57194).
    public var telephone: String?
    public var numeroRpps: String?
    public var scoreFiabilite: Int?
    public var totalMissionsTerminees: Int?

    public init(id: String, prenom: String?, nom: String?, profession: String?, nomAnonymise: Bool? = nil,
                telephone: String? = nil, numeroRpps: String? = nil, scoreFiabilite: Int? = nil,
                totalMissionsTerminees: Int? = nil) {
        self.id = id; self.prenom = prenom; self.nom = nom; self.profession = profession
        self.nomAnonymise = nomAnonymise; self.telephone = telephone; self.numeroRpps = numeroRpps
        self.scoreFiabilite = scoreFiabilite; self.totalMissionsTerminees = totalMissionsTerminees
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
