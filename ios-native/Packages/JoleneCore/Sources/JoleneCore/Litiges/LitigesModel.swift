import Foundation
import Combine

/// État d'une liste relue du serveur : en attente de la première réponse, relue, ou en échec (message affiché).
public enum EtatLecture<Valeur: Equatable & Sendable>: Equatable, Sendable {
    case chargement
    case prete(Valeur)
    case echec(String)

    public var valeur: Valeur? {
        if case let .prete(valeur) = self { return valeur }
        return nil
    }

    public var estPrete: Bool { valeur != nil }
}

/// Formulaire « Ouvrir un nouveau litige » : fermé, missions en cours de lecture, ou ouvert sur les missions proposées.
public enum FormulaireLitige: Equatable, Sendable {
    case ferme
    case chargement
    case ouvert([MissionContestable])

    public var missions: [MissionContestable] {
        if case let .ouvert(missions) = self { return missions }
        return []
    }

    public var estOuvert: Bool {
        if case .ouvert = self { return true }
        return false
    }
}

/// Modèle de « Mes litiges » (lot 4, T8), port de `LitigesSoignantContent` (`src/pages/LitigesSoignant.tsx`).
///
/// - Liste dans l'ordre serveur (`cree_le` décroissant), filtrée par groupe de statut (`FiltreLitiges`, règle golden
///   `StatutLitige`) ; un litige déplié à la fois (l.52, l.244).
/// - Cible d'un lien (`?litige=` ou fragment `#<id>`, l.53-55, l.93-114) : dès que la liste relue la contient, le filtre
///   revient à « Tous » et le litige est déplié, une seule fois.
/// - Ouverture (l.130-182) : missions assignées `EN_COURS` / `TERMINEE` sans litige, motif d'au moins 10 caractères
///   (bouton désactivé en deçà, comme le web), type `AUTRE` par la signature à 3 arguments (gateway). Le refus du
///   serveur s'affiche mot pour mot dans la feuille restée ouverte ; le succès n'est annoncé qu'après une relecture
///   de la liste qui contient le litige (PRINCIPES §3), alors déplié.
/// - Mêmes règles que `FiltresModel` (T4) : appels bornés à `resolutionTimeout`, gateways de l'epoch de l'écran,
///   réponse d'un epoch périmé ignorée, seule la dernière lecture publie, erreur de transport suivie d'une relecture
///   (le serveur a pu agir) et jamais d'un renvoi, session expirée signalée, annulation jamais présentée en erreur.
@MainActor
public final class LitigesModel: ObservableObject {
    @Published public private(set) var liste: EtatLecture<[Litige]> = .chargement
    @Published public private(set) var filtre: FiltreLitiges = .tous
    /// Litige déplié (son fil est monté par l'écran), `nil` si aucun.
    @Published public private(set) var deplie: String?
    @Published public private(set) var erreur: String?
    @Published public private(set) var confirmation: String?
    /// Jeton d'annonce VoiceOver (`InlineNotice.announcementID`) : change à chaque message.
    @Published public private(set) var jeton = 0
    @Published public private(set) var sessionExpiree = false

    @Published public private(set) var formulaire: FormulaireLitige = .ferme
    @Published public private(set) var missionChoisie = ""
    @Published public private(set) var motif = ""
    @Published public private(set) var envoiEnCours = false
    /// Refus du serveur ou erreur de l'envoi, affiché dans la feuille.
    @Published public private(set) var erreurFormulaire: String?

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    /// Litige visé par le lien d'ouverture, consommé à la première liste qui le contient.
    private var cible: String?
    private var revision = 0

