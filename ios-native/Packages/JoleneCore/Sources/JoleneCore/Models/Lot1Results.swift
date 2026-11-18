import Foundation

// Contrats d'échange des ports du lot 1 (`Ports/Lot1Ports.swift`). Posés par T1 pour que les
// tranches suivantes ne modifient ni `Gateways` ni les protocoles ; chaque tranche complète ici
// le contrat de son domaine (champs optionnels, décodage tolérant) ou le déplace dans son
// fichier de modèle. Clés snake_case explicites (PRINCIPES §2). `JoleneError.Kind` n'est pas
// étendu : les refus métier structurés sont des issues, les erreurs de transport des `JoleneError`.

// MARK: - Candidature (T6a, T7)

/// Actions de `fn_confirmer_action_planning_v1` : POSTULER, ACCEPTER et PROPOSITION au lot 1 ; SWIPE_LIKE (❤️ du
/// swipe, relayé à `fn_enregistrer_swipe(…, 'LIKE', p_choix_contrat)`) et URGENCE (acceptation rapide du pool,
/// `fn_accepter_mission_urgence(p_mission_id)`, qui ignore `p_choix_contrat` : un `choix_requis` n'y est jamais rejoué,
/// correction 10) ajoutées par L4-T1 (décision D2 de `docs/mobile-swift/DECISIONS_LOT4.md`).
public enum ActionPlanning: String, CaseIterable, Sendable {
    case postuler = "POSTULER"
    case accepter = "ACCEPTER"
    case proposition = "PROPOSITION"
    case swipeLike = "SWIPE_LIKE"
    case urgence = "URGENCE"
}

/// Élément de `p_creneaux_confirmes` : instants ISO 8601 du planning exact affiché. T6a le
/// produit depuis `creneauxConfirmesPourAction` (port T2), sans jamais recalculer un horaire.
///
/// Alias de `CreneauConfirme` (T2, `Missions/CreneauxConfirmes.swift`), le type que le
/// blueprint §2.3 désigne pour le port : le doublon temporaire posé par T1 pendant le
/// développement parallèle de T1 et T2 est retiré à leur intégration (`feat/ios-lot1`), pour
/// que `CandidaturePort.confirmer` consomme directement `CreneauxConfirmes.pourAction(_:)`
/// sans conversion en T6a. Le nom est conservé : les protocoles du lot 1 restent figés.
public typealias CreneauConfirmePayload = CreneauConfirme

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
    /// Mission sortie de l'état `OUVERTE` entre l'affichage et l'action (course réelle, revue B8 de T6a,
    /// m1) : refus « Cette mission n'est plus disponible. » de `fn_confirmer_action_planning_v1` (verrou
    /// `FOR UPDATE`, forme 3), sa variante sans point des délégués, ou « Cette mission vient d'être
    /// attribuée. » de `fn_finaliser_attribution_mission` (`CandidatureRules.messagesMissionDejaAttribuee`).
    /// Message serveur conservé verbatim ; l'écran relit la mission et ne renvoie jamais l'action.
    case missionDejaAttribuee(message: String)

    /// Code posé par le client sur un refus du Code du travail levé en exception par un trigger
    /// de `missions` (`dec_verifier_plafond_48h`, `dec_verifier_repos_11h`,
    /// `dec_verifier_moyenne_44h_12_semaines`, `dec_verifier_repos_hebdo_35h`) : SQLSTATE P0001
    /// ou 23514, sans code métier. Distinct de tout code jsonb du serveur, il permet à l'écran
    /// d'afficher le texte légal à part (le web ouvre une modale, `estBlocageCodeTravail`).
    public static let codeRefusCodeDuTravail = "CODE_DU_TRAVAIL"
}

/// Parcours de candidature non porté en natif, refusé **avant tout envoi** (« un gap connu reste
/// verrouillé », CLAUDE.md) : l'écran renvoie vers jolene.app. Aucun texte juridique ici.
public enum CandidatureVerrou: Error, Equatable, Sendable, LocalizedError {
    /// Acceptation d'une proposition dont le contrat n'est pas `LIBERAL` : le web fait d'abord compléter
    /// l'attestation hebdomadaire des heures (`CarteProposition.tsx` l.154-256), non portée au lot 1
    /// (`docs/mobile-swift/LOT1_PLAN.md` §3 T6b et §7 décision 2 amendée). `chemin` : page web de la proposition.
    case renvoiWeb(chemin: String)

