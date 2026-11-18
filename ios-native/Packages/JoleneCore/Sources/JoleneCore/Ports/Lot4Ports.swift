import Foundation

// Ports du lot 4 (blueprint `docs/mobile-swift/LOT4_PLAN.md` §2.3, tranche T1). Tous `Sendable` (concurrence
// stricte). Mêmes règles qu'aux lots 1 à 3 : chaque méthode d'un port utilisateur reçoit le `MissionReadContext` de
// l'epoch courant ; chaque appel est borné par l'appelant (`bounded(timeout: resolutionTimeout)`, décision 14 du lot 1) ;
// une mutation n'annonce un succès qu'après relecture serveur (PRINCIPES §3) ; refus métier = issues de
// `Models/Lot4Results.swift`, erreurs de transport = `JoleneError`. Les treize ports sont des champs du bloc « Lot 4 »
// de `Gateways` ; chaque monde les assigne par une fabrique de domaine (`DemoLot4`, `SupabaseLot4`, §2.2).
//
// Le ❤️ du swipe et l'acceptation rapide du pool urgence ne sont pas ici : ils passent par
// `CandidaturePort.confirmer(action: .swipeLike / .urgence, …)` du lot 1 (décision D2).

// MARK: - Ports

/// Swipe (`fn_obtenir_missions_swipe`, `fn_enregistrer_swipe`, `fn_retirer_candidature`,
/// `fn_initialiser_preferences_matching`, PostgREST `swipes`) — tranche T3a.
public protocol SwipePort: Sendable {
    /// Paquet de 20 cartes, créneaux PREVISIONNEL hors pauses.
    func paquet(context: MissionReadContext) async throws -> [CarteSwipe]
    /// ✕ et ⭐ ; la carte n'est retirée qu'après `.enregistre`.
    func enregistrer(missionId: String, direction: DirectionSwipe, context: MissionReadContext) async throws -> SwipeOutcome
    /// Annulation du ❤️ (toast 5 s) : la carte n'est jamais remise dans le paquet (correction 12, D4).
    func retirer(candidatureId: String, context: MissionReadContext) async throws -> RetraitOutcome
    /// Nombre de swipes en base (quiz au premier contact seulement).
    func nombreSwipes(context: MissionReadContext) async throws -> Int
    func initialiserPreferences(_ preferences: PreferencesMatching, context: MissionReadContext) async throws
}

/// Recherches sauvegardées et alerte rapide (`fn_*_filtre_sauvegarde`, `fn_lister_mes_filtres_sauvegardes`) — T4.
public protocol FiltresSauvegardesPort: Sendable {
    func lister(context: MissionReadContext) async throws -> [FiltreSauvegarde]
    func creer(nom: String, filtres: FiltresAlerte, alerte: Bool, frequence: FrequenceAlerte,
               context: MissionReadContext) async throws -> IssueFiltre
    /// `nom` / `frequence` à `nil` : paramètre non envoyé, valeur serveur conservée (`COALESCE`, T4 ; la cloche n'envoie
    /// que `p_alerte_active`, comme le web).
    func modifier(id: String, nom: String?, alerte: Bool, frequence: FrequenceAlerte?,
                  context: MissionReadContext) async throws -> IssueFiltre
    func supprimer(id: String, context: MissionReadContext) async throws -> IssueFiltre
}

/// Disponibilités (PostgREST `disponibilites_soignant`, `fn_definir_disponibilite`) — T5.
public protocol DisponibilitesPort: Sendable {
    func lister(depuis: JourParis, context: MissionReadContext) async throws -> Set<DispoCle>
    func definir(jour: JourParis, creneau: CreneauDispo, disponible: Bool,
                 context: MissionReadContext) async throws -> IssueDisponibilite
}

/// Parrainage (`soignants.code_parrainage`, `fn_obtenir_mes_parrainages`, `fn_appliquer_parrainage`) — T6.
public protocol ParrainagePort: Sendable {
    func etat(context: MissionReadContext) async throws -> EtatParrainage
    func appliquer(code: String, context: MissionReadContext) async throws -> ApplicationParrainage
}

