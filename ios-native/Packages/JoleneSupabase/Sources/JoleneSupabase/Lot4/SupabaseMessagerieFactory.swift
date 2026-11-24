import Foundation
import JoleneCore
import Supabase

extension SupabaseLot4 {
    /// Fabrique Supabase du port « messagerie » (`Gateways.messagerie`), T7a : `SupabaseMessagerieGateway` (liste,
    /// fil, envoi par l'edge `messagerie-validate`, lecture, saisie, présence, blocage, signalement, « Écrire à
    /// l'établissement »).
    static func messagerie(client: SupabaseClient) -> MessageriePort { SupabaseMessagerieGateway(client: client) }
}
