import Foundation
import Combine

/// Bloquer / Débloquer un interlocuteur (lot 4, T7b ; exigence Apple 1.2), port de `src/components/BloquerUtilisateur.tsx`.
///
/// Règles :
/// - statut lu par `fn_est_bloque` à l'ouverture ; lecture en échec → « Statut de blocage indisponible. » et relecture
///   possible, jamais un statut supposé ;
/// - blocage en deux temps (confirmation), déblocage direct (l.83-94) ;
/// - succès annoncé seulement sur l'état **relu** par la gateway (`basculerBlocage` rend `fn_est_bloque`) ; état relu
///   contraire à la demande → « Action impossible pour le moment. » ;
/// - refus serveur (`{error}`) → message verbatim ; délai dépassé ou coupure → statut relu (l'action a pu aboutir), puis
///   « Action impossible pour le moment. Réessayez. », sans nouvel envoi ;
/// - réponse d'un epoch périmé ignorée.
@MainActor
public final class BlocageModel: ObservableObject {
    public enum Statut: Equatable, Sendable {
        case lecture
        case indisponible
        case lu(bloque: Bool)
    }

    @Published public private(set) var statut: Statut = .lecture
    @Published public private(set) var confirmation = false
    @Published public private(set) var enCours = false
    /// Message de la dernière action (succès ou échec) et sa nature.
    @Published public private(set) var message: String?
    @Published public private(set) var succes = false

    public let cibleId: String
    public let libelleCible: String
    private let controller: SessionController
    private let contexte: ContexteMessagerie

    public convenience init(controller: SessionController, snapshot: SessionSnapshot, cibleId: String, libelleCible: String) {
        self.init(controller: controller, contexte: ContexteMessagerie(snapshot), cibleId: cibleId, libelleCible: libelleCible)
    }

    /// Lot 5 (T11) : même blocage en contexte établissement.
    public init(controller: SessionController, contexte: ContexteMessagerie, cibleId: String, libelleCible: String) {
        self.controller = controller
        self.contexte = contexte
        self.cibleId = cibleId
        self.libelleCible = libelleCible
    }

    /// Libellé du bouton (`Bloquer` / `Débloquer`) ; `nil` tant que le statut n'est pas lu.
    public var libelleBouton: String? {
        guard case let .lu(bloque) = statut else { return nil }
        return bloque ? MessagerieTextes.Blocage.debloquer : MessagerieTextes.Blocage.bloquer
    }

    public func lire() async {
        statut = .lecture
        confirmation = false
        guard let gateways = await controller.gateways(for: contexte.epoch) else { return }
        let port = gateways.messagerie
        let contexte = self.contexte
        let cible = cibleId
        do {
            let bloque = try await bounded(timeout: controller.resolutionTimeout) { try await port.bloque(cibleId: cible, contexte: contexte) }
            guard await courant() else { return }
            statut = .lu(bloque: bloque)
        } catch {
            guard await courant(), !(error is CancellationError) else { return }
            statut = .indisponible
        }
    }

    /// Bouton : déblocage immédiat, blocage après confirmation.
    public func demander() async {
        guard case let .lu(bloque) = statut, !enCours else { return }
        message = nil
        if bloque { await basculer(bloquer: false) } else { confirmation = true }
    }

    public func confirmer() async {
        guard confirmation, !enCours else { return }
        await basculer(bloquer: true)
    }

    public func annuler() { confirmation = false }

    private func basculer(bloquer: Bool) async {
        guard let gateways = await controller.gateways(for: contexte.epoch) else { return }
        enCours = true
        defer { enCours = false }
        let port = gateways.messagerie
        let contexte = self.contexte
        let cible = cibleId
        do {
            let relu = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.basculerBlocage(cibleId: cible, bloquer: bloquer, contexte: contexte)
            }
            guard await courant() else { return }
            statut = .lu(bloque: relu)
            confirmation = false
            if relu == bloquer {
                annoncer(MessagerieTextes.Blocage.succes(cible: libelleCible, bloque: relu), succes: true)
            } else {
                annoncer(MessagerieTextes.Blocage.echec, succes: false)
            }
        } catch {
            guard await courant(), !(error is CancellationError) else { return }
            if let jolene = error as? JoleneError {
                switch jolene.kind {
                case .cancelled: return
                case .unknown, .unauthorized:
                    annoncer(jolene.message, succes: false) // refus serveur verbatim (`data.error`)
                    return
                case .contract, .environment, .demoOnly, .invalidCredentials:
                    annoncer(MessagerieTextes.Blocage.echec, succes: false)
                    return
                case .network:
                    break
                }
            }
            // Issue inconnue : le statut est relu, rien n'est renvoyé.
            await lire()
            annoncer(MessagerieTextes.Blocage.echecReessayer, succes: false)
        }
    }

    private func annoncer(_ texte: String, succes: Bool) {
        message = texte
        self.succes = succes
    }

    private func courant() async -> Bool { await controller.epoch == contexte.epoch }
}

