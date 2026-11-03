import Foundation
import JoleneCore
import Supabase

/// `MesMissionsPort` sur PostgREST (lot 1, T5), lecture seule, requêtes de `MissionsSoignant.tsx`
/// (l.177-233) sous le JWT du soignant (RLS serveur) :
/// - Candidatures : `candidatures` du soignant en attente (`EN_ATTENTE`, `EN_ATTENTE_VALIDATION_ETAB`),
///   `cree_le` décroissant, mission embarquée (`missions(...)`) ; une candidature dont la mission est
///   masquée par la RLS (embed nul) est écartée, comme le web (l.188) ;
/// - À venir : missions `ASSIGNEE` / `EN_COURS` assignées au soignant, non terminées (`fin_le` ≥
///   maintenant), `debut_le` croissant ; Passées : `TERMINEE`, `ANNULEE_PAR_SOIGNANT`,
///   `ANNULEE_PAR_ETABLISSEMENT`, `ABSENCE`, `debut_le` décroissant, avec les colonnes financières
///   (`net_estime`, `type_contrat_applique`) ;
/// - pages : lecture **cumulative** du web (« M1 », l.244-246) — la page `n` relit les lignes
///   `0…(n + 1) × MissionsPage.taille − 1` et l'appelant remplace sa liste ; jamais une page disjointe,
///   dont l'offset se décale quand une mission sort de la requête entre deux lectures (`fin_le`
///   dépassée) et fait sauter la suivante. Départage par `id` après `debut_le` (absent du web) : ordre
///   stable d'une lecture à l'autre à date de début égale.
///
/// **Sans** l'embed `etablissements(...)` du web : `pol_etab_select` interdit ce SELECT au soignant.
/// Les noms viennent **exclusivement** de `fn_etablissements_safe` (même cohorte, mission assignée au
/// soignant ou OUVERTE de l'établissement, `public.sql` l.35073-35095) ; en échec, comme
/// `fetchEtablissementsSafe` du web qui ignore l'erreur, repli d'affichage « Établissement » (une
/// session expirée est propagée). Créneaux PREVISIONNEL hors pause par le pager du lot 0 (compte exact,
/// intégrité) ; en échec, l'onglet est en erreur, comme le web (« Impossible de charger les missions et
/// leurs horaires. »). Aucun montant n'est recalculé.
public struct SupabaseMesMissionsGateway: MesMissionsPort {
    public static let fallbackMessage = "Impossible de charger les missions et leurs horaires. Réessayez."
    /// Colonnes de la ligne `candidatures` (requête du web, l.181).
    public static let candidatureColumns = "id,statut,message,type_contrat_choisi,cree_le,mission_id"
    /// Colonnes financières lues en plus pour les missions passées (montant affiché selon le régime).
    public static let financeColumns = "net_estime,type_contrat_applique"

    public static var candidaturesSelect: String {
        "\(candidatureColumns),missions(\(MissionQuery.missionSelect))"
    }

    public static var passeesSelect: String {
        "\(MissionQuery.missionSelect),\(financeColumns)"
    }

    private let client: SupabaseClient
    private let clock: any ClockPort
    private let missions: SupabaseMissionsGateway
    private let enrich: MissionQuery.Enricher

    public init(client: SupabaseClient, clock: any ClockPort = SystemClock(),
                enrich: @escaping MissionQuery.Enricher = MissionQuery.defaultEnrich) {
        self.client = client
        self.clock = clock
        self.missions = SupabaseMissionsGateway(client: client, clock: clock)
        self.enrich = enrich
    }

    // MARK: - Candidatures

    /// Ligne `candidatures` et sa mission embarquée (`null` si la RLS la masque).
    private struct LigneCandidature: Decodable {
        var candidature: CandidatureRecord
        var mission: MissionRecord?

        enum CodingKeys: String, CodingKey { case missions }

        init(from decoder: Decoder) throws {
            candidature = try CandidatureRecord(from: decoder)
            mission = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(MissionRecord.self, forKey: .missions)
        }
    }

