import Foundation

/// Réglage de mise en veille de l'écran (`UIApplication.isIdleTimerDisabled` dans l'app, double en test). Le cœur ne
/// dépend pas d'UIKit : l'app conforme `UIApplication` (`Jolene/Composition/VeilleEcran.swift`).
@MainActor
public protocol IdleTimerSetting: AnyObject {
    var isIdleTimerDisabled: Bool { get set }
}

/// Écran maintenu allumé pendant l'affichage du code de pointage (lot 5, T7 ; `LOT5_PLAN.md` §2.6) : l'établissement
/// présente le code ou le QR au soignant, l'écran ne doit pas se verrouiller entre deux pointages.
///
/// Demandes comptées par demandeur (idempotentes : une apparition répétée ne compte qu'une fois) ; la veille est
/// désactivée tant qu'une demande reste ouverte et rétablie à la dernière libération, à la valeur trouvée avant la
/// première demande (jamais forcée à `false` si un autre réglage l'avait déjà désactivée). L'écran libère sa demande à la
/// disparition, en arrière-plan (`scenePhase != .active`) et dès que le code n'est plus affiché.
@MainActor
public final class IdleTimerController {
    private let reglage: IdleTimerSetting
    private var demandes: Set<String> = []
    private var valeurAvantDemandes: Bool?

    public init(reglage: IdleTimerSetting) {
        self.reglage = reglage
    }

    /// Vrai tant qu'au moins un demandeur garde l'écran allumé.
    public var veilleDesactivee: Bool { !demandes.isEmpty }

    /// Garde l'écran allumé pour `demandeur` (sans effet s'il le demande déjà).
    public func desactiverVeille(demandeur: String) {
        guard !demandes.contains(demandeur) else { return }
        if demandes.isEmpty {
            valeurAvantDemandes = reglage.isIdleTimerDisabled
            reglage.isIdleTimerDisabled = true
        }
        demandes.insert(demandeur)
    }

    /// Libère la demande de `demandeur` ; la veille est rétablie quand plus aucune demande ne reste.
    public func retablirVeille(demandeur: String) {
        guard demandes.remove(demandeur) != nil, demandes.isEmpty else { return }
        reglage.isIdleTimerDisabled = valeurAvantDemandes ?? false
        valeurAvantDemandes = nil
    }

    /// Applique l'état voulu pour `demandeur` (raccourci de l'écran).
    public func appliquer(veilleDesactivee: Bool, demandeur: String) {
        if veilleDesactivee { desactiverVeille(demandeur: demandeur) } else { retablirVeille(demandeur: demandeur) }
    }
}
