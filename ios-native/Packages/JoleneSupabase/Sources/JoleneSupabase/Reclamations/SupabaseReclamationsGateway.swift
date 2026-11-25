import Foundation
import JoleneCore
import Supabase

/// `ReclamationsPort` sur Supabase (lot 4, T8 ; `docs/mobile-swift/LOT4_PLAN.md` §2.3-§2.4), port de
/// `ReclamationsContent` (`MesReclamations.tsx`), avec le JWT du soignant. Réclamations générales seulement.
///
/// - `lister` : PostgREST `reclamations` sous RLS (`reclamations_select_own` : `utilisateur_id = auth.uid()`),
///   colonnes du web (l.78), `cree_le` décroissant. Une erreur est une erreur : jamais une liste vide à sa place.
/// - `soumettre` : `fn_soumettre_reclamation(p_categorie, p_sujet, p_details)` (`p_mission_id` jamais envoyé, comme le
///   web). Le serveur répond `{id, statut:'EN_ATTENTE'}`, **sans `success` ni `ok`** : le succès est l'`id` rendu
///   (`requiredString`, `estSucces` serait faux ici), puis la ligne relue par cet identifiant ; un `id` absent ou une
///   ligne jamais relue lève `.contract` (aucun succès fabriqué, PRINCIPES §3). Refus `{error}` en HTTP 200 :
///   « Non authentifié » → session expirée, « Rôle non autorisé » → `.refusee` mot pour mot. Catégorie hors liste :
///   exception PostgREST `23514` (`reclamations_categorie_check`), lue avant `SupabaseErrorMapping`
///   (`ExceptionsMetierLot4.soumettreReclamation`) et rendue par le libellé générique du web, jamais par le texte
///   PostgreSQL ni par « session expirée ». Une seule requête d'écriture, aucun renvoi.
public struct SupabaseReclamationsGateway: ReclamationsPort {
    public static let rpcSoumission = "fn_soumettre_reclamation"
    public static let table = "reclamations"
    /// Colonnes lues par le web (`MesReclamations.tsx` l.78), jamais `select=*`.
    public static let colonnes = "id,categorie,sujet,details,statut,reponse_admin,cree_le,traite_le"

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func lister(context: MissionReadContext) async throws -> [Reclamation] {
        try MissionQuery.validate(context: context)
        do {
            return try await client.from(Self.table)
                .select(Self.colonnes)
                .eq("utilisateur_id", value: context.userId)
                .order("cree_le", ascending: false, nullsFirst: true) // = `order=cree_le.desc` du web (défaut PostgREST)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: ReclamationsTextes.chargementImpossible)
        }
    }

    public func soumettre(categorie: CategorieReclamation, sujet: String, details: String,
                          context: MissionReadContext) async throws -> IssueReclamation {
        try MissionQuery.validate(context: context)
        let params: JSONObject = [
            "p_categorie": .string(categorie.rawValue),
            "p_sujet": .string(LitigesPresentation.nettoyer(sujet)),
            "p_details": .string(LitigesPresentation.nettoyer(details)),
        ]
        let fallback = ReclamationsTextes.erreurSoumission
        let reponse = try await RPCResponse.appeler(client, Self.rpcSoumission, params: params, fallback: fallback,
                                                    exceptions: ExceptionsMetierLot4.soumettreReclamation)
        // Exception de contrainte restituée (23514) : libellé générique, jamais le texte PostgreSQL.
        if reponse.sqlstate != nil { return .refusee(message: fallback) }
        if let erreur = reponse.erreur {
            if RPCResponse.estNonAuthentifie(erreur) {
                throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
            }
            return .refusee(message: erreur)
        }
        let id = try reponse.requiredString("id")
        // Réclamation annoncée mais jamais relue : aucun succès fabriqué (PRINCIPES §3).
        guard let relue = try await lire(id, fallback: fallback) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return .soumise(relue)
    }

    // MARK: - Interne

    private func lire(_ id: String, fallback: String) async throws -> Reclamation? {
        do {
            let lignes: [Reclamation] = try await client.from(Self.table)
                .select(Self.colonnes)
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value
            return lignes.first { $0.id == id }
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: fallback)
        }
    }
}