/// Litiges (PostgREST `litiges`, `messages_litige`, `fn_ouvrir_litige_rate_limited` 3 arguments,
/// `fn_ajouter_message_litige`) — T8.
public protocol LitigesPort: Sendable {
    func lister(context: MissionReadContext) async throws -> [Litige]
    func missionsContestables(context: MissionReadContext) async throws -> [MissionContestable]
    func ouvrir(missionId: String, motif: String, context: MissionReadContext) async throws -> OuvertureLitigeOutcome
    func fil(litigeId: String, context: MissionReadContext) async throws -> [MessageLitige]
    func ajouterMessage(litigeId: String, contenu: String, context: MissionReadContext) async throws -> IssueMessageLitige
}

/// Réclamations générales (PostgREST `reclamations`, `fn_soumettre_reclamation`) — T8.
public protocol ReclamationsPort: Sendable {
    func lister(context: MissionReadContext) async throws -> [Reclamation]
    func soumettre(categorie: CategorieReclamation, sujet: String, details: String,
                   context: MissionReadContext) async throws -> IssueReclamation
}

/// Mon score (`fn_mon_breakdown_actuel`, `fn_evolution_score_soignant`, `fn_mes_evenements_score`,
/// `fn_lister_notations_recues`, `fn_creer_reclamation_score`) — T9.
public protocol ScorePort: Sendable {
    func breakdown(context: MissionReadContext) async throws -> BreakdownScore
    func evolution(mois: Int, context: MissionReadContext) async throws -> [PointEvolutionScore]
    func evenements(limite: Int, context: MissionReadContext) async throws -> [EvenementScore]
    func notationsRecues(limite: Int, context: MissionReadContext) async throws -> [NotationRecue]
    /// `p_evenement_type = 'SOIGNANT'`, sans justificatif (D10) ; `motif` = valeur du web (`ModaleReclamationScore.tsx`).
    func contester(evenementId: String, motif: String, texte: String,
                   context: MissionReadContext) async throws -> ReclamationScoreOutcome
}

/// Évaluations reçues (`fn_mes_notations_recues_avec_stats`, `fn_signaler_notation`) — T9. Seule source des notes
/// publiées avec `ScorePort.notationsRecues` (filtre de visibilité centralisé, garde-fou 18).
public protocol EvaluationsPort: Sendable {
    func recues(filtre: FiltreEvaluations, page: Int, context: MissionReadContext) async throws -> PageEvaluations
    func signaler(notationId: String, motif: String, context: MissionReadContext) async throws -> IssueSignalement
}

/// Messagerie (RPC de liste, de lecture et de blocage, PostgREST `messages_chat`, edge `messagerie-validate`) — T7a.
public protocol MessageriePort: Sendable {
    func conversations(avant: CurseurConversations?, context: MissionReadContext) async throws -> PageConversations
    func interlocuteurs(ids: [String], context: MissionReadContext) async throws -> [Interlocuteur]
    /// 500 derniers messages.
    func messages(conversationId: String, context: MissionReadContext) async throws -> [MessageChat]
    /// Par l'edge seulement (garde-fou 19) ; succès = `message_id` puis relecture de la ligne.
    func envoyer(conversationId: String, contenu: String, context: MissionReadContext) async throws -> EnvoiOutcome
    func message(id: String, conversationId: String, context: MissionReadContext) async throws -> MessageChat?
    func marquerLus(conversationId: String, context: MissionReadContext) async throws -> IssueLecture
    func saisie(debut: Bool, conversationId: String, context: MissionReadContext) async throws
    func presence(context: MissionReadContext) async throws
    func bloque(cibleId: String, context: MissionReadContext) async throws -> Bool
    /// Rend l'état relu (`fn_est_bloque`).
    func basculerBlocage(cibleId: String, bloquer: Bool, context: MissionReadContext) async throws -> Bool
    func signaler(cibleId: String, type: TypeCibleSignalement, categorie: String, motif: String, missionId: String?,
                  context: MissionReadContext) async throws -> IssueSignalement
    /// Badge Messages : `fn_messages_non_lus()` (correction 19).
    func nonLus(context: MissionReadContext) async throws -> Int
    /// « Écrire à l'établissement » depuis le détail de mission (correction 20).
    func conversationPourMission(missionId: String, etablissementId: String,
                                 context: MissionReadContext) async throws -> IssueConversationMission
}

