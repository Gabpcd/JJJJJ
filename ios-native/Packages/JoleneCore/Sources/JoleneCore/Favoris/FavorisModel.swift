import Foundation
import Combine

/// État d'une liste de favoris : en attente de la première réponse, relue, ou en échec (message affiché).
public enum FavorisListe<Element: Equatable & Sendable>: Equatable, Sendable {
    case chargement
    case prete([Element])
    case echec(String)

    /// Éléments relus, vide tant que la liste n'est pas prête.
    public var elements: [Element] {
        if case let .prete(elements) = self { return elements }
        return []
    }

    public var estPrete: Bool {
        if case .prete = self { return true }
        return false
    }
}

/// Modèle des favoris (lot 1, T4b), port de `MesFavorisSoignant.tsx` et de `BoutonSauvegarderMission.tsx`.
/// Une seule instance par epoch, partagée par l'étoile des cartes Explorer, l'étoile du détail et l'écran
/// « Mes favoris » : l'étoile suit toujours la dernière relecture (État dérivé, une seule source).
///
/// Règles :
/// - lectures et mutations bornées à `SessionController.resolutionTimeout` (décision 14) ; gateways
///   obtenues pour l'epoch de la session, réponse d'un epoch périmé ignorée ;
/// - les deux listes sont lues en parallèle (web : `Promise.all`) et échouent séparément ; Explorer ne lit
///   que les missions sauvegardées (`chargerMissionsSiNecessaire`) ;
/// - une mutation n'est annoncée qu'après une relecture qui la confirme (PRINCIPES §3) : le port rend la
///   liste relue, l'étoile et les listes en dérivent ; une relecture qui ne confirme pas est une erreur ;
/// - délai dépassé, coupure ou refus serveur sur une mutation : message affiché puis relecture, jamais de
///   renvoi automatique ; session expirée : signalée, sans relecture (revalider la session) ;
/// - un second appui sur la même étoile (ou le même retrait) pendant l'appel est ignoré ;
/// - deux lectures qui se chevauchent : seule la dernière demandée publie ;
/// - une annulation (vue qui disparaît) n'est jamais une erreur ;
/// - établissements : retrait seulement (`actif = false`, décision 8).
@MainActor
public final class FavorisModel: ObservableObject {
    public static let echecLectureMissions = "Vos missions sauvegardées n'ont pas pu être chargées. Vérifiez votre connexion puis réessayez."
    public static let echecLectureEtablissements = "Vos établissements favoris n'ont pas pu être chargés. Vérifiez votre connexion puis réessayez."
    public static let echecMutation = "L'action n'a pas pu être confirmée. Vérifiez votre connexion puis réessayez."
    public static let sauvegardeNonConfirmee = "La sauvegarde de la mission n'a pas pu être confirmée. Réessayez."
    public static let retraitNonConfirme = "Le retrait n'a pas pu être confirmé. Réessayez."

    /// Toutes les lignes `missions_sauvegardees` relues (état des étoiles).
    @Published public private(set) var missions: FavorisListe<MissionSauvegardee> = .chargement
    /// Missions listées dans « Mes favoris » (`FavorisRegles.missionsAffichees`, horloge des gateways).
    @Published public private(set) var missionsAffichees: [MissionSauvegardee] = []
    @Published public private(set) var etablissements: FavorisListe<EtablissementFavori> = .chargement
    /// Dernière erreur d'action ou de relecture d'une liste déjà affichée ; `nil` après un succès confirmé.
    @Published public private(set) var erreurAction: String?
    /// Nombre d'erreurs signalées : jeton d'annonce VoiceOver (`InlineNotice.announcementID`).
    @Published public private(set) var tentatives = 0
    @Published public private(set) var sessionExpired = false
    @Published public private(set) var missionsEnCours: Set<String> = []
    @Published public private(set) var etablissementsEnCours: Set<String> = []

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    /// Numéro de la dernière opération demandée sur chaque liste : seule celle-ci publie sa relecture.
    private var revisionMissions = 0
    private var revisionEtablissements = 0

    public init(controller: SessionController, snapshot: SessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
    }

    // MARK: - État dérivé

    public func estSauvegardee(_ missionId: String) -> Bool {
        FavorisRegles.estSauvegardee(missionId, dans: missions.elements)
    }

    /// Vrai pendant l'appel : l'étoile est désactivée.
    public func enCours(missionId: String) -> Bool { missionsEnCours.contains(missionId) }

    public func retraitEnCours(etablissementId: String) -> Bool { etablissementsEnCours.contains(etablissementId) }

    public func etablissement(id: String) -> EtablissementFavori? { etablissements.elements.first { $0.id == id } }

    public func effacerErreur() { erreurAction = nil }

    // MARK: - Lectures

    /// Écran « Mes favoris » : relit les deux listes en parallèle (à chaque apparition, tirer pour actualiser).
    public func charger() async {
        erreurAction = nil
        async let lectureMissions: Void = lireMissions(explicite: true)
        async let lectureEtablissements: Void = lireEtablissements(explicite: true)
        _ = await (lectureMissions, lectureEtablissements)
    }

    /// Relecture des missions sauvegardées (« Réessayer » de la section).
    public func chargerMissions() async { await lireMissions(explicite: true) }

    /// Relecture des établissements suivis (« Réessayer » de la section).
    public func chargerEtablissements() async { await lireEtablissements(explicite: true) }

