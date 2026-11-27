import Foundation
import JoleneCore
import Supabase

/// `BulletinsPort` (L4-T10), port de `listerCopiesBulletins`, `ouvrirCopieBulletin` et `signalerCopieBulletin`
/// (`src/lib/copiesBulletins.ts` l.90-96, l.215-255) côté soignant :
/// - `fn_lister_copies_bulletins(p_etablissement_id, p_mission_id)` (`public.sql` l.40397, GRANT `authenticated`) : les
///   deux paramètres à `null` (copies du soignant connecté) ; réponse validée STRICTEMENT (`CopieBulletinValidation`) :
///   une ligne invalide refuse la liste (« La liste des copies ne peut pas être vérifiée. Réessayez. ») ; 42501
///   `COPIE_ACCES_REFUSE` ou toute autre erreur → texte du web (« Impossible de charger les copies… »), jamais « session
///   expirée » pour ce refus métier, jamais le code machine ;
/// - edge `copies-bulletins` `{action:'telecharger', copie_id}` (`handler.ts`) : Bearer de la session de l'epoch, en-tête
///   `Cache-Control: no-store` ; 200 `application/pdf` → octets vérifiés (type, taille, SHA-256 CryptoKit,
///   `BulletinsTelechargement`) ; 410 `COPIE_RETIREE` → `RefusCopieBulletin.retiree` ; 401 → session expirée ; tout autre
///   statut, un `application/json` en 200 ou un relais en échec → `RefusCopieBulletin.indisponible`. Une copie `RETIREE`
///   n'est jamais demandée. Ni les octets, ni le corps, ni le code machine ne sont journalisés ;
/// - `fn_signaler_copie_bulletin(p_copie_id, p_motif)` (l.56774) : `{ok:true}` exigé, puis relecture de la liste
///   (`DESTINATAIRE` la rend `RETIREE`) ; 42501 `COPIE_ACCES_REFUSE` / 22023 `COPIE_MOTIF_INVALIDE` → texte du web
///   (« Le signalement n’a pas été confirmé. Réessayez. »).
/// Une seule requête par appel, aucun renvoi.
public struct SupabaseBulletinsGateway: BulletinsPort {
    public static let rpcLister = "fn_lister_copies_bulletins"
    public static let rpcSignaler = "fn_signaler_copie_bulletin"
    public static let codeRetiree = "COPIE_RETIREE"

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func copies(context: MissionReadContext) async throws -> [CopieBulletin] {
        try MissionQuery.validate(context: context)
        let texte = LibellesWeb.CopiesBulletins.chargementImpossible
        let reponse = try await RPCResponse.appeler(client, Self.rpcLister,
                                                    params: ["p_etablissement_id": .null, "p_mission_id": .null],
                                                    fallback: texte, exceptions: ExceptionsMetierLot4.listerCopiesBulletins)
        if reponse.estRefus || reponse.erreur != nil {
            if let erreur = reponse.erreur, RPCResponse.estNonAuthentifie(erreur) {
                throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
            }
            throw JoleneError(.unknown, texte)
        }
        do {
            return try CopieBulletinValidation.valider(try Self.valeur(reponse.raw))
        } catch is CopieBulletinValidation.ListeNonVerifiable {
            throw JoleneError(.contract, CopieBulletinValidation.messageListeNonVerifiable)
        }
    }

    public func telecharger(copie: CopieBulletin, context: MissionReadContext) async throws -> PDFVerifie {
        try MissionQuery.validate(context: context)
        guard CopieBulletinValidation.telechargeable(copie.statut) else { throw RefusCopieBulletin.retiree }
        let session = try await SupabaseStripeConnectGateway.session(client, context: context)
        let options = FunctionInvokeOptions(method: .post,
                                            headers: ["Authorization": "Bearer \(session.accessToken)",
                                                      "Cache-Control": "no-store"],
                                            body: ["action": BulletinsTelechargement.action, "copie_id": copie.id])
        let recu: (statut: Int, type: String?, corps: Data)
        do {
            recu = try await client.functions.invoke(BulletinsTelechargement.edge, options: options) { corps, reponse in
                (reponse.statusCode, reponse.value(forHTTPHeaderField: "Content-Type"), corps)
            }
        } catch FunctionsError.httpError(let statut, let corps) {
            throw Self.refus(statut: statut, corps: corps)
        } catch FunctionsError.relayError {
            throw RefusCopieBulletin.indisponible
        } catch {
            let erreur = SupabaseErrorMapping.map(error, fallback: RefusCopieBulletin.indisponible.message)
            if erreur.kind == .cancelled || erreur.kind == .unauthorized { throw erreur }
            throw RefusCopieBulletin.indisponible
        }
        guard (200..<300).contains(recu.statut) else { throw Self.refus(statut: recu.statut, corps: recu.corps) }
        return try BulletinsTelechargement.verifier(donnees: recu.corps, typeContenu: recu.type, copie: copie)
    }

    public func signaler(copieId: String, motif: MotifSignalementCopie,
                         context: MissionReadContext) async throws -> [CopieBulletin] {
        try MissionQuery.validate(context: context)
        let texte = LibellesWeb.CopiesBulletins.signalementNonConfirme
        let reponse = try await RPCResponse.appeler(client, Self.rpcSignaler,
                                                    params: ["p_copie_id": .string(copieId), "p_motif": .string(motif.rawValue)],
                                                    fallback: texte, exceptions: ExceptionsMetierLot4.signalerCopieBulletin)
        if let erreur = reponse.erreur, RPCResponse.estNonAuthentifie(erreur) {
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        }
        guard reponse.ok == true, !reponse.estRefus, reponse.erreur == nil else { throw JoleneError(.unknown, texte) }
        return try await copies(context: context)
    }

    // MARK: - Interne

    /// Refus de l'edge (corps `{error:'CODE'}` lu, jamais affiché ni journalisé).
    static func refus(statut: Int, corps: Data) -> Error {
        if statut == 401 { return JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage) }
        if statut == 410, EdgeResponse(statut: statut, corps: corps).erreur == codeRetiree { return RefusCopieBulletin.retiree }
        return RefusCopieBulletin.indisponible
    }

    /// Réponse RPC (`AnyJSON` du SDK) relue en `ValeurJSON`, sans perte de type (booléen ≠ nombre).
    static func valeur(_ json: AnyJSON) throws -> ValeurJSON {
        do {
            return try JSONDecoder().decode(ValeurJSON.self, from: JSONEncoder().encode(json))
        } catch {
            throw JoleneError(.contract, CopieBulletinValidation.messageListeNonVerifiable)
        }
    }
}
