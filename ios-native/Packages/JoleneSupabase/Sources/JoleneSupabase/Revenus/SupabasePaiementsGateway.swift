import Foundation
import JoleneCore
import Supabase

/// `PaiementsDeclaresPort` sur Supabase (lot 3, T13, B9), port de `BandeauPaiementDeclare.tsx` (l.89-203). Contrats :
/// fiches `fn_confirmer_paiement_soignant` et `fn_contester_paiement_soignant` de `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md`
/// (contestation d'après B3, #1118, migration `20261102205808_contestation_paiement_soignant.sql`, corps identique au
/// dump `supabase/schema/public.sql` l.25741-25839 ; GRANT EXECUTE `authenticated` l.82094 et l.82235). Définition live
/// non relue par cette tranche (aucun appel au backend autorisé) : point à vérifier avant le go B9.
///
/// - Liste : `paiements_soignant` du soignant en `DECLARE` avec **exactement** les colonnes de l.97 (RLS
///   `pol_paie_soig_select`) ; noms d'établissement par `fn_etablissements_safe` seul, dont l'échec laisse le repli
///   « Établissement » (`fetchEtablissementsSafe` du web avale l'erreur), une session expirée étant relevée ; puis
///   missions (colonnes de l.122), présences (l.132, `pointage_arrivee_le` croissant) et créneaux (l.137, `debut`
///   croissant) des missions, dont tout échec met la section en erreur (l.124, l.141-142).
/// - Confirmer / contester : un seul POST, jamais renvoyé ; `{error}` → refus, message serveur verbatim (« Non
///   authentifié » de la confirmation → session expirée) ; `{success:true}` → relecture de la ligne
///   (`PaiementsDeclaresRelecture` : `CONFIRME` et `confirme_par_soignant`, ou `CONTESTE` et `conteste`), sans quoi
///   « Erreur lors du traitement », jamais un succès ; tout autre corps → contrat ; exception PostgREST (dont une 23505
///   non restituée par B3) → `SupabaseErrorMapping` avec le repli du web (l.200), jamais un succès. Le motif est envoyé
///   tel que saisi (le serveur le borne après `btrim`), jamais remplacé par le repli `'Contesté par le soignant'`.
/// Rien n'est journalisé (ni montant, ni identifiant, ni motif).
public struct SupabasePaiementsGateway: PaiementsDeclaresPort {
    public static let confirmerRPC = "fn_confirmer_paiement_soignant"
    public static let contesterRPC = "fn_contester_paiement_soignant"
    /// `BandeauPaiementDeclare.tsx` l.97, mot pour mot (test-garde `SupabasePaiementsGatewayTests`).
    public static let paiementsSelect = "id, montant_net, mission_id, etablissement_id, reference_virement, methode, date_paiement"
    /// Relecture après mutation : colonnes de l.97 plus l'état relu (colonnes lues aussi par `MesGains.tsx` l.102).
    public static let relectureSelect = paiementsSelect + ", statut, confirme_par_soignant, conteste"
    /// `BandeauPaiementDeclare.tsx` l.122, mot pour mot.
    public static let missionsSelect = "id, intitule, debut_le, fin_le, duree_heures, taux_horaire_base, taux_rist_plafonne, rist_plafond_applique, total_brut, net_a_payer"
    /// `BandeauPaiementDeclare.tsx` l.132, mot pour mot.
    public static let presencesSelect = "mission_id, pointage_arrivee_le, pointage_depart_le, methode_pointage_arrivee, heures_ajustees_litige"
    /// `BandeauPaiementDeclare.tsx` l.137, mot pour mot.
    public static let creneauxSelect = "id, mission_id, debut, fin, est_pause, type_creneau"

    private let client: SupabaseClient
    private let missions: SupabaseMissionsGateway

    public init(client: SupabaseClient) {
        self.client = client
        self.missions = SupabaseMissionsGateway(client: client)
    }

    // MARK: - Liste

