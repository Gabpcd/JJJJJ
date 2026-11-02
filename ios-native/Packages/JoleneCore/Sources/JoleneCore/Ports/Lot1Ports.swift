import Foundation

// Ports du lot 1 (blueprint lot 1 §2.3, `docs/mobile-swift/LOT1_PLAN.md`). Tous `Sendable`
// (concurrence stricte). Chaque méthode reçoit le `MissionReadContext` de l'epoch courant :
// la gateway vérifie la cohérence session ↔ profil et le monde démo refuse tout autre
// utilisateur. Une mutation n'annonce un succès qu'après relecture serveur (PRINCIPES §3) ;
// les refus métier passent par les issues de `Models/Lot1Results.swift`, les erreurs de
// transport par `JoleneError`.

// MARK: - Contrats

/// Tableau de bord soignant (`fn_dashboard_soignant_complet`) — tranche T3.
public protocol DashboardPort: Sendable {
    /// `delaiEcran` : délai qui borne tout l'appel côté écran, transmis par l'appelant
    /// (`AccueilModel` : `SessionController.resolutionTimeout`). Seule source de ce délai : une
    /// gateway qui enchaîne des lectures y réduit ses sous-budgets, jamais à une constante à elle.
    func dashboard(context: MissionReadContext, delaiEcran: TimeInterval) async throws -> DashboardSnapshot
}

/// Candidature (`fn_confirmer_action_planning_v1`, `fn_repondre_proposition`) — tranche T6a ;
/// annulations (`fn_annuler_candidature_soignant`, `fn_annuler_mission_soignant`) — tranche T7.
public protocol CandidaturePort: Sendable {
    /// POSTULER / ACCEPTER / PROPOSITION. `creneaux` est le planning exact confirmé à l'écran
    /// (`p_creneaux_confirmes`) ; un planning modifié depuis l'affichage est un refus
    /// `planningAReconfirmer`, jamais un renvoi.
    func confirmer(action: ActionPlanning, missionId: String, creneaux: [CreneauConfirmePayload], message: String?,
                   choixContrat: String?, candidatureId: String?, context: MissionReadContext) async throws -> CandidatureOutcome
    func refuserProposition(candidatureId: String, context: MissionReadContext) async throws
    func candidature(missionId: String, context: MissionReadContext) async throws -> CandidatureRecord?
    func annulerCandidature(id: String, motif: String, texte: String, justificatifPath: String?,
                            context: MissionReadContext) async throws -> AnnulationOutcome
    func annulerMission(id: String, motif: String?, context: MissionReadContext) async throws -> AnnulationOutcome
}

/// Confirmation de présence J-2 → J0 (`fn_confirmer_presence_mission`) — tranche T6c.
public protocol PresencePort: Sendable {
    func confirmerPresence(missionId: String, context: MissionReadContext) async throws -> PresenceOutcome
}

/// Favoris missions (`missions_sauvegardees`) et établissements (`fn_mes_favoris_etablissements`,
/// `fn_toggle_favori_etablissement`) — tranche T4b. Chaque mutation rend la liste relue.
public protocol FavorisPort: Sendable {
    func missionsSauvegardees(context: MissionReadContext) async throws -> [MissionSauvegardee]
    func sauvegarder(missionId: String, context: MissionReadContext) async throws -> [MissionSauvegardee]
    func retirer(missionId: String, context: MissionReadContext) async throws -> [MissionSauvegardee]
    func etablissementsFavoris(context: MissionReadContext) async throws -> [EtablissementFavori]
    func basculerEtablissement(id: String, actif: Bool, context: MissionReadContext) async throws -> [EtablissementFavori]
}

/// Mes missions : candidatures, à venir, passées (pages de `MissionsPage.taille`) — tranche T5.
public protocol MesMissionsPort: Sendable {
    func candidatures(context: MissionReadContext) async throws -> [CandidatureRecord]
    func aVenir(context: MissionReadContext, page: Int) async throws -> MissionsPage
    func passees(context: MissionReadContext, page: Int) async throws -> MissionsPage
}

/// Suppression de compte (edge `delete-account`, Apple 5.1.1) — tranche T8.
public protocol AccountPort: Sendable {
    func deleteAccount(context: MissionReadContext) async throws -> DeleteAccountOutcome
}