    public init(controller: SessionController, snapshot: SessionSnapshot, cible: String? = nil) {
        self.controller = controller
        self.snapshot = snapshot
        self.cible = cible.flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Lecture

    public var litiges: [Litige] { liste.valeur ?? [] }

    /// Litiges du filtre courant (l.116-119).
    public var litigesFiltres: [Litige] { litiges.filter { filtre.contient($0.statut) } }

    /// Filtres proposés et leur compte (l.201-210) : aucun sans litige.
    public var filtresVisibles: [CompteFiltreLitiges] { LitigesPresentation.filtres(litiges) }

    /// À chaque apparition, « Réessayer » et tirer-pour-rafraîchir (le web relit au montage et après chaque action).
    public func charger() async {
        erreur = nil
        await lire(explicite: true)
    }

    /// Relecture demandée par le fil après un message (`onUpdate` du web, `FilDiscussionLitige.tsx` l.75) : le statut
    /// du litige a pu changer ; son échec n'efface rien.
    public func relire() async {
        await lire(explicite: false)
    }

    public func choisir(_ nouveau: FiltreLitiges) {
        filtre = nouveau
    }

    /// Appui sur l'en-tête d'un litige (l.244) : déplie, ou replie s'il l'était.
    public func basculer(_ id: String) {
        deplie = deplie == id ? nil : id
    }

    public func effacerMessages() {
        erreur = nil
        confirmation = nil
    }

    /// « Vérifier ma session » : revalide la session, puis relit si elle est toujours prête pour cet epoch.
    public func verifierSession(_ session: SessionStore) async {
        await session.start()
        guard session.state.snapshot?.epoch == snapshot.epoch else { return }
        await charger()
    }

    // MARK: - Ouverture

    /// « Envoyer » : `disabled={creating || !selectedMissionId || newMotif.trim().length < 10}` (l.343).
    public var peutEnvoyer: Bool {
        formulaire.estOuvert && !envoiEnCours && !missionChoisie.isEmpty && LitigesPresentation.envoyable(motif)
    }

    /// « Ouvrir un litige » (l.130-160) : lit les missions proposées ; en échec, le message du web et aucune feuille.
    public func ouvrirFormulaire() async {
        guard formulaire == .ferme else { return }
        effacerMessages()
        formulaire = .chargement
        guard let gateways = await controller.gateways(for: snapshot.epoch) else {
            formulaire = .ferme
            return
        }
        let port = gateways.litiges
        let context = snapshot.context
        do {
            let missions = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.missionsContestables(context: context)
            }
            guard await controller.epoch == snapshot.epoch, formulaire == .chargement else { return }
            sessionExpiree = false
            missionChoisie = ""
            motif = ""
            erreurFormulaire = nil
            formulaire = .ouvert(missions)
        } catch {
            guard await controller.epoch == snapshot.epoch, formulaire == .chargement else { return }
            formulaire = .ferme
            guard !Task.isCancelled, let issue = Self.message(pour: error, repli: LitigesTextes.missionsIndisponibles) else { return }
            sessionExpiree = issue.sessionExpiree
            signaler(issue.sessionExpiree ? issue.message : LitigesTextes.missionsIndisponibles)
        }
    }

    /// « Annuler » ou feuille refermée : la saisie est effacée (le web la vide à la réouverture, l.154-155).
    public func fermerFormulaire() {
        guard !envoiEnCours else { return }
        formulaire = .ferme
        missionChoisie = ""
        motif = ""
        erreurFormulaire = nil
    }

    public func choisirMission(_ id: String) {
        guard !envoiEnCours, formulaire.missions.contains(where: { $0.id == id }) else { return }
        missionChoisie = id
    }

    public func saisirMotif(_ texte: String) {
        guard !envoiEnCours else { return }
        motif = LitigesPresentation.borner(texte)
    }

