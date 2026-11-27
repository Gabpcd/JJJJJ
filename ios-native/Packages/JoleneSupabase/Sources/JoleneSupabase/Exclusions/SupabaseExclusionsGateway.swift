import Foundation
import JoleneCore
import Supabase

/// `ExclusionsPort` (L4-T11), port de `ExclusionsSoignant.tsx` et `BoutonExclusion.tsx` :
/// - envoyées : PostgREST `exclusions` (`exclu_par = auth.uid()`, RLS `pol_exclusion_select`, filtre explicite sur la
///   session), `cree_le` décroissant, noms par `fn_etablissements_safe` (lecture complémentaire : en échec, l'écran
///   affiche l'identifiant, comme le web l.56) ;
/// - reçues : `fn_mes_exclusions_recues()` (`public.sql` l.42289), tableau (`[]` sans session) ; une réponse qui n'est pas
///   un tableau lisible est une erreur, jamais une liste vide ;
/// - retrait : `fn_retirer_exclusion(p_exclu_id)` (l.55469) — l'identifiant de l'établissement exclu, jamais l'id de
///   ligne ; exclusion : `fn_exclure_utilisateur(p_exclu_id: etablissement_id, p_type: 'SOIGNANT', p_motif)` (l.36102),
///   motif vide → null comme le web ;
/// - refus `{success:false, error}` verbatim (`IssueExclusion.refusee`), « Non authentifié » → session expirée ; succès
///   `{success:true}` suivi de la relecture des exclusions envoyées (`IssueExclusion.relues`) ; toute autre forme →
///   `.contract`. Une seule requête par mutation, aucun renvoi.
public struct SupabaseExclusionsGateway: ExclusionsPort {
    public static let rpcRecues = "fn_mes_exclusions_recues"
    public static let rpcRetirer = "fn_retirer_exclusion"
    public static let rpcExclure = "fn_exclure_utilisateur"
    public static let colonnes = "id,exclu_id,exclu_par,motif,type_exclu_par,cree_le"

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func envoyees(context: MissionReadContext) async throws -> [Exclusion] {
        try MissionQuery.validate(context: context)
        let lignes: [LigneExclusionEnvoyee]
        do {
            lignes = try await client.from("exclusions")
                .select(Self.colonnes)
                .eq("exclu_par", value: context.userId)
                .order("cree_le", ascending: false, nullsFirst: true) // NULLS FIRST de PostgreSQL en DESC, comme le web
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: ExclusionsTextes.chargementImpossible)
        }
        let noms = try await nomsSurs(ids: lignes.map(\.excluId))
        return lignes.map { $0.exclusion(nom: noms[$0.excluId]) }
    }

    public func recues(context: MissionReadContext) async throws -> [Exclusion] {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, Self.rpcRecues, fallback: ExclusionsTextes.chargementImpossible)
        try reponse.leverSiErreur(fallback: ExclusionsTextes.chargementImpossible)
        guard reponse.raw.arrayValue != nil, let lignes = PointageQuery.decoder([LigneExclusionRecue].self, reponse) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return lignes.map(\.exclusion)
    }

    public func retirer(excluId: String, context: MissionReadContext) async throws -> IssueExclusion {
        try MissionQuery.validate(context: context)
        let id = try SupabaseFavorisGateway.identifiant(excluId)
        return try await muter(Self.rpcRetirer, params: ["p_exclu_id": .string(id)], context: context)
    }

    public func exclure(etablissementId: String, motif: String, context: MissionReadContext) async throws -> IssueExclusion {
        try MissionQuery.validate(context: context)
        let id = try SupabaseFavorisGateway.identifiant(etablissementId)
        let params: JSONObject = [
            "p_exclu_id": .string(id),
            "p_type": .string(ExclusionsRegles.typeAuteur),
            "p_motif": ExclusionsRegles.motifEnvoye(motif).map(AnyJSON.string) ?? .null,
        ]
        return try await muter(Self.rpcExclure, params: params, context: context)
    }

    // MARK: - Interne

    private func muter(_ fonction: String, params: JSONObject, context: MissionReadContext) async throws -> IssueExclusion {
        let reponse = try await RPCResponse.appeler(client, fonction, params: params, fallback: ExclusionsTextes.erreurInconnue)
        if let erreur = reponse.erreur {
            if RPCResponse.estNonAuthentifie(erreur) { throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage) }
            return .refusee(message: erreur)
        }
        if reponse.estRefus { return .refusee(message: ExclusionsTextes.erreurInconnue) }
        guard reponse.estSucces else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        return .relues(try await envoyees(context: context))
    }

    private func nomsSurs(ids: [String]) async throws -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        do {
            return try await SupabaseMissionsGateway(client: client).etablissements(ids: ids).mapValues(\.nom)
        } catch let erreur as JoleneError where erreur.kind == .unauthorized || erreur.kind == .cancelled {
            throw erreur
        } catch {
            if Task.isCancelled { throw CancellationError() }
            return [:]
        }
    }
}
