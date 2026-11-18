import Foundation

/// Annulation d'une participation depuis le détail d'une mission (lot 1, T7, `docs/mobile-swift/LOT1_PLAN.md` §3 T7),
/// port de `DetailMissionSoignant.tsx` l.891-917 et l.1516-1661 et de `ModaleAnnulationCandidature.tsx`.
///
/// - `charger(_:)` : bouton seulement pour une mission `ASSIGNEE` au soignant ; candidature relue côté serveur
///   (`CandidaturePort.candidature`) : `ACCEPTEE` → modale de candidature (`fn_annuler_candidature_soignant`), sinon
///   confirmation simple (`fn_annuler_mission_soignant`), comme le web.
/// - Justificatif optionnel (PDF, JPEG, PNG, WebP, 5 Mo, préparé par `FichierDocument.preparer` du lot 2) : reçu
///   `RecuJustificatif` journalisé AVANT le dépôt (`prepared` → `started`), puis `stored`, et `rattache` ou
///   `non_rattache` selon l'annulation. Un dépôt incertain est réconcilié par HEAD (`existe`), jamais redéposé ; un reçu
///   `stored` de la même candidature est repris par l'essai suivant (pas de doublon à la reprise). Journal illisible :
///   annulation avec justificatif bloquée, renvoi web du détail de la mission (consigne « Lot 1 T7 » de
///   `DECISIONS_LOT2.md`).
/// - Une annulation n'est annoncée qu'après la relecture de la gateway (PRINCIPES §3), avec les conséquences rendues par
///   le serveur (`TextesWeb.Annulation`) ; aucun barème côté client, aucun renvoi automatique.
@MainActor
public final class AnnulationModel: ObservableObject {
    public enum Issue: Equatable, Sendable {
        case annulee(message: String)
        case erreur(message: String)
        case sessionExpiree(message: String)
        /// Journal des reçus illisible : l'annulation avec justificatif passe par le web.
        case bloquee(message: String)
    }

    @Published public private(set) var entree: AnnulationRules.Entree?
    @Published public private(set) var chargement = false
    @Published public private(set) var erreurChargement: String?
    @Published public private(set) var envoiEnCours = false
    @Published public private(set) var issue: Issue?
    /// Nom du justificatif déjà déposé pour cette candidature (reçu `stored`), repris tel quel par la confirmation.
    @Published public private(set) var justificatifDejaDepose: String?

    public let missionId: String
    private let controller: SessionController
    private let snapshot: SessionSnapshot
    /// Magasin des reçus durables (`Appareil.recus`) ; nil : aucun justificatif ne peut être envoyé depuis cet écran.
    public var recus: (any ReceiptStorePort)?

    public init(missionId: String, controller: SessionController, snapshot: SessionSnapshot, recus: (any ReceiptStorePort)? = nil) {
        self.missionId = missionId
        self.controller = controller
        self.snapshot = snapshot
        self.recus = recus
    }

    /// Délai d'un dépôt : au moins celui des transferts de justificatifs du lot 2.
    private var delaiTransfert: TimeInterval { max(controller.resolutionTimeout, DocumentsModel.delaiTransfertMinimum) }

    // MARK: - Chargement

    /// Détermine le parcours de cette mission (aucun pour une mission non assignée au soignant).
    public func charger(_ mission: Mission) async {
        // Une annulation relue n'est jamais « défaite » par un rechargement de l'écran (détail relu ou rouvert).
        if case .annulee = issue { return }
        guard AnnulationRules.annulable(mission.record, userId: snapshot.context.userId) else {
            entree = nil
            return
        }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.candidature
        let id = mission.id
        let context = snapshot.context
        chargement = true
        defer { chargement = false }
        do {
            let candidature = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.candidature(missionId: id, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return }
            entree = AnnulationRules.entree(mission: mission.record, userId: context.userId, candidature: candidature)
            erreurChargement = nil
        } catch {
            guard await controller.epoch == snapshot.epoch, !Self.estAnnulation(error) else { return }
            if let jolene = error as? JoleneError, jolene.kind == .unauthorized {
                issue = .sessionExpiree(message: jolene.message)
            } else {
                erreurChargement = LibellesAnnulation.chargementImpossible
            }
        }
    }

