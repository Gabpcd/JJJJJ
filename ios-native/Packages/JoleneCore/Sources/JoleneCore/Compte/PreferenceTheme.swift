import Foundation
import Combine

/// Thème de l'app (lot 3, T11, D16) : Système, Clair ou Sombre, par appareil, défaut Système. Le web n'a qu'un
/// bouton « Passer en thème clair / sombre » (`MonCompteSoignant.tsx` l.116-122, `useTheme.ts`) ; le natif suit
/// la décision D16. Libellés natifs sans équivalent web (non juridiques), listés dans `DECISIONS_LOT3.md`.
public enum ChoixTheme: String, CaseIterable, Sendable {
    case systeme, clair, sombre

    /// Titre du groupe (vocalisé par `SegmentedChoice`, affiché par l'écran).
    public static let titreGroupe = "Thème"

    public var libelle: String {
        switch self {
        case .systeme: return "Système"
        case .clair: return "Clair"
        case .sombre: return "Sombre"
        }
    }
}

/// Préférence de thème de l'appareil, appliquée à la racine de l'app (`ThemeRacine`, cible app). Stockage :
/// `UserDefaults` en staging et production, mémoire vive en démo (`AppContainer`), clé `jolene.theme` sans
/// identifiant de compte (elle survit à la déconnexion et à la purge d'un compte supprimé). Une valeur absente
/// ou illisible vaut Système.
@MainActor
public final class PreferenceThemeModel: ObservableObject {
    public static let cle = "jolene.theme"

    @Published public private(set) var choix: ChoixTheme
    private let stockage: StockageAppareilPort

    public init(stockage: StockageAppareilPort) {
        self.stockage = stockage
        self.choix = stockage.lire(Self.cle).flatMap(ChoixTheme.init(rawValue:)) ?? .systeme
    }

    public func choisir(_ choix: ChoixTheme) {
        stockage.ecrire(Self.cle, choix.rawValue)
        self.choix = stockage.lire(Self.cle).flatMap(ChoixTheme.init(rawValue:)) ?? choix
    }
}
