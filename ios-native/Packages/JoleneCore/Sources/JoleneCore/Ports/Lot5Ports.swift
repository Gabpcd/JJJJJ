import Foundation

// Ports de l'espace établissement (lot 5, T1 ; `docs/mobile-swift/LOT5_PLAN.md` §2.3-§2.4). Tous
// `Sendable` (concurrence stricte). Chaque méthode d'écran reçoit l'`EtablissementReadContext` de
// l'epoch courant : la gateway refuse un contexte incohérent avant tout appel réseau, le monde démo
// tout autre utilisateur que le compte fictif. Toutes les RPC du lot agissent sur
// `mon_etablissement_id()` côté serveur (correction 3) : aucune n'envoie l'établissement du contexte.
// Une mutation n'annonce un succès qu'après relecture serveur (PRINCIPES §3) ; les refus métier passent
// par les issues de `Models/EtablissementResults.swift`, les erreurs de transport par `JoleneError`.
// Contrats et messagerie réutilisent les ports des lots 2 et 4 (D18) : aucun port partiel ici.

// MARK: - Contrats

/// Périmètre et profil de l'établissement courant — câblé en T1, consommé par T2 (résolution de
/// l'espace, revalidation 30 min, relecture après refus `accesRefuse`). Sans contexte : il le fonde.
public protocol EtabSessionPort: Sendable {
    /// `fn_mes_permissions_etab(p_etablissement_id)` ; T2 passe toujours `nil` (D2 : le périmètre est
    /// `mon_etablissement_id()`, celui de toutes les RPC du lot). Réponse décodée sans interprétation.
    func permissions(etablissementId: String?) async throws -> PermissionsEtabResult
    /// `fn_mon_etablissement_complet()`, sous-ensemble décodé. L'appelant compare `id` à l'établissement
    /// confirmé par `permissions` : un profil d'un autre établissement est une divergence, jamais un repli.
    func profil() async throws -> EtablissementProfil
}

/// Accueil : actions prioritaires (`fn_stats_dashboard_etablissement` + prochaines missions) — T4.
public protocol EtabDashboardPort: Sendable {
    func tableauDeBord(context: EtablissementReadContext) async throws -> EtabDashboardSnapshot
}

/// Missions de l'établissement (sans montant), détail et soignant — T5.
public protocol EtabMissionsPort: Sendable {
    /// Pages de `EtabMissionsPage.taille` ; `statut` nil = tous les statuts.
    func missions(context: EtablissementReadContext, statut: String?, page: Int) async throws -> EtabMissionsPage
    func mission(id: String, context: EtablissementReadContext) async throws -> EtabMissionDetail?
    func soignant(id: String, context: EtablissementReadContext) async throws -> SoignantPourEtab?
}

/// Candidatures : lecture habilitée, acceptation (périmètre D25), refus — T6.
public protocol EtabCandidaturesPort: Sendable {
    func lecture(missionId: String, context: EtablissementReadContext) async throws -> LectureCandidaturesHabilitee
    /// `creneauxConfirmes` : chaînes `debut`/`fin` relues telles quelles (D26, voie `lus`), jamais `pourAction`.
    func accepter(candidatureId: String, creneauxConfirmes: [CreneauConfirmePayload],
                  context: EtablissementReadContext) async throws -> TraitementCandidatureOutcome
    func refuser(candidatureId: String, context: EtablissementReadContext) async throws -> TraitementCandidatureOutcome
}

/// Pointage terrain : état (polling 5 s, D23), signature du contrat, planning — T7.
public protocol EtabPointagePort: Sendable {
    func etat(missionId: String, context: EtablissementReadContext) async throws -> EtatPointageEtab
    func contratSigne(missionId: String, context: EtablissementReadContext) async throws -> Bool
    func planning(missionId: String, context: EtablissementReadContext) async throws -> PlanningMission
}

/// Présences : liste, validation, lot, contestation, note, clôture rétroactive — T8 (**B9** : escrow).
public protocol EtabPresencesPort: Sendable {
    func presences(context: EtablissementReadContext) async throws -> [PresenceEtab]
    func valider(presenceId: String, context: EtablissementReadContext) async throws -> ValidationPresenceOutcome
    func validerLot(ids: [String], context: EtablissementReadContext) async throws -> ValidationLotOutcome
    func contester(presenceId: String, motif: String, context: EtablissementReadContext) async throws -> ContestationOutcome
    /// `note` dans 1...5 (le port refuse toute autre valeur avant réseau).
    func noter(missionId: String, note: Int, context: EtablissementReadContext) async throws -> NotationOutcome
    func cloturerSegment(missionId: String, heureFin: Date, context: EtablissementReadContext) async throws -> ClotureOutcome
}

/// Publication d'une mission simple ou urgente, salariée (D8) — T9.
public protocol EtabPublicationPort: Sendable {
    func publier(_ brouillon: PublicationMission, context: EtablissementReadContext) async throws -> PublicationOutcome
}

