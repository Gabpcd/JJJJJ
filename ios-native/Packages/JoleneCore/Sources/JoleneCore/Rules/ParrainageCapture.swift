import Foundation

/// Capture du code de parrainage d'un Universal Link entrant (`?ref=` ou `?parrain=`, sur tout lien : le web capte
/// depuis n'importe quelle page, `src/lib/attribution.ts` l.35-46), blueprint `docs/mobile-swift/LOT4_PLAN.md` §2.5.
///
/// **Stub de L4-T1** (signature seulement) : posé pour que T1c branche la capture dans le coordinateur de liens sans
/// attendre T6, qui l'implémente (normalisation en majuscules, format `^[A-Z0-9-]{4,16}$` comme
/// `InscriptionSoignant.tsx` l.113, codes « ETB- » ignorés, fenêtre de 30 jours sur `ClockPort`, marqueur par
/// userId + code). Tant que T6 n'est pas livrée, aucune capture n'a lieu : `code(depuis:)` rend `nil` et
/// `estLivree` vaut `false` — jamais un code supposé, jamais une application silencieuse.
public enum ParrainageCapture {
    /// Fenêtre d'application après capture (`FENETRE_JOURS`, `useAppliquerParrainage.ts` l.19).
    public static let fenetreJours = 30

    /// Vrai quand T6 a livré la capture.
    public static let estLivree = false

    /// Code capturé et son instant de capture (stocké par userId en `UserDefaults` par T6).
    public struct Capture: Equatable, Sendable, Codable {
        public var code: String
        public var captureLe: Date

        public init(code: String, captureLe: Date) {
            self.code = code
            self.captureLe = captureLe
        }
    }

    /// Code de parrainage porté par le lien, normalisé ; `nil` sans code valide. Stub : toujours `nil` (T6).
    public static func code(depuis url: URL) -> String? {
        nil
    }

    /// Vrai si la capture peut encore être appliquée à `maintenant`. Stub : toujours `false` (T6).
    public static func estApplicable(_ capture: Capture, maintenant: Date) -> Bool {
        false
    }
}
