import Foundation
import JoleneCore
import Supabase

/// `EtabPointagePort` sur Supabase (lot 5, T7 ; `LOT5_PLAN.md` §2.4, §3 T7 ; fiches `CONTRATS_RPC_ETABLISSEMENT.md`),
/// lecture seule, sous le JWT du membre de l'établissement ; mêmes lectures que
/// `src/components/pointage/AffichageCodeRotatifEtab.tsx` (l.125-171) :
/// - état : `fn_etat_pointage_mission(p_mission_id)` (RPC du lot 2, partagée), décodé en liste blanche
///   (`CodeRotatifRules.Etat` : statut, prochain pointage, segments, `code_pointage_actif` — que le serveur ne sert
///   qu'aux membres habilités au pointage, B5b) ; un refus jsonb (`{error:'Mission introuvable'|'Accès interdit'}`) est
///   rendu tel quel dans `erreur`, sans aucune autre clé ; aucune clé de la réponse du scanner n'est lue ;
/// - signature : `fn_contrat_signe_pour_pointage(p_mission_id)` → booléen (web l.153-158 : toute autre forme est une
///   erreur) ; le 42501 « Lecture du pointage non autorisée. » de la liste blanche vaut `false` (fail-closed : aucun
///   code d'arrivée, un segment ouvert garde le code de départ) ;
/// - planning : `missions` (`id, debut_le, fin_le, nb_creneaux`, établissement **confirmé** du contexte, jamais de
///   montant) puis créneaux PREVISIONNEL hors pause par le pager exact de T5 ; mission illisible → erreur (code masqué).
public struct SupabaseEtabPointageGateway: EtabPointagePort {
    public static let etatRPC = PointageQuery.rpcEtat
    public static let contratRPC = "fn_contrat_signe_pour_pointage"
    /// Repli du web (l.212) quand le serveur ne donne aucun message.
    public static let etatFallback = CodeRotatifRules.messageEtatIndisponible
    public static let contratFallback = "État de signature indisponible." // web l.158
    public static let planningFallback = "Impossible de charger le planning détaillé. Réessayez."
    static let missionIllisible = "Le planning de cette mission n'a pas pu être relu."
    /// Colonnes lues sur `missions` (web l.141), sans aucun montant.
    static let missionSelect = "id,debut_le,fin_le,nb_creneaux,etablissement_id"

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - État

    public func etat(missionId: String, context: EtablissementReadContext) async throws -> EtatPointageEtab {
        let uuid = try Self.verifier(missionId, context)
        let reponse = try await RPCResponse.appeler(client, Self.etatRPC, params: ["p_mission_id": .string(uuid)],
                                                    fallback: Self.etatFallback,
                                                    interceptions: ListesBlanchesEtablissement.interceptions(rpc: Self.etatRPC))
        if let erreur = reponse.erreur {
            if RPCResponse.estNonAuthentifie(erreur) { throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage) }
            // Refus du serveur verbatim ; aucune autre clé n'est retenue (jamais un code à côté d'un refus).
            return EtatPointageEtab(statut: nil, prochainTypeScan: nil, segmentOuvert: false, segments: [],
                                    codePointageActif: nil, erreur: erreur)
        }
        guard !reponse.estRefus, reponse.raw.objectValue != nil,
              let etat = PointageQuery.decoder(EtatPointageEtab.self, reponse) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return etat
    }

    // MARK: - Signature

    public func contratSigne(missionId: String, context: EtablissementReadContext) async throws -> Bool {
        let uuid = try Self.verifier(missionId, context)
        let reponse = try await RPCResponse.appeler(client, Self.contratRPC, params: ["p_mission_id": .string(uuid)],
                                                    fallback: Self.contratFallback,
                                                    interceptions: ListesBlanchesEtablissement.interceptions(rpc: Self.contratRPC))
        if reponse.estAccesRefuse { return false }
        guard let signe = reponse.raw.boolValue else { throw JoleneError(.contract, Self.contratFallback) }
        return signe
    }

    // MARK: - Planning

    private struct LigneMission: Decodable {
        let id: String
        let debutLe: String?
        let finLe: String?
        let nbCreneaux: Int?
        let etablissementId: String?
        enum CodingKeys: String, CodingKey {
            case id
            case debutLe = "debut_le"
            case finLe = "fin_le"
            case nbCreneaux = "nb_creneaux"
            case etablissementId = "etablissement_id"
        }
    }

    public func planning(missionId: String, context: EtablissementReadContext) async throws -> PlanningMission {
        let uuid = try Self.verifier(missionId, context)
        let ligne: LigneMission?
        do {
            ligne = try await client.from("missions")
                .select(Self.missionSelect)
                .eq("id", value: uuid)
                .eq("etablissement_id", value: context.etablissementId)
                .maybeSingle()
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.planningFallback)
        }
        guard let ligne, ligne.id.lowercased() == uuid,
              ligne.etablissementId?.lowercased() == context.etablissementId.lowercased() else {
            throw JoleneError(.contract, Self.missionIllisible)
        }
        let creneaux = try await SupabaseEtabMissionsGateway(client: client).creneaux(missionIds: [ligne.id])[ligne.id] ?? []
        return PlanningMission(mission: MissionAvecPlanningAttendu(id: ligne.id, debutLe: ligne.debutLe ?? "", finLe: ligne.finLe ?? "",
                                                                   nbCreneaux: ligne.nbCreneaux),
                               creneaux: creneaux)
    }

    /// Contexte cohérent et identifiant canonique exigés avant tout appel réseau.
    private static func verifier(_ missionId: String, _ context: EtablissementReadContext) throws -> String {
        try context.verifier()
        guard let uuid = SupabaseAuditGateway.uuid(missionId) else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        return uuid
    }
}
