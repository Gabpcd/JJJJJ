import Foundation

/// Monde démo de l'espace établissement (lot 5 §2.10, D20) : fixtures JSON générées par
/// `scripts/mobile/export-demo-fixtures.mjs` (`demo-etablissement.json`, `demo-etab-permissions.json`,
/// permissions dérivées du `CASE` SQL de `fn_a_permission_etablissement`), horloge fixée du monde démo,
/// aucun réseau. Toute gateway démo refuse un utilisateur autre que `demo-etablissement` (`.demoOnly`,
/// même règle que `DemoWorld`).
///
/// L'établissement démo est le premier établissement fictif du monde soignant (`demo-etab-1`), vu de
/// l'autre côté : un seul nom par identifiant. Les arguments de lancement DEBUG
/// (`-JOLENE_DEMO_ROLE_ETAB`, `-JOLENE_DEMO_LEGACY`, `-JOLENE_DEMO_BLOCAGE`) sont analysés par l'app
/// (T2) et traduits en `Configuration`.
public enum DemoEtablissementWorld {
    public static let userId = "demo-etablissement"
    public static let messageDemoSeulement = "Le mode démonstration utilise uniquement son établissement fictif."

    /// Variante du compte démo.
    public struct Configuration: Equatable, Sendable {
        /// Rôle d'équipe demandé (`-JOLENE_DEMO_ROLE_ETAB`).
        public var role: RoleEtab
        /// Compte legacy (`app_metadata.role = 'ETABLISSEMENT'`, sans `etablissement_id`).
        public var legacy: Bool
        /// Établissement bloqué automatiquement (`bloque_auto_le` posé).
        public var blocage: Bool

        public init(role: RoleEtab = .proprietaire, legacy: Bool = false, blocage: Bool = false) {
            self.role = role; self.legacy = legacy; self.blocage = blocage
        }

        /// Rôle servi par le serveur : un compte legacy est toujours propriétaire
        /// (`fn_role_etablissement_courant`, repli `PROPRIETAIRE` l.55462-55471).
        public var roleServi: RoleEtab { legacy ? .proprietaire : role }
    }

    /// Utilisateur confirmé de la variante (`utilisateur` ou `utilisateur_legacy` de la fixture).
    public static func utilisateur(_ configuration: Configuration = Configuration()) throws -> AuthenticatedUser {
        let fichier = try DemoFixtures.loadEtablissementDemo()
        let source = configuration.legacy ? fichier.utilisateurLegacy : fichier.utilisateur
        return AuthenticatedUser(id: source.id, email: source.email, emailConfirmedAt: DemoWorld.fixedNow,
                                 appMetadataRole: source.appMetadata.role,
                                 appMetadataEtablissementId: source.appMetadata.etablissementId)
    }

    /// Ports établissement du monde démo. `identite` rend l'utilisateur de la session démo courante
    /// (l'équivalent du JWT) : `DemoWorld` y branche `DemoAuthGateway.restoreSession`. Chaque port est
    /// câblé ici dans la même PR que sa tranche ; un port encore stub y est nommé explicitement
    /// (`DemoWorldTests.portsEnAttenteLot5`).
    public static func gateways(configuration: Configuration = Configuration(),
                                identite: @escaping @Sendable () async -> String?) -> EtablissementGateways {
        EtablissementGateways(
            session: DemoEtabSessionGateway(configuration: configuration, identite: identite),
            dashboard: UnwiredEtabDashboardPort(),        // T4
            missions: UnwiredEtabMissionsPort(),          // T5
            candidatures: UnwiredEtabCandidaturesPort(),  // T6
            pointage: UnwiredEtabPointagePort(),          // T7
            presences: UnwiredEtabPresencesPort(),        // T8
            publication: UnwiredEtabPublicationPort(),    // T9
            audit: DemoEtabAuditGateway()
        )
    }

    /// Contrôle commun des gateways démo à contexte : contexte cohérent, puis compte fictif seulement.
    static func verifier(_ context: EtablissementReadContext) throws {
        try context.verifier()
        guard context.userId == userId else { throw JoleneError(.demoOnly, messageDemoSeulement) }
    }
}

// MARK: - Fixtures

public extension DemoFixtures {
    /// `app_metadata` signé du compte démo.
    struct AppMetadataDemo: Decodable, Equatable, Sendable {
        public var role: String?
        public var etablissementId: String?
        enum CodingKeys: String, CodingKey { case role, etablissementId = "etablissement_id" }
    }

    struct UtilisateurDemo: Decodable, Equatable, Sendable {
        public var id: String
        public var email: String?
        public var appMetadata: AppMetadataDemo
        enum CodingKeys: String, CodingKey { case id, email, appMetadata = "app_metadata" }
    }

    /// `demo-etablissement.json`.
    struct EtablissementDemoFile: Decodable, Sendable {
        public var fixedNow: String
        public var utilisateur: UtilisateurDemo
        public var utilisateurLegacy: UtilisateurDemo
        public var etablissement: EtablissementProfil
        public var etablissementBloque: EtablissementProfil
        enum CodingKeys: String, CodingKey {
            case fixedNow = "fixed_now", utilisateur, etablissement
            case utilisateurLegacy = "utilisateur_legacy"
            case etablissementBloque = "etablissement_bloque"
        }
    }

    /// `demo-etab-permissions.json` : rôle → onze permissions, lues dans le `CASE` SQL.
    struct PermissionsEtabFile: Decodable, Sendable {
        public var fixedNow: String
        public var cles: [String]
        public var roles: [String: PermissionsEtab]
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", cles, roles }
    }

    static func loadEtablissementDemo() throws -> EtablissementDemoFile { try load("demo-etablissement") }
    static func loadPermissionsEtab() throws -> PermissionsEtabFile { try load("demo-etab-permissions") }
}
