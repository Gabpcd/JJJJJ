import Foundation
import Combine

/// Point d'extension des liens d'inscription (lot 3, T7) pour le coordinateur de liens de L1-T10 / T3b, absent de
/// la base du lot 3 (`DECISIONS_LOT3.md`, « T3 livrée en deux temps » et section T7) : ces liens sont consommés
/// **hors de l'espace prêt** (écran de connexion, aiguillage d'onboarding), comme la connexion et le reset ; le
/// coordinateur y dépose la `DestinationLien` reçue (Universal Link, `-JOLENE_OPEN_URL`) et `RootView` présente :
/// - `/inscription/confirmer` → écran de confirmation (une demande par lien reçu, au-dessus de tout état) ;
/// - `/inscription/soignant` et `/inscription/reprendre` → « Créer un compte » (profession du lien pré-remplie)
///   ou aiguillage d'onboarding, selon la session.
/// Seule la **destination** est lue (`DestinationLien.destination`) : une page dont l'écran n'est pas livré
/// (`/inscription/completer` avant T8) reste un renvoi web et n'est pas consommée ici. Rien n'est journalisé :
/// les identifiants du lien (`token_hash`, `code`, jetons) ne sont portés que par `AuthCallbackCredentials`,
/// dont la description est masquée.
@MainActor
public final class BoiteLiensInscription: ObservableObject {
    /// Confirmation à présenter ; `id` distingue deux liens successifs (une nouvelle tentative par lien reçu).
    public struct Confirmation: Identifiable, Equatable, Sendable {
        public let id: Int
        public let credentials: AuthCallbackCredentials?
    }

    @Published public private(set) var confirmation: Confirmation?
    @Published public private(set) var inscription: EtapeInscription?
    private var compteur = 0

    public init() {}

    /// Vrai si le lien est un lien d'inscription consommé hors de l'espace (le coordinateur ne le présente pas
    /// lui-même) ; faux pour toute autre destination.
    @discardableResult
    public func recevoir(_ lien: DestinationLien) -> Bool {
        switch lien.destination {
        case .confirmerInscription(let credentials):
            compteur += 1
            confirmation = Confirmation(id: compteur, credentials: credentials)
            return true
        case .inscription(let etape):
            inscription = etape
            return true
        default:
            return false
        }
    }

    public func retirerConfirmation() { confirmation = nil }
    public func retirerInscription() { inscription = nil }
}
