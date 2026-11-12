import Foundation

/// Arguments de lancement du push, honorés en build DEBUG seulement par `AppContainer` (comme
/// `-JOLENE_MODE`, `JOLENE_FORCE_BAD_KEY`) ; jamais lus en Release.
///
/// - `-JOLENE_PUSH_AUTORISATION nonDemandee|accordee|refusee|provisoire` : état d'autorisation du double
///   `DemoPushPermission` (monde démo, blueprint §2.7) ; aucune feuille système.
/// - `-JOLENE_PUSH_TOKEN_FACTICE <hex>` : token factice de la preuve STAGING (§3 T4 critère, T16), relu
///   dans `tokens_push` (`actif` vrai puis faux) ; mode `staging` seulement, autorisation simulée accordée.
public enum PushLancement {
    public static let argumentAutorisation = "-JOLENE_PUSH_AUTORISATION"
    public static let argumentTokenFactice = "-JOLENE_PUSH_TOKEN_FACTICE"
    /// Un token APNs fait 32 octets ; la fonction serveur accepte jusqu'à 4096 caractères (2048 octets).
    public static let octetsTokenFactice: ClosedRange<Int> = 32...2048

    public static func autorisation(arguments: [String]) -> AutorisationPush? {
        valeur(apres: argumentAutorisation, dans: arguments).flatMap(AutorisationPush.init(rawValue:))
    }

    /// Octets du token factice, ou nil si la valeur n'est pas un hexadécimal de longueur paire,
    /// entre 32 et 2048 octets, sans espace.
    public static func tokenFactice(arguments: [String]) -> Data? {
        guard let hex = valeur(apres: argumentTokenFactice, dans: arguments), hex.count % 2 == 0,
              octetsTokenFactice.contains(hex.count / 2) else { return nil }
        var octets: [UInt8] = []
        octets.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let suivant = hex.index(index, offsetBy: 2)
            guard let octet = UInt8(hex[index..<suivant], radix: 16),
                  hex[index..<suivant].allSatisfy(\.isHexDigit) else { return nil }
            octets.append(octet)
            index = suivant
        }
        return Data(octets)
    }

    private static func valeur(apres argument: String, dans arguments: [String]) -> String? {
        guard let position = arguments.firstIndex(of: argument), arguments.indices.contains(position + 1) else { return nil }
        return arguments[position + 1]
    }
}
