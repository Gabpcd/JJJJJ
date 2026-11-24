import Foundation
import Combine

/// Fil de discussion d'un litige déplié (lot 4, T8), port de `FilDiscussionLitige.tsx` (l.39-76, l.149-206) sans les
/// accords amiables (renvoi web, D9) ni aucun texte de délai.
///
/// - Lecture de `messages_litige` dans l'ordre chronologique, à l'apparition et après chaque envoi.
/// - Message d'au moins 10 caractères après `trim` (bouton désactivé en deçà, comme le web), saisie bornée à 1 000.
///   Le serveur reste seul juge : son refus (« Ce litige est clôturé. », longueur, accès) s'affiche mot pour mot et
///   la saisie est conservée.
/// - Un envoi n'est confirmé que si le fil relu compte un message de plus de l'utilisateur au même contenu
///   (PRINCIPES §3) : la saisie est alors vidée. Après une erreur de transport, le fil est relu (le serveur a pu
///   agir) : un message retrouvé vaut confirmation, sinon l'erreur reste affichée — jamais de renvoi automatique.
@MainActor
public final class LitigeFilModel: ObservableObject {
    @Published public private(set) var fil: EtatLecture<[MessageLitige]> = .chargement
    @Published public private(set) var saisie = ""
    @Published public private(set) var envoiEnCours = false
    @Published public private(set) var erreur: String?
    /// Jeton d'annonce VoiceOver : change à chaque message d'erreur.
    @Published public private(set) var jeton = 0
    @Published public private(set) var sessionExpiree = false

    public let litigeId: String
    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private var revision = 0

    public init(litigeId: String, controller: SessionController, snapshot: SessionSnapshot) {
        self.litigeId = litigeId
        self.controller = controller
        self.snapshot = snapshot
    }

    public var messages: [MessageLitige] { fil.valeur ?? [] }

    /// Identifiant de l'utilisateur : ses messages sont signés « Vous ».
    public var userId: String { snapshot.context.userId }

    /// « Envoyer » : `disabled={sending || newMsg.trim().length < 10}` (l.201).
    public var peutEnvoyer: Bool { !envoiEnCours && LitigesPresentation.envoyable(saisie) }

    public func saisir(_ texte: String) {
        guard !envoiEnCours else { return }
        saisie = LitigesPresentation.borner(texte)
    }

    public func charger() async {
        await lire(explicite: true)
    }

    /// « Envoyer » (l.58-76) ; `true` si le fil relu confirme le message.
    @discardableResult
    public func envoyer() async -> Bool {
        guard peutEnvoyer else { return false }
        let contenu = LitigesPresentation.nettoyer(saisie)
        let avant = nombre(contenu, dans: messages)
        envoiEnCours = true
        erreur = nil
        defer { envoiEnCours = false }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return false }
        let port = gateways.litiges
        let context = snapshot.context
        let litige = litigeId
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.ajouterMessage(litigeId: litige, contenu: contenu, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return false }
            sessionExpiree = false
            switch issue {
            case let .refuse(message):
                signaler(message.isEmpty ? LitigesTextes.erreurEnvoi : message)
                return false
            case let .ajoute(relu):
                revision += 1
                fil = .prete(relu)
                guard nombre(contenu, dans: relu) > avant else {
                    signaler(LitigesTextes.messageNonConfirme)
                    return false
                }
                saisie = ""
                return true
            }
        } catch {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled,
                  let issue = LitigesModel.message(pour: error, repli: LitigesTextes.erreurEnvoi) else { return false }
            sessionExpiree = issue.sessionExpiree
            signaler(issue.message)
            guard !issue.sessionExpiree else { return false }
            await lire(explicite: false)
            guard await controller.epoch == snapshot.epoch, nombre(contenu, dans: messages) > avant else { return false }
            // Message retrouvé malgré la réponse perdue : la relecture fait foi.
            erreur = nil
            saisie = ""
            return true
        }
    }

    // MARK: - Interne

    /// Messages de l'utilisateur portant exactement ce contenu.
    private func nombre(_ contenu: String, dans messages: [MessageLitige]) -> Int {
        let moi = userId
        return messages.filter { $0.auteurId == moi && $0.contenu == contenu }.count
    }

    private func lire(explicite: Bool) async {
        revision += 1
        let revisionLecture = revision
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.litiges
        let context = snapshot.context
        let litige = litigeId
        do {
            let lus = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.fil(litigeId: litige, context: context)
            }
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision else { return }
            fil = .prete(lus)
            sessionExpiree = false
        } catch {
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision, !Task.isCancelled,
                  let issue = LitigesModel.message(pour: error, repli: LitigesTextes.filIndisponible) else { return }
            if issue.sessionExpiree { sessionExpiree = true }
            let message = issue.sessionExpiree ? issue.message : LitigesTextes.filIndisponible
            if fil.estPrete {
                if explicite { signaler(message) }
            } else {
                fil = .echec(message)
            }
        }
    }

    private func signaler(_ message: String) {
        erreur = message
        jeton += 1
    }
}