/// Audit de consultation `DONNEES_PERSO_CONSULTATION` (D19) — câblé en T1, consommé par T4.
/// Best-effort comme `AuditPort` du lot 1 : un refus serveur rend `.nonEnregistre`, l'appelant avale
/// toute erreur levée sans l'afficher ; aucun doublon des audits déjà écrits par le serveur.
public protocol EtabAuditPort: Sendable {
    func consultation(page: PageAuditEtab, context: EtablissementReadContext) async throws -> AuditResultat
}

// MARK: - Ports « non câblés »

/// Erreur des stubs du lot 5 (même règle que `UnwiredPorts` du lot 1 : un gap connu reste verrouillé).
public enum UnwiredPortsLot5 {
    public static func erreur(port: String, tranche: String) -> JoleneError {
        JoleneError(.contract, "Port « \(port) » non câblé : livré par la tranche \(tranche) du lot 5 (docs/mobile-swift/LOT5_PLAN.md §3).")
    }
}

public struct UnwiredEtabSessionPort: EtabSessionPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { UnwiredPortsLot5.erreur(port: "session établissement", tranche: "T1") }
    public func permissions(etablissementId: String?) async throws -> PermissionsEtabResult { throw erreur }
    public func profil() async throws -> EtablissementProfil { throw erreur }
}

public struct UnwiredEtabDashboardPort: EtabDashboardPort, UnwiredPort {
    public init() {}
    public func tableauDeBord(context: EtablissementReadContext) async throws -> EtabDashboardSnapshot {
        throw UnwiredPortsLot5.erreur(port: "accueil établissement", tranche: "T4")
    }
}

public struct UnwiredEtabMissionsPort: EtabMissionsPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { UnwiredPortsLot5.erreur(port: "missions établissement", tranche: "T5") }
    public func missions(context: EtablissementReadContext, statut: String?, page: Int) async throws -> EtabMissionsPage { throw erreur }
    public func mission(id: String, context: EtablissementReadContext) async throws -> EtabMissionDetail? { throw erreur }
    public func soignant(id: String, context: EtablissementReadContext) async throws -> SoignantPourEtab? { throw erreur }
}

public struct UnwiredEtabCandidaturesPort: EtabCandidaturesPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { UnwiredPortsLot5.erreur(port: "candidatures établissement", tranche: "T6") }
    public func lecture(missionId: String, context: EtablissementReadContext) async throws -> LectureCandidaturesHabilitee {
        throw erreur
    }
    public func accepter(candidatureId: String, creneauxConfirmes: [CreneauConfirmePayload],
                         context: EtablissementReadContext) async throws -> TraitementCandidatureOutcome { throw erreur }
    public func refuser(candidatureId: String, context: EtablissementReadContext) async throws -> TraitementCandidatureOutcome {
        throw erreur
    }
}

public struct UnwiredEtabPointagePort: EtabPointagePort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { UnwiredPortsLot5.erreur(port: "pointage établissement", tranche: "T7") }
    public func etat(missionId: String, context: EtablissementReadContext) async throws -> EtatPointageEtab { throw erreur }
    public func contratSigne(missionId: String, context: EtablissementReadContext) async throws -> Bool { throw erreur }
    public func planning(missionId: String, context: EtablissementReadContext) async throws -> PlanningMission { throw erreur }
}

public struct UnwiredEtabPresencesPort: EtabPresencesPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { UnwiredPortsLot5.erreur(port: "présences établissement", tranche: "T8") }
    public func presences(context: EtablissementReadContext) async throws -> [PresenceEtab] { throw erreur }
    public func valider(presenceId: String, context: EtablissementReadContext) async throws -> ValidationPresenceOutcome { throw erreur }
    public func validerLot(ids: [String], context: EtablissementReadContext) async throws -> ValidationLotOutcome { throw erreur }
    public func contester(presenceId: String, motif: String, context: EtablissementReadContext) async throws -> ContestationOutcome {
        throw erreur
    }
    public func noter(missionId: String, note: Int, context: EtablissementReadContext) async throws -> NotationOutcome { throw erreur }
    public func cloturerSegment(missionId: String, heureFin: Date, context: EtablissementReadContext) async throws -> ClotureOutcome {
        throw erreur
    }
}

public struct UnwiredEtabPublicationPort: EtabPublicationPort, UnwiredPort {
    public init() {}
    public func publier(_ brouillon: PublicationMission, context: EtablissementReadContext) async throws -> PublicationOutcome {
        throw UnwiredPortsLot5.erreur(port: "publication de mission", tranche: "T9")
    }
}

public struct UnwiredEtabAuditPort: EtabAuditPort, UnwiredPort {
    public init() {}
    public func consultation(page: PageAuditEtab, context: EtablissementReadContext) async throws -> AuditResultat {
        throw UnwiredPortsLot5.erreur(port: "audit établissement", tranche: "T1")
    }
}
