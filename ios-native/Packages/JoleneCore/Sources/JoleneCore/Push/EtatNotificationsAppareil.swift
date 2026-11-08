import Foundation

/// Carte « Autorisation du téléphone » (lot 3, T4 ; hôte définitif : les préférences de T6, voir
/// `REVUES_LOT3.md`, section L3-T4) : état système des notifications de l'appareil et de son
/// enregistrement. Textes **verbatim** de `src/pages/PageParametresNotifications.tsx` (HARD STOP n°4),
/// choisis comme le web l.147-155 et l.341-352 :
/// - autorisation pas encore lue → aucune carte (la lecture native est immédiate) ;
/// - autorisé (ou provisoire), enregistrement en cours de vérification → l.343 ;
/// - autorisé et enregistrement confirmé → l.346, ou l.347 si les préférences (T6) savent le canal push
///   coupé dans Jolene. Canal inconnu (hub provisoire) → l.346 : le web n'affiche l.346 que si
///   `global.canal_push` est vrai (sinon l.347) ; écart du hub consigné dans `REVUES_LOT3.md` (section L3-T4),
///   levé par T6 (`canalPush` lu des préférences) ;
/// - autorisé sans enregistrement confirmé → l.352 (`registration-error`) ;
/// - jamais demandé → l.349 (`prompt`) **seulement si le canal push est connu actif** : le texte affirme
///   « Le canal est actif dans Jolene » ; canal inconnu (hub) ou coupé → aucune carte (le web affiche l.349
///   quel que soit le canal : écart assumé, à confirmer par T6) ;
/// - refusé → l.350 (`denied`).
/// `indisponible` (l.351) est repris pour T6 ; la lecture native de l'autorisation ne peut pas échouer.
///
/// Bouton « Ouvrir les réglages » (`ouvrirReglages`, sans source web) seulement quand un réglage système
/// est utile : refusé, ou autorisé sans enregistrement confirmé. Absent quand l'autorisation n'a jamais été
/// demandée (Réglages n'a pas d'entrée Notifications tant que l'app n'a rien demandé ; l'activation relève
/// du pré-prompt de T5 et des préférences de T6) et quand tout est en ordre (superflu).
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
    /// Libellé du bouton qui ouvre la page Notifications de l'app dans Réglages
    /// (`UIApplication.openNotificationSettingsURLString`). **Sans source web** (le web n'ouvre pas les
    /// réglages système) : nommé au §1.1 du blueprint, action non juridique, à relire par Gabrielle
    /// (`DECISIONS_LOT3.md`, HARD STOP n°4) ; épinglé par `EtatNotificationsAppareilTests`.
    public static let ouvrirReglages = "Ouvrir les réglages"

    /// Message de la carte, nil quand elle ne doit rien affirmer (aucune carte).
    /// - Parameters:
    ///   - autorisation: nil tant que l'autorisation système n'est pas lue.
    ///   - enregistrementConfirme: nil tant que l'enregistrement n'est pas vérifié (autorisé seulement).
    ///   - canalPush: canal push de Jolene, connu des préférences seulement (T6) ; nil dans le hub.
    public static func message(autorisation: AutorisationPush?, enregistrementConfirme: Bool?,
                               canalPush: Bool? = nil) -> String? {
        guard let autorisation else { return nil }
        switch autorisation {
        case .accordee, .provisoire:
            guard let enregistrementConfirme else { return verification }
            guard enregistrementConfirme else { return nonEnregistre }
            return canalPush == false ? canalDesactive : autorisees
        case .nonDemandee:
            return canalPush == true ? aAutoriser : nil
        case .refusee:
            return bloquees
        }
    }

    /// Vrai quand « Ouvrir les réglages » sert à quelque chose : refusé, ou autorisé sans enregistrement confirmé.
    public static func proposeReglages(autorisation: AutorisationPush?, enregistrementConfirme: Bool?) -> Bool {
        switch autorisation {
        case .refusee: return true
        case .accordee, .provisoire: return enregistrementConfirme == false
        case .nonDemandee, nil: return false
        }
    }

    /// Ton de la carte (web l.328-332 : succès pour `granted`, alerte sinon).
    public static func estPositif(autorisation: AutorisationPush?, enregistrementConfirme: Bool?) -> Bool {
        (autorisation?.permetEnregistrement ?? false) && enregistrementConfirme == true
    }
}
