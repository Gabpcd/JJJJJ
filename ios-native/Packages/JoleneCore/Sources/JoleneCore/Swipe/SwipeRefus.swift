import Foundation

/// Refus de `fn_enregistrer_swipe` (lot 4, T3a ; `LOT4_PLAN.md` §2.4, fiche `CONTRATS_RPC_SOIGNANT.md`) : la RPC
/// répond `{ok:false, error:<code technique>}` en HTTP 200. Le web affiche le code brut (point ouvert, DECISIONS_LOT4
/// précision 10) ; le natif le traduit par cette table de libellés produit, vouvoyés, sans portée juridique.
/// Les messages rédigés par le serveur (« Vous avez déjà candidaté à cette mission », refus documentaire libéral,
/// conflit de planning) ne sont pas des codes : restitués verbatim (DECISIONS_LOT4 précision 4).
/// `auth_required` n'est pas un refus : `.unauthorized` (session expirée), traité avant cette table.
public enum SwipeRefus {
    /// Six codes techniques du corps SQL, hors `auth_required`.
    public static let libelles: [String: String] = [
        "direction_invalide": "Cette action n'a pas pu être enregistrée. Réessayez.",
        "mission_indisponible": "Cette mission n'est plus disponible.",
        "profil_introuvable": "Votre profil soignant est introuvable. Reconnectez-vous puis réessayez.",
        "profession_incompatible": "Cette mission ne correspond pas à votre profession ou à votre spécialité.",
        "acces_refuse": "Cette mission n'est pas accessible depuis votre compte.",
        "mission_deja_swipee": "Vous avez déjà répondu à cette mission.",
    ]

    /// Refus définitifs pour cette mission : la carte quitte le paquet après le message et n'y revient pas de la session
    /// (`SwipeModel` l'écarte aussi des paquets relus), au lieu d'y rester bloquée en tête.
    /// - `mission_indisponible` (sortie de `OUVERTE`), `mission_deja_swipee` (ligne `swipes` posée) : le paquet relu ne la
    ///   servirait plus ;
    /// - `acces_refuse` (établissement qui a exclu le soignant), `profession_incompatible` : refusés par
    ///   `fn_enregistrer_swipe` **avant** l'écriture de la ligne `swipes`, alors que `fn_obtenir_missions_swipe` ne filtre
    ///   pas les exclusions (`fn_soignant_eligible_mission` n'appelle pas `fn_est_exclu`, revue B8 de #1165, m1) : le
    ///   serveur la resservirait à chaque paquet. Correctif backend en suivi (B9, `LOT4_PLAN.md` écart de T3a).
    public static let horsPaquet: Set<String> = ["mission_indisponible", "mission_deja_swipee", "acces_refuse", "profession_incompatible"]

    /// Repli quand le serveur ne dit rien de lisible.
    public static let repli = "Votre réponse à cette mission n'a pas pu être enregistrée. Réessayez."

    /// Issue d'un `error` serveur : code connu → `(code, libellé)` ; message rédigé → `(nil, message verbatim)` ;
    /// absent → `(nil, repli)`.
    public static func traduire(_ erreur: String?) -> (code: String?, message: String) {
        guard let erreur, !erreur.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return (nil, repli) }
        if let libelle = libelles[erreur] { return (erreur, libelle) }
        return (nil, erreur)
    }

    public static func estHorsPaquet(_ code: String?) -> Bool {
        code.map(horsPaquet.contains) ?? false
    }
}
