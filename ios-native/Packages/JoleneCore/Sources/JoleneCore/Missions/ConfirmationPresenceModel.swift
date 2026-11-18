import Foundation

/// Confirmation de présence depuis le détail de mission (lot 1, T6c) : un seul appel `PresencePort.confirmerPresence`
/// à la fois, aucun renvoi automatique, succès annoncé seulement quand la gateway a relu `presence_confirmee_le`.
///
/// La RPC n'est pas idempotente (chaque appel réécrit l'instant et notifie l'établissement). Revue B8 (M1) :
/// - `enCours` est posé avant le premier `await` : un double toucher n'envoie qu'un appel ;
/// - la date relue par la gateway (relecture serveur de `missions.presence_confirmee_le`) est gardée : le bloc passe à
///   « confirmée » sans attendre la relecture de la mission par l'écran, même si celle-ci échoue, et le bouton ne
///   redevient jamais actif après un succès.
///
/// Revue B8 delta de #1157 (M1), intégration de la vague B — issue INCERTAINE : `{success:true}` sans relecture
/// concluante (`PresenceOutcome.envoyeeNonRelue`) ou délai dépassé de `bounded` (le serveur a pu écrire). L'écran affiche
/// alors le texte de relecture (`PresenceRules.Textes.envoyeeNonRelue`), jamais « Confirmation impossible. », et
/// `relectureRequise` interdit tout nouvel envoi : le bouton cède la place à « Actualiser » (`relire()`), qui relit la
/// mission. Date relue : confirmée. Mission relue sans la date : tout dépend de l'origine de l'incertitude (revue B8 de
/// #1158, M1) —
/// - **après l'accusé** `{success:true}` : l'issue RESTE incertaine. Le serveur écrit `presence_confirmee_le = NOW()` sans
///   condition avant de répondre (`public.sql` l.25003-25010) et rien ne la remet à NULL : une lecture sans la date est
///   anormale, elle ne prouve pas la non-réception (PRINCIPES §4) ; seule la réouverture de la mission recrée le bloc ;
/// - **après un délai dépassé sans accusé** : `bounded` annule la tâche locale, pas la requête déjà partie ; la RPC peut
///   encore valider après le délai. Une relecture sans la date ne conclut « non enregistrée » que si elle a lieu au moins
///   `delaiAvantConclusion` (30 s) après le début de l'appel expiré (revue B8 delta de #1158, m7) ; avant, l'issue reste
///   incertaine (« Actualiser »). Conclue, l'écran l'annonce sans promesse (`PresenceRules.Textes.nonEnregistree`, m8) et
///   l'envoi redevient possible.
/// Une mission relue qui n'est plus attribuée au soignant ne laisse rien à confirmer ; après l'accusé, le verrou d'envoi
/// est pourtant gardé tant que l'écran n'a pas relu la mission (m6 : le bloc est alors masqué, ou « Actualiser »
/// réapparaît). Une relecture en échec garde l'issue incertaine. « Confirmation impossible. » reste le repli d'un refus sans message et d'une erreur d'envoi, comme le web
/// (l.1426), jamais après un succès serveur. Mêmes gardes d'epoch que `MissionDetailModel`.
@MainActor
public final class ConfirmationPresenceModel: ObservableObject {
    public enum Issue: Equatable, Sendable {
        /// Relue confirmée : notice `TextesWeb.ConfirmationPresence.confirmation`.
        case confirmee
        /// Refus serveur verbatim, sinon le repli web « Confirmation impossible. » (erreur d'envoi, comme le web).
        case refus(String)
        /// Envoyée sans relecture concluante : texte de relecture, aucun nouvel envoi avant `relire()`.
        case incertaine(String)
        /// Délai dépassé sans accusé, puis relue sans la date au moins 30 s après le début de l'appel : constat neutre
        /// (`PresenceRules.Textes.nonEnregistree`), l'envoi redevient possible.
        case nonEnregistree(String)
    }

    /// Délai minimal entre le début d'un appel expiré (sans accusé) et une relecture sans la date qui peut conclure « non
    /// enregistrée » (revue B8 delta de #1158, m7) : au-delà, une RPC encore en vol côté PostgREST a eu le temps de valider.
    public static let delaiAvantConclusion: TimeInterval = 30

    @Published public private(set) var enCours = false
    @Published public private(set) var issue: Issue?
    @Published public private(set) var maintenant: Date?
    /// `presence_confirmee_le` relu par la gateway après un succès (jamais posé localement).
    @Published public private(set) var presenceRelue: String?
    /// Vrai tant qu'une confirmation a pu être reçue sans être relue : aucun envoi, seulement « Actualiser ».
    @Published public private(set) var relectureRequise = false

    /// Origine de l'incertitude (revue B8 de #1158, M1) : seul un délai dépassé sans accusé permet de conclure « non
    /// enregistrée » sur une relecture sans la date.
    private enum OrigineIncertitude { case accuse, delaiSansAccuse }
    private var origine: OrigineIncertitude?
    /// Début (horloge des gateways) du dernier appel `confirmerPresence` : base du délai de `delaiAvantConclusion`.
    private var debutAppel: Date?

    public let missionId: String
    private let controller: SessionController
    private let snapshot: SessionSnapshot

    public init(missionId: String, controller: SessionController, snapshot: SessionSnapshot) {
        self.missionId = missionId
        self.controller = controller
        self.snapshot = snapshot
    }

    /// Horloge des gateways de la session (démo : horloge fixée).
    public func charger() async {
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        maintenant = gateways.clock.now()
    }

