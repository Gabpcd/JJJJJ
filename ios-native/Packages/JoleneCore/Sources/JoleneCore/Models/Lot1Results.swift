import Foundation

// Contrats d'échange des ports du lot 1 (`Ports/Lot1Ports.swift`). Posés par T1 pour que les
// tranches suivantes ne modifient ni `Gateways` ni les protocoles ; chaque tranche complète ici
// le contrat de son domaine (champs optionnels, décodage tolérant) ou le déplace dans son
// fichier de modèle. Clés snake_case explicites (PRINCIPES §2). `JoleneError.Kind` n'est pas
// étendu : les refus métier structurés sont des issues, les erreurs de transport des `JoleneError`.

// MARK: - Candidature (T6a, T7)

/// Actions de `fn_confirmer_action_planning_v1` servies au lot 1 (SWIPE_LIKE et URGENCE : lot 4).
public enum ActionPlanning: String, CaseIterable, Sendable {
    case postuler = "POSTULER"
    case accepter = "ACCEPTER"
    case proposition = "PROPOSITION"
}

/// Élément de `p_creneaux_confirmes` : instants ISO 8601 du planning exact affiché. T6a le
/// produit depuis `creneauxConfirmesPourAction` (port T2), sans jamais recalculer un horaire.
///
/// Doublon assumé, temporaire, de `CreneauConfirme` (T2, `Missions/CreneauxConfirmes.swift`,
/// mêmes clés `debut`/`fin`, même init, mêmes conformances), que le blueprint §2.3 désigne
/// comme type du port. Les deux tranches sont développées en parallèle : la PR mergée en
/// second remplace ce struct par `public typealias CreneauConfirmePayload = CreneauConfirme`
/// (ou le port par `[CreneauConfirme]`), pour que `CandidaturePort.confirmer` consomme
/// directement `CreneauxConfirmes.pourAction(_:)` sans conversion en T6a.
public struct CreneauConfirmePayload: Codable, Hashable, Sendable {
    public var debut: String
    public var fin: String

    public init(debut: String, fin: String) { self.debut = debut; self.fin = fin }
}

/// Option de contrat proposée par le serveur quand `choix_requis` est vrai (`{value, label}`).
public struct ChoixContratOption: Codable, Equatable, Sendable {
    public var value: String
    public var label: String

    public init(value: String, label: String) { self.value = value; self.label = label }
}

public enum CandidatureOutcome: Equatable, Sendable {
    /// Acceptée par le serveur et relue (candidature, ou mission ASSIGNEE au soignant).
    case confirmed(candidatureId: String?, contratId: String?)
    /// Le serveur demande un mode de contrat : l'action est rejouée avec l'option choisie.
    case choixRequis([ChoixContratOption])
    /// Refus serveur affiché verbatim (HARD STOP n°4) : refus jsonb (`code` serveur) ou exception
    /// `[CODE DU TRAVAIL]` d'un trigger, message mot pour mot et `code` =
    /// `codeRefusCodeDuTravail` (décision 2).
    case refusee(code: String?, message: String, documentsRequisPour: String?)
    /// Le planning a changé : relire la mission et redemander une confirmation, jamais renvoyer.
    case planningAReconfirmer(code: String, message: String)

    /// Code posé par le client sur un refus du Code du travail levé en exception par un trigger
    /// de `missions` (`dec_verifier_plafond_48h`, `dec_verifier_repos_11h`,
    /// `dec_verifier_moyenne_44h_12_semaines`, `dec_verifier_repos_hebdo_35h`) : SQLSTATE P0001
    /// ou 23514, sans code métier. Distinct de tout code jsonb du serveur, il permet à l'écran
    /// d'afficher le texte légal à part (le web ouvre une modale, `estBlocageCodeTravail`).
    public static let codeRefusCodeDuTravail = "CODE_DU_TRAVAIL"
}

/// Ligne `candidatures` relue sous RLS. Seuls `id` et `mission_id` conditionnent une action.
public struct CandidatureRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var missionId: String
    public var statut: String?
    public var message: String?
    public var typeContratChoisi: String?
    public var creeLe: String?

    public init(id: String, missionId: String, statut: String?, message: String?, typeContratChoisi: String?, creeLe: String?) {
        self.id = id; self.missionId = missionId; self.statut = statut; self.message = message
        self.typeContratChoisi = typeContratChoisi; self.creeLe = creeLe
    }

    enum CodingKeys: String, CodingKey {
        case id, statut, message
        case missionId = "mission_id"
        case typeContratChoisi = "type_contrat_choisi"
        case creeLe = "cree_le"
    }
}

