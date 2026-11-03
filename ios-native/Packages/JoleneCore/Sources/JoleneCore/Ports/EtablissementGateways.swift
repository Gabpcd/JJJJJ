import Foundation

/// Ports de l'espace établissement regroupés dans **un seul** champ de `Gateways`
/// (`Gateways.etablissement`, lot 5 §2.3) : un conteneur parallèle aurait créé un second chemin
/// d'invalidation d'epoch. Chaque port est « non câblé » par défaut ; chaque monde (démo, Supabase)
/// câble le sien dans la même PR que sa tranche. La liste attendue des ports encore stubs n'existe
/// qu'à un endroit (`DemoWorldTests.portsEnAttenteLot5`) ; `SupabaseGatewaysTests` compare les deux
/// mondes ; elle est vide à la clôture du lot (T14).
public struct EtablissementGateways: Sendable {
    public var session: EtabSessionPort = UnwiredEtabSessionPort()
    public var dashboard: EtabDashboardPort = UnwiredEtabDashboardPort()
    public var missions: EtabMissionsPort = UnwiredEtabMissionsPort()
    public var candidatures: EtabCandidaturesPort = UnwiredEtabCandidaturesPort()
    public var pointage: EtabPointagePort = UnwiredEtabPointagePort()
    public var presences: EtabPresencesPort = UnwiredEtabPresencesPort()
    public var publication: EtabPublicationPort = UnwiredEtabPublicationPort()
    public var audit: EtabAuditPort = UnwiredEtabAuditPort()

    /// Aucun port câblé : valeur par défaut de `Gateways.etablissement`.
    public static let nonCable = EtablissementGateways()

    public init() {}

    /// Jeu complet : chaque port est nommé, aucun défaut implicite (un port encore livré par sa
    /// tranche est passé explicitement en `UnwiredEtab…`).
    public init(session: EtabSessionPort, dashboard: EtabDashboardPort, missions: EtabMissionsPort,
                candidatures: EtabCandidaturesPort, pointage: EtabPointagePort, presences: EtabPresencesPort,
                publication: EtabPublicationPort, audit: EtabAuditPort) {
        self.session = session; self.dashboard = dashboard; self.missions = missions
        self.candidatures = candidatures; self.pointage = pointage; self.presences = presences
        self.publication = publication; self.audit = audit
    }

    /// Ports encore servis par un stub, nommés `etablissement.<champ>` dans l'ordre de déclaration.
    /// Vide pour un monde complet.
    public var unwiredPorts: [String] {
        let ports: [(nom: String, port: Any)] = [
            ("session", session), ("dashboard", dashboard), ("missions", missions), ("candidatures", candidatures),
            ("pointage", pointage), ("presences", presences), ("publication", publication), ("audit", audit),
        ]
        return ports.filter { $0.port is UnwiredPort }.map { "etablissement.\($0.nom)" }
    }
}
