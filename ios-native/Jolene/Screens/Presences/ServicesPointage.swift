import SwiftUI
import JoleneCore
import JoleneDesign

/// Services de la page Présences partagés par ses zones de pointage (lot 2, T4b), posés par `PresencesScreen`
/// (`.environment(\.servicesPointage, …)`) et transmis par `BlocPointageView` dans `ZonePointageContexte` :
/// - le consentement GPS de l'utilisateur (un seul modèle pour la page : feuille, bandeau, retour) ;
/// - l'état du réseau (bandeau hors ligne, boutons désactivés) ;
/// - la relecture de l'instantané des présences après un pointage enregistré (revue fraîche de T4a, m1 : le web relit
///   `presences-soignant` après chaque succès, `PointageRotatifSoignant.tsx` l.145-149).
struct ServicesPointage: Sendable {
    let consentement: ConsentementGpsModel
    let reseau: EtatReseauModel
    let recharger: @MainActor @Sendable () async -> Void
}

private struct ServicesPointageKey: EnvironmentKey {
    static let defaultValue: ServicesPointage? = nil
}

extension EnvironmentValues {
    /// Services de la page Présences, nil hors de `PresencesScreen`.
    var servicesPointage: ServicesPointage? {
        get { self[ServicesPointageKey.self] }
        set { self[ServicesPointageKey.self] = newValue }
    }
}

extension LibellesPresences.Pointage.Ton {
    /// Ton de l'encart (`InlineNotice`) : porté par l'icône et un préfixe vocalisé, jamais par la couleur seule.
    var inlineNotice: InlineNotice.Tone {
        switch self {
        case .succes: return .success
        case .info: return .info
        case .attention: return .warning
        case .erreur: return .error
        }
    }
}
