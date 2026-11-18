import Foundation
import Combine

/// Modèle de l'onglet Missions de l'espace établissement (lot 5, T5), port de `ListeMissions.tsx` : liste par
/// filtre de statut (« Toutes » par défaut, web l.27-36), compteurs, pages de 50 relues **cumulativement**
/// (`EtabMissionsPage`), lues par `gateways.etablissement.missions` pour l'epoch de la session et bornées à
/// `SessionController.resolutionTimeout`. Mêmes règles d'état que `MesMissionsModel` :
/// - une annulation de tâche SwiftUI n'est jamais une erreur (l'état reste celui d'avant) ;
/// - une relecture d'une liste affichée la conserve et n'expose qu'`erreurRafraichissement` ;
/// - une réponse d'un epoch périmé, ou dépassée par une lecture plus récente, est abandonnée.
/// Sélectionner un filtre revient à la première page ; « Charger plus » relit une page de plus et n'est actif
/// que si la dernière lecture était pleine, hors relecture et hors page suivante en cours. Lecture seule.
@MainActor
public final class EtabMissionsModel: ObservableObject {
    public enum Contenu: Equatable, Sendable {
        case chargement
        case chargee([EtabMissionResume])
        case echec(String)
    }

    public static let genericFailureMessage = "Les missions n'ont pas pu être chargées. Vérifiez votre connexion puis réessayez."

    @Published public private(set) var filtre: EtabMissionsFiltre
    @Published public private(set) var contenu: Contenu = .chargement
    @Published public private(set) var page = 0
    @Published public private(set) var aSuivre = false
    @Published public private(set) var rafraichissement = false
    @Published public private(set) var erreurRafraichissement: String?
    @Published public private(set) var chargementSuite = false
    @Published public private(set) var erreurSuite: String?
    /// Compteurs de la dernière lecture réussie (`nil` : non relus, pastilles sans nombre).
    @Published public private(set) var compteurs: EtabMissionsCompteurs?
    @Published public private(set) var candidaturesEnAttente: [String: Int] = [:]
    @Published public private(set) var creneaux: [String: [MissionSlot]] = [:]

    private let controller: SessionController
    private let snapshot: EtablissementSessionSnapshot
    private var generation = 0

    public init(controller: SessionController, snapshot: EtablissementSessionSnapshot, filtre: EtabMissionsFiltre = .toutes) {
        self.controller = controller
        self.snapshot = snapshot
        self.filtre = filtre
    }

    public var missions: [EtabMissionResume] {
        if case let .chargee(missions) = contenu { return missions }
        return []
    }

    public var estChargee: Bool {
        if case .chargee = contenu { return true }
        return false
    }

    public var peutChargerPlus: Bool { estChargee && aSuivre && !chargementSuite && !rafraichissement }

    /// Carte d'une mission affichée (créneaux et candidatures de la dernière lecture).
    public func carte(_ mission: EtabMissionResume) -> EtabMissionsPresentation.Carte {
        EtabMissionsPresentation.carte(mission, creneaux: creneaux[mission.id] ?? [],
                                       candidaturesEnAttente: candidaturesEnAttente[mission.id])
    }

    /// Sélectionne un filtre et relit sa première page (liste conservée pendant la relecture si affichée).
    public func selectionner(_ filtre: EtabMissionsFiltre) async {
        self.filtre = filtre
        await lire(page: 0, suite: false)
    }

    /// Relit le filtre affiché avec les pages déjà chargées (apparition, tirer pour actualiser, « Réessayer »).
    public func charger() async {
        await lire(page: estChargee ? page : 0, suite: false)
    }

    public func chargerPlus() async {
        guard peutChargerPlus else { return }
        await lire(page: page + 1, suite: true)
    }

    private func lire(page demandee: Int, suite: Bool) async {
        generation += 1
        let courant = generation
        let conserver = estChargee
        if suite {
            chargementSuite = true
            erreurSuite = nil
        } else {
            chargementSuite = false
            erreurSuite = nil
            erreurRafraichissement = nil
            if conserver { rafraichissement = true } else { contenu = .chargement }
        }
        defer {
            if generation == courant {
                rafraichissement = false
                chargementSuite = false
            }
        }

        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        guard generation == courant, !Task.isCancelled else { return }
        let port = gateways.etablissement.missions
        let context = snapshot.context
        let statut = filtre.statut
        do {
            let lue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.missions(context: context, statut: statut, page: demandee)
            }
            guard await controller.epoch == snapshot.epoch, generation == courant else { return }
            var vus = Set<String>()
            contenu = .chargee(lue.missions.filter { vus.insert($0.id).inserted })
            page = demandee
            aSuivre = lue.aSuivre
            // Compteurs non relus cette fois : les derniers connus restent plutôt qu'un « (0) » supposé.
            if let relus = lue.compteurs { compteurs = relus }
            candidaturesEnAttente = lue.candidaturesEnAttente
            creneaux = lue.creneaux
        } catch {
            guard await controller.epoch == snapshot.epoch, generation == courant, !Task.isCancelled else { return }
            let message: String
            if let jolene = error as? JoleneError {
                if jolene.kind == .cancelled { return }
                message = jolene.message
            } else if error is CancellationError {
                return
            } else {
                message = Self.genericFailureMessage
            }
            if suite {
                erreurSuite = message
            } else if conserver {
                erreurRafraichissement = message
            } else {
                contenu = .echec(message)
            }
        }
    }
}

