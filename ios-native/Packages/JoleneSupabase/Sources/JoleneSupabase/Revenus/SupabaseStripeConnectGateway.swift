import Foundation
import JoleneCore
import Supabase

/// `StripeConnectPort` sur Supabase (lot 3, T14a, B9), comme `src/pages/PageStripeConnect.tsx`, d'après les fiches
/// « Edge `stripe-connect-status` » et « Edge `stripe-connect-onboard` » de `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md`
/// (sources : `supabase/functions/stripe-connect-status/index.ts`, `supabase/functions/stripe-connect-onboard/index.ts`
/// du dépôt). Aucune nouvelle edge, aucune écriture directe : les deux edges existantes seules, Bearer de la session.
///
/// - Exercice : `soignants(type_exercice, statut_liberal, est_compte_test)` (colonnes de l.95, sans prénom ni nom), lu
///   **avant** tout appel d'edge ; ligne absente → profil indisponible (« ne jamais déduire le mode d'exercice d'une
///   lecture en panne », l.93).
/// - Statut : `POST stripe-connect-status`, `?force=true` quand demandé (retour de Stripe, « Actualiser » : cache serveur de
///   5 min, correction 17) ; corps 200 contrôlé par `StatutConnect.lire` (six statuts, `COMPLET` avec ses trois drapeaux) ;
///   tout refus → statut indisponible (message serveur, jamais un défaut).
/// - Onboarding : `POST stripe-connect-onboard` avec `Origin: https://jolene.app` (correction 1, D6 : sans cet en-tête,
///   403 `ORIGINE_NON_AUTORISEE`) ; 200 `{success:true, url}` (URL `https`) → lien ; `ORIGINE_NON_AUTORISEE` → erreur de
///   contrat (défaut de l'app, jamais affiché tel quel) ; `TEST_ACCOUNT_PAYMENT_DISABLED` → compte de test ; refus 403
///   « libéral » → non éligible ; autre refus → texte serveur verbatim, sinon le texte du web (l.146).
/// Rien n'est journalisé (ni URL d'onboarding, ni identifiant de compte).
public struct SupabaseStripeConnectGateway: StripeConnectPort {
    public static let statutEdge = "stripe-connect-status"
    public static let onboardingEdge = "stripe-connect-onboard"
    /// Origine envoyée à `stripe-connect-onboard` (D6) : `return_url` = `https://jolene.app/soignant/stripe-connect?success=true`.
    public static let origine = "https://jolene.app"
    /// Sous-ensemble des colonnes de `PageStripeConnect.tsx` l.95 (`prenom, nom` inutiles ici).
    public static let exerciceSelect = "type_exercice, statut_liberal, est_compte_test"
    static let origineNonAutorisee = "ORIGINE_NON_AUTORISEE"
    static let compteTestDesactive = "TEST_ACCOUNT_PAYMENT_DISABLED"

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func exercice(context: MissionReadContext) async throws -> ExerciceConnect {
        try MissionQuery.validate(context: context)
        let ligne: ExerciceConnect?
        do {
            ligne = try await client.from("soignants")
                .select(Self.exerciceSelect)
                .eq("id", value: context.userId)
                .maybeSingle()
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: StripeConnectTextes.profilIndisponible)
        }
        guard let ligne else { throw JoleneError(.unknown, StripeConnectTextes.profilIndisponible) }
        return ligne
    }

    public func statut(force: Bool, context: MissionReadContext) async throws -> StatutConnect {
        try MissionQuery.validate(context: context)
        let session = try await Self.session(client, context: context)
        let options = FunctionInvokeOptions(method: .post,
                                            query: force ? [URLQueryItem(name: "force", value: "true")] : [],
                                            headers: ["Authorization": "Bearer \(session.accessToken)"])
        let reponse = try await EdgeResponse.invoquer(client, Self.statutEdge, options: options,
                                                      fallback: StripeConnectTextes.statutIndisponible)
        if let refus = try reponse.refus(fallback: StripeConnectTextes.statutIndisponible) {
            throw JoleneError(.unknown, refus.message)
        }
        let exigence = reponse.valeur("requirements")?.arrayValue?.first?.stringValue
        guard let statut = StatutConnect.lire(statut: reponse.string("statut"),
                                              onboardingComplete: reponse.bool("onboarding_complete"),
                                              chargesEnabled: reponse.bool("charges_enabled"),
                                              payoutsEnabled: reponse.bool("payouts_enabled"),
                                              ibanLast4: reponse.string("iban_last4"),
                                              disabledReason: reponse.string("disabled_reason"),
                                              premiereExigence: exigence,
                                              message: reponse.message) else {
            throw JoleneError(.contract, StripeConnectTextes.statutIndisponible)
        }
        return statut
    }

    public func lienOnboarding(context: MissionReadContext) async throws -> ResultatLienConnect {
        try MissionQuery.validate(context: context)
        let session = try await Self.session(client, context: context)
        let options = FunctionInvokeOptions(method: .post,
                                            headers: ["Authorization": "Bearer \(session.accessToken)", "Origin": Self.origine])
        let reponse = try await EdgeResponse.invoquer(client, Self.onboardingEdge, options: options,
                                                      fallback: StripeConnectTextes.erreurConnexionStripe)
        if let refus = try reponse.refus(fallback: StripeConnectTextes.erreurConnexionStripe) {
            switch refus.code {
            case Self.origineNonAutorisee?:
                throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
            case Self.compteTestDesactive?:
                return .compteTest
            default:
                // Refus « libéral » de l'edge (l.120-131) : 403 dont le texte nomme l'exercice libéral (web l.142).
                if refus.statut == 403, refus.message.contains("libéral") { return .nonEligible(message: refus.message) }
                return .refuse(code: refus.code, message: refus.message)
            }
        }
        guard reponse.success == true, let texte = reponse.string("url"), let url = URL(string: texte),
              url.scheme?.lowercased() == "https", url.host != nil else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return .lien(url)
    }

    /// Session de l'utilisateur du contexte (`auth.session`, rafraîchie si expirée), Bearer des deux edges.
    static func session(_ client: SupabaseClient, context: MissionReadContext) async throws -> Session {
        let session: Session
        do {
            session = try await client.auth.session
        } catch {
            if error is CancellationError { throw JoleneError(.cancelled, SupabaseErrorMapping.cancelledMessage) }
            throw SupabaseErrorMapping.map(error, fallback: SupabaseErrorMapping.unauthorizedMessage)
        }
        guard session.user.id.uuidString.lowercased() == context.userId.lowercased() else {
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        }
        return session
    }
}