/// Realtime (`client.realtimeV2`, `messages_chat`, `typing_status`, `presence_status`) — T7a. Un flux n'est jamais une
/// preuve d'envoi ; à chaque `rejoint` après coupure, relecture du fil.
public protocol RealtimePort: Sendable {
    func messagesEntrants(conversationId: String?) -> AsyncStream<MessageChat>
    func saisies(conversationId: String) -> AsyncStream<EtatSaisie>
    func presence(userId: String) -> AsyncStream<EtatPresence>
    func etat() -> AsyncStream<EtatCanal>
    func fermerTout() async
}

/// Copies officielles des bulletins (`fn_lister_copies_bulletins`, edge `copies-bulletins`,
/// `fn_signaler_copie_bulletin`) — T10.
public protocol BulletinsPort: Sendable {
    func copies(context: MissionReadContext) async throws -> [CopieBulletin]
    /// Type, taille et SHA-256 vérifiés contre la ligne ; aucun cache.
    func telecharger(copie: CopieBulletin, context: MissionReadContext) async throws -> PDFVerifie
    /// Rend la liste relue (`signalee`, et `RETIREE` pour `DESTINATAIRE`).
    func signaler(copieId: String, motif: MotifSignalementCopie, context: MissionReadContext) async throws -> [CopieBulletin]
}

/// Pool urgence (`fn_pool_urgence_missions_pour_soignant`, `fn_toggle_pool_urgence`, `fn_toggle_pool_urgence_sms`) — T11.
public protocol PoolUrgencePort: Sendable {
    func etat(context: MissionReadContext) async throws -> EtatPool
    func basculer(actif: Bool, rayonKm: Int, context: MissionReadContext) async throws -> IssuePool
    func basculerSMS(_ actif: Bool, context: MissionReadContext) async throws -> IssuePool
}

/// Établissements exclus (PostgREST `exclusions`, `fn_mes_exclusions_recues`, `fn_retirer_exclusion`,
/// `fn_exclure_utilisateur`) — T11.
public protocol ExclusionsPort: Sendable {
    func envoyees(context: MissionReadContext) async throws -> [Exclusion]
    func recues(context: MissionReadContext) async throws -> [Exclusion]
    func retirer(excluId: String, context: MissionReadContext) async throws -> IssueExclusion
    /// « Ne plus travailler ensemble » depuis le détail de mission (`p_type = 'SOIGNANT'`).
    func exclure(etablissementId: String, motif: String, context: MissionReadContext) async throws -> IssueExclusion
}

// MARK: - Stubs « non câblés »

/// Message des stubs du lot 4 : tranche et lot cités (`UnwiredPorts.erreur(port:tranche:lot:)`).
enum Lot4 {
    static func erreur(_ port: String, _ tranche: String) -> JoleneError {
        UnwiredPorts.erreur(port: port, tranche: tranche, lot: 4)
    }
}

public struct UnwiredSwipePort: SwipePort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot4.erreur("swipe", "T3a") }
    public func paquet(context: MissionReadContext) async throws -> [CarteSwipe] { throw erreur }
    public func enregistrer(missionId: String, direction: DirectionSwipe, context: MissionReadContext) async throws -> SwipeOutcome {
        throw erreur
    }
    public func retirer(candidatureId: String, context: MissionReadContext) async throws -> RetraitOutcome { throw erreur }
    public func nombreSwipes(context: MissionReadContext) async throws -> Int { throw erreur }
    public func initialiserPreferences(_ preferences: PreferencesMatching, context: MissionReadContext) async throws { throw erreur }
}

