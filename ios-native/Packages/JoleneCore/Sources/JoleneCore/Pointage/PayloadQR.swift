import Foundation

/// Lecture du QR affiché par l'établissement (`AffichageCodeRotatifEtab.tsx` l.284 : le QR
/// encode `code_pointage_actif`, six chiffres). Règle native, volontairement plus stricte que le
/// web (`PointageRotatifSoignant.tsx` l.186 garde les six premiers chiffres d'un texte quelconque) :
/// un jeton du système de pointage ① ou un QR étranger ne produit jamais un code (lot 2, Q3).
/// Le code décodé est envoyé tel quel à `fn_scanner_code_pointage` ; le serveur fait foi.
public enum PayloadQR {
    /// Six chiffres ASCII exactement après suppression des espaces et retours de bord ; sinon `nil`
    /// (l'écran propose alors la saisie manuelle du code).
    public static func codePointage(depuis payload: String?) -> String? {
        guard let payload else { return nil }
        let code = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let scalaires = code.unicodeScalars
        guard scalaires.count == 6, scalaires.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
        return code
    }
}