/// Audit best-effort (décision 5) : `fn_audit_connexion('CONNEXION'|'DECONNEXION')`,
/// `fn_maj_activite_soignant()` et `fn_ecrire_audit_safe` comme le web — câblé en T1.
/// L'appelant n'en fait jamais dépendre une connexion ni une déconnexion ; aucun renvoi.
///
/// Jamais une erreur utilisateur : un refus du serveur (`{success:false}`, « Non authentifié »
/// compris) rend `.nonEnregistre`, et l'appelant avale toute erreur levée (transport, contrat,
/// identifiant invalide) sans l'afficher ni la propager — l'audit qui suit un ACCEPTER réussi ne
/// doit jamais faire afficher « session expirée » après ce succès.
public protocol AuditPort: Sendable {
    func connexion() async throws -> AuditResultat
    func deconnexion() async throws -> AuditResultat
    func activite() async throws -> AuditResultat
    func ecrire(action: AuditAction, typeRessource: String, idRessource: String, details: [String: String],
                context: MissionReadContext) async throws -> AuditResultat
}

/// Drapeaux d'écran (`fn_param_bool`, lu avec la session : aucun GRANT `anon`) — câblé en T1.
/// Ne lève jamais : toute erreur rend `defaut` (décision 15).
public protocol FlagsPort: Sendable {
    func ecranActif(cle: String, defaut: Bool) async -> Bool
}

public extension FlagsPort {
    /// Drapeau d'un écran natif, défaut fail-open (`FlagsPolicy.defautFailOpen`).
    func ecranActif(_ ecran: EcranNatif) async -> Bool {
        await ecranActif(cle: ecran.cle, defaut: FlagsPolicy.defautFailOpen)
    }
}

/// Écrans natifs pilotés par un drapeau `parametres_systeme` (décision 15 : onglets du socle).
public enum EcranNatif: String, CaseIterable, Sendable {
    case accueil, explorer, missions, revenus, profil

    /// Clé `parametres_systeme.cle` (lignes créées par la PR backend B0).
    public var cle: String { "ios_natif_\(rawValue)_actif" }
}

public enum FlagsPolicy {
    /// Décision 15 : un écran natif reste actif si le drapeau est absent ou illisible
    /// (inverse assumé de `useParamBool.ts`, fail-closed côté web).
    public static let defautFailOpen = true
}

/// Réinitialisation du mot de passe (formats `token_hash` et implicit ; `.pkce` refusé,
/// décision 7 option B) — tranche T10. La session de récupération est mise en quarantaine.
public protocol RecoveryPort: Sendable {
    func requestReset(email: String) async throws
    func openRecoverySession(_ credentials: AuthCallbackCredentials) async throws -> RecoveryOutcome
    func updatePassword(_ password: String) async throws
    func signOutAfterRecovery() async throws
}

/// Justificatif d'annulation (bucket `justificatifs`) — tranche T7. Rend le chemin Storage
/// (`<uid>/annulations-candidature/<candidatureId>/<ts>_<nom>`), précédé d'un reçu Keychain.
public protocol JustificatifStoragePort: Sendable {
    func upload(data: Data, fileName: String, candidatureId: String, userId: String) async throws -> String
}

// MARK: - Ports « non câblés »

/// Marqueur des stubs : `Gateways.unwiredPorts` les nomme. Règle « un gap connu reste
/// verrouillé » : un stub ne rend jamais un état vide plausible, il lève `.contract` en citant
/// la tranche qui livre le port.
public protocol UnwiredPort: Sendable {}

public enum UnwiredPorts {
    public static func erreur(port: String, tranche: String) -> JoleneError {
        JoleneError(.contract, "Port « \(port) » non câblé : livré par la tranche \(tranche) du lot 1 (docs/mobile-swift/LOT1_PLAN.md §3).")
    }
}

public struct UnwiredDashboardPort: DashboardPort, UnwiredPort {
    public init() {}
    public func dashboard(context: MissionReadContext, delaiEcran: TimeInterval) async throws -> DashboardSnapshot {
        throw UnwiredPorts.erreur(port: "tableau de bord", tranche: "T3")
    }
}

