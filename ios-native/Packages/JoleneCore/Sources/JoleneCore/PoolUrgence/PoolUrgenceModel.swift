import Foundation
import Combine

/// État de l'écran Pool urgence : en attente de la première réponse, relu, ou en échec (message affiché).
public enum EtatEcranPool: Equatable, Sendable {
    case chargement
    case pret(EtatPool)
    case echec(String)

    public var etat: EtatPool? {
        if case let .pret(etat) = self { return etat }
        return nil
    }
}

/// Modèle de « Pool urgence » (L4-T11), port de `PoolUrgenceSoignant.tsx` et `PoolUrgenceToggle.tsx`.
///
/// Règles (mêmes que `FiltresModel`, L4-T4) :
/// - lectures et actions bornées à `SessionController.resolutionTimeout`, gateways de l'epoch de l'écran, réponse d'un
///   epoch périmé ignorée ; une action en cours n'accepte pas de second appui ;
/// - bascule du pool et rayon : `PoolUrgencePort.basculer` (seul chemin d'écriture de la disponibilité urgence de `soignants`,
///   `fn_toggle_pool_urgence`) ; SMS : `basculerSMS` ; chaque succès n'est annoncé qu'après une relecture de l'état qui le
///   confirme (PRINCIPES §3) ; refus serveur (rayon hors bornes, documents) affiché verbatim, l'interrupteur reste à
///   l'état relu ;
/// - acceptation rapide : planning exact obligatoire (web l.100-104), puis `CandidaturePort.confirmer(.urgence)` ; le
///   succès (« En attente de validation étab ») n'est affiché qu'après relecture de l'état du pool qui montre
///   `EN_ATTENTE_VALIDATION_ETAB` ; `choixRequis` n'est jamais rejoué : message et lien vers le détail de la mission ;
///   refus verbatim ; planning modifié ou mission déjà attribuée : message puis relecture ;
/// - erreur de transport : message puis relecture (le serveur a pu agir), jamais de renvoi ; session expirée signalée ;
///   une annulation (vue qui disparaît) n'est jamais une erreur.
@MainActor
public final class PoolUrgenceModel: ObservableObject {
    @Published public private(set) var ecran: EtatEcranPool = .chargement
    @Published public private(set) var erreur: String?
    @Published public private(set) var confirmation: String?
    @Published public private(set) var jeton = 0
    @Published public private(set) var sessionExpiree = false
    /// Clés d'action en cours : `pool`, `sms`, ou l'id d'une mission.
    @Published public private(set) var enCours: Set<String> = []
    /// Missions dont l'acceptation rapide demande un choix de contrat : seul le détail de la mission (lot 1) le fait.
    @Published public private(set) var choixRequis: Set<String> = []
    /// Refus « documents » de la dernière bascule (`documents_salarie_ok:false`) : lien vers les documents.
    @Published public private(set) var documentsManquants = false

    public static let clePool = "pool"
    public static let cleSMS = "sms"

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private var revision = 0

    public init(controller: SessionController, snapshot: SessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
    }

    public func occupe(_ cle: String) -> Bool { enCours.contains(cle) }

    public func verifierSession(_ session: SessionStore) async {
        await session.start()
        guard session.state.snapshot?.epoch == snapshot.epoch else { return }
        await charger()
    }

    // MARK: - Lecture

    /// À chaque apparition et « Réessayer » (le web relit au montage et après chaque action).
    public func charger() async {
        erreur = nil
        await lire(explicite: true)
    }

    // MARK: - Bascules

    /// Interrupteur du pool (l.114-122) : rayon courant conservé ; refus → interrupteur à l'état relu.
    public func basculer(actif: Bool) async {
        guard let etat = ecran.etat else { return }
        let rayon = PoolUrgenceRegles.rayonCurseur(etat.rayonKm)
        await muterPool(cle: Self.clePool, succes: actif ? PoolUrgenceTextes.active : PoolUrgenceTextes.desactive,
                        confirme: { $0.actif == actif && $0.rayonKm == rayon }) { port, context in
            try await port.basculer(actif: actif, rayonKm: rayon, context: context)
        }
    }

    /// Fin du geste sur le curseur (`onValueCommit`, l.167-171) : `p_actif = true`, nouveau rayon.
    public func validerRayon(_ rayon: Int) async {
        guard let etat = ecran.etat, etat.actif, etat.rayonKm != rayon else { return }
        await muterPool(cle: Self.clePool, succes: PoolUrgenceTextes.active,
                        confirme: { $0.actif && $0.rayonKm == rayon }) { port, context in
            try await port.basculer(actif: true, rayonKm: rayon, context: context)
        }
    }

