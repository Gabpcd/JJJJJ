import Foundation
import Combine

/// État des disponibilités : en attente de la première réponse, relues, ou en échec (message affiché sous le titre
/// « Disponibilités indisponibles »).
public enum EtatDisponibilites: Equatable, Sendable {
    case chargement
    case prete(Set<DispoCle>)
    case echec(String)

    /// Cases déclarées relues ; vide hors de l'état prêt.
    public var declarees: Set<DispoCle> {
        if case let .prete(declarees) = self { return declarees }
        return []
    }

    public var estPrete: Bool {
        if case .prete = self { return true }
        return false
    }
}

/// Modèle de « Mes disponibilités » (L4-T5), port de `src/pages/MesDisponibilites.tsx` (`/soignant/disponibilites`).
///
/// État dérivé (`CLAUDE.md`) : la grille de quatre semaines vient de l'horloge du monde (`ClockPort`,
/// `SemainesDisponibilites`, lundi Europe/Paris), re-dérivée à chaque lecture et avant chaque bascule ; les cases
/// déclarées viennent de la relecture serveur. Rien n'est pré-rempli ni initialisé par un défaut.
///
/// Règles :
/// - lectures et bascules bornées à `SessionController.resolutionTimeout`, gateways de l'epoch de l'écran, réponse d'un
///   epoch périmé ignorée ;
/// - **aucun état optimiste** (le web en a un, l.72-77) : une case ne change qu'après la relecture qui suit l'écriture
///   (PRINCIPES §3) ; une relecture qui ne montre pas la bascule est un échec (`nonConfirmee`) ;
/// - une bascule à la fois par case ; des cases distinctes peuvent être basculées en même temps. Une relecture faite
///   pendant que d'autres appels sont en vol ne prouve rien sur les autres cases (elle a pu précéder leur écriture) :
///   elle ne publie alors que la case basculée ; seule une bascule sans chevauchement publie la semaine relue ;
/// - un jour passé ou hors de la grille n'est jamais envoyé (refus du serveur repris tel quel) ; un refus serveur est
///   affiché verbatim ;
/// - erreur de transport ou délai dépassé : le serveur a pu agir, donc relecture, jamais de renvoi ; si la relecture
///   montre la bascule, elle est confirmée, sinon le message reste ; si elle échoue, la grille n'est plus affichée ;
/// - une lecture en échec retire la grille (« Réessayez avant de les modifier. », comme le web) ; session expirée
///   signalée ; une annulation (vue qui disparaît) n'est jamais une erreur.
@MainActor
public final class DisponibilitesModel: ObservableObject {
    @Published public private(set) var etat: EtatDisponibilites = .chargement
    /// Grille dérivée de l'horloge à la dernière lecture ou bascule ; `nil` avant la première.
    @Published public private(set) var grille: GrilleDisponibilites?
    /// Dernière erreur de bascule ; `nil` après une bascule confirmée par relecture.
    @Published public private(set) var erreur: String?
    /// Jeton d'annonce VoiceOver (`InlineNotice.announcementID`) : change à chaque message.
    @Published public private(set) var jeton = 0
    @Published public private(set) var sessionExpiree = false
    /// Cases dont la bascule est en vol.
    @Published public private(set) var enCours: Set<DispoCle> = []

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    /// Avance au début de chaque lecture, au début de chaque bascule et à chaque publication d'une bascule : une réponse
    /// dont le numéro n'est plus le dernier a été chevauchée.
    private var operations = 0

    public init(controller: SessionController, snapshot: SessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
    }

    // MARK: - Dérivés

    /// Semaines à afficher : vide tant que les disponibilités ne sont pas relues.
    public var semaines: [SemaineDisponibilitesAffichee] {
        guard let grille, case let .prete(declarees) = etat else { return [] }
        return DisponibilitesPresentation.semaines(grille: grille, declarees: declarees, enCours: enCours)
    }

    /// Nombre de créneaux déclarés à partir d'aujourd'hui (`nbDispos` du web, l.101).
    public var nombre: Int { etat.declarees.count }

    public func effacerErreur() { erreur = nil }

    /// « Vérifier ma session » : revalide la session, puis relit si elle est toujours prête pour cet epoch.
    public func verifierSession(_ session: SessionStore) async {
        await session.start()
        guard session.state.snapshot?.epoch == snapshot.epoch else { return }
        await charger()
    }

    // MARK: - Lecture

