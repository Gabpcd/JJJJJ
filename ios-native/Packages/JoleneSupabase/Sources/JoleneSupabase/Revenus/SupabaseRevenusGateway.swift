import Foundation
import JoleneCore
import Supabase

/// `RevenusPort` sur Supabase (lot 3, T12, B9 ; lecture seule), comme l'aperçu web `MesGainsApercuContent`
/// (`src/pages/MesGains.tsx` l.92-157), `PaiementsEscrowAVenir.tsx` l.100 et `PageStripeConnect.tsx` l.70-82.
/// Définitions live de `fn_mes_revenus_connect` et `fn_mes_paiements_escrow` relues en lecture seule le 09/11/2026
/// (identiques au dump, GRANT EXECUTE `authenticated`) ; droits de colonne `authenticated` vérifiés sur `missions`,
/// `paiements_soignant` et `soignants`.
///
/// - Missions : `missions` avec **exactement** les colonnes de `MesGains.tsx` l.95 (aucune colonne Rist, ni
///   `soignant_assigne_id`, ni `profession_requise`, ni embed `etablissements` : D5, correction 19), filtrées
///   `soignant_assigne_id = <utilisateur>` et `statut = TERMINEE`, `debut_le` décroissant, pages de 50 ; en parallèle,
///   les déclarations `paiements_soignant` du soignant (colonnes et ordre de l.102-107 ; RLS `pol_paie_soig_select`),
///   requises comme dans le `Promise.all` du web ; noms d'établissement par `fn_etablissements_safe` seul (lot 0), dont
///   l'échec laisse les noms absents (`enrichirEtablissements` du web), une session expirée étant relevée.
/// - Totaux : `soignants(type_exercice, est_compte_test)` (colonnes de `PageStripeConnect.tsx` l.95) puis
///   `fn_mes_revenus_connect()` seulement pour `LIBERAL` ou `MIXTE` hors compte de test, et cartes seulement si
///   `stripe_connect_actif` est vrai : conditions d'AFFICHAGE du web (l.178, l.300, l.302, l.367 ; revue B8 de T12, M1),
///   la condition de l.106 n'étant que celle du chargement ; trois nombres finis exigés, sinon « indisponible ».
/// - Paiements rapides : tableau de `fn_mes_paiements_escrow()`, ordre serveur ; autre corps → contrat.
/// Aucune écriture. Rien n'est journalisé (ni montant, ni identifiant).
public struct SupabaseRevenusGateway: RevenusPort {
    public static let totauxRPC = "fn_mes_revenus_connect"
    public static let escrowRPC = "fn_mes_paiements_escrow"
    /// `MesGains.tsx` l.95, mot pour mot (test-garde `SupabaseRevenusGatewayTests.testSelectIdentiqueALaSourceWeb`).
    public static let missionsSelect = "id, intitule, debut_le, fin_le, duree_heures, nb_creneaux, taux_horaire_base, net_a_payer, net_estime, total_brut, statut, etablissement_id, service, type_contrat_applique, type_contrat_recherche, presences(valide_par_etablissement, valide_auto_72h_le, valide_le)"
    /// `MesGains.tsx` l.102, mot pour mot.
    public static let paiementsSelect = "id, mission_id, facture_honoraire_id, statut, montant_net, confirme_par_soignant, conteste, montant_du_reference, source_montant_du, methode, reference_virement, date_paiement, modifie_le, cree_le"
    /// Sous-ensemble des colonnes de `PageStripeConnect.tsx` l.95 (`prenom, nom, type_exercice, statut_liberal,
    /// est_compte_test`) : ni nom ni prénom (inutiles ici), ni `statut_liberal` (ignoré par l'affichage, l.178).
    public static let exerciceSelect = "type_exercice, est_compte_test"
    public static let statutTerminee = "TERMINEE"

    private let client: SupabaseClient
    private let missions: SupabaseMissionsGateway

    public init(client: SupabaseClient) {
        self.client = client
        self.missions = SupabaseMissionsGateway(client: client)
    }

    // MARK: - Totaux

