import Foundation
import Combine

/// Contenu lu de « Mon score » : les quatre lectures de la page, toutes servies par le serveur.
public struct ContenuScore: Equatable, Sendable {
    public var breakdown: BreakdownScore
    public var evolution: [PointEvolutionScore]
    public var evenements: [EvenementScore]
    /// Notations reçues et publiées (`fn_lister_notations_recues`), au plus `EvaluationsDecodage.limiteScore` affichées.
    public var notations: [NotationRecue]

    public init(breakdown: BreakdownScore, evolution: [PointEvolutionScore], evenements: [EvenementScore],
                notations: [NotationRecue]) {
        self.breakdown = breakdown; self.evolution = evolution; self.evenements = evenements; self.notations = notations
    }
}

/// État de la page : en attente de la première réponse, lue, ou en échec (message affiché).
public enum EtatScore: Equatable, Sendable {
    case chargement
    case pret(ContenuScore)
    case echec(String)

    public var contenu: ContenuScore? {
        if case let .pret(contenu) = self { return contenu }
        return nil
    }
}

/// Modèle de « Mon score » (L4-T9), port de `ScoreContent` (`src/pages/PageScoreSoignant.tsx`) et de la contestation
/// d'un événement (`ModaleReclamationScore.tsx`, sans justificatif : D10).
///
/// Sur `/soignant/score`, le web lit la clé `evenements` alors que le serveur sert `events` (correction 16 du plan) et
/// n'y affiche donc pas la liste ; il l'affiche en revanche sur le profil du soignant (`ProfilSoignant.tsx` l.381-385,
/// `SectionEvenementsScore`, qui lit `events`), avec sa contestation (revue B8 des textes de la vague D, M2).
///
/// Règles :
/// - les quatre lectures (détail du calcul, évolution, événements, notations reçues) partent ensemble, chacune bornée à
///   `SessionController.resolutionTimeout` ; la page n'est affichée que si les quatre ont répondu — une lecture en
///   échec n'est jamais remplacée par un état vide plausible (le web, lui, affiche « aucun événement » quand la
///   lecture échoue) ;
/// - gateways de l'epoch de l'écran, réponse d'un epoch périmé ignorée, deux lectures qui se chevauchent : seule la
///   dernière publie ;
/// - une contestation n'est annoncée qu'après une relecture des événements qui montre `contestable == false`
///   (valeur calculée par le serveur, PRINCIPES §3) ; refus serveur verbatim ; erreur de transport ou refus : message
///   puis relecture des événements (le serveur a pu agir), jamais de renvoi ;
/// - une annulation (vue qui disparaît) n'est jamais une erreur.
@MainActor
public final class ScoreModel: ObservableObject {
    @Published public private(set) var etat: EtatScore = .chargement
    /// Dernière erreur d'action ou de relecture sur une page affichée ; `nil` après un succès confirmé.
    @Published public private(set) var erreur: String?
    /// Dernier succès confirmé par relecture (« Réclamation envoyée… »).
    @Published public private(set) var confirmation: String?
    /// Jeton d'annonce VoiceOver (`InlineNotice.announcementID`) : change à chaque message.
    @Published public private(set) var jeton = 0
    @Published public private(set) var sessionExpiree = false
    /// Événement dont la contestation est en vol (une seule à la fois).
    @Published public private(set) var contestationEnCours: String?

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private var revision = 0