    public func candidatures(context: MissionReadContext) async throws -> [CandidatureRecord] {
        try MissionQuery.validate(context: context)
        let lignes: [LigneCandidature]
        do {
            lignes = try await client.from("candidatures")
                .select(Self.candidaturesSelect)
                .eq("soignant_id", value: context.userId)
                .in("statut", values: MesMissionsPresentation.statutsCandidatures)
                // `order('cree_le', { ascending: false })` : NULLS FIRST, défaut Postgres d'un DESC.
                .order("cree_le", ascending: false, nullsFirst: true)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.fallbackMessage)
        }
        var visibles: [(CandidatureRecord, MissionRecord)] = []
        for ligne in lignes {
            guard let mission = ligne.mission else { continue }
            guard mission.id == ligne.candidature.missionId else {
                throw JoleneError(.contract, "La mission retournée ne correspond pas à la candidature.")
            }
            visibles.append((ligne.candidature, mission))
        }
        let enrichies = Dictionary(try await enrichAll(visibles.map(\.1), context: context).map { ($0.id, $0) },
                                   uniquingKeysWith: { premiere, _ in premiere })
        return visibles.map { candidature, mission in
            var record = candidature
            record.mission = enrichies[mission.id]
            return record
        }
    }

    // MARK: - À venir et passées

    /// Ligne `missions` d'une mission passée et ses colonnes financières, lues du même objet.
    private struct LignePassee: Decodable {
        var record: MissionRecord
        var finance: MissionGainLigne

        init(from decoder: Decoder) throws {
            record = try MissionRecord(from: decoder)
            finance = try MissionGainLigne(from: decoder)
        }
    }

    public func aVenir(context: MissionReadContext, page: Int) async throws -> MissionsPage {
        try MissionQuery.validate(context: context)
        let bornes = Self.bornes(page: page)
        let records: [MissionRecord]
        do {
            records = try await client.from("missions")
                .select(MissionQuery.missionSelect)
                .eq("soignant_assigne_id", value: context.userId)
                .in("statut", values: MesMissionsPresentation.statutsAVenir)
                .gte("fin_le", value: MissionQuery.isoTimestamp(clock.now()))
                .order("debut_le", ascending: true)
                .order("id", ascending: true)
                .range(from: bornes.debut, to: bornes.fin)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.fallbackMessage)
        }
        return MissionsPage(missions: try await enrichAll(records, context: context), page: max(0, page),
                            aSuivre: records.count == bornes.fin + 1)
    }

    public func passees(context: MissionReadContext, page: Int) async throws -> MissionsPage {
        try MissionQuery.validate(context: context)
        let bornes = Self.bornes(page: page)
        let lignes: [LignePassee]
        do {
            lignes = try await client.from("missions")
                .select(Self.passeesSelect)
                .eq("soignant_assigne_id", value: context.userId)
                .in("statut", values: MesMissionsPresentation.statutsPassees)
                .order("debut_le", ascending: false, nullsFirst: true)
                .order("id", ascending: true)
                .range(from: bornes.debut, to: bornes.fin)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.fallbackMessage)
        }
        var lue = MissionsPage(missions: try await enrichAll(lignes.map(\.record), context: context), page: max(0, page),
                               aSuivre: lignes.count == bornes.fin + 1)
        lue.finances = Dictionary(lignes.map { ($0.finance.id, $0.finance) }, uniquingKeysWith: { premiere, _ in premiere })
        return lue
    }

    // MARK: - Interne

    /// Bornes `range` (incluses) de la lecture cumulative des pages 0…`page`, comme le web
    /// (`range(0, (page + 1) * PAGE_SIZE - 1)`) : 0-49, 0-99, 0-149…
    static func bornes(page: Int) -> (debut: Int, fin: Int) {
        (0, (max(0, page) + 1) * MissionsPage.taille - 1)
    }

    /// Établissements (`fn_etablissements_safe`, repli sans nom sur erreur) et créneaux (pager), puis
    /// enrichissement de chaque fiche ; ordre serveur conservé.
    private func enrichAll(_ records: [MissionRecord], context: MissionReadContext) async throws -> [Mission] {
        guard !records.isEmpty else { return [] }
        async let etablissements = lireEtablissements(records.map(\.etablissementId))
        async let creneaux = missions.slots(missionIds: records.map(\.id))
        return try await enrich(context, records, etablissements, creneaux)
    }

    private func lireEtablissements(_ ids: [String]) async throws -> [String: EtablissementSummary] {
        do {
            return try await missions.etablissements(ids: ids)
        } catch {
            if error is CancellationError { throw error }
            let erreur = SupabaseErrorMapping.map(error, fallback: Self.fallbackMessage)
            if erreur.kind == .unauthorized || erreur.kind == .cancelled { throw erreur }
            return [:]
        }
    }
}
