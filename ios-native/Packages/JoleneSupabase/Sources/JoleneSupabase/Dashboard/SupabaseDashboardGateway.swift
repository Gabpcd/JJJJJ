import Foundation
import JoleneCore
import Supabase
#if DEBUG
import os
#endif

/// `DashboardPort` sur Supabase (lot 1, T3), comme `DashboardSoignant.tsx` l.104-215 :
/// 1. `fn_dashboard_soignant_complet()` (JWT du soignant) : `{error}` en HTTP 200 n'est jamais un
///    succès (`RPCResponse` : « Non authentifié » → session expirée, sinon message verbatim) ; un
///    corps qui n'est pas un objet est un refus de contrat ;
/// 2. des lectures complémentaires, chacune bornée par son sous-budget, qui ne font jamais échouer
///    l'écran sur une panne :
///    - missions TERMINEE du mois relues avec les colonnes du web (décision 10), lancées **en
///      parallèle de la RPC** comme le `Promise.all` du web ; en échec, carte des gains masquée ;
///    - après la RPC (elles en lisent les identifiants) et en parallèle : fiches `missions`
///      (`MissionQuery.missionSelect`, dont `nb_creneaux`) et créneaux PREVISIONNEL hors pause
///      (pager du lot 0, mêmes contrôles d'intégrité), en échec planning « à confirmer »
///      (`planning_indisponible`) ; `fn_etablissements_safe`, seule source du nom, en échec `etab_nom`.
///
/// Repli (`nil`) sur une erreur de transport, de serveur ou de contrat, et au dépassement du
/// sous-budget ; une session expirée (`.unauthorized`) et l'annulation sont propagées : l'écran
/// propose alors « Vérifier ma session », jamais un tableau partiel qui masquerait l'expiration.
/// Le sous-budget est réduit à ce qu'il reste du délai de l'écran, `delaiEcran`, transmis par
/// l'appelant (`AccueilModel` borne l'appel à `SessionController.resolutionTimeout` et passe cette
/// même valeur, seule source du délai) : une lecture lente ne jette jamais une RPC réussie.
/// Aucun montant n'est recalculé ; `gains_mois.net_total` n'est jamais affiché.
public struct SupabaseDashboardGateway: DashboardPort {
    public static let rpc = "fn_dashboard_soignant_complet"
    public static let fallbackMessage = "Impossible de charger votre tableau de bord. Réessayez."
    /// Colonnes de la relecture des gains du web (`DashboardSoignant.tsx` l.115-120).
    public static let gainsSelect = "id,type_contrat_applique,type_contrat_recherche,total_brut,net_a_payer,net_estime"
    public static let statutTerminee = "TERMINEE"
    /// Sous-budget de chaque lecture complémentaire. Au-delà, la lecture vaut « indisponible »
    /// (pager multi-pages, rejeu SDK d'un GET d'environ 7 s, CPU partagé de la base).
    public static let sousBudgetLecture: TimeInterval = 5
    /// Marge laissée à l'assemblage avant la borne de l'écran.
    public static let margeEcran: TimeInterval = 0.5

    private let client: SupabaseClient
    private let clock: any ClockPort
    private let missions: SupabaseMissionsGateway
    private let sousBudget: TimeInterval

    public init(client: SupabaseClient, clock: any ClockPort = SystemClock(),
                sousBudgetLecture: TimeInterval = SupabaseDashboardGateway.sousBudgetLecture) {
        self.client = client
        self.clock = clock
        self.missions = SupabaseMissionsGateway(client: client, clock: clock)
        self.sousBudget = sousBudgetLecture
    }

    public func dashboard(context: MissionReadContext, delaiEcran: TimeInterval) async throws -> DashboardSnapshot {
        try MissionQuery.validate(context: context)
        let debut = ContinuousClock.now
        let maintenant = clock.now()

        // Comme le `Promise.all` du web : la relecture des gains ne dépend pas de la RPC. Si la RPC
        // échoue, la sortie de portée annule cette lecture et son résultat est ignoré.
        let budgetGains = Self.budgetLecture(ecoule: 0, sousBudget: sousBudget, delaiEcran: delaiEcran)
        async let gains = Self.lectureComplementaire("gains du mois", budget: budgetGains) {
            try await self.lireGains(context: context, maintenant: maintenant)
        }

        let corps = try await lireCorps()
        let budget = Self.budgetLecture(ecoule: Self.secondes(ContinuousClock.now - debut),
                                        sousBudget: sousBudget, delaiEcran: delaiEcran)
        let idsMissions = AccueilAssemblage.identifiantsMissions(corps, email: context.email)
        let idsEtablissements = AccueilAssemblage.identifiantsEtablissements(corps)
        async let lecture = Self.lectureComplementaire("fiches et créneaux", budget: budget) {
            try await self.lireMissions(idsMissions)
        }
        async let etablissements = Self.lectureComplementaire("établissements", budget: budget) {
            try await self.missions.etablissements(ids: idsEtablissements)
        }
        return try await AccueilAssemblage.snapshot(corps: corps, context: context, maintenant: maintenant,
                                                    lecture: lecture, etablissements: etablissements ?? [:], gains: gains)
    }

