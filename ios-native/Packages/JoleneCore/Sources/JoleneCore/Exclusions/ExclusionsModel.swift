import Foundation
import Combine

/// Listes de « Mes exclusions » : envoyées (retirables) et reçues (lecture seule).
public struct ListesExclusions: Equatable, Sendable {
    public var envoyees: [Exclusion]
    public var recues: [Exclusion]
    public init(envoyees: [Exclusion], recues: [Exclusion]) { self.envoyees = envoyees; self.recues = recues }
}

public enum EtatEcranExclusions: Equatable, Sendable {
    case chargement
    case pret(ListesExclusions)
    case echec(String)

    public var listes: ListesExclusions? {
        if case let .pret(listes) = self { return listes }
        return nil
    }
}

/// Modèle de « Mes exclusions » (`/soignant/exclusions`, L4-T11), port de `ExclusionsSoignant.tsx`, et du bouton
/// « Ne plus travailler ensemble » du détail de mission (`BoutonExclusion.tsx`). Mêmes règles que `FiltresModel` :
/// actions bornées, epoch, second appui refusé ; retrait (`fn_retirer_exclusion(p_exclu_id)`, l'identifiant de
/// l'établissement exclu, jamais l'id de ligne) et exclusion (`fn_exclure_utilisateur(…, 'SOIGNANT')`) annoncés seulement
/// après relecture des exclusions envoyées qui les montre ; refus verbatim ; erreur de transport : message puis relecture.
@MainActor
public final class ExclusionsModel: ObservableObject {
    @Published public private(set) var ecran: EtatEcranExclusions = .chargement
    @Published public private(set) var erreur: String?
    @Published public private(set) var confirmation: String?
    @Published public private(set) var jeton = 0
    @Published public private(set) var sessionExpiree = false
    @Published public private(set) var enCours: Set<String> = []

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private var revision = 0

    public init(controller: SessionController, snapshot: SessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
    }

    public func occupe(_ id: String) -> Bool { enCours.contains(id) }

    public func effacerMessages() {
        erreur = nil
        confirmation = nil
    }

    public func verifierSession(_ session: SessionStore) async {
        await session.start()
        guard session.state.snapshot?.epoch == snapshot.epoch else { return }
        await charger()
    }

    public func charger() async {
        erreur = nil
        await lire(explicite: true)
    }

    /// Retrait confirmé d'une exclusion envoyée (l.69-83) ; `true` si la relecture ne la montre plus.
    @discardableResult
    public func retirer(_ exclusion: Exclusion) async -> Bool {
        await muter(exclusion.excluId, succes: ExclusionsTextes.supprimee,
                    confirme: { envoyees in !envoyees.contains { $0.excluId == exclusion.excluId } }) { port, context in
            try await port.retirer(excluId: exclusion.excluId, context: context)
        }
    }

    /// « Confirmer l'exclusion » (`BoutonExclusion.tsx` l.23-45) ; `true` si la relecture montre l'établissement exclu.
    @discardableResult
    public func exclure(etablissementId: String, motif saisie: String) async -> Bool {
        let motif = ExclusionsRegles.motifEnvoye(saisie) ?? ""
        return await muter(etablissementId, succes: TextesWeb.Exclusion.enregistree,
                           confirme: { envoyees in envoyees.contains { $0.excluId == etablissementId } }) { port, context in
            try await port.exclure(etablissementId: etablissementId, motif: motif, context: context)
        }
    }

    // MARK: - Interne

    private func muter(_ id: String, succes: String, confirme: @escaping ([Exclusion]) -> Bool,
                       _ appel: @escaping @Sendable (ExclusionsPort, MissionReadContext) async throws -> IssueExclusion)
        async -> Bool {
        guard !id.isEmpty, !enCours.contains(id) else { return false }
        enCours.insert(id)
        defer { enCours.remove(id) }
        effacerMessages()
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return false }
        let port = gateways.exclusions
        let context = snapshot.context
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) { try await appel(port, context) }
            guard await controller.epoch == snapshot.epoch else { return false }
            sessionExpiree = false
            switch issue {
            case let .refusee(message):
                signaler(message.isEmpty ? ExclusionsTextes.erreurInconnue : message)
                return false
            case let .relues(envoyees):
                revision += 1
                ecran = .pret(ListesExclusions(envoyees: envoyees, recues: ecran.listes?.recues ?? []))
                guard confirme(envoyees) else {
                    signaler(ExclusionsTextes.nonConfirmee)
                    return false
                }
                confirmation = succes
                jeton += 1
                return true
            }
        } catch {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled,
                  let issue = PoolUrgenceModel.message(pour: error, repli: ExclusionsTextes.nonConfirmee) else { return false }
            sessionExpiree = issue.sessionExpiree
            signaler(issue.message)
            if !issue.sessionExpiree { await lire(explicite: false) }
            return false
        }
    }

    private func lire(explicite: Bool) async {
        revision += 1
        let revisionLecture = revision
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.exclusions
        let context = snapshot.context
        do {
            let listes = try await bounded(timeout: controller.resolutionTimeout) {
                async let envoyees = port.envoyees(context: context)
                async let recues = port.recues(context: context)
                return ListesExclusions(envoyees: try await envoyees, recues: try await recues)
            }
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision else { return }
            ecran = .pret(listes)
            sessionExpiree = false
        } catch {
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision, !Task.isCancelled,
                  let issue = PoolUrgenceModel.message(pour: error, repli: ExclusionsTextes.chargementImpossible) else { return }
            if issue.sessionExpiree { sessionExpiree = true }
            if ecran.listes != nil {
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
}
