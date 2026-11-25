import Foundation
import JoleneCore
import Supabase

/// `EvaluationsPort` (L4-T9), port de `EvaluationsContent` (`src/pages/EvaluationsSoignant.tsx`). **Deux RPC
/// seulement**, SECURITY DEFINER, GRANT `authenticated` (manifeste `RPC_UTILISATEUR_AUTH_INTERNE`), identité
/// `auth.uid()` lue en interne :
/// - `fn_mes_notations_recues_avec_stats(p_periode, p_note_min, p_etablissement_id, p_limit, p_offset)` — page de 20
///   (`p_limit = 20`, `p_offset = page × 20`), `p_note_min` et `p_etablissement_id` omis quand ils sont `nil`
///   (`DEFAULT NULL`) ; `{success:true, total, limit, offset, notations, stats, evolution_6m, etabs_disponibles}`,
///   lu par `EvaluationsDecodage.page` ; `{success:false, error_code:'NON_AUTHENTIFIE'}` → session expirée ; toute autre
///   forme → `.contract`, jamais une page vide ;
/// - `fn_signaler_notation(p_notation_id, p_motif)` — `{success:true}` (`IssueSignalement.signale`, la page est
///   relue par le modèle) ; refus `{success:false, error}` restitué verbatim (« Notation déjà signalée », « Vous ne
///   pouvez signaler que les notations vous concernant », compte désactivé), sauf « Non authentifié » → session
///   expirée ; exception `P0001` « Le signalement n’a pas pu être enregistré… » restituée telle quelle
///   (`ExceptionsMetierLot4.signalerNotation`).
///
/// Filtre de visibilité centralisé (`CLAUDE.md`, « Publication différée » ; fiche « Jamais … côté natif » de
/// `CONTRATS_RPC_SOIGNANT.md`) : cette gateway n'ouvre aucune requête PostgREST ni aucun canal. Les cinq lectures de
/// la RPC filtrent `masque = false AND publie_le IS NOT NULL` côté serveur ; l'app ne lit jamais la table des
/// notations, ni la vue des évaluations publiées (réservée à `service_role`), et ne recalcule aucune moyenne
/// (`EvaluationsSourceGuardTests`, garde-fou 18). Une seule requête par appel, aucun renvoi.
public struct SupabaseEvaluationsGateway: EvaluationsPort {
    public static let rpcLecture = "fn_mes_notations_recues_avec_stats"
    public static let rpcSignaler = "fn_signaler_notation"
    /// `error_code` d'une session absente (`public.sql`, corps de la RPC de lecture).
    public static let codeNonAuthentifie = "NON_AUTHENTIFIE"

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func recues(filtre: FiltreEvaluations, page: Int, context: MissionReadContext) async throws -> PageEvaluations {
        try MissionQuery.validate(context: context)
        var params: JSONObject = [
            "p_periode": .string(filtre.periode.rawValue),
            "p_limit": .integer(EvaluationsDecodage.parPage),
            "p_offset": .integer(max(0, page) * EvaluationsDecodage.parPage),
        ]
        if let noteMin = filtre.noteMin { params["p_note_min"] = .integer(noteMin) }
        if let etablissement = filtre.etablissementId { params["p_etablissement_id"] = .string(etablissement) }
        let reponse = try await RPCResponse.appeler(client, Self.rpcLecture, params: params,
                                                    fallback: EvaluationsTextes.erreurChargement)
        if reponse.codeErreur == Self.codeNonAuthentifie {
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        }
        try reponse.leverSiErreur(fallback: EvaluationsTextes.erreurChargement)
        guard let lue = EvaluationsDecodage.page(try ReponseJSON.valeur(reponse.raw)) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return lue
    }

    public func signaler(notationId: String, motif: String, context: MissionReadContext) async throws -> IssueSignalement {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, Self.rpcSignaler,
                                                    params: ["p_notation_id": .string(notationId), "p_motif": .string(motif)],
                                                    fallback: EvaluationsTextes.erreurSignalement,
                                                    exceptions: ExceptionsMetierLot4.signalerNotation)
        if let erreur = reponse.erreur {
            if RPCResponse.estNonAuthentifie(erreur) {
                throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
            }
            return .refuse(message: erreur)
        }
        guard reponse.estSucces else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        return .signale
    }
}

/// Réponse RPC (`AnyJSON` du SDK) relue en `ValeurJSON` pour les décodeurs de JoleneCore, sans perte de type
/// (booléen ≠ nombre). Partagé par les gateways des évaluations et du score (L4-T9).
enum ReponseJSON {
    static func valeur(_ json: AnyJSON) throws -> ValeurJSON {
        do {
            return try JSONDecoder().decode(ValeurJSON.self, from: JSONEncoder().encode(json))
        } catch {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
    }
}