/// Modèle du détail d'une mission de l'établissement (lot 5, T5), port de `DetailMission.tsx` sans montant :
/// mission relue sous le JWT courant (l'état de navigation n'est jamais une autorisation), planning (lecture
/// secondaire, échec porté par `EtabMissionDetail.erreurPlanning`), puis soignant assigné par
/// `fn_soignant_pour_etablissement` (lecture secondaire : son échec n'efface jamais la mission).
@MainActor
public final class EtabMissionDetailModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case chargement
        case chargee(EtabMissionDetail)
        /// Aucune ligne lisible (mission inexistante, supprimée ou hors de l'établissement) : web « Mission introuvable ».
        case introuvable
        case echec(String)
    }

    public enum Soignant: Equatable, Sendable {
        /// Aucun soignant assigné.
        case aucun
        case chargement
        case charge(SoignantPourEtab)
        /// `null` SQL : soignant supprimé (« Soignant indisponible »), jamais un profil vide.
        case indisponible
        case echec(String)
    }

    public static let genericFailureMessage = "La mission n'a pas pu être chargée. Vérifiez votre connexion puis réessayez."

    public let missionId: String
    @Published public private(set) var etat: Etat = .chargement
    @Published public private(set) var soignant: Soignant = .aucun
    @Published public private(set) var rafraichissement = false
    /// Relecture d'une mission affichée en échec : la mission reste affichée, l'erreur est signalée.
    @Published public private(set) var erreurRafraichissement: String?

    private let controller: SessionController
    private let snapshot: EtablissementSessionSnapshot
    private var generation = 0

    public init(missionId: String, controller: SessionController, snapshot: EtablissementSessionSnapshot) {
        self.missionId = missionId
        self.controller = controller
        self.snapshot = snapshot
    }

    public var detail: EtabMissionDetail? {
        if case let .chargee(detail) = etat { return detail }
        return nil
    }

    /// Lit (ou relit) la mission puis son soignant assigné ; une mission affichée est conservée pendant la relecture.
    public func charger() async {
        generation += 1
        let courant = generation
        let conserver = detail != nil
        erreurRafraichissement = nil
        if conserver { rafraichissement = true } else { etat = .chargement }
        defer { if generation == courant { rafraichissement = false } }

        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        guard generation == courant, !Task.isCancelled else { return }
        let port = gateways.etablissement.missions
        let context = snapshot.context
        let id = missionId
        let lu: EtabMissionDetail?
        do {
            lu = try await bounded(timeout: controller.resolutionTimeout) { try await port.mission(id: id, context: context) }
        } catch {
            guard await controller.epoch == snapshot.epoch, generation == courant, !Task.isCancelled else { return }
            guard let message = Self.message(error) else { return }
            if conserver { erreurRafraichissement = message } else { etat = .echec(message) }
            return
        }
        guard await controller.epoch == snapshot.epoch, generation == courant else { return }
        guard let lu else {
            etat = .introuvable
            soignant = .aucun
            return
        }
        etat = .chargee(lu)
        guard let soignantId = lu.soignantAssigneId ?? lu.mission.soignantAssigneId, !soignantId.isEmpty else {
            soignant = .aucun
            return
        }
        await lireSoignant(soignantId, port: port, context: context, generation: courant)
    }

    /// Relit le seul soignant assigné (« Réessayer » de sa section).
    public func rechargerSoignant() async {
        guard let lu = detail, let soignantId = lu.soignantAssigneId ?? lu.mission.soignantAssigneId, !soignantId.isEmpty,
              let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        generation += 1
        await lireSoignant(soignantId, port: gateways.etablissement.missions, context: snapshot.context, generation: generation)
    }

    private func lireSoignant(_ id: String, port: any EtabMissionsPort, context: EtablissementReadContext, generation courant: Int) async {
        if case .charge = soignant {} else { soignant = .chargement }
        do {
            let lu = try await bounded(timeout: controller.resolutionTimeout) { try await port.soignant(id: id, context: context) }
            guard await controller.epoch == snapshot.epoch, generation == courant else { return }
            soignant = lu.map(Soignant.charge) ?? .indisponible
        } catch {
            guard await controller.epoch == snapshot.epoch, generation == courant, !Task.isCancelled else { return }
            guard let message = Self.message(error) else { return }
            soignant = .echec(message)
        }
    }

    /// Message affichable d'une erreur ; `nil` pour une annulation (aucun changement d'état).
    private static func message(_ error: Error) -> String? {
        if let jolene = error as? JoleneError { return jolene.kind == .cancelled ? nil : jolene.message }
        if error is CancellationError { return nil }
        return genericFailureMessage
    }
}
