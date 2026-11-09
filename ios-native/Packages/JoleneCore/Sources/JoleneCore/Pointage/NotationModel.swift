import Combine
import Foundation

/// Mémoire « note déjà proposée » d'une mission, par utilisateur (`localStorage` `jolene_note_checkout_<mission>` du web,
/// `PointageRotatifSoignant.tsx` l.33, l.154-161) : posée AVANT l'ouverture de la feuille, jamais effacée ; « Plus tard »
/// ne la retire pas (le bandeau des évaluations du web rattrape). Locale à l'appareil : aucune lecture serveur.
@MainActor
public protocol MemoireNotation: AnyObject, Sendable {
    func dejaProposee(userId: String, missionId: String) -> Bool
    func marquerProposee(userId: String, missionId: String)
}

/// Mémoire persistante (Staging, Production) : `UserDefaults`, clé `jolene.notation.checkout.<userId>.<missionId>`.
@MainActor
public final class MemoireNotationDefaults: MemoireNotation {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public static func cle(userId: String, missionId: String) -> String {
        "jolene.notation.checkout." + userId + "." + missionId
    }

    public func dejaProposee(userId: String, missionId: String) -> Bool {
        defaults.bool(forKey: Self.cle(userId: userId, missionId: missionId))
    }

    public func marquerProposee(userId: String, missionId: String) {
        defaults.set(true, forKey: Self.cle(userId: userId, missionId: missionId))
    }
}

/// Mémoire du monde démo : en mémoire seulement, rien n'est persisté entre deux lancements (comme la session démo).
@MainActor
public final class MemoireNotationEnMemoire: MemoireNotation {
    private var cles: Set<String> = []

    public init() {}

    public func dejaProposee(userId: String, missionId: String) -> Bool {
        cles.contains(MemoireNotationDefaults.cle(userId: userId, missionId: missionId))
    }

    public func marquerProposee(userId: String, missionId: String) {
        cles.insert(MemoireNotationDefaults.cle(userId: userId, missionId: missionId))
    }
}

/// Notation rapide au départ final (lot 2, T5a, décision 10 ; parité `SheetNotationRapide`, `NotationRapide.tsx`
/// l.143-216, et `PointageRotatifSoignant.tsx` l.152-163). Aucun texte ici hors des libellés web et vouvoyés.
///
/// - `proposer()` est appelé quand `PointageModel.notationAProposer` passe à vrai (FERMETURE relue) : rien si la note a
///   déjà été proposée pour cette mission et cet utilisateur ; sinon `missions.fin_le` est RELU (l.156, revue fraîche de
///   L2-T3, m6) et la feuille s'ouvre si `maintenant ≥ fin − 30 min`, mémoire posée d'abord. Toute erreur de relecture
///   ne propose rien (l.162 : « le prompt de note ne doit jamais gêner le pointage »). Aucun contrôle de statut côté
///   client : le serveur accepte une mission `EN_COURS` dont le départ est pointé (`fn_creer_notation_mission`).
/// - Note globale 1-5 en un tap ; « Détailler » pré-remplit les quatre critères avec la note (ou 3) ; sans détail, la
///   gateway réplique la note sur les quatre critères (l.47).
/// - Envoi unique : `.enregistree` et `.dejaNotee` (silencieux, l.58-61) ferment la feuille avec le remerciement du web ;
///   un refus serveur s'affiche tel quel, feuille ouverte ; une erreur de transport affiche le texte opérationnel
///   `LibellesDetailPresences.Notation.erreurEnregistrement`. Aucune lecture de note (filtre centralisé
///   `evaluations_publiees`) : rien n'est jamais affiché d'une note, publiée ou non.
@MainActor
public final class NotationModel: ObservableObject {
    /// Retour affiché : remerciement (feuille fermée) ou erreur (feuille ouverte).
    public enum Retour: Equatable, Sendable {
        case remerciement
        case erreur(String)
    }

    public static let noteMaximale = 5
    /// Valeur des critères quand « Détailler » s'ouvre sans note choisie (`note || 3`, l.192).
    public static let critereParDefaut = 3

    @Published public private(set) var ouverte = false
    @Published public private(set) var note = 0
    @Published public private(set) var detailOuvert = false
    @Published public private(set) var criteres: [Int]?
    @Published public private(set) var envoiEnCours = false
    @Published public private(set) var retour: Retour?
    @Published public private(set) var sessionExpired = false

