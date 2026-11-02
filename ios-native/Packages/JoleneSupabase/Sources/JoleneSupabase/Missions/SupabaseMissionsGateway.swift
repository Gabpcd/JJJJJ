import Foundation
import JoleneCore
import Supabase

/// `MissionsPort` sur PostgREST, lecture seule (plan §4.4). Client authentifié ordinaire :
/// visibilité, exclusions et cohortes TEST restent dans la RLS serveur. Toute ligne
/// relue est contrôlée (id du profil = session, id de mission = demande).
public struct SupabaseMissionsGateway: MissionsPort {
    public static let profileFallbackMessage = "Impossible de charger votre profil. Réessayez."
    public static let missionsFallbackMessage = "Impossible de charger les missions. Réessayez."
    public static let missionFallbackMessage = "Impossible de charger cette mission. Réessayez."
    public static let etablissementsFallbackMessage = "Impossible de charger les établissements des missions. Réessayez."
    public static let slotsFallbackMessage = "Impossible de charger le planning détaillé. Réessayez."

    private let client: SupabaseClient
    private let clock: any ClockPort
    private let enrich: MissionQuery.Enricher

    public init(client: SupabaseClient, clock: any ClockPort = SystemClock(), enrich: @escaping MissionQuery.Enricher = MissionQuery.defaultEnrich) {
        self.client = client
        self.clock = clock
        self.enrich = enrich
    }

    // MARK: - Profil

    public func profile(userId: String) async throws -> SoignantProfile? {
        guard !userId.isEmpty else { throw JoleneError(.unauthorized, "Session absente.") }
        let row: SoignantProfile?
        do {
            row = try await client.from("soignants")
                .select(MissionQuery.profileSelect)
                .eq("id", value: userId)
                .maybeSingle()
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.profileFallbackMessage)
        }
        guard let row else { return nil }
        guard row.id == userId else {
            throw JoleneError(.contract, "Le profil retourné ne correspond pas à la session.")
        }
        // L'onboarding utilise fn_explorer_missions_inscription, un contrat distinct : un
        // profil sans profession ne doit jamais déclencher une requête large.
        guard !row.profession.isEmpty else { return nil }
        return row
    }

    // MARK: - Liste

    public func listMissions(context: MissionReadContext, filters: MissionFilters) async throws -> [Mission] {
        try MissionQuery.validate(context: context)
        let server = MissionQuery.serverFilters(filters, profile: context.profile)
        let records: [MissionRecord]
        do {
            var query = client.from("missions")
                .select(MissionQuery.missionSelect)
                .eq("statut", value: MissionQuery.openStatus)
                .gte("debut_le", value: MissionQuery.isoTimestamp(clock.now()))
            let profession = server.profession ?? context.profile.profession
            if server.profession == nil, let compatible = MissionQuery.compatibleProfessionFilter(profession) {
                query = query.or(compatible)
            } else {
                query = query.eq("profession_requise", value: profession)
            }
            if server.tauxMin > 0 { query = query.gte("taux_horaire_base", value: server.tauxMin) }
            if server.urgentesOnly { query = query.eq("est_urgente", value: true) }
            if let etablissementId = server.etablissementId { query = query.eq("etablissement_id", value: etablissementId) }
            // Ordre exact du pilote (supabase-js) : `boostee_le.desc.nullslast`,
            // `est_urgente.desc` (sans suffixe côté JS, donc NULLS FIRST par défaut Postgres sur
            // un DESC : reproduit ici par `nullsFirst: true`), `debut_le.asc` (NOT NULL).
            records = try await query
                .order("boostee_le", ascending: false, nullsFirst: false)
                .order("est_urgente", ascending: false, nullsFirst: true)
                .order("debut_le", ascending: true)
                .limit(MissionQuery.missionLimit)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.missionsFallbackMessage)
        }
        // Comme le pilote : enrichissement, puis filtres de présentation (`filterMissions` :
        // cohorte Playwright, hiérarchie de profession, rayon, ville, contrat, horaire, tri
        // par distance). Ces filtres ne remplacent jamais la RLS.
        let enriched = try await enrichAll(records, context: context)
        return MissionBusiness.filter(enriched, context: context, filters: filters)
    }

    // MARK: - Détail

    public func mission(id: String, context: MissionReadContext) async throws -> Mission? {
        try MissionQuery.validate(context: context)
        guard !id.isEmpty else { return nil }
        // Relecture sous le JWT courant : l'état de navigation n'est jamais une autorisation.
        let row: MissionRecord?
        do {
            row = try await client.from("missions")
                .select(MissionQuery.missionSelect)
                .eq("id", value: id)
                .maybeSingle()
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.missionFallbackMessage)
        }
        guard let row else { return nil }
        guard row.id == id else {
            throw JoleneError(.contract, "La mission retournée ne correspond pas à la demande.")
        }
        // Comme `getMission` du pilote : une fixture Playwright n'existe pas pour un compte ordinaire.
        guard MissionBusiness.estComptePlaywright(email: context.email)
                || !MissionBusiness.estMissionPlaywright(intitule: row.intitule) else { return nil }
        return try await enrichAll([row], context: context).first
    }

    // MARK: - Enrichissement

    private func enrichAll(_ records: [MissionRecord], context: MissionReadContext) async throws -> [Mission] {
        guard !records.isEmpty else { return [] }
        async let etablissements = self.etablissements(ids: records.map(\.etablissementId))
        async let slots = self.slots(missionIds: records.map(\.id))
        return try await enrich(context, records, etablissements, slots)
    }

    /// `fn_etablissements_safe(p_ids)` : seules les lignes dont l'id a été demandé sont gardées.
    func etablissements(ids: [String]) async throws -> [String: EtablissementSummary] {
        var seen = Set<String>()
        let unique = ids.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !unique.isEmpty else { return [:] }
        let rows: [EtablissementSummary]
        do {
            rows = try await client
                .rpc(MissionQuery.etablissementsRPC, params: ["p_ids": unique])
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.etablissementsFallbackMessage)
        }
        var result: [String: EtablissementSummary] = [:]
        for row in rows where seen.contains(row.id) {
            result[row.id] = row
        }
        return result
    }

    /// Pagination bornée identique au web : lots de 50 missions, pages de 500 créneaux,
    /// compte exact et vérifications d'intégrité de `MissionSlotPager`.
    func slots(missionIds: [String]) async throws -> [MissionSlot] {
        var result: [MissionSlot] = []
        for batch in MissionSlotPager.batches(missionIds) {
            var pager = MissionSlotPager(batch: batch)
            while pager.needsMore {
                try Task.checkCancellation()
                let response: PostgrestResponse<[MissionSlot]>
                do {
                    response = try await client.from("mission_creneaux")
                        .select(MissionQuery.slotSelect, count: .exact)
                        .in("mission_id", values: batch)
                        .eq("type_creneau", value: MissionQuery.forecastSlotType)
                        .eq("est_pause", value: false)
                        .order("mission_id", ascending: true)
                        .order("debut", ascending: true)
                        .order("id", ascending: true)
                        .range(from: pager.offset, to: pager.offset + MissionQuery.slotPageSize - 1)
                        .execute()
                } catch {
                    throw SupabaseErrorMapping.map(error, fallback: Self.slotsFallbackMessage)
                }
                try pager.ingest(page: response.value, count: response.count)
            }
            result.append(contentsOf: try pager.finish())
        }
        return result
    }
}
