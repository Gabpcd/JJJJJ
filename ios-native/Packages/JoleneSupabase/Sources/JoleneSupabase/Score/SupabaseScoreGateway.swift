import Foundation
import JoleneCore
import Supabase

/// `ScorePort` (L4-T9), port de `ScoreContent` (`src/pages/PageScoreSoignant.tsx`) et de la contestation d'un
/// événement (`ModaleReclamationScore.tsx`). Cinq RPC SECURITY DEFINER, GRANT `authenticated` (manifeste
/// `RPC_UTILISATEUR_AUTH_INTERNE`), identité `auth.uid()` lue en interne, et une lecture du profil :
/// - `fn_mon_breakdown_actuel()` — ligne `scoring_breakdown` ou `{}` sans calcul, `{error:'Non authentifié'}` → session
///   expirée ; complétée de `soignants(total_missions_terminees, score_fiabilite, niveau, en_periode_probatoire)`
///   (PostgREST, ligne du soignant, comme le web l.62). Aucun défaut fabriqué : sans calcul, score et niveau sont ceux
///   du profil ou absents (`ScoreDecodage.breakdown`) ;
/// - `fn_evolution_score_soignant(p_limit)` — tableau `[{mois, score, niveau, cree_le}]` ; non authentifié : **objet**
///   `{error}` → session expirée ; toute autre forme → `.contract` ;
/// - `fn_mes_evenements_score(p_limit)` — `{success:true, type:'SOIGNANT', events:[…]}` : clé **`events`** (correction
///   16 du plan : le web lit `evenements` et n'affiche rien). Une réponse sans `events` (dont une réponse `evenements`)
///   ou d'un autre `type` → `.contract`, jamais une liste vide ; `{success:false, error:'Non authentifié'}` → session
///   expirée ; `{success:false, error:'Profil non identifié'}` verbatim ;
/// - `fn_lister_notations_recues(p_limit)` — tableau de notations publiées (filtré côté serveur), sans `signale` ;
/// - `fn_creer_reclamation_score(p_evenement_id, p_evenement_type, p_motif_categorie, p_texte_libre)` —
///   `p_evenement_type = 'SOIGNANT'` ; **le cinquième paramètre de la RPC (chemin d'un justificatif) n'est jamais
///   envoyé** (D10 : un motif « urgence médicale » avec pièce jointe inviterait à déposer un document de santé,
///   `docs/CONFORMITE.md` §1.2) ; `{success:true, reclamation_id, statut:'PENDING'}` → `.enregistree` (les événements
///   sont relus par le modèle) ; refus `{success:false, error_code, error}` → `.refusee(code:, message:)` verbatim
///   (`TEXTE_REQUIS`, `NON_CONTESTABLE`, `DEJA_TRAITE`, `RECLAMATION_EN_COURS`…), `NON_AUTHENTIFIE` → session expirée.
///
/// Filtre de visibilité centralisé : les notes ne viennent que de `fn_lister_notations_recues` ; la seule requête
/// PostgREST de cette gateway lit la ligne `soignants` du compte (`EvaluationsSourceGuardTests`, garde-fou 18).
/// Aucun renvoi.
public struct SupabaseScoreGateway: ScorePort {
    public static let rpcBreakdown = "fn_mon_breakdown_actuel"
    public static let rpcEvolution = "fn_evolution_score_soignant"
    public static let rpcEvenements = "fn_mes_evenements_score"
    public static let rpcNotations = "fn_lister_notations_recues"
    public static let rpcContester = "fn_creer_reclamation_score"
    /// Colonnes du profil lues par la page (`PageScoreSoignant.tsx` l.62).
    public static let profilSelect = "total_missions_terminees,score_fiabilite,niveau,en_periode_probatoire"
    public static let codeNonAuthentifie = "NON_AUTHENTIFIE"

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func breakdown(context: MissionReadContext) async throws -> BreakdownScore {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, Self.rpcBreakdown, fallback: ScoreTextes.chargementImpossible)
        try reponse.leverSiErreur(fallback: ScoreTextes.chargementImpossible)
        let profil: ValeurJSON?
        do {
            profil = try await client.from("soignants")
                .select(Self.profilSelect)
                .eq("id", value: context.userId)
                .maybeSingle()
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: ScoreTextes.chargementImpossible)
        }
        guard let lu = ScoreDecodage.breakdown(calcul: try ReponseJSON.valeur(reponse.raw), profil: profil) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return lu
    }

    public func evolution(mois: Int, context: MissionReadContext) async throws -> [PointEvolutionScore] {
        let reponse = try await lire(Self.rpcEvolution, limite: mois, context: context)
        guard let points = ScoreDecodage.evolution(try ReponseJSON.valeur(reponse.raw)) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return points
    }

    public func evenements(limite: Int, context: MissionReadContext) async throws -> [EvenementScore] {
        let reponse = try await lire(Self.rpcEvenements, limite: limite, context: context)
        // `{success:false, error:'Profil non identifié'}` : refus du serveur, verbatim.
        if reponse.estRefus { throw JoleneError(.unknown, reponse.erreur ?? ScoreTextes.chargementImpossible) }
        guard let evenements = ScoreDecodage.evenements(try ReponseJSON.valeur(reponse.raw)) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return evenements
    }

    public func notationsRecues(limite: Int, context: MissionReadContext) async throws -> [NotationRecue] {
        let reponse = try await lire(Self.rpcNotations, limite: limite, context: context)
        guard let notations = EvaluationsDecodage.liste(try ReponseJSON.valeur(reponse.raw)) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return notations
    }

    public func contester(evenementId: String, motif: String, texte: String,
                          context: MissionReadContext) async throws -> ReclamationScoreOutcome {
        try MissionQuery.validate(context: context)
        // Quatre paramètres seulement : aucun justificatif n'est joint par l'app (D10).
        let params: JSONObject = [
            "p_evenement_id": .string(evenementId),
            "p_evenement_type": .string(ScoreDecodage.typeSoignant),
            "p_motif_categorie": .string(motif),
            "p_texte_libre": .string(texte),
        ]
        let reponse = try await RPCResponse.appeler(client, Self.rpcContester, params: params, fallback: ScoreTextes.erreurReseau)
        if reponse.codeErreur == Self.codeNonAuthentifie || reponse.erreur.map(RPCResponse.estNonAuthentifie) == true {
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        }
        if reponse.estRefus { return .refusee(code: reponse.codeErreur, message: reponse.erreur ?? "") }
        guard reponse.success == true, reponse.erreur == nil else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return .enregistree(reclamationId: try reponse.requiredString("reclamation_id"))
    }

    // MARK: - Interne

    /// Lecture à un paramètre `p_limit` ; `{error:'Non authentifié'}` (objet, avec ou sans `success:false`) → session
    /// expirée, autre `{error}` sans drapeau → message serveur verbatim.
    private func lire(_ fonction: String, limite: Int, context: MissionReadContext) async throws -> RPCResponse {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, fonction, params: ["p_limit": .integer(limite)],
                                                    fallback: ScoreTextes.chargementImpossible)
        try reponse.leverSiErreur(fallback: ScoreTextes.chargementImpossible)
        return reponse
    }
}