public struct UnwiredFiltresSauvegardesPort: FiltresSauvegardesPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot4.erreur("recherches sauvegardées", "T4") }
    public func lister(context: MissionReadContext) async throws -> [FiltreSauvegarde] { throw erreur }
    public func creer(nom: String, filtres: FiltresAlerte, alerte: Bool, frequence: FrequenceAlerte,
                      context: MissionReadContext) async throws -> IssueFiltre { throw erreur }
    public func modifier(id: String, nom: String?, alerte: Bool, frequence: FrequenceAlerte?,
                         context: MissionReadContext) async throws -> IssueFiltre { throw erreur }
    public func supprimer(id: String, context: MissionReadContext) async throws -> IssueFiltre { throw erreur }
}

public struct UnwiredDisponibilitesPort: DisponibilitesPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot4.erreur("disponibilités", "T5") }
    public func lister(depuis: JourParis, context: MissionReadContext) async throws -> Set<DispoCle> { throw erreur }
    public func definir(jour: JourParis, creneau: CreneauDispo, disponible: Bool,
                        context: MissionReadContext) async throws -> IssueDisponibilite { throw erreur }
}

public struct UnwiredParrainagePort: ParrainagePort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot4.erreur("parrainage", "T6") }
    public func etat(context: MissionReadContext) async throws -> EtatParrainage { throw erreur }
    public func appliquer(code: String, context: MissionReadContext) async throws -> ApplicationParrainage { throw erreur }
}

public struct UnwiredLitigesPort: LitigesPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot4.erreur("litiges", "T8") }
    public func lister(context: MissionReadContext) async throws -> [Litige] { throw erreur }
    public func missionsContestables(context: MissionReadContext) async throws -> [MissionContestable] { throw erreur }
    public func ouvrir(missionId: String, motif: String, context: MissionReadContext) async throws -> OuvertureLitigeOutcome {
        throw erreur
    }
    public func fil(litigeId: String, context: MissionReadContext) async throws -> [MessageLitige] { throw erreur }
    public func ajouterMessage(litigeId: String, contenu: String, context: MissionReadContext) async throws -> IssueMessageLitige {
        throw erreur
    }
}

public struct UnwiredReclamationsPort: ReclamationsPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot4.erreur("réclamations", "T8") }
    public func lister(context: MissionReadContext) async throws -> [Reclamation] { throw erreur }
    public func soumettre(categorie: CategorieReclamation, sujet: String, details: String,
                          context: MissionReadContext) async throws -> IssueReclamation { throw erreur }
}

public struct UnwiredScorePort: ScorePort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot4.erreur("score", "T9") }
    public func breakdown(context: MissionReadContext) async throws -> BreakdownScore { throw erreur }
    public func evolution(mois: Int, context: MissionReadContext) async throws -> [PointEvolutionScore] { throw erreur }
    public func evenements(limite: Int, context: MissionReadContext) async throws -> [EvenementScore] { throw erreur }
    public func notationsRecues(limite: Int, context: MissionReadContext) async throws -> [NotationRecue] { throw erreur }
    public func contester(evenementId: String, motif: String, texte: String,
                          context: MissionReadContext) async throws -> ReclamationScoreOutcome { throw erreur }
}

public struct UnwiredEvaluationsPort: EvaluationsPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot4.erreur("évaluations reçues", "T9") }
    public func recues(filtre: FiltreEvaluations, page: Int, context: MissionReadContext) async throws -> PageEvaluations {
        throw erreur
    }
    public func signaler(notationId: String, motif: String, context: MissionReadContext) async throws -> IssueSignalement {
        throw erreur
    }
}

