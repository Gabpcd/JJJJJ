import Combine
import Foundation

/// Modèle du détail des présences d'une mission (lot 2, T5a ; parité `src/pages/DetailPresencesMission.tsx` pour le
/// soignant). Deux lectures en parallèle, bornées chacune à `SessionController.resolutionTimeout` :
/// `gateways.pointage.detail` (créneaux et synthèse serveur `fn_presences_detail_mission`, carte masquée sur `{error}`)
/// et `gateways.pointage.ficheDetail` (mission, première présence). Mission illisible → `.introuvable` (l.184-191) ;
/// échec de lecture → `.echec` (message du port), « Réessayer » relance. Aucun texte ici hors des libellés web assemblés
/// par `PresentationDetailPresences`.
///
/// Relance de l'établissement (l.115-124) : un envoi à la fois ; message serveur verbatim (`DEJA_RELANCE`, succès) ou
/// repli du web (`LibellesWeb.Presences.messageRelance`) ; une erreur de transport affiche son message (l.120) ;
/// `.unauthorized` → `sessionExpired`. Règles d'état du lot 1 : annulation jamais une erreur, epoch périmé abandonné.
@MainActor
public final class DetailPresencesModel: ObservableObject {
    public enum Etat: Equatable, Sendable {
        case chargement
        case introuvable
        /// Message levé par le port, ou nil quand l'erreur n'en porte aucun de lisible.
        case echec(String?)
        case pret(PresentationDetailPresences)
    }

    /// Retour de la relance (toast du web) : succès ou refus, message à afficher.
    public struct RetourRelance: Equatable, Sendable {
        public let succes: Bool
        public let message: String
    }

    @Published public private(set) var etat: Etat = .chargement
    @Published public private(set) var sessionExpired = false
    @Published public private(set) var relanceEnCours = false
    @Published public private(set) var retourRelance: RetourRelance?

    public let missionId: String
    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private var generation = 0

    public init(missionId: String, controller: SessionController, snapshot: SessionSnapshot) {
        self.missionId = missionId
        self.controller = controller
        self.snapshot = snapshot
    }

    public var presentation: PresentationDetailPresences? {
        if case let .pret(presentation) = etat { return presentation }
        return nil
    }

    public func charger() async {
        generation += 1
        let courant = generation
        if presentation == nil { etat = .chargement }
        guard let gateways = await controller.gateways(for: snapshot.epoch), generation == courant else { return }
        let port = gateways.pointage, mission = missionId, context = snapshot.context, delai = controller.resolutionTimeout
        do {
            async let lectureDetail = bounded(timeout: delai) { try await port.detail(missionId: mission, context: context) }
            async let lectureFiche = bounded(timeout: delai) { try await port.ficheDetail(missionId: mission, context: context) }
            let (detail, fiche) = try await (lectureDetail, lectureFiche)
            guard await estCourant(courant) else { return }
            sessionExpired = false
            guard let lue = fiche.mission else {
                etat = .introuvable
                return
            }
            etat = .pret(PresentationDetailPresences.construire(mission: lue, creneaux: detail.creneaux, resume: detail.resume,
                                                                presence: fiche.presence, maintenant: gateways.clock.now()))
        } catch {
            guard await estCourant(courant), case let .message(message) = Self.echec(error) else { return }
            sessionExpired = (error as? JoleneError)?.kind == .unauthorized
            etat = .echec(message)
        }
    }

    /// « Relancer l'établissement » (l.115-124, l.699-701).
    public func relancer() async {
        guard !relanceEnCours, presentation?.relanceProposee == true else { return }
        relanceEnCours = true
        retourRelance = nil
        defer { relanceEnCours = false }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.pointage, mission = missionId, context = snapshot.context
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.relancerValidation(missionId: mission, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return }
            switch issue {
            case let .envoyee(message):
                retourRelance = RetourRelance(succes: true,
                                              message: LibellesWeb.Presences.messageRelance(succes: true, message: message, erreur: nil))
            case let .refusee(message):
                retourRelance = RetourRelance(succes: false, message: message)
            }
        } catch {
            guard await controller.epoch == snapshot.epoch, case let .message(message) = Self.echec(error) else { return }
            if (error as? JoleneError)?.kind == .unauthorized { sessionExpired = true }
            retourRelance = RetourRelance(succes: false, message: message ?? LibellesWeb.Presences.relanceImpossible)
        }
    }

    /// « Vérifier ma session » : revalide la session puis relit le détail si elle reste prête pour cet epoch.
    public func verifierSession(_ session: SessionStore) async {
        await session.start()
        guard session.state.snapshot?.epoch == snapshot.epoch else { return }
        await charger()
    }

    private func estCourant(_ jeton: Int) async -> Bool {
        guard generation == jeton, !Task.isCancelled else { return false }
        return await controller.epoch == snapshot.epoch && generation == jeton
    }

    private enum Echec { case annulation, message(String?) }

    /// Annulation (jamais une erreur affichée) ou message du port (nil s.il n.en porte aucun de lisible).
    private static func echec(_ error: Error) -> Echec {
        if error is CancellationError { return .annulation }
        guard let jolene = error as? JoleneError else { return .message(nil) }
        return jolene.kind == .cancelled ? .annulation : .message(jolene.message)
    }
}
