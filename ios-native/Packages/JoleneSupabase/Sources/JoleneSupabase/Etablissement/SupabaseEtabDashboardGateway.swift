import Foundation
import JoleneCore
import Supabase

/// `EtabDashboardPort` sur Supabase (lot 5, T4 ; `LOT5_PLAN.md` §2.4) : deux lectures parallèles, comme le web
/// (`DashboardEtablissement.tsx` l.184-200, l.288-369) :
/// - principale : `fn_stats_dashboard_etablissement()` (périmètre serveur `mon_etablissement_id()`, aucun argument),
///   décodée en `EtabDashboardStats` (compteurs seulement : montants et noms de soignants jamais décodés). `{error}`
///   en HTTP 200 → message serveur verbatim ; corps non objet ou refus inattendu → refus de contrat. Aucune
///   exception levée par le corps (liste blanche vide) ;
/// - secondaire : planning des 31 prochains jours — `missions` (OUVERTE/ASSIGNEE/EN_COURS, `fin_le` ≥ maintenant,
///   `debut_le` ≤ fin de fenêtre, colonnes sans montant ni soignant) puis `mission_creneaux` PREVISIONNEL hors pause
///   par la pagination vérifiée du lot 0 (`SupabaseMissionsGateway.slots`, `MissionSlotPager`). Son échec ne fait pas
///   échouer l'Accueil : `planning == nil`, bandeau « partiel » (web l.711-713).
///
/// L'audit de consultation (D19) est écrit par `EtabAccueilModel` après une lecture réussie, par `EtabAuditPort`,
/// dans les deux mondes ; il n'est pas doublé ici.
public struct SupabaseEtabDashboardGateway: EtabDashboardPort {
    public static let rpc = "fn_stats_dashboard_etablissement"
    public static let fallbackMessage = "Impossible de charger le tableau de bord de votre établissement. Réessayez."
    public static let missionsSelect = "id,intitule,statut,debut_le,fin_le,nb_creneaux"

    private let client: SupabaseClient
    private let clock: any ClockPort

    public init(client: SupabaseClient, clock: any ClockPort = SystemClock()) {
        self.client = client
        self.clock = clock
    }

    public func tableauDeBord(context: EtablissementReadContext) async throws -> EtabDashboardSnapshot {
        try context.verifier()
        let maintenant = clock.now()
        async let planning = planningOuNil(etablissementId: context.etablissementId, maintenant: maintenant)
        let stats = try await self.stats()
        return EtabDashboardSnapshot(stats: stats, planning: await planning)
    }

    func stats() async throws -> EtabDashboardStats {
        let reponse = try await RPCResponse.appeler(client, Self.rpc, fallback: Self.fallbackMessage,
                                                    interceptions: ListesBlanchesEtablissement.interceptions(rpc: Self.rpc))
        try reponse.leverSiErreur(fallback: Self.fallbackMessage)
        guard reponse.raw.objectValue != nil, !reponse.estRefus else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return try SupabaseEtabSessionGateway.decoder(EtabDashboardStats.self, reponse)
    }

    /// Lecture secondaire : toute erreur (annulation comprise) rend `nil`, jamais un planning vide supposé.
    func planningOuNil(etablissementId: String, maintenant: Date) async -> EtabPlanningAVenir? {
        try? await planning(etablissementId: etablissementId, maintenant: maintenant)
    }

    func planning(etablissementId: String, maintenant: Date) async throws -> EtabPlanningAVenir {
        let finFenetre = EtabPlanningAccueil.finFenetre(maintenant)
        let missions: [EtabMissionPlanifiee]
        do {
            missions = try await client.from("missions")
                .select(Self.missionsSelect)
                .eq("etablissement_id", value: etablissementId)
                .gte("fin_le", value: MissionQuery.isoTimestamp(maintenant))
                .lte("debut_le", value: MissionQuery.isoTimestamp(finFenetre))
                .in("statut", values: EtabPlanningAccueil.statuts)
                .order("debut_le", ascending: true)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.fallbackMessage)
        }
        guard Set(missions.map(\.id)).count == missions.count,
              missions.allSatisfy({ EtabPlanningAccueil.statuts.contains($0.statut) }) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        let creneaux = missions.isEmpty ? [] : try await SupabaseMissionsGateway(client: client).slots(missionIds: missions.map(\.id))
        return EtabPlanningAccueil.construire(missions: missions, creneaux: creneaux, maintenant: maintenant)
    }
}