    /// Bloc de la mission relue par l'écran, complétée par la date relue par la gateway quand la mission ne la porte pas
    /// encore (relecture de la mission en retard ou en échec).
    public func bloc(_ mission: MissionRecord) -> PresenceRules.Bloc {
        guard let maintenant else { return .masque }
        var relue = mission
        if (relue.presenceConfirmeeLe ?? "").isEmpty, let presenceRelue { relue.presenceConfirmeeLe = presenceRelue }
        return PresenceRules.bloc(relue, userId: snapshot.context.userId, maintenant: maintenant)
    }

    /// Rend `true` quand l'écran doit relire la mission (confirmation relue, issue incertaine, ou refus : l'état a pu
    /// changer). Aucun envoi pendant un appel, après un succès relu, ni tant qu'une issue incertaine n'est pas relue.
    public func confirmer() async -> Bool {
        guard !enCours, presenceRelue == nil, !relectureRequise else { return false }
        enCours = true
        defer { enCours = false }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return false }
        let port = gateways.presence
        let id = missionId
        let context = snapshot.context
        issue = nil
        debutAppel = gateways.clock.now()
        do {
            let outcome = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.confirmerPresence(missionId: id, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return false }
            switch outcome {
            case let .confirmee(presenceConfirmeeLe):
                presenceRelue = presenceConfirmeeLe
                issue = .confirmee
            case let .refusee(message):
                issue = .refus(PresenceRules.messageRefus(message))
            case let .envoyeeNonRelue(message):
                relectureRequise = true
                origine = .accuse
                issue = .incertaine(message)
                await relireMission(gateways)
            }
            return true
        } catch {
            guard await controller.epoch == snapshot.epoch else { return false }
            if Self.estAnnulation(error) { return false }
            if Self.estDelaiDepasse(error) {
                // Le serveur a pu écrire : jamais un échec annoncé (Bounded.swift, PRINCIPES §3-§4).
                relectureRequise = true
                origine = .delaiSansAccuse
                issue = .incertaine(PresenceRules.Textes.envoyeeNonRelue)
                await relireMission(gateways)
                return true
            }
            // Revue B8 (m3) : `error || data?.error` du web → repli pour une erreur d'envoi sans message serveur.
            issue = .refus(TextesWeb.ConfirmationPresence.repliRefus)
            return true
        }
    }

    /// « Actualiser » d'une issue incertaine : relit la mission. Rend `true` quand l'écran doit la relire aussi.
    public func relire() async -> Bool {
        guard !enCours, relectureRequise else { return false }
        enCours = true
        defer { enCours = false }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return false }
        await relireMission(gateways)
        return true
    }

    /// Relecture de la mission sous la session (`MissionsPort.mission`, qui lit `presence_confirmee_le`). Conclut ou laisse
    /// l'issue incertaine ; jamais d'envoi.
    private func relireMission(_ gateways: Gateways) async {
        let missions = gateways.missions
        let id = missionId
        let context = snapshot.context
        do {
            let relue = try await bounded(timeout: controller.resolutionTimeout) {
                try await missions.mission(id: id, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return }
            guard let record = relue?.record, let assigne = record.soignantAssigneId,
                  assigne.caseInsensitiveCompare(context.userId) == .orderedSame else {
                // Plus attribuée au soignant (ligne absente sous RLS comprise) : plus rien à confirmer. Après l'accusé,
                // le verrou d'envoi reste posé tant que l'écran n'a pas relu la mission (m6) : le bloc sera masqué, ou
                // « Actualiser » réapparaîtra si la mission relue par l'écran est encore assignée.
                if origine == .accuse {
                    issue = nil
                } else {
                    conclure(issue: nil)
                }
                return
            }
            if let date = record.presenceConfirmeeLe, !date.isEmpty {
                presenceRelue = date
                conclure(issue: .confirmee)
            } else if origine == .delaiSansAccuse {
                // Délai dépassé sans accusé, mission relue sans la date : non enregistrée seulement si la relecture a lieu
                // au moins `delaiAvantConclusion` après le début de l'appel expiré (m7) ; avant, l'issue reste incertaine.
                let ecoule = debutAppel.map { gateways.clock.now().timeIntervalSince($0) } ?? 0
                if ecoule >= Self.delaiAvantConclusion {
                    conclure(issue: .nonEnregistree(PresenceRules.Textes.nonEnregistree))
                } else {
                    issue = .incertaine(PresenceRules.Textes.envoyeeNonRelue)
                }
            } else {
                // Accusé reçu, mission relue sans la date : lecture anormale, jamais une preuve de non-réception
                // (revue B8 de #1158, M1) ; l'issue reste incertaine, aucun envoi.
                issue = .incertaine(PresenceRules.Textes.envoyeeNonRelue)
            }
        } catch {
            guard await controller.epoch == snapshot.epoch, !Self.estAnnulation(error) else { return }
            issue = .incertaine(PresenceRules.Textes.envoyeeNonRelue)
        }
    }

    /// Relecture concluante : l'incertitude est levée.
    private func conclure(issue nouvelle: Issue?) {
        issue = nouvelle
        relectureRequise = false
        origine = nil
    }

    private static func estAnnulation(_ error: Error) -> Bool {
        error is CancellationError || (error as? JoleneError)?.kind == .cancelled
    }

    /// Dépassement de `bounded` (`SessionController.timeoutMessage`), distinct d'une erreur de transport du port.
    private static func estDelaiDepasse(_ error: Error) -> Bool {
        (error as? JoleneError) == JoleneError(.network, SessionController.timeoutMessage)
    }
}