    // MARK: - Lectures complémentaires (rendu partiel)

    /// Budget d'une lecture complémentaire lancée `ecoule` secondes après le début de l'appel : le
    /// sous-budget, réduit à ce qu'il reste de `delaiEcran` moins `margeEcran`, jamais négatif.
    /// `delaiEcran` n'a pas de valeur par défaut : il vient toujours de l'appelant.
    static func budgetLecture(ecoule: TimeInterval,
                              sousBudget: TimeInterval = SupabaseDashboardGateway.sousBudgetLecture,
                              delaiEcran: TimeInterval) -> TimeInterval {
        max(0, min(sousBudget, delaiEcran - ecoule - margeEcran))
    }

    /// Lecture bornée à `budget` : `nil` (rendu partiel) au dépassement ou sur une erreur de
    /// transport, de serveur ou de contrat ; `.unauthorized` et l'annulation sont relevées. Un
    /// budget épuisé n'émet aucune requête.
    static func lectureComplementaire<T: Sendable>(
        _ lecture: String,
        budget: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T? {
        guard budget > 0 else {
            journaliser(lecture, motif: "délai de l'écran épuisé")
            return nil
        }
        do {
            return try await bounded(timeout: budget, operation)
        } catch {
            if error is CancellationError { throw error }
            if Task.isCancelled { throw CancellationError() }
            let erreur = SupabaseErrorMapping.map(error, fallback: fallbackMessage)
            if erreur.kind == .unauthorized { throw erreur }
            journaliser(lecture, motif: String(describing: erreur.kind))
            return nil
        }
    }

    /// Journal DEBUG d'une lecture dégradée : nom de la lecture et catégorie d'erreur seulement
    /// (ni URL, ni identifiant, ni valeur). Rien en Release.
    private static func journaliser(_ lecture: String, motif: String) {
        #if DEBUG
        Logger(subsystem: "app.jolene", category: "accueil")
            .debug("Lecture complémentaire indisponible (\(lecture, privacy: .public)) : \(motif, privacy: .public)")
        #endif
    }

    private static func secondes(_ duree: Duration) -> TimeInterval {
        let (secondes, attosecondes) = duree.components
        return TimeInterval(secondes) + TimeInterval(attosecondes) / 1e18
    }

    // MARK: - Requêtes

    private func lireCorps() async throws -> DashboardCorps {
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
        return try DashboardCorps.decoder(donnees)
    }

    /// Fiches et créneaux des missions du tableau de bord ; lève si l'une des deux lectures échoue.
    private func lireMissions(_ ids: [String]) async throws -> LectureMissionsAccueil {
        guard !ids.isEmpty else { return LectureMissionsAccueil(records: [], creneaux: []) }
        async let records = lireFiches(ids)
        async let creneaux = missions.slots(missionIds: ids)
        return try await LectureMissionsAccueil(records: records, creneaux: creneaux)
    }

    /// Fiches relues sous RLS ; seules les lignes demandées sont gardées.
    private func lireFiches(_ ids: [String]) async throws -> [MissionRecord] {
        let lignes: [MissionRecord]
        do {
            lignes = try await client.from("missions")
                .select(MissionQuery.missionSelect)
                .in("id", values: ids)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.fallbackMessage)
        }
        let demandes = Set(ids)
        return lignes.filter { demandes.contains($0.id) }
    }

    /// Missions TERMINEE du soignant terminées depuis le début du mois (heure de Paris).
    private func lireGains(context: MissionReadContext, maintenant: Date) async throws -> [MissionGainLigne] {
        let debutMois = MissionQuery.isoTimestamp(DateHeureParis.debutMois(maintenant))
        do {
            return try await client.from("missions")
                .select(Self.gainsSelect)
                .eq("soignant_assigne_id", value: context.userId)
                .eq("statut", value: Self.statutTerminee)
                .gte("fin_le", value: debutMois)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.fallbackMessage)
        }
    }
}
