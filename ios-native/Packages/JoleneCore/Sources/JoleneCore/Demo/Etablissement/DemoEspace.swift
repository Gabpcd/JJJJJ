import Foundation

/// Espace ouvert par défaut dans le monde démo (lot 5, T2a ; §2.10, D20). `.soignant` est le monde du
/// lot 0, inchangé. `.etablissement` ajoute le compte établissement fictif (`demo-etablissement`, sur
/// `demo-etab-1`) dans la variante demandée ; le compte soignant fictif y reste joignable par son propre
/// email, pour prouver la frontière d'epoch entre deux espaces dans la même session.
public enum DemoEspace: Equatable, Sendable {
    case soignant
    case etablissement(DemoEtablissementWorld.Configuration)

    /// Email du compte établissement fictif (`demo-etablissement.json`, vérifié par test).
    public static let emailEtablissement = "etablissement-demonstration@example.invalid"

    /// Compte ouvert pour `email` dans le monde établissement : l'email du soignant fictif ouvre le
    /// soignant, tout autre email le compte établissement de la variante (comme le lot 0 accepte tout email).
    static func compte(email: String, configuration: DemoEtablissementWorld.Configuration) throws -> AuthenticatedUser {
        if let soignant = DemoWorld.context.email, email.lowercased() == soignant.lowercased() {
            return DemoWorld.user
        }
        return try DemoEtablissementWorld.utilisateur(configuration)
    }
}

/// Arguments de lancement DEBUG de l'espace démo (`-JOLENE_DEMO_ESPACE etablissement`,
/// `-JOLENE_DEMO_ROLE_ETAB <rôle>`, `-JOLENE_DEMO_LEGACY 1`, `-JOLENE_DEMO_BLOCAGE 1`), lus par
/// `AppContainer` en mode démo seulement. Une valeur absente ou illisible garde l'espace du lot 0 ; les
/// variantes sont ignorées sans `-JOLENE_DEMO_ESPACE etablissement`. `-JOLENE_POLL_INTERVAL` appartient à T7.
public enum DemoEspaceLancement {
    public static let argumentEspace = "-JOLENE_DEMO_ESPACE"
    public static let argumentRole = "-JOLENE_DEMO_ROLE_ETAB"
    public static let argumentLegacy = "-JOLENE_DEMO_LEGACY"
    public static let argumentBlocage = "-JOLENE_DEMO_BLOCAGE"

    public static func espace(arguments: [String]) -> DemoEspace {
        guard valeur(argumentEspace, dans: arguments)?.lowercased() == "etablissement" else { return .soignant }
        var configuration = DemoEtablissementWorld.Configuration()
        if let role = valeur(argumentRole, dans: arguments)?.trimmingCharacters(in: .whitespacesAndNewlines), !role.isEmpty {
            configuration.role = RoleEtab(brut: role)
        }
        configuration.legacy = valeur(argumentLegacy, dans: arguments) == "1"
        configuration.blocage = valeur(argumentBlocage, dans: arguments) == "1"
        return .etablissement(configuration)
    }

    private static func valeur(_ argument: String, dans arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}

/// Rôle démo selon l'identité de la session courante (équivalent de `fn_get_my_role`, l.38216) : le
/// compte établissement fictif est servi en `ADMIN_ETABLISSEMENT` sur `demo-etab-1`, y compris en
/// variante legacy (le serveur résout `mon_etablissement_id()` pour un legacy réel, correction 2) ; le
/// soignant fictif en `SOIGNANT`. Sans session, aucun rôle n'est servi.
public struct DemoRoleEspaceGateway: RolePort {
    private let identite: @Sendable () async -> String?

    public init(identite: @escaping @Sendable () async -> String?) {
        self.identite = identite
    }

    public func currentRole() async throws -> RoleResult {
        let utilisateur = await identite()
        if utilisateur == DemoEtablissementWorld.userId {
            let etablissement = try DemoFixtures.loadEtablissementDemo().etablissement
            return RoleResult(role: UserRole.adminEtablissement.rawValue, etablissementId: etablissement.id)
        }
        if utilisateur == DemoWorld.context.userId {
            return RoleResult(role: UserRole.soignant.rawValue, etablissementId: nil)
        }
        throw JoleneError(.unauthorized, DemoEtablissementWorld.messageDemoSeulement)
    }
}

public extension DemoWorld {
    /// Ports du monde démo pour l'espace demandé (surcharge additive ; `gateways()` et
    /// `gateways(drapeaux:)` du lot 0 et du lot 1 sont inchangés). Dans l'espace établissement, auth,
    /// rôle et ports établissement partagent la même session démo (une seule identité, comme un JWT).
    static func gateways(espace: DemoEspace, drapeaux: [String: Bool] = [:]) -> Gateways {
        var gateways = DemoWorld.gateways(drapeaux: drapeaux)
        guard case let .etablissement(configuration) = espace else { return gateways }
        let auth = DemoAuthGateway(compte: { email in try DemoEspace.compte(email: email, configuration: configuration) })
        let identite: @Sendable () async -> String? = { try? await auth.restoreSession()?.id }
        gateways.auth = auth
        gateways.role = DemoRoleEspaceGateway(identite: identite)
        gateways.etablissement = DemoEtablissementWorld.gateways(configuration: configuration, identite: identite)
        return gateways
    }
}
