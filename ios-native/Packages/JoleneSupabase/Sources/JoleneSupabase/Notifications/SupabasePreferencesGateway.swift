import Foundation
import JoleneCore
import Supabase

/// `NotificationPreferencesPort` sur Supabase (lot 3, T6), comme `PageParametresNotifications.tsx` ; fiches
/// `fn_obtenir_mes_preferences_notifications` et `fn_modifier_preferences_notifications` de
/// `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md`.
///
/// Lecture (l.113-131), dans l'ordre du web :
/// 1. `fn_obtenir_mes_preferences_notifications()` (JWT ; crée la ligne par défaut, idempotente) — `{error}`
///    jamais un succès (`RPCResponse` : « Non authentifié » → session expirée, sinon message verbatim) ;
/// 2. `soignants.select('sms_alertes_actives, type_exercice').eq('id', <utilisateur de la session>)`
///    (`maybeSingle`, sans ligne → alerte non affichée) ; une erreur fait échouer l'écran (l.123) ;
/// 3. décodage strict `PreferencesNotifications.decoder` (quatre booléens, jamais de défaut).
///
/// Écriture (l.206-249) :
/// 1. RPC à cinq paramètres ; `p_par_evenement` = `parEvenementAEnvoyer` (catalogue soignant seul) ;
///    `{success:true}` seul succès ; une valeur hors enum (22P02) est un refus de contrat, sans détail ;
/// 2. si l'alerte a été lue (`smsAlertesActives` non nil) : `PATCH soignants` de la seule colonne accordée
///    (`sms_alertes_actives`, GRANT l.85758), `return=minimal` comme supabase-js ; son échec n'arrête pas
///    la relecture : la valeur relue, différente de la demande, fait annoncer l'échec partiel (web l.236-238) ;
/// 3. relecture complète (`lire`), rendue au modèle, qui ne déclare un succès que sur concordance.
/// Aucune requête n'est renvoyée : seules les lectures `GET` bénéficient du rejeu du SDK (503, réseau).
public struct SupabasePreferencesGateway: NotificationPreferencesPort {
    public static let rpcLecture = "fn_obtenir_mes_preferences_notifications"
    public static let rpcEcriture = "fn_modifier_preferences_notifications"
    /// Colonnes lues avec les préférences (web l.122).
    public static let soignantSelect = "sms_alertes_actives,type_exercice"
    /// Exception métier de l'écriture : valeur hors enum (casts l.44130-44131), refus de contrat.
    public static let exceptionsEcriture: Set<String> = ["22P02"]

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func lire(context: MissionReadContext) async throws -> PreferencesNotifications {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, Self.rpcLecture, fallback: PreferencesTextes.chargementImpossible)
        try reponse.leverSiErreur(fallback: PreferencesTextes.chargementImpossible)
        let ligne: ValeurJSON?
        do {
            ligne = try await client.from("soignants")
                .select(Self.soignantSelect)
                .eq("id", value: context.userId)
                .maybeSingle()
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: PreferencesTextes.chargementImpossible)
        }
        return try PreferencesNotifications.decoder(preferences: Self.valeur(reponse.raw), soignant: ligne)
    }

    public func enregistrer(_ preferences: PreferencesNotifications,
                            context: MissionReadContext) async throws -> PreferencesNotifications {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, Self.rpcEcriture, params: Self.parametres(preferences),
                                                    fallback: PreferencesTextes.echecEnregistrement,
                                                    exceptionsMetier: Self.exceptionsEcriture)
        if reponse.sqlstate != nil {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        try reponse.leverSiErreur(fallback: PreferencesTextes.echecEnregistrement)
        guard reponse.estSucces else {
            // `data?.error` du web s'il existe (refus avec drapeau compris), sinon son repli (l.224, l.244).
            throw JoleneError(.unknown, reponse.erreur ?? PreferencesTextes.echecEnregistrement)
        }
        if let alerte = preferences.smsAlertesActives {
            do {
                try await client.from("soignants")
                    .update(["sms_alertes_actives": AnyJSON.bool(alerte)], returning: .minimal)
                    .eq("id", value: context.userId)
                    .execute()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Échec de la seule colonne : la relecture le montre (valeur inchangée) et le modèle annonce
                // l'échec partiel du web ; la RPC, elle, a réussi.
            }
        }
        return try await lire(context: context)
    }

    /// Corps de `fn_modifier_preferences_notifications` : quatre canaux et `p_par_evenement`
    /// (`[{type_evenement, canal, actif}]`, catalogue soignant seul).
    static func parametres(_ preferences: PreferencesNotifications) -> JSONObject {
        let lignes: [AnyJSON] = preferences.parEvenementAEnvoyer.map { ligne in
            .object(["type_evenement": .string(ligne.typeEvenement), "canal": .string(ligne.canal.rawValue),
                     "actif": .bool(ligne.actif)])
        }
        return [
            "p_canal_email": .bool(preferences.canalEmail),
            "p_canal_sms": .bool(preferences.canalSms),
            "p_canal_push": .bool(preferences.canalPush),
            "p_canal_in_app": .bool(preferences.canalInApp),
            "p_par_evenement": .array(lignes),
        ]
    }

    /// Réponse RPC (`AnyJSON` du SDK) relue en `ValeurJSON`, sans perte de type (booléen ≠ nombre).
    static func valeur(_ json: AnyJSON) throws -> ValeurJSON {
        do {
            return try JSONDecoder().decode(ValeurJSON.self, from: JSONEncoder().encode(json))
        } catch {
            throw JoleneError(.contract, PreferencesNotifications.messageIndisponible)
        }
    }
}
