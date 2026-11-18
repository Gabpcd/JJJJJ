import Foundation

/// Candidature depuis le détail d'une mission (lot 1, T6b) : relit la candidature et le profil côté serveur, envoie
/// POSTULER / ACCEPTER / PROPOSITION par `CandidaturePort` et rend l'issue à l'écran. Jamais de succès supposé
/// (PRINCIPES §3) : la gateway relit avant de répondre `.confirmed`, puis l'écran relit la mission et ce modèle la
/// candidature. Aucun renvoi automatique : après un délai dépassé ou une erreur, l'état est relu, et c'est le
/// soignant qui décide de réessayer. Mêmes gardes d'epoch que `MissionDetailModel`.
@MainActor
public final class CandidatureModel: ObservableObject {
    /// Issue affichée sous les actions jusqu'à la prochaine action.
    public enum Issue: Equatable, Sendable {
        /// Refus ou erreur : texte serveur verbatim (Code du travail compris) ou message `JoleneError`.
        case erreur(String)
        /// Planning modifié depuis l'affichage : texte serveur, mission relue avant toute nouvelle confirmation.
        case planningAReconfirmer(String)
        /// Proposition refusée et relue `REFUSEE`.
        case propositionRefusee
    }

    @Published public private(set) var candidature: CandidatureRecord?
    @Published public private(set) var profil: SoignantProfile?
    @Published public private(set) var maintenant: Date?
    @Published public private(set) var enCours = false
    @Published public private(set) var issue: Issue?
    /// Options du serveur quand `choix_requis` : non vide → feuille de choix, l'action est rejouée avec l'option.
    @Published public var optionsContrat: [ChoixContratOption] = []
    /// Message de POSTULER, borné à 300 caractères comme le web.
    @Published public var message = "" {
        didSet {
            if message.count > LibellesCandidature.messageLongueurMax {
                message = String(message.prefix(LibellesCandidature.messageLongueurMax))
            }
        }
    }

    public let missionId: String
    private let controller: SessionController
    private let snapshot: SessionSnapshot

    public init(missionId: String, controller: SessionController, snapshot: SessionSnapshot) {
        self.missionId = missionId
        self.controller = controller
        self.snapshot = snapshot
        self.profil = snapshot.context.profile
    }

    /// État du bloc pour la mission relue ; `nil` tant que la candidature n'a pas été relue une première fois.
    public func etat(_ mission: Mission) -> CandidatureEcran? {
        guard let maintenant else { return nil }
        return CandidatureEcran.etat(mission: mission, candidature: candidature, profil: profil,
                                     userId: snapshot.context.userId, maintenant: maintenant)
    }

    /// Relit la dernière candidature du soignant sur la mission et le profil (soft-gate). Une lecture du profil en
    /// échec garde le profil de la session ; une lecture de candidature en échec garde la précédente.
    public func charger() async {
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let id = missionId
        let context = snapshot.context
        let candidaturePort = gateways.candidature
        let missionsPort = gateways.missions
        let delai = controller.resolutionTimeout
        // `nil` relu (aucune candidature) et lecture en échec se distinguent : seule la seconde garde la précédente.
        var lue: CandidatureRecord?
        var candidatureRelue = false
        do {
            lue = try await bounded(timeout: delai) { try await candidaturePort.candidature(missionId: id, context: context) }
            candidatureRelue = true
        } catch {}
        let profilLu = try? await bounded(timeout: delai) { try await missionsPort.profile(userId: context.userId) }
        guard await controller.epoch == snapshot.epoch else { return }
        if candidatureRelue { candidature = lue }
        if let profilLu { profil = profilLu }
        maintenant = gateways.clock.now()
    }

    /// POSTULER ou ACCEPTER (selon `mode_attribution`) avec le planning exact affiché, éventuellement rejoué avec
    /// l'option de contrat choisie. Rend `true` quand l'écran doit relire la mission.
    public func confirmer(_ mission: Mission, choixContrat: String? = nil) async -> Bool {
        let action = CandidatureRules.action(pour: mission.record)
        return await envoyer(action, mission: mission, choixContrat: choixContrat, candidatureId: nil)
    }