    /// À chaque apparition, au tirer-pour-rafraîchir et sur « Réessayer » (le web lit au montage).
    public func charger() async {
        erreur = nil
        operations += 1
        let numero = operations
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let grille = SemainesDisponibilites.grille(maintenant: gateways.clock.now())
        let port = gateways.disponibilites
        let context = snapshot.context
        do {
            let declarees = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.lister(depuis: grille.aujourdhui, context: context)
            }
            guard await controller.epoch == snapshot.epoch, numero == operations else { return }
            self.grille = grille
            etat = .prete(declarees)
            sessionExpiree = false
        } catch {
            guard await controller.epoch == snapshot.epoch, numero == operations, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: DisponibilitesTextes.echecMessage) else { return }
            indisponible(issue)
        }
    }

    // MARK: - Bascule

    /// Appui sur « Jour » ou « Nuit » : pose le créneau s'il n'est pas déclaré, le retire sinon (l.65-99).
    public func basculer(jour: JourParis, creneau: CreneauDispo) async {
        let cle = DispoCle(jour: jour, creneau: creneau)
        guard etat.estPrete, !enCours.contains(cle) else { return }
        enCours.insert(cle)
        defer { enCours.remove(cle) }
        erreur = nil
        operations += 1
        let numero = operations
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        // État dérivé : un jour devenu passé depuis l'affichage (minuit franchi) n'est plus basculable.
        let grille = SemainesDisponibilites.grille(maintenant: gateways.clock.now())
        deriver(grille)
        guard case let .prete(declarees) = etat else { return }
        guard jour >= grille.aujourdhui, grille.semaines.contains(where: { $0.jours.contains { $0.jour == jour } }) else {
            signaler(DisponibilitesTextes.horsFenetre)
            return
        }
        let cible = !declarees.contains(cle)
        let port = gateways.disponibilites
        let context = snapshot.context
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.definir(jour: jour, creneau: creneau, disponible: cible, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return }
            sessionExpiree = false
            switch issue {
            case let .refusee(message):
                signaler(message.isEmpty ? DisponibilitesTextes.basculeImpossible : message)
            case let .relue(semaine):
                publier(semaine, portee: jour.semaine.map(Portee.semaine) ?? .caseSeule, apres: cle, numero: numero)
                if semaine.contains(cle) != cible { signaler(DisponibilitesTextes.nonConfirmee) }
            }
        } catch {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: DisponibilitesTextes.basculeImpossible) else { return }
            sessionExpiree = issue.sessionExpiree
            signaler(issue.message)
            // Le serveur a pu agir (délai, coupure) : relecture, jamais de renvoi.
            if !issue.sessionExpiree {
                await reconcilier(cle, cible: cible, depuis: grille.aujourdhui, port: port, context: context, numero: numero,
                                  annonce: jeton)
            }
        }
    }

    // MARK: - Interne

    /// Portée sur laquelle une relecture faite après une bascule fait foi.
    private enum Portee {
        /// Semaine civile du jour basculé (`IssueDisponibilite.relue`).
        case semaine(ClosedRange<JourParis>)
        /// Toute la grille, depuis aujourd'hui (relecture de réconciliation).
        case grille
        /// La seule case basculée.
        case caseSeule
    }

    /// Relecture après une bascule dont l'issue est inconnue : confirmée si la case relue vaut la cible (le message de
    /// cette bascule, s'il est encore le dernier affiché, est retiré), inchangée sinon (le message reste) ; relecture
    /// impossible : la grille n'est plus affichée.
    private func reconcilier(_ cle: DispoCle, cible: Bool, depuis: JourParis, port: any DisponibilitesPort,
                             context: MissionReadContext, numero: Int, annonce: Int) async {
        do {
            let declarees = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.lister(depuis: depuis, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return }
            publier(declarees, portee: .grille, apres: cle, numero: numero)
            if declarees.contains(cle) == cible, jeton == annonce { erreur = nil }
        } catch {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled,
                  let issue = Self.message(pour: error, repli: DisponibilitesTextes.echecMessage) else { return }
            indisponible(issue)
        }
    }

    /// Publie une relecture faite après l'écriture de `cle`. Sans chevauchement (aucun autre appel lancé ni publié depuis
    /// le début de cette bascule, aucune autre bascule en vol), elle fait foi sur toute sa portée : la semaine civile du
    /// jour, jours passés écartés, ou toute la grille. Sinon elle ne fait foi que sur la case qu'elle suit : elle a pu
    /// précéder l'écriture d'une autre case.
    private func publier(_ relue: Set<DispoCle>, portee: Portee, apres cle: DispoCle, numero: Int) {
        guard case var .prete(declarees) = etat else { return }
        let sansChevauchement = numero == operations && enCours == [cle]
        operations += 1
        switch sansChevauchement ? portee : .caseSeule {
        case let .semaine(jours):
            let aujourdhui = grille?.aujourdhui ?? jours.lowerBound
            declarees = declarees.filter { !jours.contains($0.jour) }
            declarees.formUnion(relue.filter { jours.contains($0.jour) && $0.jour >= aujourdhui })
        case .grille:
            declarees = relue
        case .caseSeule:
            if relue.contains(cle) { declarees.insert(cle) } else { declarees.remove(cle) }
        }
        etat = .prete(declarees)
    }

    /// Nouvelle grille dérivée de l'horloge : les cases des jours devenus passés ne sont plus comptées.
    private func deriver(_ grille: GrilleDisponibilites) {
        guard self.grille != grille else { return }
        self.grille = grille
        if case let .prete(declarees) = etat {
            etat = .prete(declarees.filter { $0.jour >= grille.aujourdhui })
        }
    }

    private func indisponible(_ issue: (message: String, sessionExpiree: Bool)) {
        if issue.sessionExpiree { sessionExpiree = true }
        etat = .echec(issue.sessionExpiree ? issue.message : DisponibilitesTextes.echecMessage)
    }

    private func signaler(_ message: String) {
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
