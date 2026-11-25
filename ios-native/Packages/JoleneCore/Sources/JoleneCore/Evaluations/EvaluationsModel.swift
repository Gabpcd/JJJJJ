import Foundation
import Combine

/// État de la page des évaluations : en attente de la première réponse, page lue, ou échec (message affiché).
public enum EtatEvaluations: Equatable, Sendable {
    case chargement
    case prete(PageEvaluations)
    case echec(String)

    public var page: PageEvaluations? {
        if case let .prete(page) = self { return page }
        return nil
    }
}

/// Modèle de « Mes évaluations » (L4-T9), port de `EvaluationsContent` (`src/pages/EvaluationsSoignant.tsx`).
///
/// Filtre de visibilité centralisé (`CLAUDE.md`, « Publication différée ») : le modèle ne connaît que la page servie
/// par `EvaluationsPort.recues` (RPC filtrée côté serveur). Il n'additionne, ne moyenne ni ne compte aucune note : note
/// moyenne, total, part de cinq étoiles et évolution sont les valeurs de la réponse, et le nombre de pages vient de
/// `total`.
///
/// Règles (mêmes que `FiltresModel`, L4-T4) :
/// - lectures et mutations bornées à `SessionController.resolutionTimeout`, gateways de l'epoch de l'écran, réponse d'un
///   epoch périmé ignorée, deux lectures qui se chevauchent : seule la dernière publie ;
/// - **état dérivé** : les filtres et la page affichés décrivent toujours la page lue — changer un filtre remet la page
///   à 0 (web l.189, l.200, l.211) puis relit ; si la relecture échoue, filtres et page reviennent à ceux de la page
///   encore affichée ;
/// - un signalement n'est annoncé qu'après une relecture de la page qui montre `signale == true` (PRINCIPES §3) ; refus
///   serveur verbatim ; erreur de transport ou refus : message puis relecture (le serveur a pu agir), jamais de renvoi ;
/// - une annulation (vue qui disparaît) n'est jamais une erreur.
@MainActor
public final class EvaluationsModel: ObservableObject {
    @Published public private(set) var etat: EtatEvaluations = .chargement
    @Published public private(set) var filtre = FiltreEvaluations()
    /// Page demandée, à partir de 0 (`p_offset = page × 20`).
    @Published public private(set) var page = 0
    /// Dernière erreur d'action ou de relecture sur une page affichée ; `nil` après un succès confirmé.
    @Published public private(set) var erreur: String?
    /// Dernier succès confirmé par relecture (« Signalement transmis… »).
    @Published public private(set) var confirmation: String?
    /// Jeton d'annonce VoiceOver (`InlineNotice.announcementID`) : change à chaque message.
    @Published public private(set) var jeton = 0
    @Published public private(set) var sessionExpiree = false
    /// Une lecture est en vol sur une page déjà affichée (changement de filtre ou de page).
    @Published public private(set) var lectureEnCours = false
    /// Notation dont le signalement est en vol (un seul à la fois).
    @Published public private(set) var signalementEnCours: String?

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private var revision = 0
    /// Filtres et page de la page affichée (`etat == .prete`).
    private var affiches: (filtre: FiltreEvaluations, page: Int) = (FiltreEvaluations(), 0)

    public init(controller: SessionController, snapshot: SessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
    }

    /// `Math.ceil(total / PAR_PAGE)` de la page lue ; 0 tant qu'aucune page n'est lue.
    public var nombreDePages: Int { EvaluationsPresentation.nombreDePages(total: etat.page?.total ?? 0) }
    public var aPagePrecedente: Bool { page > 0 }
    public var aPageSuivante: Bool { page < nombreDePages - 1 }

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

    /// À chaque apparition et « Réessayer » (le web relit au montage et à chaque changement de filtre ou de page).
    public func charger() async {
        erreur = nil
        await lire(explicite: true)
    }

    public func choisir(periode: PeriodeEvaluations) async {
        guard periode != filtre.periode else { return }
        filtre.periode = periode
        await filtrer()
    }

    public func choisir(noteMin: Int?) async {
        guard noteMin != filtre.noteMin else { return }
        filtre.noteMin = noteMin
        await filtrer()
    }

    public func choisir(etablissementId: String?) async {
        let cible = etablissementId.flatMap { $0.isEmpty ? nil : $0 }
        guard cible != filtre.etablissementId else { return }
        filtre.etablissementId = cible
        await filtrer()
    }

    public func pageSuivante() async {
        guard aPageSuivante else { return }
        page += 1
        effacerMessages()
        await lire(explicite: true)
    }

