import Foundation
import Combine

/// Modèle de l'écran « Préférences de notifications » (lot 3, T6), port de `PageParametresNotifications.tsx`.
///
/// - Lecture par `gateways.preferences` de l'epoch de la session, bornée à
///   `SessionController.resolutionTimeout` (le web : `avecDelai(…, 15_000)`) ; une réponse d'un epoch
///   périmé ou d'un chargement dépassé est ignorée ; l'annulation n'est jamais une erreur ; échec →
///   message du web (l.257), jamais des préférences par défaut ; session expirée → `sessionExpired`.
/// - Édition sur le brouillon relu, selon les règles de `PreferencesNotifications` (case grisée si le
///   canal global est coupé, alerte SMS seulement si la ligne `soignants` a été lue et le canal SMS actif).
/// - Enregistrement : un seul envoi à la fois, aucune modification pendant l'envoi ; « Préférences
///   enregistrées » seulement si la relecture rendue par le port concorde avec la demande (PRINCIPES §3) ;
///   alerte SMS non relue → échec partiel du web (l.237) ; relecture non concordante → « Erreur
///   enregistrement » ; refus serveur → message verbatim, brouillon conservé ; issue inconnue (délai
///   dépassé, réseau) → relecture, jamais de renvoi (PRINCIPES §5).
@MainActor
public final class PreferencesModel: ObservableObject {
    public enum State: Equatable, Sendable {
        case loading
        /// Brouillon affiché : préférences relues, puis modifiées par l'utilisateur.
        case loaded(PreferencesNotifications)
        case failed(String)
    }

    public enum Enregistrement: Equatable, Sendable {
        case aucun
        case enCours
        case enregistre
        case partiel(String)
        case echec(String)
    }

    @Published public private(set) var state: State = .loading
    @Published public private(set) var enregistrement: Enregistrement = .aucun
    @Published public private(set) var sessionExpired = false

    private let controller: SessionController
    private let snapshot: SessionSnapshot
    /// Numéro du dernier chargement lancé : seul ce chargement publie (main actor, donc sans course).
    private var generation = 0

    public init(controller: SessionController, snapshot: SessionSnapshot) {
        self.controller = controller
        self.snapshot = snapshot
    }

    public var preferences: PreferencesNotifications? {
        if case let .loaded(preferences) = state { return preferences }
        return nil
    }

    public var estEnregistrementEnCours: Bool { enregistrement == .enCours }

    // MARK: - Lecture

    public func load() async {
        generation += 1
        let courant = generation
        state = .loading
        enregistrement = .aucun
        guard let gateways = await controller.gateways(for: snapshot.epoch), generation == courant else { return }
        let port = gateways.preferences
        let context = snapshot.context
        do {
            let lu = try await bounded(timeout: controller.resolutionTimeout) { try await port.lire(context: context) }
            guard await controller.epoch == snapshot.epoch, generation == courant else { return }
            sessionExpired = false
            state = .loaded(lu)
        } catch {
            guard await controller.epoch == snapshot.epoch, generation == courant, !Task.isCancelled,
                  !(error is CancellationError) else { return }
            let jolene = error as? JoleneError
            if jolene?.kind == .cancelled { return }
            if let jolene, jolene.kind == .unauthorized {
                sessionExpired = true
                state = .failed(jolene.message)
            } else {
                state = .failed(PreferencesTextes.chargementImpossible)
            }
        }
    }

    /// Apparition de l'écran : premier chargement, ou relance après une tâche annulée ; un écran chargé
    /// garde son brouillon, un échec attend « Réessayer ».
    public func chargerSiNecessaire() async {
        guard case .loading = state else { return }
        await load()
    }

    /// « Vérifier ma session » : revalide la session puis relit si elle reste prête pour cet epoch.
    public func verifierSession(_ session: SessionStore) async {
        await session.start()
        guard session.state.snapshot?.epoch == snapshot.epoch else { return }
        await load()
    }

    // MARK: - Édition

    public func definirCanalGlobal(_ canal: CanalNotification, actif: Bool) {
        modifier { $0.definirCanalGlobal(canal, actif: actif) }
    }

    public func basculer(type: String, canal: CanalNotification) {
        modifier { $0.basculer(type: type, canal: canal) }
    }

    public func definirAlerteSms(_ actif: Bool) {
        modifier { preferences in
            guard preferences.afficheAlerteSms, preferences.alerteSmsModifiable else { return }
            preferences.smsAlertesActives = actif
        }
    }

    private func modifier(_ edition: (inout PreferencesNotifications) -> Void) {
        guard !estEnregistrementEnCours, var preferences else { return }
        let avant = preferences
        edition(&preferences)
        guard preferences != avant else { return }
        state = .loaded(preferences)
        enregistrement = .aucun
    }

    // MARK: - Enregistrement

    public func enregistrer() async {
        guard !estEnregistrementEnCours, let demande = preferences else { return }
        enregistrement = .enCours
        guard let gateways = await controller.gateways(for: snapshot.epoch) else {
            enregistrement = .aucun
            return
        }
        let port = gateways.preferences
        let context = snapshot.context
        let delai = controller.resolutionTimeout
        do {
            let relu = try await bounded(timeout: delai) { try await port.enregistrer(demande, context: context) }
            guard await controller.epoch == snapshot.epoch else { return }
            state = .loaded(relu)
            let concordance = relu.concordance(avec: demande)
            if !concordance.generales {
                enregistrement = .echec(PreferencesTextes.echecEnregistrement)
            } else if !concordance.alerteSms {
                enregistrement = .partiel(PreferencesTextes.echecPartielAlerteSms)
            } else {
                enregistrement = .enregistre
            }
        } catch {
            guard await controller.epoch == snapshot.epoch else { return }
            let jolene = error as? JoleneError
            if error is CancellationError || jolene?.kind == .cancelled {
                // Vue fermée pendant l'envoi : rien n'est annoncé ; la prochaine ouverture relit le serveur.
                enregistrement = .aucun
                return
            }
            sessionExpired = jolene?.kind == .unauthorized
            enregistrement = .echec(jolene?.message ?? PreferencesTextes.echecEnregistrement)
            // Issue inconnue (délai dépassé, réseau) : le serveur a peut-être agi. Relecture, jamais de renvoi ;
            // si elle échoue aussi, le brouillon reste affiché.
            if jolene?.kind == .network {
                if let relu = try? await bounded(timeout: delai, { try await port.lire(context: context) }),
                   await controller.epoch == snapshot.epoch {
                    state = .loaded(relu)
                }
            }
        }
    }
}
