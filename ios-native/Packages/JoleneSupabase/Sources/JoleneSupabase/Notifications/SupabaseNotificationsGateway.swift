import Foundation
import JoleneCore
import Supabase

/// `NotificationsCenterPort` (lot 3, T5) sur la table `notifications` (PostgREST, client authentifié ordinaire),
/// contrat du web repris à l'identique (`src/pages/PageNotifications.tsx` l.53-58, l.91) ; aucune modification
/// backend, aucune RPC.
///
/// - Liste : `select(id, titre, corps, type, lien, lue, lue_le, cree_le)`, `destinataire_id = <utilisateur>`,
///   `order(cree_le desc)`, `limit(200)`. RLS `pol_notif_select` (`public.sql` l.79399 : destinataire ou admin),
///   restrictive `pol_compte_auth_actif_restrictive` (l.78759), GRANT SELECT/UPDATE `authenticated` (l.86271) ;
///   une liste vide (RLS) est une liste vide, jamais une erreur.
/// - Marquer lue : `update {lue: true, lue_le: <maintenant ISO>}` filtré par `id` **et** `destinataire_id`
///   (`pol_notif_update` l.79403 ; triggers `fn_protect_notification_update` l.50476 et
///   `dec_proteger_contenu_notification` l.2951 : le destinataire ne peut changer que `lue` et `lue_le`), puis
///   **relecture** de la ligne : succès seulement si elle est relue avec `lue = true`. Une mise à jour qui ne
///   touche aucune ligne (RLS, ligne d'un autre compte) est relue non lue ou absente → erreur, jamais un faux
///   succès (PRINCIPES §3). Pas de DELETE (`pol_notif_delete` réservé aux admins, correction 9 du blueprint).
public struct SupabaseNotificationsGateway: NotificationsCenterPort {
    public static let table = "notifications"
    public static let colonnes = "id, titre, corps, type, lien, lue, lue_le, cree_le"
    public static let limite = CentreNotificationsModel.limite
    /// Messages de repli (le centre affiche ses propres textes web) : jamais un détail technique.
    static let fallbackListe = CentreNotificationsTextes.erreurChargement
    static let fallbackLecture = CentreNotificationsTextes.marquerLueImpossible

    /// Corps de la mise à jour : seuls les deux champs modifiables par le destinataire.
    private struct Marquage: Encodable, Sendable {
        let lue: Bool
        let lueLe: String

        enum CodingKeys: String, CodingKey {
            case lue
            case lueLe = "lue_le"
        }
    }

    private let client: SupabaseClient
    private let clock: any ClockPort

    public init(client: SupabaseClient, clock: any ClockPort = SystemClock()) {
        self.client = client
        self.clock = clock
    }

    public func liste(context: MissionReadContext) async throws -> [NotificationJolene] {
        try MissionQuery.validate(context: context)
        do {
            return try await client.from(Self.table)
                .select(Self.colonnes)
                .eq("destinataire_id", value: context.userId)
                .order("cree_le", ascending: false)
                .limit(Self.limite)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.fallbackListe)
        }
    }

    public func marquerLue(id: String, context: MissionReadContext) async throws -> NotificationJolene {
        try MissionQuery.validate(context: context)
        guard !id.isEmpty else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        do {
            try await client.from(Self.table)
                .update(Marquage(lue: true, lueLe: MissionQuery.isoTimestamp(clock.now())), returning: .minimal)
                .eq("id", value: id)
                .eq("destinataire_id", value: context.userId)
                .execute()
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.fallbackLecture)
        }
        let relue: NotificationJolene?
        do {
            relue = try await client.from(Self.table)
                .select(Self.colonnes)
                .eq("id", value: id)
                .eq("destinataire_id", value: context.userId)
                .maybeSingle()
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.fallbackLecture)
        }
        guard let relue, relue.id == id, relue.lue else {
            throw JoleneError(.unknown, Self.fallbackLecture)
        }
        return relue
    }
}
