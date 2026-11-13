import Foundation
import JoleneCore
import Supabase

/// `PushRegistrationPort` (lot 3, T4) : contrat du web repris à l'identique, aucune modification backend.
///
/// - Enregistrement : `fn_upsert_token_push(p_token, p_plateforme: 'IOS')` (web `src/lib/pushNative.ts`
///   l.32-35), token APNs en hexadécimal minuscule. La fonction renvoie `void` : appel par
///   `RPCResponse.appelerSansCorps` (`execute()` sans décodage, correction 16 ; 204 ou 200 à corps vide =
///   succès). 42501 « Non authentifie » → `.unauthorized` (mapping inchangé) ; 22023 (token ou plateforme
///   invalide, l.64645-64674) restitué avant `SupabaseErrorMapping` puis refusé en `.contract`, sans renvoi.
///   L'appelant (`PushCoordinator`) avale toute erreur : jamais de déconnexion.
/// - Désactivation : `fn_desactiver_mon_token_push(p_token)` (web `src/lib/pushDeviceToken.ts` l.90-102) ;
///   `{success:true, tokens_desactives}` → `.desactive` ; `{success:false, error}` (« Non authentifie »,
///   « Token push invalide », l.30186-30191) → `.nonDesactive`, jamais bloquant ni « session expirée » ;
///   toute autre forme n'est jamais un succès. Le délai de 2,5 s est posé par l'appelant (D3).
public struct SupabasePushGateway: PushRegistrationPort {
    public static let enregistrementRPC = "fn_upsert_token_push"
    public static let desactivationRPC = "fn_desactiver_mon_token_push"
    public static let plateforme = PushCoordinator.plateforme
    /// SQLSTATE métier de `fn_upsert_token_push` restitués avant `SupabaseErrorMapping`.
    public static let exceptionsMetier: Set<String> = ["22023"]
    /// Messages de repli, jamais affichés (échec avalé par le coordinateur).
    static let fallbackEnregistrement = "L'appareil n'a pas pu être enregistré pour les notifications."
    static let fallbackDesactivation = "Le token de notification de l'appareil n'a pas pu être désactivé."

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func enregistrer(token: String, context: MissionReadContext) async throws {
        try MissionQuery.validate(context: context)
        let params: JSONObject = ["p_token": .string(token), "p_plateforme": .string(Self.plateforme)]
        let issue = try await RPCResponse.appelerSansCorps(client, Self.enregistrementRPC, params: params,
                                                           fallback: Self.fallbackEnregistrement,
                                                           exceptionsMetier: Self.exceptionsMetier)
        switch issue {
        case .succes:
            return
        case .refus:
            // Token ou plateforme refusés : l'app envoie une valeur que le backend n'accepte pas.
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
    }

    public func desactiver(token: String) async throws -> IssueDesactivationPush {
        let reponse = try await RPCResponse.appeler(client, Self.desactivationRPC, params: ["p_token": .string(token)],
                                                    fallback: Self.fallbackDesactivation)
        if reponse.success == false { return .nonDesactive }
        if reponse.estSucces { return .desactive(tokensDesactives: reponse.int("tokens_desactives") ?? 0) }
        try reponse.leverSiErreur(fallback: Self.fallbackDesactivation)
        throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
    }
}