    /// « ⚠️ Ouvrir le litige » (l.162-182) ; `true` si le litige ouvert est relu dans la liste (la feuille se referme).
    @discardableResult
    public func envoyer() async -> Bool {
        guard peutEnvoyer else { return false }
        let mission = missionChoisie
        let texte = LitigesPresentation.nettoyer(motif)
        let avant = Set(litiges.map(\.id))
        envoiEnCours = true
        erreurFormulaire = nil
        defer { envoiEnCours = false }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return false }
        let port = gateways.litiges
        let context = snapshot.context
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.ouvrir(missionId: mission, motif: texte, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return false }
            sessionExpiree = false
            switch issue {
            case let .refuse(message):
                // Refus du serveur, mot pour mot ; repli du web si le message est vide.
                erreurFormulaire = message.isEmpty ? LitigesTextes.erreurOuverture : message
                return false
            case let .ouvert(id, _):
                await lire(explicite: false)
                guard await controller.epoch == snapshot.epoch else { return false }
                guard litiges.contains(where: { $0.id == id }) else {
                    erreurFormulaire = LitigesTextes.nonConfirme
                    return false
                }
                confirmerOuverture(id)
                return true
            }
        } catch {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: LitigesTextes.erreurOuverture) else { return false }
            sessionExpiree = issue.sessionExpiree
            erreurFormulaire = issue.message
            guard !issue.sessionExpiree else { return false }
            // Le serveur a pu ouvrir le litige (délai, réponse perdue) : relecture, jamais de renvoi. Un litige nouveau
            // sur cette mission fait foi ; sinon la feuille reste ouverte avec l'erreur.
            await lire(explicite: false)
            guard await controller.epoch == snapshot.epoch,
                  let recu = litiges.first(where: { $0.missionId == mission && !avant.contains($0.id) }) else { return false }
            confirmerOuverture(recu.id)
            return true
        }
    }

    /// Litige relu dans la liste : feuille refermée, filtre « Tous », litige déplié (son fil), succès du web annoncé.
    private func confirmerOuverture(_ id: String) {
        formulaire = .ferme
        missionChoisie = ""
        motif = ""
        erreurFormulaire = nil
        filtre = .tous
        deplie = id
        erreur = nil
        confirmation = LitigesTextes.litigeOuvert
        jeton += 1
    }

    // MARK: - Interne

    /// `explicite` : lecture demandée (son échec sur une liste affichée est signalé) ; sinon relecture de
    /// réconciliation (son échec n'écrase pas le message de l'action).
    private func lire(explicite: Bool) async {
        revision += 1
        let revisionLecture = revision
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.litiges
        let context = snapshot.context
        do {
            let lignes = try await bounded(timeout: controller.resolutionTimeout) { try await port.lister(context: context) }
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision else { return }
            publier(lignes)
            sessionExpiree = false
        } catch {
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: LitigesTextes.chargementImpossible) else { return }
            if issue.sessionExpiree { sessionExpiree = true }
            let message = issue.sessionExpiree ? issue.message : LitigesTextes.chargementImpossible
            if liste.estPrete {
                if explicite { signaler(message) }
            } else {
                liste = .echec(message)
            }
        }
    }

    private func publier(_ lignes: [Litige]) {
        liste = .prete(lignes)
        // Cible du lien (l.93-114) : filtre « Tous », litige déplié, une seule fois.
        if let visee = cible, lignes.contains(where: { $0.id == visee }) {
            filtre = .tous
            deplie = visee
            cible = nil
        }
        // Un filtre devenu vide n'a plus de pastille : retour à « Tous ».
        if filtre != .tous, !lignes.contains(where: { filtre.contient($0.statut) }) { filtre = .tous }
        if let ouvert = deplie, !lignes.contains(where: { $0.id == ouvert }) { deplie = nil }
    }

    private func signaler(_ message: String) {
        confirmation = nil
        erreur = message
        jeton += 1
    }

    /// Message affiché pour une erreur, `nil` pour une annulation (jamais présentée comme une erreur).
    nonisolated static func message(pour error: Error, repli: String) -> (message: String, sessionExpiree: Bool)? {
        if error is CancellationError { return nil }
        if let jolene = error as? JoleneError {
            if jolene.kind == .cancelled { return nil }
            return (jolene.message, jolene.kind == .unauthorized)
        }
        return (repli, false)
    }
}
