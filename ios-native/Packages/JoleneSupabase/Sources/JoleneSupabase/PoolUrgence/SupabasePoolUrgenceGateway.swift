import Foundation
import JoleneCore
import Supabase

/// `PoolUrgencePort` (L4-T11), port de `PoolUrgenceSoignant.tsx` et `PoolUrgenceToggle.tsx`. Trois RPC SECURITY DEFINER,
/// GRANT `authenticated` (manifeste `RPC_UTILISATEUR_AUTH_INTERNE`), identité `auth.uid()` lue en interne :
/// - `fn_pool_urgence_missions_pour_soignant()` (`public.sql` l.47819) : `{missions, pool_actif, rayon_km, sms_opt_in}`,
///   sans `success` ; complétée, comme le web (l.70-84), par PostgREST `missions(id, nb_creneaux, duree_heures)` et les
///   créneaux PREVISIONNEL hors pauses (`SupabaseMissionsGateway.slots`, pagination contrôlée) ; un planning illisible
///   marque la mission « planning non exact » (acceptation impossible), jamais un planning vide accepté ;
/// - `fn_toggle_pool_urgence(p_actif, p_rayon_km, p_creneaux = [])` (l.62077) : **seule** écriture native de
///   la disponibilité urgence de `soignants` (D26, correction 17, garde `PoolUrgenceSourceGuardTests`) ; refus `{error}` sans drapeau
///   (rayon hors 1-200, documents) restitué verbatim ; un rayon hors bornes serveur n'est jamais envoyé (refus verbatim
///   local, mêmes mots que le serveur) ;
/// - `fn_toggle_pool_urgence_sms(p_actif)` (l.62128) : `{success:true, pool_urgence_sms_opt_in}`.
/// « Non authentifié » → session expirée. Chaque bascule acceptée est suivie de la relecture de l'état (`IssuePool.relu`) ;
/// toute autre forme → `.contract`. Une seule requête par appel, aucun renvoi.
public struct SupabasePoolUrgenceGateway: PoolUrgencePort {
    public static let rpcEtat = "fn_pool_urgence_missions_pour_soignant"
    public static let rpcBasculer = "fn_toggle_pool_urgence"
    public static let rpcSMS = "fn_toggle_pool_urgence_sms"
    /// Colonnes complémentaires lues comme le web (l.74).
    public static let colonnesMissions = "id,nb_creneaux,duree_heures"

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    private struct Complement: Decodable {
        var id: String
        var nbCreneaux: Int?
        var dureeHeures: Double?
        enum CodingKeys: String, CodingKey {
            case id
            case nbCreneaux = "nb_creneaux"
            case dureeHeures = "duree_heures"
        }
    }

    public func etat(context: MissionReadContext) async throws -> EtatPool {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, Self.rpcEtat, fallback: PoolUrgenceTextes.chargementImpossible)
        try reponse.leverSiErreur(fallback: PoolUrgenceTextes.chargementImpossible)
        if let erreur = reponse.erreur { throw JoleneError(.unknown, erreur) }
        guard let corps = PointageQuery.decoder(ReponsePoolUrgence.self, reponse), corps.estLisible,
              let lignes = corps.missions, let actif = corps.poolActif, let sms = corps.smsOptIn else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return EtatPool(actif: actif, rayonKm: corps.rayonKm, smsOptIn: sms, missions: try await enrichir(lignes))
    }

    public func basculer(actif: Bool, rayonKm: Int, context: MissionReadContext) async throws -> IssuePool {
        try MissionQuery.validate(context: context)
        // Gap verrouillé : un rayon que le serveur refuserait n'est jamais envoyé (même texte que la RPC).
        guard PoolUrgenceRegles.rayonServeur.contains(rayonKm) else { return .refuse(message: PoolUrgenceRegles.refusRayon) }
        let params: JSONObject = ["p_actif": .bool(actif), "p_rayon_km": .integer(rayonKm), "p_creneaux": .array([])]
        return try await muter(Self.rpcBasculer, params: params, context: context)
    }

    public func basculerSMS(_ actif: Bool, context: MissionReadContext) async throws -> IssuePool {
        try MissionQuery.validate(context: context)
        return try await muter(Self.rpcSMS, params: ["p_actif": .bool(actif)], context: context)
    }

    // MARK: - Interne

    private func muter(_ fonction: String, params: JSONObject, context: MissionReadContext) async throws -> IssuePool {
        let reponse = try await RPCResponse.appeler(client, fonction, params: params, fallback: PoolUrgenceTextes.nonConfirmee)
        if let erreur = reponse.erreur {
            if RPCResponse.estNonAuthentifie(erreur) { throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage) }
            return .refuse(message: erreur)
        }
        guard reponse.estSucces else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        return .relu(try await etat(context: context))
    }

    private func enrichir(_ lignes: [LignePoolUrgence]) async throws -> [MissionUrgente] {
        guard !lignes.isEmpty else { return [] }
        let ids = lignes.map(\.id)
        var complements: [Complement] = []
        var creneaux: [MissionSlot] = []
        var erreurPlanning = false
        do {
            do {
                complements = try await client.from("missions").select(Self.colonnesMissions).in("id", values: ids).execute().value
            } catch {
                throw SupabaseErrorMapping.map(error, fallback: PoolUrgenceTextes.chargementImpossible)
            }
            creneaux = try await SupabaseMissionsGateway(client: client).slots(missionIds: ids)
        } catch let erreur as JoleneError where erreur.kind == .unauthorized || erreur.kind == .cancelled {
            throw erreur
        } catch {
            if Task.isCancelled { throw CancellationError() }
            // Web l.85-87 : missions affichées, planning « ne peut pas être vérifié », acceptation impossible.
            erreurPlanning = true
            complements = []
            creneaux = []
        }
        let parId = Dictionary(complements.map { ($0.id, $0) }, uniquingKeysWith: { premier, _ in premier })
        return lignes.map { ligne in
            ligne.missionUrgente(nbCreneaux: parId[ligne.id]?.nbCreneaux, dureeHeures: parId[ligne.id]?.dureeHeures,
                                 creneaux: creneaux.filter { $0.missionId == ligne.id }, erreurPlanning: erreurPlanning)
        }
    }
}
