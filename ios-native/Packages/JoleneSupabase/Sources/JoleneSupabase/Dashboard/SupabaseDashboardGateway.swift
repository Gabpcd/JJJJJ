import Foundation
import JoleneCore
import Supabase

/// `DashboardPort` sur Supabase (lot 1, T3), comme `DashboardSoignant.tsx` l.104-215 :
/// 1. `fn_dashboard_soignant_complet()` (JWT du soignant) : `{error}` en HTTP 200 n'est jamais un
///    succès (`RPCResponse` : « Non authentifié » → session expirée, sinon message verbatim) ; un
///    corps qui n'est pas un objet est un refus de contrat ;
/// 2. puis, en parallèle et sans jamais faire échouer l'écran :
///    - fiches `missions` (`MissionQuery.missionSelect`, dont `nb_creneaux`) et créneaux
///      PREVISIONNEL hors pause (pager du lot 0, mêmes contrôles d'intégrité) des missions du
///      tableau de bord ; en échec : planning « à confirmer » (`planning_indisponible`) ;
///    - `fn_etablissements_safe` : seule source du nom d'établissement ; en échec, `etab_nom` ;
///    - missions TERMINEE du mois relues avec les colonnes du web (décision 10) ; en échec, carte
///      des gains masquée.
/// Aucun montant n'est recalculé ; `gains_mois.net_total` n'est jamais affiché.
public struct SupabaseDashboardGateway: DashboardPort {
    public static let rpc = "fn_dashboard_soignant_complet"
    public static let fallbackMessage = "Impossible de charger votre tableau de bord. Réessayez."
    /// Colonnes de la relecture des gains du web (`DashboardSoignant.tsx` l.115-120).
    public static let gainsSelect = "id,type_contrat_applique,type_contrat_recherche,total_brut,net_a_payer,net_estime"
    public static let statutTerminee = "TERMINEE"

    private let client: SupabaseClient
    private let clock: any ClockPort
    private let missions: SupabaseMissionsGateway

    public init(client: SupabaseClient, clock: any ClockPort = SystemClock()) {
        self.client = client
        self.clock = clock
        self.missions = SupabaseMissionsGateway(client: client, clock: clock)
    }

    public func dashboard(context: MissionReadContext) async throws -> DashboardSnapshot {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, Self.rpc, fallback: Self.fallbackMessage)
        try reponse.leverSiErreur(fallback: Self.fallbackMessage)
        guard !reponse.estRefus, reponse.raw.objectValue != nil else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        let donnees: Data
        do {
            donnees = try JSONEncoder().encode(reponse.raw)
        } catch {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        let corps = try DashboardCorps.decoder(donnees)
        let maintenant = clock.now()

        async let lecture = lireMissions(AccueilAssemblage.identifiantsMissions(corps, email: context.email))
        async let etablissements = lireEtablissements(AccueilAssemblage.identifiantsEtablissements(corps))
        async let gains = lireGains(context: context, maintenant: maintenant)
        return try await AccueilAssemblage.snapshot(corps: corps, context: context, maintenant: maintenant,
                                                    lecture: lecture, etablissements: etablissements, gains: gains)
    }

    // MARK: - Lectures complémentaires (rendu partiel)

    /// Fiches et créneaux des missions du tableau de bord ; `nil` si l'une des deux lectures échoue.
    private func lireMissions(_ ids: [String]) async -> LectureMissionsAccueil? {
        guard !ids.isEmpty else { return LectureMissionsAccueil(records: [], creneaux: []) }
        do {
            async let records = lireFiches(ids)
            async let creneaux = missions.slots(missionIds: ids)
            return try await LectureMissionsAccueil(records: records, creneaux: creneaux)
        } catch {
            return nil
        }
    }

    /// Fiches relues sous RLS ; seules les lignes demandées sont gardées.
    private func lireFiches(_ ids: [String]) async throws -> [MissionRecord] {
        let lignes: [MissionRecord] = try await client.from("missions")
            .select(MissionQuery.missionSelect)
            .in("id", values: ids)
            .execute()
            .value
        let demandes = Set(ids)
        return lignes.filter { demandes.contains($0.id) }
    }

    private func lireEtablissements(_ ids: [String]) async -> [String: EtablissementSummary] {
        (try? await missions.etablissements(ids: ids)) ?? [:]
    }

    /// Missions TERMINEE du soignant terminées depuis le début du mois (heure de Paris).
    private func lireGains(context: MissionReadContext, maintenant: Date) async -> [MissionGainLigne]? {
        let debutMois = MissionQuery.isoTimestamp(DateHeureParis.debutMois(maintenant))
        do {
            let lignes: [MissionGainLigne] = try await client.from("missions")
                .select(Self.gainsSelect)
                .eq("soignant_assigne_id", value: context.userId)
                .eq("statut", value: Self.statutTerminee)
                .gte("fin_le", value: debutMois)
                .execute()
                .value
            return lignes
        } catch {
            return nil
        }
    }
}