    public func totaux(context: MissionReadContext) async throws -> TotauxRevenus? {
        try MissionQuery.validate(context: context)
        let exercice: ExerciceRevenus?
        do {
            exercice = try await client.from("soignants")
                .select(Self.exerciceSelect)
                .eq("id", value: context.userId)
                .maybeSingle()
                .execute()
                .value
        } catch {
            throw Self.indisponible(error)
        }
        // « Ne jamais déduire le mode d'exercice d'une lecture en panne » (web l.93) : sans ligne, section en erreur.
        guard let exercice else { throw JoleneError(.unknown, RevenusTextes.totauxIndisponibles) }
        guard exercice.afficheTotaux else { return nil }
        let corps: ValeurJSON
        do {
            corps = try await client.rpc(Self.totauxRPC).execute().value
        } catch {
            throw Self.indisponible(error)
        }
        return try TotauxRevenus.visibles(corps)
    }

    // MARK: - Paiements rapides

    public func paiementsRapides(context: MissionReadContext) async throws -> [PaiementRapide] {
        try MissionQuery.validate(context: context)
        let corps: ValeurJSON
        do {
            corps = try await client.rpc(Self.escrowRPC).execute().value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: RevenusTextes.escrowErreurDefaut)
        }
        return try PaiementRapide.lireListe(corps)
    }

    // MARK: - Missions terminées

    public func missionsTerminees(context: MissionReadContext, page: Int) async throws -> PageMissionsTerminees {
        try MissionQuery.validate(context: context)
        guard page >= 0 else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        async let lignes = lireMissions(userId: context.userId, page: page)
        async let declarations = lirePaiements(userId: context.userId)
        let (missionsLues, paiements) = try await (lignes, declarations)
        let noms = try await nomsEtablissements(missionsLues.compactMap(\.etablissementId))
        return RevenusAssemblage.page(missionsLues, paiements: paiements, etablissements: noms, page: page)
    }

    private func lireMissions(userId: String, page: Int) async throws -> [MissionTerminee] {
        let taille = RevenusAssemblage.taillePage
        do {
            return try await client.from("missions")
                .select(Self.missionsSelect)
                .eq("soignant_assigne_id", value: userId)
                .eq("statut", value: Self.statutTerminee)
                // Web `.order('debut_le', { ascending: false })` sans suffixe : NULLS FIRST par défaut de Postgres sur un
                // DESC, reproduit par `nullsFirst: true` (le SDK Swift pose toujours le suffixe).
                .order("debut_le", ascending: false, nullsFirst: true)
                .range(from: page * taille, to: (page + 1) * taille - 1)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: RevenusTextes.erreurDefaut)
        }
    }

    private func lirePaiements(userId: String) async throws -> [PaiementSoignantLu] {
        do {
            return try await client.from("paiements_soignant")
                .select(Self.paiementsSelect)
                .eq("soignant_id", value: userId)
                .order("modifie_le", ascending: false, nullsFirst: false)
                .order("cree_le", ascending: false, nullsFirst: false)
                .order("date_paiement", ascending: false, nullsFirst: false)
                // `.order('id', { ascending: false })` sans suffixe : NULLS FIRST par défaut (id non nul de toute façon).
                .order("id", ascending: false, nullsFirst: true)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: RevenusTextes.erreurDefaut)
        }
    }

    /// `fn_etablissements_safe`, seule source du nom (lot 0) ; en échec, noms absents (le web affiche « — ») sauf une
    /// session expirée, relevée pour proposer « Vérifier ma session ».
    private func nomsEtablissements(_ ids: [String]) async throws -> [String: String] {
        do {
            return try await missions.etablissements(ids: ids).mapValues(\.nom)
        } catch {
            let erreur = SupabaseErrorMapping.map(error, fallback: RevenusTextes.erreurDefaut)
            if erreur.kind == .unauthorized || erreur.kind == .cancelled { throw erreur }
            return [:]
        }
    }

    /// Erreur d'une lecture des totaux : session expirée et annulation relevées, tout autre échec → « indisponible ».
    private static func indisponible(_ error: Error) -> JoleneError {
        let erreur = SupabaseErrorMapping.map(error, fallback: RevenusTextes.totauxIndisponibles)
        switch erreur.kind {
        case .unauthorized, .cancelled: return erreur
        default: return JoleneError(.unknown, RevenusTextes.totauxIndisponibles)
        }
    }
}