    /// Page web où la proposition s'accepte (carte de l'Accueil, `DashboardSoignant.tsx`).
    public static let cheminProposition = "/soignant/tableau-de-bord"
    public static let messageRenvoiWeb = "Pour accepter cette proposition, continuez sur jolene.app : cette étape n'est pas encore disponible dans l'application (docs/mobile-swift/LOT1_PLAN.md, T6b)."

    public var errorDescription: String? { Self.messageRenvoiWeb }
}

/// Ligne `candidatures` relue sous RLS. Seuls `id` et `mission_id` conditionnent une action.
public struct CandidatureRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var missionId: String
    public var statut: String?
    public var message: String?
    public var typeContratChoisi: String?
    public var creeLe: String?
    /// Mission de la candidature relue sous RLS et enrichie (`MissionBusiness.enrich`) par Mes missions
    /// (T5, `MesMissionsPort.candidatures`) ; `nil` hors de cette lecture. Hors `CodingKeys` : jamais
    /// encodée ni décodée avec la ligne `candidatures`.
    public var mission: Mission? = nil

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

// `DashboardSnapshot` et le corps de `fn_dashboard_soignant_complet` : `Models/Dashboard.swift`
// (déplacés par T3 avec leurs sections ; l'init `DashboardSnapshot(notifsNonLues:missionsOublieesCount:)`
// de T1 est conservé).

// MARK: - Favoris (T4b)

// `MissionSauvegardee` (avec la mission jointe) et `EtablissementFavori` : `Models/Favoris.swift`
// (déplacés par T4b avec leur décodage tolérant ; les inits de T1 sont conservés).

// MARK: - Mes missions (T5)

public struct MissionsPage: Equatable, Sendable {
    /// Pagination de `MissionsSoignant.tsx` (pages de 50, lues de façon cumulative).
    public static let taille = 50

    /// Missions des pages 0…`page`, ordre serveur (lecture cumulative du web, « M1 »).
    public var missions: [Mission]
    /// Dernière page incluse.
    public var page: Int
    /// Lecture pleine : « Charger plus de missions » est proposé (web l.623).
    public var aSuivre: Bool
    /// Colonnes financières relues avec les missions passées (T5 : `net_estime`, `type_contrat_applique`,
    /// `total_brut`, `net_a_payer`), par id de mission ; vide pour « À venir ». Valeurs serveur affichées
    /// par `MesMissionsPresentation.montantPassee`, jamais recalculées.
    public var finances: [String: MissionGainLigne] = [:]

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
    /// Lot 2 (T4b, décision 4) : réponse à la feuille de consentement GPS du premier pointage, acceptation comme refus
    /// (parité `src/pages/PresencesSoignant.tsx` l.67-74, l.87-94 ; valeur du CHECK, `public.sql` l.70290).
    case rgpdConsentementDonne = "RGPD_CONSENTEMENT_DONNE"
    // Lot 3 (T1, blueprint `LOT3_PLAN.md` §2.1) : consultation et modification du profil (T9, T11,
    // web `ProfilSoignant.tsx` l.157-163) et export RGPD (T11), toutes trois dans le CHECK
    // (`Lot3PortsTests.testChaqueActionAuditFigureDansLaContrainteDuDump`).
    case donneesPersoConsultation = "DONNEES_PERSO_CONSULTATION"
    case donneesPersoModification = "DONNEES_PERSO_MODIFICATION"
    case rgpdExportDonnees = "RGPD_EXPORT_DONNEES"
    /// Lot 2 (T5b, revue B8 m5) : contestation d'une présence (parité `PanneauContestation.tsx` l.134-139), détails
    /// minimisés (longueur du motif, litige ; décision m2 de `DECISIONS_LOT2.md`).
    case presenceContestation = "PRESENCE_CONTESTATION"
    /// Lot 1, T7 : annulation sans candidature (`fn_annuler_mission_soignant`), comme le web (`DetailMissionSoignant.tsx`
    /// l.903-914) ; valeur du CHECK `journaux_audit_action_check`.
    case missionAnnulation = "MISSION_ANNULATION"
}

/// Issue d'une écriture d'audit best-effort. `nonEnregistre` (`{success:false}`) n'est pas une
/// erreur et ne porte aucun texte serveur (SQLERRM jamais conservé).
public enum AuditResultat: Equatable, Sendable {
    case enregistre
    case nonEnregistre
}
