import Foundation

/// Porte d'un écran natif soumis à un coupe-circuit D-FLAGS (`EcranNatif`, `docs/mobile-swift/DECISIONS_LOT2.md`) :
/// trois états, pour que l'écran natif ne soit construit — et ne lance ses lectures réseau — qu'une fois le drapeau lu
/// (revue B8 n°1 de L2-T10, m3 : avec un booléen initialisé à vrai, l'écran des contrats partait lire le serveur avant
/// que le drapeau ne dise s'il devait exister). Le fail-open de la décision 15 est conservé : un drapeau absent ou
/// illisible rend son défaut (`FlagsPolicy.defautFailOpen`, la passerelle ne lève jamais), donc l'écran natif.
public enum PorteEcranNatif: Equatable, Sendable {
    /// Drapeau pas encore lu : vue neutre de chargement, ni écran natif ni renvoi web.
    case lecture
    /// Drapeau lu à vrai (ou absent, illisible : fail-open) : écran natif.
    case natif
    /// Drapeau lu à faux : renvoi web de l'écran.
    case renvoiWeb

    /// `nil` tant que le drapeau n'est pas lu.
    public init(drapeau: Bool?) {
        switch drapeau {
        case nil: self = .lecture
        case true?: self = .natif
        case false?: self = .renvoiWeb
        }
    }

    /// Lit le drapeau de `ecran`. Sans drapeaux (aucune passerelle pour l'epoch de l'écran), fail-open comme la
    /// passerelle et comme la lecture d'avant la porte à trois états : l'écran natif.
    public static func lire(_ ecran: EcranNatif, flags: (any FlagsPort)?) async -> PorteEcranNatif {
        guard let flags else { return .natif }
        return PorteEcranNatif(drapeau: await flags.ecranActif(ecran))
    }
}