    public func aConfirmer(context: MissionReadContext) async throws -> [PaiementDeclare] {
        try MissionQuery.validate(context: context)
        let lignes: [LignePaiementDeclare] = try await lire {
            try await client.from("paiements_soignant")
                .select(Self.paiementsSelect)
                .eq("soignant_id", value: context.userId)
                .eq("statut", value: PaiementsDeclaresAssemblage.statutDeclare)
                .execute()
                .value
        }
        guard !lignes.isEmpty else { return [] }
        let noms = try await nomsEtablissements(PaiementsDeclaresAssemblage.identifiants(lignes.map(\.etablissementId)))
        let ids = PaiementsDeclaresAssemblage.identifiants(lignes.map(\.missionId))
        let missionsLues: [MissionPaiementDeclare] = try await lire {
            try await client.from("missions").select(Self.missionsSelect).in("id", values: ids).execute().value
        }
        async let presences: [PresencePaiementDeclare] = lire {
            try await client.from("presences").select(Self.presencesSelect).in("mission_id", values: ids)
                .order("pointage_arrivee_le", ascending: true).execute().value
        }
        async let creneaux: [CreneauPaiementDeclare] = lire {
            try await client.from("mission_creneaux").select(Self.creneauxSelect).in("mission_id", values: ids)
                .order("debut", ascending: true).execute().value
        }
        return PaiementsDeclaresAssemblage.assembler(lignes, etablissements: noms, missions: missionsLues,
                                                     presences: try await presences, creneaux: try await creneaux)
    }

    // MARK: - Mutations

    public func confirmer(id: String, context: MissionReadContext) async throws -> IssuePaiement {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, Self.confirmerRPC, params: ["p_paiement_id": .string(id)],
                                                    fallback: PaiementsDeclaresTextes.erreurTraitement)
        if let refus = try Self.refus(reponse) { return refus }
        return try PaiementsDeclaresRelecture.confirmation(relue: try await relire(id: id, context: context))
    }

    public func contester(id: String, motif: String, context: MissionReadContext) async throws -> IssuePaiement {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, Self.contesterRPC,
                                                    params: ["p_paiement_id": .string(id), "p_motif": .string(motif)],
                                                    fallback: PaiementsDeclaresTextes.erreurTraitement)
        if let refus = try Self.refus(reponse) { return refus }
        let litige = reponse.string("litige_id")
        return try PaiementsDeclaresRelecture.contestation(relue: try await relire(id: id, context: context), litigeId: litige)
    }

    /// Refus `{error}` (et `error_code` de B3) → issue `.refuse`, message verbatim ; « Non authentifié » → session
    /// expirée. `{success:true}` sans `error` → nil (relecture). Tout autre corps → contrat.
    static func refus(_ reponse: RPCResponse) throws -> IssuePaiement? {
        if let erreur = reponse.erreur {
            if RPCResponse.estNonAuthentifie(erreur) {
                throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
            }
            return .refuse(message: erreur)
        }
        guard reponse.success == true else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        return nil
    }

    // MARK: - Interne

    /// Relecture de la ligne après un succès annoncé (une requête, aucun renvoi de la mutation).
    private func relire(id: String, context: MissionReadContext) async throws -> PaiementDeclare? {
        let ligne: LignePaiementDeclare? = try await lire(fallback: PaiementsDeclaresTextes.erreurTraitement) {
            try await client.from("paiements_soignant")
                .select(Self.relectureSelect)
                .eq("id", value: id)
                .eq("soignant_id", value: context.userId)
                .maybeSingle()
                .execute()
                .value
        }
        return ligne.map { PaiementsDeclaresAssemblage.paiement($0) }
    }

    private func lire<T: Sendable>(fallback: String = PaiementsDeclaresTextes.erreurChargement,
                                   _ requete: @Sendable () async throws -> T) async throws -> T {
        do {
            return try await requete()
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: fallback)
        }
    }

    /// `fn_etablissements_safe`, seule source du nom ; en échec, repli « Établissement » (le web avale l'erreur), sauf
    /// une session expirée ou une annulation, relevées.
    private func nomsEtablissements(_ ids: [String]) async throws -> [String: String] {
        do {
            return try await missions.etablissements(ids: ids).mapValues(\.nom)
        } catch {
            let erreur = SupabaseErrorMapping.map(error, fallback: PaiementsDeclaresTextes.erreurChargement)
            if erreur.kind == .unauthorized || erreur.kind == .cancelled { throw erreur }
            return [:]
        }
    }
}