    /// Interrupteur des SMS (l.190-198).
    public func basculerSMS(_ actif: Bool) async {
        await muterPool(cle: Self.cleSMS, succes: actif ? PoolUrgenceTextes.smsActives : PoolUrgenceTextes.smsDesactives,
                        confirme: { $0.smsOptIn == actif }) { port, context in
            try await port.basculerSMS(actif, context: context)
        }
    }

    // MARK: - Acceptation rapide

    /// « Confirmer mon acceptation urgente » du récapitulatif (l.99-127, l.257-264).
    public func accepter(_ mission: MissionUrgente) async {
        guard !enCours.contains(mission.id) else { return }
        guard let creneaux = CreneauxConfirmes.pourAction(PlanningCandidatInput(mission: mission.mission)), !creneaux.isEmpty,
              mission.mission.planningExact else {
            signaler(PoolUrgenceTextes.planningARecharger)
            return
        }
        enCours.insert(mission.id)
        defer { enCours.remove(mission.id) }
        effacerMessages()
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.candidature
        let context = snapshot.context
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.confirmer(action: .urgence, missionId: mission.id, creneaux: creneaux, message: nil,
                                         choixContrat: nil, candidatureId: nil, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return }
            sessionExpiree = false
            switch issue {
            case .confirmed:
                await lire(explicite: false)
                let relue = ecran.etat?.missions.first { $0.id == mission.id }
                guard relue?.statutCandidature == PoolUrgenceRegles.statutEnAttenteValidation else {
                    signaler(PoolUrgenceTextes.nonConfirmee)
                    return
                }
                confirmation = PoolUrgenceTextes.acceptationEnregistree
                jeton += 1
            case .choixRequis:
                choixRequis.insert(mission.id)
                signaler(PoolUrgenceTextes.choixContratRequis)
            case let .refusee(_, message, _):
                signaler(message)
            case let .planningAReconfirmer(_, message), let .missionDejaAttribuee(message):
                signaler(message)
                await lire(explicite: false)
            }
        } catch {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: PoolUrgenceTextes.nonConfirmee) else { return }
            sessionExpiree = issue.sessionExpiree
            signaler(issue.message)
            if !issue.sessionExpiree { await lire(explicite: false) }
        }
    }

    // MARK: - Interne

    public func effacerMessages() {
        erreur = nil
        confirmation = nil
    }

    private func muterPool(cle: String, succes: String, confirme: @escaping (EtatPool) -> Bool,
                           _ appel: @escaping @Sendable (PoolUrgencePort, MissionReadContext) async throws -> IssuePool) async {
        guard !enCours.contains(cle) else { return }
        enCours.insert(cle)
        defer { enCours.remove(cle) }
        effacerMessages()
        documentsManquants = false
        revision += 1
        let revisionMutation = revision
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.poolUrgence
        let context = snapshot.context
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) { try await appel(port, context) }
            guard await controller.epoch == snapshot.epoch else { return }
            sessionExpiree = false
            switch issue {
            case let .refuse(message):
                documentsManquants = message == PoolUrgenceRegles.refusDocuments
                signaler(message)
                // L'interrupteur revient à l'état serveur (le web le remet à sa valeur précédente).
                objectWillChange.send()
            case let .relu(etat):
                if revisionMutation == revision { ecran = .pret(etat) }
                guard confirme(etat) else {
                    signaler(PoolUrgenceTextes.nonConfirmee)
                    return
                }
                confirmation = succes
                jeton += 1
            }
        } catch {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: PoolUrgenceTextes.nonConfirmee) else { return }
            sessionExpiree = issue.sessionExpiree
            signaler(issue.message)
            if !issue.sessionExpiree { await lire(explicite: false) }
        }
    }

    private func lire(explicite: Bool) async {
        revision += 1
        let revisionLecture = revision
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.poolUrgence
        let context = snapshot.context
        do {
            let etat = try await bounded(timeout: controller.resolutionTimeout) { try await port.etat(context: context) }
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision else { return }
            ecran = .pret(etat)
            sessionExpiree = false
        } catch {
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: PoolUrgenceTextes.chargementImpossible) else { return }
            if issue.sessionExpiree { sessionExpiree = true }
            if ecran.etat != nil {
                if explicite { signaler(issue.message) }
            } else {
                ecran = .echec(issue.message)
            }
        }
    }

    private func signaler(_ message: String) {
        confirmation = nil
        erreur = message
        jeton += 1
    }

    nonisolated static func message(pour error: Error, repli: String) -> (message: String, sessionExpiree: Bool)? {
        if error is CancellationError { return nil }
        if let jolene = error as? JoleneError {
            if jolene.kind == .cancelled { return nil }
            return (jolene.message, jolene.kind == .unauthorized)
        }
        return (repli, false)
    }
}
