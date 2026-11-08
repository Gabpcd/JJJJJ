import Foundation

/// Carte « Autorisation du téléphone » (lot 3, T4 ; reprise par les préférences de T6) : état système
/// des notifications de l'appareil et de son enregistrement. Textes **verbatim** de
/// `src/pages/PageParametresNotifications.tsx` (HARD STOP n°4), choisis comme le web l.147-155 et
/// l.341-352 :
/// - lecture en cours → l.343 ;
/// - autorisé (ou provisoire) et enregistrement confirmé → l.346, ou l.347 si les préférences (T6)
///   savent le canal push coupé dans Jolene ;
/// - autorisé sans enregistrement confirmé → l.352 (`registration-error`) ;
/// - jamais demandé → l.349 (`prompt`, affiché par le web quel que soit le canal) ;
/// - refusé → l.350 (`denied`).
/// `indisponible` (l.351) est repris pour T6 ; la lecture native de l'autorisation ne peut pas échouer.
public enum EtatNotificationsAppareil {
    /// `PageParametresNotifications.tsx` l.341.
    public static let titre = "Autorisation du téléphone"
    /// l.343.
    public static let verification = "Vérification de l’autorisation système…"
    /// l.346.
    public static let autorisees = "Les notifications sont autorisées sur cet appareil."
    /// l.347.
    public static let canalDesactive = "Le téléphone les autorise, mais le canal est désactivé dans Jolene."
    /// l.349.
    public static let aAutoriser = "Le canal est actif dans Jolene, mais le téléphone doit encore autoriser les notifications."
    /// l.350.
    public static let bloquees = "Les notifications sont bloquées par le téléphone. Réactivez Jolene dans les réglages système."
    /// l.351.
    public static let indisponible = "L’état système n’a pas pu être vérifié. Réessayez dans quelques instants."
    /// l.352.
    public static let nonEnregistre =
        "Les notifications sont autorisées, mais cet appareil n’a pas pu être enregistré. Vérifiez votre connexion puis réessayez."
    /// Titre de la section du hub : entrée « Notifications » de la section « Réglages » du web
    /// (`src/pages/MonCompteSoignant.tsx` l.115).
    public static let sectionHub = "Notifications"

    /// Message de la carte. `autorisation` nil : lecture en cours. `canalPush` : canal push de Jolene,
    /// connu des préférences seulement (T6) ; nil ailleurs.
    public static func message(autorisation: AutorisationPush?, enregistrementConfirme: Bool,
                               canalPush: Bool? = nil) -> String {
        guard let autorisation else { return verification }
        switch autorisation {
        case .accordee, .provisoire:
            guard enregistrementConfirme else { return nonEnregistre }
            return canalPush == false ? canalDesactive : autorisees
        case .nonDemandee:
            return aAutoriser
        case .refusee:
            return bloquees
        }
    }

    /// Ton de la carte (web l.328-332 : succès pour `granted`, alerte sinon).
    public static func estPositif(autorisation: AutorisationPush?, enregistrementConfirme: Bool) -> Bool {
        (autorisation?.permetEnregistrement ?? false) && enregistrementConfirme
    }
}
