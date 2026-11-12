import Foundation

/// Onglets de l'espace soignant prêt (`MainTabView`), calqués sur `NAV_SOIGNANT_MOBILE` de
/// `src/components/BarreNavigation.tsx` (l.33-37), dans l'ordre de la barre.
///
/// Enum dédié (lot 3, T5 ; revue L3-T5, m9) : les drapeaux d'écran `EcranNatif` (`Lot1Ports.swift`) ne sont pas
/// des onglets — le lot 2 les étend aux présences, documents et contrats — ; une cible de navigation
/// (`CibleNotification.onglet`) ou la sélection de la barre ne peut donc valoir qu'un de ces cinq onglets.
public enum OngletEspace: String, CaseIterable, Hashable, Sendable {
    case accueil, explorer, missions, revenus, profil
}