public struct UnwiredMessageriePort: MessageriePort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot4.erreur("messagerie", "T7a") }
    public func conversations(avant: CurseurConversations?, context: MissionReadContext) async throws -> PageConversations {
        throw erreur
    }
    public func interlocuteurs(ids: [String], context: MissionReadContext) async throws -> [Interlocuteur] { throw erreur }
    public func messages(conversationId: String, context: MissionReadContext) async throws -> [MessageChat] { throw erreur }
    public func envoyer(conversationId: String, contenu: String, context: MissionReadContext) async throws -> EnvoiOutcome {
        throw erreur
    }
    public func message(id: String, conversationId: String, context: MissionReadContext) async throws -> MessageChat? {
        throw erreur
    }
    public func marquerLus(conversationId: String, context: MissionReadContext) async throws -> IssueLecture { throw erreur }
    public func saisie(debut: Bool, conversationId: String, context: MissionReadContext) async throws { throw erreur }
    public func presence(context: MissionReadContext) async throws { throw erreur }
    public func bloque(cibleId: String, context: MissionReadContext) async throws -> Bool { throw erreur }
    public func basculerBlocage(cibleId: String, bloquer: Bool, context: MissionReadContext) async throws -> Bool { throw erreur }
    public func signaler(cibleId: String, type: TypeCibleSignalement, categorie: String, motif: String, missionId: String?,
                         context: MissionReadContext) async throws -> IssueSignalement { throw erreur }
    public func nonLus(context: MissionReadContext) async throws -> Int { throw erreur }
    public func conversationPourMission(missionId: String, etablissementId: String,
                                        context: MissionReadContext) async throws -> IssueConversationMission { throw erreur }
}

/// Flux terminés immédiatement : aucun événement plausible n'est émis par un port non câblé.
public struct UnwiredRealtimePort: RealtimePort, UnwiredPort {
    public init() {}
    public func messagesEntrants(conversationId: String?) -> AsyncStream<MessageChat> { AsyncStream { $0.finish() } }
    public func saisies(conversationId: String) -> AsyncStream<EtatSaisie> { AsyncStream { $0.finish() } }
    public func presence(userId: String) -> AsyncStream<EtatPresence> { AsyncStream { $0.finish() } }
    public func etat() -> AsyncStream<EtatCanal> { AsyncStream { $0.finish() } }
    public func fermerTout() async {}
}

public struct UnwiredBulletinsPort: BulletinsPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot4.erreur("copies des bulletins", "T10") }
    public func copies(context: MissionReadContext) async throws -> [CopieBulletin] { throw erreur }
    public func telecharger(copie: CopieBulletin, context: MissionReadContext) async throws -> PDFVerifie { throw erreur }
    public func signaler(copieId: String, motif: MotifSignalementCopie,
                         context: MissionReadContext) async throws -> [CopieBulletin] { throw erreur }
}

public struct UnwiredPoolUrgencePort: PoolUrgencePort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot4.erreur("pool urgence", "T11") }
    public func etat(context: MissionReadContext) async throws -> EtatPool { throw erreur }
    public func basculer(actif: Bool, rayonKm: Int, context: MissionReadContext) async throws -> IssuePool { throw erreur }
    public func basculerSMS(_ actif: Bool, context: MissionReadContext) async throws -> IssuePool { throw erreur }
}

public struct UnwiredExclusionsPort: ExclusionsPort, UnwiredPort {
    public init() {}
    private var erreur: JoleneError { Lot4.erreur("exclusions", "T11") }
    public func envoyees(context: MissionReadContext) async throws -> [Exclusion] { throw erreur }
    public func recues(context: MissionReadContext) async throws -> [Exclusion] { throw erreur }
    public func retirer(excluId: String, context: MissionReadContext) async throws -> IssueExclusion { throw erreur }
    public func exclure(etablissementId: String, motif: String, context: MissionReadContext) async throws -> IssueExclusion {
        throw erreur
    }
}
