import UIKit
import JoleneCore

/// `UIApplication.isIdleTimerDisabled` comme réglage de veille du cœur (lot 5, T7). La logique (demandes comptées,
/// valeur initiale rétablie) vit dans `JoleneCore/Etablissement/Pointage/IdleTimerController.swift`, testée par
/// `swift test` : la cible app n'a pas de tests unitaires. Adaptateur plutôt qu'une conformance d'`UIApplication`
/// (type et protocole importés : conformance rétroactive).
@MainActor
final class ReglageVeilleApplication: IdleTimerSetting {
    var isIdleTimerDisabled: Bool {
        get { UIApplication.shared.isIdleTimerDisabled }
        set { UIApplication.shared.isIdleTimerDisabled = newValue }
    }
}

/// Contrôleur unique de la veille de l'app : un seul propriétaire du réglage, quel que soit le nombre d'écrans.
enum VeilleEcran {
    @MainActor static let controleur = IdleTimerController(reglage: ReglageVeilleApplication())
}