    public init(controller: SessionController, snapshot: SessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
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

    // MARK: - Lecture

    /// À chaque apparition et « Réessayer ».
    public func charger() async {
        erreur = nil
        revision += 1
        let revisionLecture = revision
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.score
        let context = snapshot.context
        let delai = controller.resolutionTimeout
        do {
            async let breakdown = bounded(timeout: delai) { try await port.breakdown(context: context) }
            async let evolution = bounded(timeout: delai) {
                try await port.evolution(mois: ScoreDecodage.moisEvolution, context: context)
            }
            async let evenements = bounded(timeout: delai) {
                try await port.evenements(limite: ScoreDecodage.limiteEvenements, context: context)
            }
            async let notations = bounded(timeout: delai) {
                try await port.notationsRecues(limite: EvaluationsDecodage.limiteScore, context: context)
            }
            let contenu = ContenuScore(breakdown: try await breakdown, evolution: try await evolution,
                                       evenements: try await evenements,
                                       notations: Array(try await notations.prefix(EvaluationsDecodage.limiteScore)))
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision else { return }
            etat = .pret(contenu)
            sessionExpiree = false
        } catch {
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision, !Task.isCancelled,
                  let issue = FiltresModel.message(pour: error, repli: ScoreTextes.chargementImpossible) else { return }
            if issue.sessionExpiree { sessionExpiree = true }
            if etat.contenu != nil {
                signaler(issue.message)
            } else {
                etat = .echec(issue.message)
            }
        }
    }

    // MARK: - Contestation

    /// « Envoyer » de la feuille de contestation : motif choisi, explication de vingt caractères au moins sans espaces
    /// de bord ; `true` si les événements relus montrent l'événement non contestable (la feuille se referme), sinon le
    /// message reste affiché.
    @discardableResult
    public func contester(_ evenement: EvenementScore, motif: MotifContestationScore?, texte saisie: String) async -> Bool {
        guard contestationEnCours == nil else { return false }
        guard let motif else {
            signaler(ScoreTextes.motifRequis)
            return false
        }
        guard let texte = ScorePresentation.texteValide(saisie) else {
            signaler(ScoreTextes.texteRequis)
            return false
        }
        contestationEnCours = evenement.id
        defer { contestationEnCours = nil }
        effacerMessages()
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return false }
        let port = gateways.score
        let context = snapshot.context
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.contester(evenementId: evenement.id, motif: motif.rawValue, texte: texte, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return false }
            sessionExpiree = false
            switch issue {
            case let .refusee(_, message):
                signaler(message.isEmpty ? ScoreTextes.erreur : message)
                // « Une réclamation est déjà ouverte… » : les événements relus le montrent.
                await relireEvenements(port: port, context: context)
                return false
            case .enregistree:
                guard await relireEvenements(port: port, context: context),
                      etat.contenu?.evenements.first(where: { $0.id == evenement.id })?.contestable == false else {
                    if erreur == nil { signaler(ScoreTextes.contestationNonConfirmee) }
                    return false
                }
                confirmation = ScoreTextes.reclamationEnvoyee
                jeton += 1
                return true
            }
        } catch {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled,
                  let issue = FiltresModel.message(pour: error, repli: ScoreTextes.erreurReseau) else { return false }
            sessionExpiree = issue.sessionExpiree
            signaler(issue.message)
            // Le serveur a pu agir (délai, coupure) : relecture, jamais de renvoi.
            if !issue.sessionExpiree { await relireEvenements(port: port, context: context) }
            return false
        }
    }

    // MARK: - Interne

    /// Relecture des seuls événements après une contestation (`rechargerEvenements`, `PageScoreSoignant.tsx` l.47-56) ;
    /// son échec n'écrase pas le message de l'action. Rend `true` si les événements relus sont publiés.
    @discardableResult
    private func relireEvenements(port: ScorePort, context: MissionReadContext) async -> Bool {
        guard var contenu = etat.contenu else { return false }
        let revisionLecture = revision
        do {
            let evenements = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.evenements(limite: ScoreDecodage.limiteEvenements, context: context)
            }
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision else { return false }
            contenu.evenements = evenements
            etat = .pret(contenu)
            return true
        } catch {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled,
                  let issue = FiltresModel.message(pour: error, repli: ScoreTextes.chargementImpossible) else { return false }
            if issue.sessionExpiree { sessionExpiree = true }
            if erreur == nil { signaler(issue.message) }
            return false
        }
    }

    private func signaler(_ message: String) {
        confirmation = nil
        erreur = message
        jeton += 1
    }
}
