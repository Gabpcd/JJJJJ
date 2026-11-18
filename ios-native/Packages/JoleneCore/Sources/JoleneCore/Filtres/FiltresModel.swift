import Foundation
import Combine

/// État de la liste des recherches : en attente de la première réponse, relue, ou en échec (message affiché).
public enum ListeRecherches: Equatable, Sendable {
    case chargement
    case prete([FiltreSauvegarde])
    case echec(String)

    public var recherches: [FiltreSauvegarde] {
        if case let .prete(recherches) = self { return recherches }
        return []
    }

    public var estPrete: Bool {
        if case .prete = self { return true }
        return false
    }
}

/// Modèle de « Mes recherches sauvegardées » (L4-T4), port de `PageRecherchesSauvegardees.tsx` (rôle SOIGNANT,
/// alertes toujours disponibles : `useCapaciteAlertesRecherches` ne vérifie que l'audience établissement).
///
/// Règles (mêmes que `FavorisModel`, lot 1 T4b) :
/// - lectures et mutations bornées à `SessionController.resolutionTimeout` (décision 14 du lot 1), gateways de l'epoch
///   de l'écran, réponse d'un epoch périmé ignorée, deux lectures qui se chevauchent : seule la dernière publie ;
/// - une mutation n'est annoncée qu'après une relecture qui la confirme (PRINCIPES §3) : le port rend la liste relue
///   (`IssueFiltre.relue`) ; une relecture qui ne montre pas la modification est un échec (`nonConfirmee`) ;
/// - refus serveur (`IssueFiltre.refusee`) affiché verbatim ; erreur de transport : message puis relecture (le
///   serveur a pu agir), jamais de renvoi ; session expirée signalée, sans relecture ;
/// - une recherche en cours d'action n'accepte pas de second appui ;
/// - une annulation (vue qui disparaît) n'est jamais une erreur.
@MainActor
public final class FiltresModel: ObservableObject {
    @Published public private(set) var liste: ListeRecherches = .chargement
    /// Dernière erreur d'action ou de relecture sur une liste affichée ; `nil` après un succès confirmé.
    @Published public private(set) var erreur: String?
    /// Dernier succès confirmé par relecture (« Recherche supprimée », « Alerte activée »…).
    @Published public private(set) var confirmation: String?
    /// Jeton d'annonce VoiceOver (`InlineNotice.announcementID`) : change à chaque message.
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

    /// « Vérifier ma session » : revalide la session, puis relit si elle est toujours prête pour cet epoch.
    public func verifierSession(_ session: SessionStore) async {
        await session.start()
        guard session.state.snapshot?.epoch == snapshot.epoch else { return }
        await charger()
    }

    // MARK: - Lecture

    /// À chaque apparition et « Réessayer » (le web relit au montage et après chaque mutation).
    public func charger() async {
        erreur = nil
        await lire(explicite: true)
    }

    // MARK: - Mutations

    /// Cloche de la ligne (l.98-108) : `p_alerte_active` seul, comme le web ; nom et fréquence restent ceux du serveur
    /// (un renommage fait ailleurs entre-temps n'est jamais écrasé).
    public func basculerAlerte(_ recherche: FiltreSauvegarde) async {
        let cible = !recherche.alerteActive
        _ = await muter(recherche.id, succes: cible ? FiltresTextes.alerteActivee : FiltresTextes.alerteDesactivee,
                        repli: FiltresTextes.erreurMiseAJour,
                        confirme: { liste in liste.first { $0.id == recherche.id }?.alerteActive == cible }) { port, context in
            try await port.modifier(id: recherche.id, nom: nil, alerte: cible, frequence: nil, context: context)
        }
    }

    /// « Enregistrer » de la feuille « Modifier la recherche » (l.263-280) : nom sans espaces de bord, alerte et
    /// fréquence ; `true` si la relecture confirme (la feuille se referme), sinon le message reste affiché.
    @discardableResult
    public func enregistrer(_ recherche: FiltreSauvegarde, nom saisie: String, alerte: Bool,
                            frequence: FrequenceAlerte) async -> Bool {
        guard let nom = FiltresSauvegardesEncodage.nomSaisi(saisie) else {
            signaler(FiltresTextes.nomRequis)
            return false
        }
        return await muter(recherche.id, succes: FiltresTextes.miseAJour, repli: FiltresTextes.erreurMiseAJour,
                           confirme: { liste in
                               guard let ligne = liste.first(where: { $0.id == recherche.id }) else { return false }
                               return ligne.nom == nom && ligne.alerteActive == alerte && ligne.frequence == frequence
                           }) { port, context in
            try await port.modifier(id: recherche.id, nom: nom, alerte: alerte, frequence: frequence, context: context)
        }
    }

    /// Suppression après confirmation (l.86-96) ; `true` si la relecture ne montre plus la recherche.
    @discardableResult
    public func supprimer(_ recherche: FiltreSauvegarde) async -> Bool {
        await muter(recherche.id, succes: FiltresTextes.supprimee, repli: FiltresTextes.erreurSuppression,
                    confirme: { liste in !liste.contains { $0.id == recherche.id } }) { port, context in
            try await port.supprimer(id: recherche.id, context: context)
        }
    }

    // MARK: - Interne

    private func muter(_ id: String, succes: String, repli: String, confirme: @escaping ([FiltreSauvegarde]) -> Bool,
                       _ appel: @escaping @Sendable (FiltresSauvegardesPort, MissionReadContext) async throws -> IssueFiltre)
        async -> Bool {
        guard !id.isEmpty, !enCours.contains(id) else { return false }
        enCours.insert(id)
        defer { enCours.remove(id) }
        effacerMessages()
        revision += 1
        let revisionMutation = revision
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return false }
        let port = gateways.filtres
        let context = snapshot.context
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) { try await appel(port, context) }
            guard await controller.epoch == snapshot.epoch else { return false }
            sessionExpiree = false
            switch issue {
            case let .refusee(message):
                signaler(message.isEmpty ? repli : message)
                return false
            case let .relue(lignes):
                if revisionMutation == revision { liste = .prete(lignes) }
                guard confirme(lignes) else {
                    signaler(FiltresTextes.nonConfirmee)
                    return false
                }
                confirmation = succes
                jeton += 1
                return true
            }
        } catch {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: repli) else { return false }
            sessionExpiree = issue.sessionExpiree
            signaler(issue.message)
            // Le serveur a pu agir (délai, coupure) : relecture, jamais de renvoi.
            if !issue.sessionExpiree { await lire(explicite: false) }
            return false
        }
    }

    /// `explicite` : lecture demandée (son échec sur une liste affichée est signalé) ; sinon relecture de
    /// réconciliation après une mutation (son échec n'écrase pas le message de l'action).
    private func lire(explicite: Bool) async {
        revision += 1
        let revisionLecture = revision
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.filtres
        let context = snapshot.context
        do {
            let lignes = try await bounded(timeout: controller.resolutionTimeout) { try await port.lister(context: context) }
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision else { return }
            liste = .prete(lignes)
            sessionExpiree = false
        } catch {
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: FiltresTextes.chargementImpossible) else { return }
            if issue.sessionExpiree { sessionExpiree = true }
            if liste.estPrete {
                if explicite { signaler(issue.message) }
            } else {
                liste = .echec(issue.sessionExpiree ? issue.message : FiltresTextes.echecListe)
            }
        }
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
