import Foundation

/// Carte « Autorisation du téléphone » (lot 3, T4 ; hôte définitif depuis T6 : l'écran des préférences de
/// notifications, une seule surface — `REVUES_LOT3.md`, section L3-T4) : état système des notifications de
/// l'appareil et de son enregistrement. Textes **verbatim** de `src/pages/PageParametresNotifications.tsx`
/// (HARD STOP n°4), choisis comme le web l.147-155, l.180-183 et l.341-352 :
/// - autorisation pas encore lue → aucune carte (la lecture native est immédiate) ;
/// - activation en échec (web `unavailable`, l.180-182) → l.351, jusqu'à la prochaine lecture système ;
/// - autorisé (ou provisoire), enregistrement en cours de vérification → l.343 ;
/// - autorisé et enregistrement confirmé → l.346, ou l.347 si les préférences savent le canal push coupé
///   dans Jolene (canal inconnu → l.346 ; le web n'affiche l.346 que si `global.canal_push` est vrai, ce que
///   l'écran des préférences de T6 fournit toujours) ;
/// - autorisé sans enregistrement confirmé → l.352 (`registration-error`) ;
/// - jamais demandé → l.349 (`prompt`) **seulement si le canal push est connu actif** : le texte affirme
///   « Le canal est actif dans Jolene » ; canal coupé → aucune carte (le web affiche l.349 quel que soit le
///   canal : écart assumé par T6, `DECISIONS_LOT3.md`, section T6) ;
/// - refusé → l.350 (`denied`).
///
/// Action de la carte (`action`, T6 ; mineur 4 de la revue B8 de T4) :
/// - « Activer sur cet appareil » (`activerSurAppareil`, l.365) là où le web propose sa relance (l.356) :
///   jamais demandé, enregistrement en échec ou état indisponible, **et** canal push connu actif. Elle demande
///   l'autorisation au tap seulement (D1 : « plus l'activation depuis Préférences »), puis enregistre
///   l'appareil (`EtatNotificationsAppareilModel.activer`) ;
/// - « Ouvrir les réglages » (`ouvrirReglages`, sans source web) seulement si refusé : seul Réglages peut
///   alors agir. Un enregistrement en échec ne se corrige pas dans Réglages (T4 y proposait Réglages) ;
/// - aucune quand tout est en ordre, pendant une vérification, ou canal push coupé (web l.356).
public enum EtatNotificationsAppareil {
    /// Action proposée sous le message de la carte.
    public enum Action: Equatable, Sendable {
        /// « Activer sur cet appareil » : demande au tap, puis enregistrement.
        case activer
        /// « Ouvrir les réglages » : page Notifications de l'app dans Réglages.
        case ouvrirReglages
    }

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
    /// Libellé du bouton d'activation, l.365 (T6).
    public static let activerSurAppareil = "Activer sur cet appareil"
    /// Libellé du bouton qui ouvre la page Notifications de l'app dans Réglages
    /// (`UIApplication.openNotificationSettingsURLString`). **Sans source web** (le web n'ouvre pas les
    /// réglages système) : nommé au §1.1 du blueprint, action non juridique, à relire par Gabrielle
    /// (`DECISIONS_LOT3.md`, HARD STOP n°4) ; épinglé par `EtatNotificationsAppareilTests`.
    public static let ouvrirReglages = "Ouvrir les réglages"

    /// Message de la carte, nil quand elle ne doit rien affirmer (aucune carte).
    /// - Parameters:
    ///   - autorisation: nil tant que l'autorisation système n'est pas lue.
    ///   - enregistrementConfirme: nil tant que l'enregistrement n'est pas vérifié (autorisé seulement).
    ///   - canalPush: canal push de Jolene, connu des préférences (T6) ; nil s'il est inconnu.
    ///   - indisponible: dernière activation en échec (web `unavailable`), levé par la lecture système suivante.
    public static func message(autorisation: AutorisationPush?, enregistrementConfirme: Bool?,
                               canalPush: Bool? = nil, indisponible: Bool = false) -> String? {
        if indisponible { return Self.indisponible }
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

    /// Action proposée sous le message ; nil : aucun bouton.
    public static func action(autorisation: AutorisationPush?, enregistrementConfirme: Bool?,
                              canalPush: Bool?, indisponible: Bool = false) -> Action? {
        // Web l.356 : relance seulement pour `prompt`, `registration-error` et `unavailable`, canal push actif.
        let relance: Action? = canalPush == true ? .activer : nil
        if indisponible { return relance }
        switch autorisation {
        case nil:
            return nil
        case .refusee:
            return .ouvrirReglages
        case .nonDemandee:
            return relance
        case .accordee, .provisoire:
            return enregistrementConfirme == false ? relance : nil
        }
    }

    /// Ton de la carte (web l.328-332 : succès pour `granted`, alerte sinon).
    public static func estPositif(autorisation: AutorisationPush?, enregistrementConfirme: Bool?,
                                  indisponible: Bool = false) -> Bool {
        !indisponible && (autorisation?.permetEnregistrement ?? false) && enregistrementConfirme == true
    }
}
