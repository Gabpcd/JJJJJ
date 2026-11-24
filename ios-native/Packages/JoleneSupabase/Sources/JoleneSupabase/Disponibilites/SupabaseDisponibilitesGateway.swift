import Foundation
import JoleneCore
import Supabase

/// `DisponibilitesPort` (L4-T5), port de `src/pages/MesDisponibilites.tsx`, sous le JWT du soignant :
/// - lecture PostgREST de `disponibilites_soignant` (`select=jour,creneau`, `jour >= <jour Paris>`, l.51-53 ; RLS
///   `dispos_soignant_select` et restrictive « compte actif », `GRANT SELECT` à `authenticated`). La policy admet aussi
///   l'administrateur : la lecture est bornée à `soignant_id = <identité de la session>`, jamais les lignes d'un autre ;
/// - `fn_definir_disponibilite(p_jour, p_creneau, p_disponible)` (SECURITY DEFINER, GRANT `authenticated`, manifeste
///   `RPC_UTILISATEUR_AUTH_INTERNE`, identité `auth.uid()` lue en interne) : `{success:true}`, puis relecture de la
///   **semaine civile** du jour (du lundi au dimanche), rendue au modèle (`IssueDisponibilite.relue`, aucun état
///   optimiste) ; refus `{error}` en HTTP 200 restitué verbatim (`IssueDisponibilite.refusee` : « Profil soignant
///   introuvable », « Créneau invalide », « La disponibilité doit être entre aujourd'hui et J+90 ») ; toute autre forme
///   → `.contract`. L'app n'envoie que `JOURNEE` et `NUIT` (`CreneauDispo`), comme le web.
/// Une réponse de lecture illisible (forme, jour qui n'est pas une date) est une erreur de contrat, jamais une grille
/// vide. Un jour qui n'est pas une date `yyyy-MM-dd` n'est jamais envoyé. Aucune exception PostgREST métier déclarée
/// par la RPC : le mapping des lots 0-1 s'applique (`RPCResponse.appeler`). La bascule n'est jamais renvoyée (seule une
/// lecture GET, idempotente, est rejouée par le SDK sur coupure) : si la relecture échoue après une bascule acceptée,
/// l'erreur remonte et le modèle réconcilie par relecture.
public struct SupabaseDisponibilitesGateway: DisponibilitesPort {
    public static let rpcDefinir = "fn_definir_disponibilite"
    public static let table = "disponibilites_soignant"

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func lister(depuis: JourParis, context: MissionReadContext) async throws -> Set<DispoCle> {
        try MissionQuery.validate(context: context)
        guard depuis.estValide else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        return try await lire(context: context) { $0.gte("jour", value: depuis.iso) }
    }

    public func definir(jour: JourParis, creneau: CreneauDispo, disponible: Bool,
                        context: MissionReadContext) async throws -> IssueDisponibilite {
        try MissionQuery.validate(context: context)
        // Gap verrouillé : un jour qui n'est pas une date n'est jamais envoyé (le serveur lèverait une erreur de type).
        guard let semaine = jour.semaine else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        let params: JSONObject = [
            "p_jour": .string(jour.iso),
            "p_creneau": .string(creneau.rawValue),
            "p_disponible": .bool(disponible),
        ]
        let reponse = try await RPCResponse.appeler(client, Self.rpcDefinir, params: params,
                                                    fallback: DisponibilitesTextes.basculeImpossible)
        if let erreur = reponse.erreur {
            if RPCResponse.estNonAuthentifie(erreur) {
                throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
            }
            return .refusee(message: erreur)
        }
        guard reponse.estSucces else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        return .relue(try await lire(context: context) {
            $0.gte("jour", value: semaine.lowerBound.iso).lte("jour", value: semaine.upperBound.iso)
        })
    }

    // MARK: - Interne

    private func lire(context: MissionReadContext,
                      _ borner: (PostgrestFilterBuilder) -> PostgrestFilterBuilder) async throws -> Set<DispoCle> {
        let lignes: [LigneDisponibilite]
        do {
            lignes = try await borner(client.from(Self.table)
                .select(DisponibilitesLecture.colonnes)
                .eq("soignant_id", value: context.userId))
                .execute()
                .value
        } catch is DecodingError {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: DisponibilitesTextes.echecMessage)
        }
        guard let cles = DisponibilitesLecture.cles(lignes) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return cles
    }
}