    /// Explorer : état des étoiles, lu une fois par epoch (les mutations rendent ensuite la liste relue).
    public func chargerMissionsSiNecessaire() async {
        guard !missions.estPrete else { return }
        await lireMissions(explicite: true)
    }

    // MARK: - Missions

    /// Étoile : sauvegarde une mission non sauvegardée, retire une mission sauvegardée.
    public func basculer(missionId: String) async {
        await appliquer(missionId: missionId, sauvegarder: !estSauvegardee(missionId))
    }

    /// « Retirer » de l'écran « Mes favoris ».
    public func retirerMission(_ missionId: String) async {
        await appliquer(missionId: missionId, sauvegarder: false)
    }

    private func appliquer(missionId: String, sauvegarder: Bool) async {
        guard !missionId.isEmpty, !missionsEnCours.contains(missionId) else { return }
        missionsEnCours.insert(missionId)
        defer { missionsEnCours.remove(missionId) }
        revisionMissions += 1
        let revision = revisionMissions
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.favoris
        let context = snapshot.context
        let horloge = gateways.clock
        do {
            let lignes = try await bounded(timeout: controller.resolutionTimeout) {
                sauvegarder ? try await port.sauvegarder(missionId: missionId, context: context)
                            : try await port.retirer(missionId: missionId, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return }
            if revision == revisionMissions { publier(missions: lignes, maintenant: horloge.now()) }
            sessionExpired = false
            // Succès annoncé seulement si la relecture le confirme (PRINCIPES §3).
            if FavorisRegles.estSauvegardee(missionId, dans: lignes) == sauvegarder {
                erreurAction = nil
            } else {
                signaler(sauvegarder ? Self.sauvegardeNonConfirmee : Self.retraitNonConfirme)
            }
        } catch {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: Self.echecMutation) else { return }
            sessionExpired = issue.sessionExpiree
            signaler(issue.message)
            // Le serveur a pu agir (délai, coupure) : relecture, jamais de renvoi.
            if !issue.sessionExpiree { await lireMissions(explicite: false) }
        }
    }

    // MARK: - Établissements (retrait seulement, décision 8)

    /// Retrait confirmé par la relecture : `true` (la feuille de confirmation se referme) ; sinon le message
    /// reste affiché (`erreurAction`) et la feuille reste ouverte pour une nouvelle tentative manuelle.
    @discardableResult
    public func retirerEtablissement(_ etablissementId: String) async -> Bool {
        guard !etablissementId.isEmpty, !etablissementsEnCours.contains(etablissementId) else { return false }
        etablissementsEnCours.insert(etablissementId)
        defer { etablissementsEnCours.remove(etablissementId) }
        revisionEtablissements += 1
        let revision = revisionEtablissements
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return false }
        let port = gateways.favoris
        let context = snapshot.context
        do {
            let liste = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.basculerEtablissement(id: etablissementId, actif: false, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return false }
            if revision == revisionEtablissements { etablissements = .prete(liste) }
            sessionExpired = false
            guard !liste.contains(where: { $0.id == etablissementId }) else {
                signaler(Self.retraitNonConfirme)
                return false
            }
            erreurAction = nil
            return true
        } catch {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: Self.echecMutation) else { return false }
            sessionExpired = issue.sessionExpiree
            signaler(issue.message)
            if !issue.sessionExpiree { await lireEtablissements(explicite: false) }
            return false
        }
    }

    // MARK: - Interne

    /// `explicite` : lecture demandée par l'utilisateur ou par l'écran (son échec sur une liste affichée est
    /// signalé) ; sinon relecture de réconciliation après une mutation (son échec n'écrase pas le message
    /// de l'action).
    private func lireMissions(explicite: Bool) async {
        revisionMissions += 1
        let revision = revisionMissions
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.favoris
        let context = snapshot.context
        let horloge = gateways.clock
        do {
            let lignes = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.missionsSauvegardees(context: context)
            }
            guard await controller.epoch == snapshot.epoch, revision == revisionMissions else { return }
            publier(missions: lignes, maintenant: horloge.now())
            sessionExpired = false
        } catch {
            guard await controller.epoch == snapshot.epoch, revision == revisionMissions, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: Self.echecLectureMissions) else { return }
            if issue.sessionExpiree { sessionExpired = true }
            if missions.estPrete {
                if explicite { signaler(issue.message) }
            } else {
                missions = .echec(issue.message)
            }
        }
    }

    private func lireEtablissements(explicite: Bool) async {
        revisionEtablissements += 1
        let revision = revisionEtablissements
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.favoris
        let context = snapshot.context
        do {
            let liste = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.etablissementsFavoris(context: context)
            }
            guard await controller.epoch == snapshot.epoch, revision == revisionEtablissements else { return }
            etablissements = .prete(liste)
        } catch {
            guard await controller.epoch == snapshot.epoch, revision == revisionEtablissements, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: Self.echecLectureEtablissements) else { return }
            if issue.sessionExpiree { sessionExpired = true }
            if etablissements.estPrete {
                if explicite { signaler(issue.message) }
            } else {
                etablissements = .echec(issue.message)
            }
        }
    }

    private func publier(missions lignes: [MissionSauvegardee], maintenant: Date) {
        missions = .prete(lignes)
        missionsAffichees = FavorisRegles.missionsAffichees(lignes, maintenant: maintenant)
    }

    private func signaler(_ message: String) {
        tentatives += 1
        erreurAction = message
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