/// Issue d'une annulation : conséquences renvoyées par le serveur, jamais un barème client.
public enum AnnulationOutcome: Equatable, Sendable {
    case annulee(points: Int?, libre: Bool?, contestable: Bool?)
    case refusee(code: String?, message: String)
}

// MARK: - Présence (T6c)

public enum PresenceOutcome: Equatable, Sendable {
    /// `presence_confirmee_le` relu non nul (valeur serveur, jamais posée localement).
    case confirmee(presenceConfirmeeLe: String)
    case refusee(message: String)
}

// MARK: - Tableau de bord (T3)

/// Instantané de `fn_dashboard_soignant_complet`. T3 y ajoute les sections (profil, missions,
/// propositions, gains, documents) avec un décodage tolérant ; les montants restent serveur.
public struct DashboardSnapshot: Equatable, Sendable {
    public var notifsNonLues: Int
    public var missionsOublieesCount: Int

    public init(notifsNonLues: Int = 0, missionsOublieesCount: Int = 0) {
        self.notifsNonLues = notifsNonLues; self.missionsOublieesCount = missionsOublieesCount
    }
}

// MARK: - Favoris (T4b)

/// Ligne `missions_sauvegardees` (RLS `soignant_id = auth.uid()`).
public struct MissionSauvegardee: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var missionId: String
    public var creeLe: String?

    public init(id: String, missionId: String, creeLe: String?) { self.id = id; self.missionId = missionId; self.creeLe = creeLe }

    enum CodingKeys: String, CodingKey {
        case id
        case missionId = "mission_id"
        case creeLe = "cree_le"
    }
}

/// Élément de `fn_mes_favoris_etablissements`. Seul `etablissement_id` conditionne une action.
public struct EtablissementFavori: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var nom: String?
    public var ville: String?
    public var logoUrl: String?
    public var typeEtablissement: String?
    public var nbMissionsOuvertes: Int?
    public var creeLe: String?

    public init(id: String, nom: String?, ville: String?, logoUrl: String?, typeEtablissement: String?,
                nbMissionsOuvertes: Int?, creeLe: String?) {
        self.id = id; self.nom = nom; self.ville = ville; self.logoUrl = logoUrl
        self.typeEtablissement = typeEtablissement; self.nbMissionsOuvertes = nbMissionsOuvertes; self.creeLe = creeLe
    }

    enum CodingKeys: String, CodingKey {
        case id = "etablissement_id"
        case nom, ville
        case logoUrl = "logo_url"
        case typeEtablissement = "type_etablissement"
        case nbMissionsOuvertes = "nb_missions_ouvertes"
        case creeLe = "cree_le"
    }
}

// MARK: - Mes missions (T5)

public struct MissionsPage: Equatable, Sendable {
    /// Pagination de `MissionsSoignant.tsx` (pages de 50).
    public static let taille = 50

    public var missions: [Mission]
    public var page: Int
    public var aSuivre: Bool

    public init(missions: [Mission], page: Int, aSuivre: Bool) { self.missions = missions; self.page = page; self.aSuivre = aSuivre }
}

// MARK: - Compte (T8)

public enum DeleteAccountOutcome: Equatable, Sendable {
    /// HTTP 200 `{success:true}` : seule preuve possible (le JWT est révoqué, aucune relecture).
    case deleted
    /// Refus du serveur affiché verbatim (409, 429, 503…).
    case refused(code: String?, message: String)
}

// MARK: - Réinitialisation du mot de passe (T10)

public enum RecoveryOutcome: Equatable, Sendable {
    /// Session de récupération ouverte (preuve serveur `token_hash` ou implicit), en quarantaine.
    case sessionOuverte
    /// Lien refusé (format `.pkce`, lien expiré ou d'un autre type) : écran d'erreur, jamais le formulaire.
    case lienRefuse(message: String)
}

// MARK: - Audit (T1)

/// Actions écrites par `fn_ecrire_audit_safe`, limitées aux valeurs vérifiées dans
/// `journaux_audit_action_check` (l.70243 du dump) : une action hors CHECK serait avalée.
public enum AuditAction: String, CaseIterable, Sendable {
    case missionAssignation = "MISSION_ASSIGNATION"
}

/// Issue d'une écriture d'audit best-effort. `nonEnregistre` (`{success:false}`) n'est pas une
/// erreur et ne porte aucun texte serveur (SQLERRM jamais conservé).
public enum AuditResultat: Equatable, Sendable {
    case enregistre
    case nonEnregistre
}
