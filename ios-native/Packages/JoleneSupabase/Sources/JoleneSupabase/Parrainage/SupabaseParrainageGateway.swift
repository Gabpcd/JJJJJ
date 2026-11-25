import Foundation
import JoleneCore
import Supabase

/// `ParrainagePort` (L4-T6), port de `PageParrainage.tsx` (lecture, l.55-60) et de `useAppliquerParrainage.ts`
/// (application, l.66). Deux RPC SECURITY DEFINER, GRANT `authenticated` (manifeste `RPC_UTILISATEUR_AUTH_INTERNE`),
/// identité `auth.uid()` lue en interne, et une lecture PostgREST de la ligne `soignants` du compte :
/// - `soignants` : `code_parrainage, badge_ambassadeur`, filtre `id = userId`, `maybeSingle` (aucune ligne : profil à
///   préparer) ;
/// - `fn_obtenir_mes_parrainages()` : `{filleuls, total_gains_eur, nb_primes_versees, prime_eur, seuil_gmv_eur,
///   mon_parrain}` ; `{error:'Non authentifié'}` → session expirée ; toute réponse sans tableau `filleuls` → `.contract`
///   (jamais un parrainage vide). Montants et seuil serveur lus, jamais affichés par l'écran natif (T6-HS) ;
/// - `fn_appliquer_parrainage(p_code)` : le code part seulement s'il a la forme du web (`ParrainageCapture.normaliser`,
///   jamais une valeur brute d'un lien) ; `{success:true, message}` : le message (promesse de prime contradictoire,
///   HARD STOP n°4) n'est **jamais** rendu, le succès n'est annoncé qu'après la relecture qui montre `mon_parrain`
///   (PRINCIPES §3) ; refus définitifs `{error}` (`ParrainageApplication.refusDefinitifs`) restitués verbatim, autres
///   `{error}` (« Non authentifié », compte suspendu, profil introuvable) à réessayer ; exception PostgREST
///   (« Attribution du parrain non persistée », `P0001`) et transport : erreur, code conservé par l'appelant.
/// Une requête par lecture, aucun renvoi.
public struct SupabaseParrainageGateway: ParrainagePort {
    public static let rpcLire = "fn_obtenir_mes_parrainages"
    public static let rpcAppliquer = "fn_appliquer_parrainage"
    public static let profilSelect = "code_parrainage,badge_ambassadeur"

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func etat(context: MissionReadContext) async throws -> EtatParrainage {
        try MissionQuery.validate(context: context)
        async let profil = lireProfil(context: context)
        async let reponse = RPCResponse.appeler(client, Self.rpcLire, fallback: ParrainageTextes.indisponible)
        let (ligne, brute) = try await (profil, reponse)
        try brute.leverSiErreur(fallback: ParrainageTextes.indisponible)
        guard let etat = ParrainageDecodage.etat(profil: ligne, reponse: try SupabaseFiltresGateway.valeur(brute.raw)) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return etat
    }

    public func appliquer(code: String, context: MissionReadContext) async throws -> ApplicationParrainage {
        try MissionQuery.validate(context: context)
        // Gap verrouillé : un code hors forme (lien non fiable) n'est jamais envoyé.
        guard let normalise = ParrainageCapture.normaliser(code) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        let reponse = try await RPCResponse.appeler(client, Self.rpcAppliquer, params: ["p_code": .string(normalise)],
                                                    fallback: ParrainageTextes.indisponible)
        if let erreur = reponse.erreur {
            return ParrainageApplication.refusDefinitifs.contains(erreur) ? .refusDefinitif(message: erreur) : .aReessayer
        }
        guard reponse.success == true else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        // Relecture : succès annoncé seulement si le parrain est rattaché ; sinon, nouvel essai à la session suivante
        // (le serveur répondra alors « déjà appliqué », refus définitif silencieux).
        guard let relu = try? await etat(context: context), relu.monParrain != nil else { return .aReessayer }
        return .appliquee
    }

    private func lireProfil(context: MissionReadContext) async throws -> ValeurJSON? {
        do {
            let ligne: ValeurJSON? = try await client.from("soignants")
                .select(Self.profilSelect)
                .eq("id", value: context.userId)
                .maybeSingle()
                .execute()
                .value
            return ligne
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: ParrainageTextes.indisponible)
        }
    }
}