    public let missionId: String
    private let controller: SessionController
    private let snapshot: SessionSnapshot
    private let memoire: any MemoireNotation
    private var propositionEnCours = false

    public init(missionId: String, controller: SessionController, snapshot: SessionSnapshot, memoire: any MemoireNotation) {
        self.missionId = missionId
        self.controller = controller
        self.snapshot = snapshot
        self.memoire = memoire
    }

    public var peutEnvoyer: Bool { ouverte && note > 0 && !envoiEnCours }

    /// FERMETURE relue (`PointageModel.notationAProposer`) : ouvre la feuille une seule fois par mission et par
    /// utilisateur, si la fin prévue relue est atteinte à 30 min près.
    public func proposer() async {
        let userId = snapshot.context.userId
        guard !ouverte, !propositionEnCours, !memoire.dejaProposee(userId: userId, missionId: missionId) else { return }
        propositionEnCours = true
        defer { propositionEnCours = false }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.notation, mission = missionId, context = snapshot.context
        guard let fin = try? await bounded(timeout: controller.resolutionTimeout, {
            try await port.finPrevue(missionId: mission, context: context)
        }) else { return }
        guard await controller.epoch == snapshot.epoch, !Task.isCancelled,
              PointageRules.notationAProposer(typeScan: .fermeture, finLe: fin, maintenant: gateways.clock.now()),
              !memoire.dejaProposee(userId: userId, missionId: missionId) else { return }
        memoire.marquerProposee(userId: userId, missionId: missionId)
        reinitialiser()
        retour = nil
        ouverte = true
    }

    /// Note globale (l.184) : sans détail ouvert, les critères suivent la note (aucun critère envoyé).
    public func choisirNote(_ valeur: Int) {
        guard (1...Self.noteMaximale).contains(valeur), !envoiEnCours else { return }
        note = valeur
        if !detailOuvert { criteres = nil }
    }

    /// « Détailler ma note (optionnel) » / « Masquer le détail » (l.190-194).
    public func basculerDetail() {
        guard !envoiEnCours else { return }
        if detailOuvert {
            detailOuvert = false
            criteres = nil
        } else {
            let valeur = note > 0 ? note : Self.critereParDefaut
            criteres = Array(repeating: valeur, count: LibellesDetailPresences.Notation.criteres.count)
            detailOuvert = true
        }
    }

    /// Critère `index` (0…3) du détail ouvert.
    public func choisirCritere(_ index: Int, _ valeur: Int) {
        guard detailOuvert, !envoiEnCours, var actuels = criteres, actuels.indices.contains(index),
              (1...Self.noteMaximale).contains(valeur) else { return }
        actuels[index] = valeur
        criteres = actuels
    }

    /// « Envoyer ma note » (l.156-170).
    public func envoyer() async {
        guard peutEnvoyer else { return }
        envoiEnCours = true
        retour = nil
        defer { envoiEnCours = false }
        guard let gateways = await controller.gateways(for: snapshot.epoch) else { return }
        let port = gateways.notation, mission = missionId, context = snapshot.context, valeur = note
        let detail = criteres.flatMap { $0.count == 4 ? CriteresNotation($0[0], $0[1], $0[2], $0[3]) : nil }
        do {
            let issue = try await bounded(timeout: controller.resolutionTimeout) {
                try await port.noter(missionId: mission, note: valeur, criteres: detail, context: context)
            }
            guard await controller.epoch == snapshot.epoch else { return }
            switch issue {
            case .enregistree, .dejaNotee:
                fermer()
                retour = .remerciement
            case let .refusee(message):
                retour = .erreur(message)
            }
        } catch {
            guard await controller.epoch == snapshot.epoch else { return }
            if error is CancellationError || (error as? JoleneError)?.kind == .cancelled { return }
            if let jolene = error as? JoleneError, jolene.kind == .unauthorized {
                sessionExpired = true
                retour = .erreur(jolene.message)
                return
            }
            retour = .erreur(LibellesDetailPresences.Notation.erreurEnregistrement)
        }
    }

    /// « Plus tard » ou feuille fermée sans envoi (l.150-154, l.207) : la mémoire reste posée.
    public func plusTard() {
        guard !envoiEnCours else { return }
        fermer()
        retour = nil
    }

    /// Le remerciement a été affiché.
    public func oublierRetour() {
        retour = nil
    }

    private func fermer() {
        ouverte = false
        reinitialiser()
    }

    private func reinitialiser() {
        note = 0
        detailOuvert = false
        criteres = nil
    }
}
