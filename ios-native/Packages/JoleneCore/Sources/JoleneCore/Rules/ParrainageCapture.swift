import Foundation

/// Capture du code de parrainage d'un Universal Link entrant (`?ref=` ou `?parrain=`, sur tout lien : le web capte
/// depuis n'importe quelle page, `src/lib/attribution.ts` l.35-46), blueprint `docs/mobile-swift/LOT4_PLAN.md` §2.5,
/// livrée par L4-T6 (D14).
///
/// Un lien est une source non fiable : le code est lu seulement sur un lien que le routeur accepte (hôte, schéma et port
/// de `LinkRouter`), mis en majuscules puis validé par la forme exacte du web (`InscriptionSoignant.tsx` l.113-115,
/// `/^[A-Z0-9-]{4,16}$/i` puis `toUpperCase()`) ; les codes d'établissement `ETB-` sont ignorés (`attribution.ts`
/// l.29-31, `useAppliquerParrainage.ts` l.37). Un code hors forme est ignoré sans erreur visible : il n'est ni stocké,
/// ni envoyé, ni journalisé. Seul appelant dans l'app : `VerrousLot4.codeParrainageACapturer(depuis:)`.
public enum ParrainageCapture {
    /// Fenêtre d'application après capture (`FENETRE_JOURS`, `useAppliquerParrainage.ts` l.19).
    public static let fenetreJours = 30

    /// Vrai depuis L4-T6 : capture et application branchées (`VerrousLot4.parrainageBranche`).
    public static let estLivree = true

    /// Paramètres lus, dans l'ordre du web (`params.get('ref') || params.get('parrain')`, `attribution.ts` l.39).
    public static let parametres = ["ref", "parrain"]

    /// Code capturé et son instant de capture (stocké par appareil, `ParrainageStockage`).
    public struct Capture: Equatable, Sendable, Codable {
        public var code: String
        public var captureLe: Date

        public init(code: String, captureLe: Date) {
            self.code = code
            self.captureLe = captureLe
        }
    }

    /// Code normalisé (majuscules), ou `nil` hors de la forme du web ou pour un code d'établissement.
    /// Seuls les caractères ASCII `A-Z`, `0-9` et `-` sont admis, 4 à 16 : aucun espace, aucune ponctuation.
    public static func normaliser(_ brut: String) -> String? {
        let code = String(brut.unicodeScalars.map { scalaire -> Character in
            ("a"..."z").contains(scalaire) ? Character(Unicode.Scalar(scalaire.value - 32)!) : Character(scalaire)
        })
        let scalaires = code.unicodeScalars
        guard (4...16).contains(scalaires.count),
              scalaires.allSatisfy({ ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }) else { return nil }
        guard !code.hasPrefix("ETB-") else { return nil }
        return code
    }

    /// Code de parrainage porté par le lien, normalisé ; `nil` sans code valide ou sur un lien que le routeur refuse.
    public static func code(depuis url: URL) -> String? {
        guard DestinationLien(url: url) != nil,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        // `get('ref') || get('parrain')` : premier paramètre non vide, dans l'ordre.
        for nom in parametres {
            if let valeur = items.first(where: { $0.name == nom })?.value, !valeur.isEmpty { return normaliser(valeur) }
        }
        return nil
    }

    /// Vrai si la capture peut encore être appliquée à `maintenant` : moins de 30 jours révolus, jamais dans le futur
    /// (`age >= 0 && age < FENETRE_JOURS * 86_400_000`, `useAppliquerParrainage.ts` l.43-45).
    public static func estApplicable(_ capture: Capture, maintenant: Date) -> Bool {
        let age = maintenant.timeIntervalSince(capture.captureLe)
        return age >= 0 && age < TimeInterval(fenetreJours) * 86_400
    }
}
