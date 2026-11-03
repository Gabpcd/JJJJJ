import Foundation

/// Session établissement démo : rejoue les formes de `fn_mes_permissions_etab` et de
/// `fn_mon_etablissement_complet` depuis les fixtures, sans réseau. L'utilisateur courant est lu par
/// `identite` (session démo, équivalent du JWT) : tout autre compte que `demo-etablissement`, ou
/// l'absence de session, est refusé (`.demoOnly`) — la démo n'est jamais un repli pour un compte réel.
public struct DemoEtabSessionGateway: EtabSessionPort {
    public let configuration: DemoEtablissementWorld.Configuration
    private let identite: @Sendable () async -> String?

    public init(configuration: DemoEtablissementWorld.Configuration = DemoEtablissementWorld.Configuration(),
                identite: @escaping @Sendable () async -> String?) {
        self.configuration = configuration
        self.identite = identite
    }

    /// - établissement demandé autre que celui du compte → `{success:true, role:null,
    ///   etablissement_id:null}` (le serveur ne trouve aucune adhésion, l.42281-42283) ;
    /// - rôle connu → les onze permissions de la fixture pour ce rôle (`CASE` SQL) ;
    /// - rôle inconnu (cas de test : administrateur, valeur inattendue) → rôle servi tel quel, aucune
    ///   permission : l'espace ne l'ouvre jamais (§2.2).
    public func permissions(etablissementId: String?) async throws -> PermissionsEtabResult {
        try await verifierIdentite()
        let etablissement = try profilFixture()
        if let etablissementId, etablissementId != etablissement.id {
            return PermissionsEtabResult(success: true, role: nil, etablissementId: nil, permissions: .aucune)
        }
        let role = configuration.roleServi
        guard role.estConnu else {
            return PermissionsEtabResult(success: true, role: role, etablissementId: etablissement.id, permissions: .aucune)
        }
        guard let permissions = try DemoFixtures.loadPermissionsEtab().roles[role.brut] else {
            throw JoleneError(.contract, "Fixture démo illisible : demo-etab-permissions.json.")
        }
        return PermissionsEtabResult(success: true, role: role, etablissementId: etablissement.id, permissions: permissions)
    }

    public func profil() async throws -> EtablissementProfil {
        try await verifierIdentite()
        return try profilFixture()
    }

    private func profilFixture() throws -> EtablissementProfil {
        let fichier = try DemoFixtures.loadEtablissementDemo()
        return configuration.blocage ? fichier.etablissementBloque : fichier.etablissement
    }

    private func verifierIdentite() async throws {
        guard await identite() == DemoEtablissementWorld.userId else {
            throw JoleneError(.demoOnly, DemoEtablissementWorld.messageDemoSeulement)
        }
    }
}