    /// Reprise à l'ouverture de la modale : tout essai en vol est réconcilié (HEAD), un justificatif déjà déposé pour
    /// cette candidature est annoncé et sera repris, celui d'une autre candidature est abandonné.
    public func preparerJustificatif(candidatureId: String) async {
        guard let recus, let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let journal = ReceiptJournal<RecuJustificatif>(store: recus)
        do {
            let repris = try await reprendre(journal: journal, candidatureId: candidatureId, gateways: gateways)
            justificatifDejaDepose = repris?.nomFichier
        } catch {
            publierEchecJustificatif(error)
        }
    }

    // MARK: - Annulation de la candidature

    /// `fn_annuler_candidature_soignant` avec le justificatif choisi (ou celui déjà déposé), après les contrôles du web.
    public func annulerCandidature(id: String, motif: AnnulationRules.Motif?, texte: String, accepte: Bool,
                                   fichier: FichierPret?) async {
        if let manque = AnnulationRules.manque(motif: motif, texte: texte, accepte: accepte) {
            issue = .erreur(message: manque)
            return
        }
        guard let motif, !envoiEnCours else { return }
        // Journal illisible (revue B8 de #1156, m7) : aucune annulation depuis la modale, la voie est le web.
        if case .bloquee = issue { return }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        envoiEnCours = true
        defer { envoiEnCours = false }
        issue = nil
        let context = snapshot.context

        var recu: RecuJustificatif?
        var journal: ReceiptJournal<RecuJustificatif>?
        if fichier != nil || justificatifDejaDepose != nil {
            guard let recus else {
                issue = .erreur(message: LibellesAnnulation.indisponibleSurCetEcran)
                return
            }
            let leJournal = ReceiptJournal<RecuJustificatif>(store: recus)
            journal = leJournal
            do {
                recu = try await reprendre(journal: leJournal, candidatureId: id, gateways: gateways)
                if recu == nil, let fichier {
                    guard let depose = try await deposer(fichier, candidatureId: id, journal: leJournal, gateways: gateways) else { return }
                    recu = depose
                }
            } catch {
                publierEchecJustificatif(error)
                return
            }
            justificatifDejaDepose = recu?.nomFichier
        }

        let port = gateways.candidature
        let texteEnvoye = AnnulationRules.texteNettoye(texte)
        let chemin = recu?.chemin
        do {
            var outcome = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.annulerCandidature(id: id, motif: motif.rawValue, texte: texteEnvoye, justificatifPath: chemin,
                                                  context: context)
            }
            // Revue B8 de #1156, m2 : après une réponse perdue, le nouvel essai rend `STATUT_INVALIDE` si le serveur avait
            // déjà annulé. La candidature est relue avant tout message : `ANNULEE` relue = annulation relue (conséquences
            // inconnues de l'app, donc « Candidature annulée. »), sinon le refus du serveur s'affiche tel quel.
            if case let .refusee(code, _) = outcome, code == AnnulationRules.codeStatutInvalide {
                let missionId = self.missionId
                let relue = try await bounded(timeout: controller.resolutionTimeout) {
                    try await port.candidature(missionId: missionId, context: context)
                }
                if AnnulationRules.candidatureAnnuleeRelue(relue, id: id) { outcome = .annulee(points: nil, libre: nil, contestable: nil) }
            }
            guard await controller.epoch == snapshot.epoch else { return }
            switch outcome {
            case let .annulee(points, _, _):
                if let recu, let journal { await terminer(try? recu.rattacher(), journal: journal) }
                justificatifDejaDepose = nil
                entree = nil
                issue = .annulee(message: TextesWeb.Annulation.succesCandidature(points: points))
            case let .refusee(_, message):
                if let recu, let journal { await terminer(try? recu.abandonner(), journal: journal) }
                justificatifDejaDepose = nil
                issue = .erreur(message: message)
            }
        } catch {
            // Réponse perdue ou relecture non concordante : le reçu reste `stored` et sera repris tel quel ; rien
            // n'est renvoyé automatiquement (un délai ne prouve pas que le serveur n'a pas agi).
            guard await controller.epoch == snapshot.epoch else { return }
            publierEchec(error)
        }
    }

    // MARK: - Annulation de la mission (sans candidature)

    /// `fn_annuler_mission_soignant` (web l.891-917), sans motif, comme le web.
    public func annulerMission() async {
        guard !envoiEnCours, let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        envoiEnCours = true
        defer { envoiEnCours = false }
        issue = nil
        let port = gateways.candidature
        let id = missionId
        let context = snapshot.context
        do {
            var outcome = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.annulerMission(id: id, motif: nil, context: context)
            }
            // Revue B8 delta de #1156 (m1), intégration de la vague B : après une réponse perdue, le nouvel essai est
            // refusé (« Annulation impossible dans cet état… », la mission n'étant plus attribuée). Comme pour
            // `STATUT_INVALIDE` côté candidature, la mission est relue avant tout message : relue sans le soignant de la
            // session (`soignant_assigne_id` nul ou autre, ligne lue) = annulation relue ; sinon le refus s'affiche tel quel.
            if case .refusee = outcome {
                let missions = gateways.missions
                // Revue B8 de #1158 (m4) : une relecture en échec ne masque pas le refus du serveur, affiché tel quel.
                let relue = try? await bounded(timeout: controller.resolutionTimeout) {
                    try await missions.mission(id: id, context: context)
                }
                if let relue, AnnulationRules.missionAnnuleeRelue(soignantAssigneId: relue.record.soignantAssigneId,
                                                                   userId: context.userId, ligneLue: true) {
                    outcome = .annulee(points: nil, libre: nil, contestable: nil)
                }
            }
            guard await controller.epoch == snapshot.epoch else { return }
            switch outcome {
            case .annulee:
                entree = nil
                issue = .annulee(message: TextesWeb.Annulation.participationAnnulee)
            case let .refusee(_, message):
                issue = .erreur(message: message)
            }
        } catch {
            guard await controller.epoch == snapshot.epoch else { return }
            publierEchec(error)
        }
    }

    /// Efface une erreur affichée (nouvelle saisie, modale refermée) ; une annulation relue et un journal illisible restent.
    public func effacerIssue() {
        switch issue {
        case .erreur, .sessionExpiree: issue = nil
        case .annulee, .bloquee, .none: return
        }
    }

    // MARK: - Reçus

    /// Réconcilie le reçu en vol du soignant, puis rend le reçu `stored` de cette candidature à reprendre (nil sinon).
    private func reprendre(journal: ReceiptJournal<RecuJustificatif>, candidatureId: String,
                           gateways: Gateways) async throws -> RecuJustificatif? {
        guard var recu = try await journal.lire(userId: snapshot.context.userId) else { return nil }
        switch recu.phase {
        case .prepared:
            // Journalisé avant toute requête : rien n'est parti.
            recu = try recu.marquerNonEnvoye()
            try await journal.ecrire(recu)
        case .started:
            let port = gateways.justificatifs
            let chemin = recu.chemin
            let context = snapshot.context
            let present = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.existe(chemin: chemin, context: context)
            }
            recu = present ? try recu.stocker() : try recu.marquerNonEnvoye()
            try await journal.ecrire(recu)
        case .stored, .rattache, .nonRattache, .notSent:
            break
        }
        guard recu.phase == .stored else { return nil }
        if recu.candidatureId == candidatureId { return recu }
        // Justificatif d'une autre candidature, jamais rattaché : l'objet reste (comme le web), l'essai est clos.
        try await journal.ecrire(try recu.abandonner())
        return nil
    }

    /// Dépôt d'un nouveau justificatif sous le chemin du reçu ; nil (issue publiée) si rien n'est déposé.
    private func deposer(_ fichier: FichierPret, candidatureId: String, journal: ReceiptJournal<RecuJustificatif>,
                         gateways: Gateways) async throws -> RecuJustificatif? {
        let context = snapshot.context
        let horodatage = Int64((gateways.clock.now().timeIntervalSince1970 * 1_000).rounded(.down))
        var recu = try RecuJustificatif.preparer(userId: context.userId, candidatureId: candidatureId,
                                                 fichier: fichier.fichier, horodatageMs: horodatage)
        try await journal.ecrire(recu)
        recu = try recu.demarrer()
        try await journal.ecrire(recu)

        let port = gateways.justificatifs
        let chemin = recu.chemin
        let octets = fichier.octets
        let mime = fichier.fichier.mime
        var depot: IssueDepotJustificatif
        do {
            depot = try await bounded(timeout: delaiTransfert) {
                try await port.deposer(chemin: chemin, octets: octets, mime: mime, context: context)
            }
        } catch let erreur as JoleneError where erreur.kind == .unauthorized {
            throw erreur
        } catch {
            if Self.estAnnulation(error) { throw error }
            depot = .incertain
        }
        if depot == .incertain {
            // Une seule relecture immédiate ; en échec, le reçu reste `started` et la prochaine tentative la refait.
            let present: Bool
            do {
                present = try await bounded(timeout: controller.resolutionTimeout) {
                    try await port.existe(chemin: chemin, context: context)
                }
            } catch let erreur as JoleneError where erreur.kind == .unauthorized {
                throw erreur
            } catch {
                if Self.estAnnulation(error) { throw error }
                issue = .erreur(message: LibellesAnnulation.depotIncertain)
                return nil
            }
            depot = present ? .depose : .nonEnvoye
        }
        switch depot {
        case .depose:
            recu = try recu.stocker()
            try await journal.ecrire(recu)
            return recu
        case .nonEnvoye, .refuse, .incertain:
            try await journal.ecrire(try recu.marquerNonEnvoye())
            issue = .erreur(message: LibellesAnnulation.depotImpossible)
            return nil
        }
    }

    /// Phase terminale journalisée puis reçu effacé, au mieux : l'annulation relue ne dépend pas du trousseau.
    private func terminer(_ recu: RecuJustificatif?, journal: ReceiptJournal<RecuJustificatif>) async {
        guard let recu else { return }
        do {
            try await journal.ecrire(recu)
            try await journal.effacer(recu)
        } catch {
            // Reçu terminal laissé en place : l'essai suivant le remplace (`ReceiptJournal`).
        }
    }

    // MARK: - Erreurs

    private func publierEchecJustificatif(_ error: any Error) {
        if let recu = error as? RecuErreur {
            switch recu {
            case .illisible, .utilisateurDifferent:
                issue = .bloquee(message: LibellesAnnulation.suiviIllisible)
            case .recuEnCours:
                issue = .erreur(message: LibellesAnnulation.recuEnCours)
            case .borneDepassee, .champInvalide, .transitionInterdite:
                issue = .erreur(message: LibellesAnnulation.depotImpossible)
            }
            return
        }
        if Self.estAnnulation(error) { return }
        if let jolene = error as? JoleneError, jolene.kind == .unauthorized {
            issue = .sessionExpiree(message: jolene.message)
            return
        }
        issue = .erreur(message: LibellesAnnulation.depotIncertain)
    }

    private func publierEchec(_ error: any Error) {
        if Self.estAnnulation(error) { return }
        if let jolene = error as? JoleneError {
            issue = jolene.kind == .unauthorized ? .sessionExpiree(message: jolene.message) : .erreur(message: jolene.message)
        } else {
            issue = .erreur(message: LibellesAnnulation.erreurAnnulation)
        }
    }

    private static func estAnnulation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? JoleneError)?.kind == .cancelled
    }
}