    /// Acceptation native d'une proposition libérale (`.proposition`) : le contrat relu par l'écran
    /// (`CandidatureRules.contratProposition`) est déclaré à la gateway, qui le revérifie et verrouille tout autre
    /// contrat (`CandidatureVerrou.renvoiWeb`, attestation hebdomadaire non portée).
    public func accepterProposition(_ mission: Mission) async -> Bool {
        guard case let .proposition(id)? = etat(mission), let candidature, candidature.id == id else { return false }
        let contrat = CandidatureRules.contratProposition(typeContratChoisi: candidature.typeContratChoisi,
                                                          typeContratRecherche: mission.record.typeContratRecherche)
        return await envoyer(.proposition, mission: mission, choixContrat: contrat, candidatureId: id)
    }

    /// Refus d'une proposition (`fn_repondre_proposition(p_accepter := false)`, relu `REFUSEE` par la gateway).
    public func refuserProposition(_ mission: Mission) async -> Bool {
        guard !enCours, let etat = etat(mission) else { return false }
        let id: String
        switch etat {
        case let .proposition(candidatureId), let .propositionWeb(candidatureId): id = candidatureId
        default: return false
        }
        // Revue B8 (m1) : `enCours` posé avant le premier `await`, un second toucher est ignoré.
        enCours = true
        defer { enCours = false }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return false }
        let port = gateways.candidature
        let context = snapshot.context
        issue = nil
        do {
            try await bounded(timeout: controller.resolutionTimeout) { try await port.refuserProposition(candidatureId: id, context: context) }
            guard await controller.epoch == snapshot.epoch else { return false }
            issue = .propositionRefusee
        } catch {
            guard await controller.epoch == snapshot.epoch, let message = Self.message(error) else { return false }
            issue = .erreur(message)
        }
        await charger()
        return true
    }

    public func effacerIssue() { issue = nil }

    // MARK: - Interne

    private func envoyer(_ action: ActionPlanning, mission: Mission, choixContrat: String?, candidatureId: String?) async -> Bool {
        guard !enCours else { return false }
        // Revue B8 (m1) : `enCours` posé avant le premier `await`, un second toucher est ignoré.
        enCours = true
        defer { enCours = false }
        guard let creneaux = CreneauxConfirmes.pourAction(PlanningCandidatInput(mission: mission)) else {
            let planning = PlanningCandidatRules.construirePlanningCandidat(PlanningCandidatInput(mission: mission))
            issue = .erreur(planning.messageBlocage ?? PlanningCandidatRules.messagePlanningIncomplet)
            return false
        }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return false }
        let port = gateways.candidature
        let context = snapshot.context
        let texte = action == .postuler && !message.isEmpty ? message : nil
        let id = mission.id
        issue = nil
        let relire: Bool
        do {
            let outcome = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.confirmer(action: action, missionId: id, creneaux: creneaux, message: texte,
                                         choixContrat: choixContrat, candidatureId: candidatureId, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return false }
            relire = traiter(outcome)
        } catch {
            guard await controller.epoch == snapshot.epoch else { return false }
            optionsContrat = []
            guard let message = Self.message(error) else { return false }
            issue = .erreur(message)
            relire = true
        }
        if relire { await charger() }
        return relire
    }

    /// Issue de `confirmer` : `true` si l'écran relit la mission (tout sauf le choix de contrat demandé).
    private func traiter(_ outcome: CandidatureOutcome) -> Bool {
        if case .choixRequis = outcome {} else { optionsContrat = [] }
        switch outcome {
        case .confirmed:
            message = ""
            return true
        case let .choixRequis(options):
            optionsContrat = options
            return false
        case let .refusee(_, texte, _):
            issue = .erreur(texte)
            return true
        case let .planningAReconfirmer(_, texte):
            issue = .planningAReconfirmer(texte)
            return true
        case let .missionDejaAttribuee(texte):
            // Course réelle : message serveur exact (« Cette mission n'est plus disponible. »…), mission relue.
            issue = .erreur(texte)
            return true
        }
    }

    /// Message affiché pour une erreur (`nil` : annulation, rien à montrer).
    private static func message(_ error: Error) -> String? {
        if let verrou = error as? CandidatureVerrou { return verrou.errorDescription }
        if let jolene = error as? JoleneError {
            return jolene.kind == .cancelled ? nil : jolene.message
        }
        if error is CancellationError { return nil }
        return MissionDetailModel.genericFailureMessage
    }
}