public struct UnwiredCandidaturePort: CandidaturePort, UnwiredPort {
    public init() {}
    public func confirmer(action: ActionPlanning, missionId: String, creneaux: [CreneauConfirmePayload], message: String?,
                          choixContrat: String?, candidatureId: String?, context: MissionReadContext) async throws -> CandidatureOutcome {
        throw UnwiredPorts.erreur(port: "candidature", tranche: "T6a")
    }
    public func refuserProposition(candidatureId: String, context: MissionReadContext) async throws {
        throw UnwiredPorts.erreur(port: "candidature", tranche: "T6a")
    }
    public func candidature(missionId: String, context: MissionReadContext) async throws -> CandidatureRecord? {
        throw UnwiredPorts.erreur(port: "candidature", tranche: "T6a")
    }
    public func annulerCandidature(id: String, motif: String, texte: String, justificatifPath: String?,
                                   context: MissionReadContext) async throws -> AnnulationOutcome {
        throw UnwiredPorts.erreur(port: "annulation", tranche: "T7")
    }
    public func annulerMission(id: String, motif: String?, context: MissionReadContext) async throws -> AnnulationOutcome {
        throw UnwiredPorts.erreur(port: "annulation", tranche: "T7")
    }
}

public struct UnwiredPresencePort: PresencePort, UnwiredPort {
    public init() {}
    public func confirmerPresence(missionId: String, context: MissionReadContext) async throws -> PresenceOutcome {
        throw UnwiredPorts.erreur(port: "confirmation de présence", tranche: "T6c")
    }
}

public struct UnwiredFavorisPort: FavorisPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { UnwiredPorts.erreur(port: "favoris", tranche: "T4b") }
    public func missionsSauvegardees(context: MissionReadContext) async throws -> [MissionSauvegardee] { throw erreur }
    public func sauvegarder(missionId: String, context: MissionReadContext) async throws -> [MissionSauvegardee] { throw erreur }
    public func retirer(missionId: String, context: MissionReadContext) async throws -> [MissionSauvegardee] { throw erreur }
    public func etablissementsFavoris(context: MissionReadContext) async throws -> [EtablissementFavori] { throw erreur }
    public func basculerEtablissement(id: String, actif: Bool, context: MissionReadContext) async throws -> [EtablissementFavori] {
        throw erreur
    }
}

public struct UnwiredMesMissionsPort: MesMissionsPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { UnwiredPorts.erreur(port: "mes missions", tranche: "T5") }
    public func candidatures(context: MissionReadContext) async throws -> [CandidatureRecord] { throw erreur }
    public func aVenir(context: MissionReadContext, page: Int) async throws -> MissionsPage { throw erreur }
    public func passees(context: MissionReadContext, page: Int) async throws -> MissionsPage { throw erreur }
}

public struct UnwiredAccountPort: AccountPort, UnwiredPort {
    public init() {}
    public func deleteAccount(context: MissionReadContext) async throws -> DeleteAccountOutcome {
        throw UnwiredPorts.erreur(port: "compte", tranche: "T8")
    }
}

public struct UnwiredAuditPort: AuditPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { UnwiredPorts.erreur(port: "audit", tranche: "T1") }
    public func connexion() async throws -> AuditResultat { throw erreur }
    public func deconnexion() async throws -> AuditResultat { throw erreur }
    public func activite() async throws -> AuditResultat { throw erreur }
    public func ecrire(action: AuditAction, typeRessource: String, idRessource: String, details: [String: String],
                       context: MissionReadContext) async throws -> AuditResultat { throw erreur }
}

/// Seul stub non levant (le port ne lève jamais) : il applique la politique documentée —
/// `defaut` — et reste nommé par `unwiredPorts`, contrôlé par les tests de chaque monde.
public struct UnwiredFlagsPort: FlagsPort, UnwiredPort {
    public init() {}
    public func ecranActif(cle: String, defaut: Bool) async -> Bool { defaut }
}

public struct UnwiredRecoveryPort: RecoveryPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { UnwiredPorts.erreur(port: "réinitialisation du mot de passe", tranche: "T10") }
    public func requestReset(email: String) async throws { throw erreur }
    public func openRecoverySession(_ credentials: AuthCallbackCredentials) async throws -> RecoveryOutcome { throw erreur }
    public func updatePassword(_ password: String) async throws { throw erreur }
    public func signOutAfterRecovery() async throws { throw erreur }
}

public struct UnwiredJustificatifStoragePort: JustificatifStoragePort, UnwiredPort {
    public init() {}
    public func upload(data: Data, fileName: String, candidatureId: String, userId: String) async throws -> String {
        throw UnwiredPorts.erreur(port: "justificatifs", tranche: "T7")
    }
}