    public func pagePrecedente() async {
        guard aPagePrecedente else { return }
        page -= 1
        effacerMessages()
        await lire(explicite: true)
    }

    // MARK: - Signalement

    /// « Signaler » de la feuille (`ModaleSignaler`) : motif de dix caractères au moins, sans espaces de bord ; `true` si
    /// la page relue montre la notation signalée (la feuille se referme), sinon le message reste affiché.
    @discardableResult
    public func signaler(_ notation: NotationRecue, motif saisie: String) async -> Bool {
        guard signalementEnCours == nil else { return false }
        guard let motif = EvaluationsPresentation.motifValide(saisie) else {
            signaler(EvaluationsTextes.signalementMotifRequis)
            return false
        }
        signalementEnCours = notation.id
        defer { signalementEnCours = nil }
        effacerMessages()
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return false }
        let port = gateways.evaluationsRecues
        let context = snapshot.context
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.signaler(notationId: notation.id, motif: motif, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return false }
            sessionExpiree = false
            switch issue {
            case let .refuse(message):
                signaler(message.isEmpty ? EvaluationsTextes.erreurSignalement : message)
                // « Notation déjà signalée » : la page relue le montre ; l'échec de cette relecture n'écrase pas le refus.
                await lire(explicite: false)
                return false
            case .signale:
                guard await lire(explicite: false) else {
                    if erreur == nil { signaler(EvaluationsTextes.signalementNonConfirme) }
                    return false
                }
                guard etat.page?.notations.first(where: { $0.id == notation.id })?.signale == true else {
                    signaler(EvaluationsTextes.signalementNonConfirme)
                    return false
                }
                confirmation = EvaluationsTextes.signalementTransmis
                jeton += 1
                return true
            }
        } catch {
            guard await controller.epoch == snapshot.epoch, !Task.isCancelled,
                  let issue = FiltresModel.message(pour: error, repli: EvaluationsTextes.erreurSignalement) else { return false }
            sessionExpiree = issue.sessionExpiree
            signaler(issue.message)
            // Le serveur a pu agir (délai, coupure) : relecture, jamais de renvoi.
            if !issue.sessionExpiree { await lire(explicite: false) }
            return false
        }
    }

    // MARK: - Interne

    private func filtrer() async {
        page = 0
        effacerMessages()
        await lire(explicite: true)
    }

    /// `explicite` : lecture demandée (son échec sur une page affichée est signalé, filtres et page reviennent à ceux
    /// de la page affichée) ; sinon relecture après un signalement (son échec n'écrase pas le message de l'action).
    /// Rend `true` si la page demandée a été lue et publiée.
    @discardableResult
    private func lire(explicite: Bool) async -> Bool {
        revision += 1
        let revisionLecture = revision
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return false }
        let port = gateways.evaluationsRecues
        let context = snapshot.context
        let demande = (filtre: filtre, page: page)
        if etat.page != nil { lectureEnCours = true }
        defer { if revisionLecture == revision { lectureEnCours = false } }
        do {
            var lue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.recues(filtre: demande.filtre, page: demande.page, context: context)
            }
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision else { return false }
            var pageLue = demande.page
            // Page vidée par un filtre serveur entre-temps (notation masquée) : dernière page existante, une seule fois.
            let pages = EvaluationsPresentation.nombreDePages(total: lue.total)
            if lue.notations.isEmpty, pageLue > 0, pages > 0, pageLue >= pages {
                let derniere = pages - 1
                pageLue = derniere
                lue = try await bounded(timeout: controller.resolutionTimeout) {
                    try await port.recues(filtre: demande.filtre, page: derniere, context: context)
                }
                guard await controller.epoch == snapshot.epoch, revisionLecture == revision else { return false }
            }
            etat = .prete(lue)
            page = pageLue
            affiches = (demande.filtre, pageLue)
            sessionExpiree = false
            return true
        } catch {
            guard await controller.epoch == snapshot.epoch, revisionLecture == revision, !Task.isCancelled,
                  let issue = FiltresModel.message(pour: error, repli: EvaluationsTextes.erreurChargement) else { return false }
            if issue.sessionExpiree { sessionExpiree = true }
            if etat.page != nil {
                // La page affichée reste celle d'avant : filtres et page la décrivent de nouveau.
                filtre = affiches.filtre
                page = affiches.page
                if explicite { signaler(issue.message) }
            } else {
                etat = .echec(issue.message)
            }
            return false
        }
    }

    private func signaler(_ message: String) {
        confirmation = nil
        erreur = message
        jeton += 1
    }
}