/// Signaler un interlocuteur à Jolene (lot 4, T7b ; exigence Apple 1.2), port de `src/components/SignalerUtilisateur.tsx` :
/// catégorie parmi la liste fermée du web, motif obligatoire d'au moins 10 caractères (espaces de bord retirés), envoi
/// par `fn_signaler_utilisateur`, succès annoncé seulement sur `{success:true}`. Un refus garde la saisie.
@MainActor
public final class SignalementModel: ObservableObject {
    @Published public var categorie = MessagerieTextes.Signalement.categorieParDefaut
    @Published public var motif = ""
    @Published public private(set) var enCours = false
    @Published public private(set) var erreur: String?
    /// Vrai après un signalement accepté par le serveur : la feuille se referme et l'écran annonce le succès.
    @Published public private(set) var transmis = false

    public let cible: ModerationConversation.CibleSignalement
    private let controller: SessionController
    private let contexte: ContexteMessagerie

    public convenience init(controller: SessionController, snapshot: SessionSnapshot, cible: ModerationConversation.CibleSignalement) {
        self.init(controller: controller, contexte: ContexteMessagerie(snapshot), cible: cible)
    }

    /// Lot 5 (T11) : même signalement en contexte établissement.
    public init(controller: SessionController, contexte: ContexteMessagerie, cible: ModerationConversation.CibleSignalement) {
        self.controller = controller
        self.contexte = contexte
        self.cible = cible
    }

    /// Bouton d'envoi actif (`disabled={saving || motif.trim().length < 10}`, l.90).
    public var envoiPossible: Bool {
        !enCours && motif.trimmingCharacters(in: .whitespacesAndNewlines).count >= SignalementUtilisateur.longueurMotifMin
    }

    @discardableResult
    public func envoyer() async -> Bool {
        guard !enCours else { return false }
        erreur = nil
        let texte = motif.trimmingCharacters(in: .whitespacesAndNewlines)
        guard texte.count >= SignalementUtilisateur.longueurMotifMin else {
            erreur = MessagerieTextes.Signalement.motifTropCourt
            return false
        }
        guard let gateways = await controller.gateways(for: contexte.epoch) else { return false }
        enCours = true
        defer { enCours = false }
        let port = gateways.messagerie
        let contexte = self.contexte
        let cible = self.cible
        let categorie = self.categorie
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.signaler(cibleId: cible.cibleId, type: cible.type, categorie: categorie, motif: texte,
                                        missionId: cible.missionId, contexte: contexte)
            }
            guard await courant() else { return false }
            switch issue {
            case .signale:
                transmis = true
                motif = ""
                return true
            case let .refuse(message):
                erreur = message.isEmpty ? MessagerieTextes.Signalement.echec : message
                return false
            }
        } catch {
            guard await courant(), !(error is CancellationError) else { return false }
            if let jolene = error as? JoleneError {
                if jolene.kind == .cancelled { return false }
                if jolene.kind == .unknown || jolene.kind == .unauthorized {
                    erreur = jolene.message
                    return false
                }
            }
            erreur = MessagerieTextes.Signalement.echec
            return false
        }
    }

    private func courant() async -> Bool { await controller.epoch == contexte.epoch }
}

/// « Écrire à l'établissement » depuis le détail d'une mission (lot 4, T7b ; correction 20, D25) :
/// `fn_user_id_pour_etablissement` puis `fn_obtenir_conversation(p_autre_id, p_mission_id)`, puis ouverture du fil.
@MainActor
public final class ContactMissionModel: ObservableObject {
    /// Statuts où le fil de la mission est proposé (`DetailMissionSoignant.tsx` l.1550), au soignant assigné seulement.
    public static let statuts: Set<String> = ["ASSIGNEE", "EN_COURS", "TERMINEE", "ABSENCE", "LITIGE"]

    /// Bouton proposé : soignant assigné (`soignant_assigne_id === user.id`, l.633) et statut de la liste.
    public static func propose(_ mission: MissionRecord, userId: String) -> Bool {
        guard let assigne = mission.soignantAssigneId, !userId.isEmpty,
              assigne.caseInsensitiveCompare(userId) == .orderedSame else { return false }
        return statuts.contains(mission.statut) && !mission.etablissementId.isEmpty
    }

    @Published public private(set) var enCours = false
    @Published public private(set) var erreur: String?

    private let controller: SessionController
    private let snapshot: SessionSnapshot

    public init(controller: SessionController, snapshot: SessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
    }

    /// Identifiant de la conversation de la mission, `nil` en cas d'échec (message affiché, jamais « session expirée »
    /// pour un refus de relation).
    public func ouvrir(_ mission: MissionRecord) async -> String? {
        guard !enCours, let gateways = await controller.gateways(for: snapshot.epoch) else { return nil }
        enCours = true
        defer { enCours = false }
        erreur = nil
        let port = gateways.messagerie
        let context = snapshot.context
        let missionId = mission.id
        let etablissementId = mission.etablissementId
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.conversationPourMission(missionId: missionId, etablissementId: etablissementId, context: context)
            }
            guard await courant() else { return nil }
            switch issue {
            case let .conversation(id): return id
            case .indisponible: erreur = MessagerieTextes.ouvertureImpossible
            }
        } catch {
            guard await courant(), !(error is CancellationError) else { return nil }
            if let jolene = error as? JoleneError, jolene.kind == .cancelled { return nil }
            if let jolene = error as? JoleneError, jolene.kind == .unauthorized {
                erreur = jolene.message
            } else {
                erreur = MessagerieTextes.ouvertureImpossible
            }
        }
        return nil
    }

    private func courant() async -> Bool { await controller.epoch == snapshot.epoch }
}
