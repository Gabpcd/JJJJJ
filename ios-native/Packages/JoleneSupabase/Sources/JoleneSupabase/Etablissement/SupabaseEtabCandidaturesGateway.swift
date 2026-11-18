import Foundation
import JoleneCore
import Supabase

/// `EtabCandidaturesPort` sur Supabase (lot 5, T6 ; `LOT5_PLAN.md` §2.4-§2.5, §3 T6 ; fiches
/// `CONTRATS_RPC_ETABLISSEMENT.md`), sous le JWT du membre de l'établissement :
/// - lecture : `fn_lire_candidatures_mission_habilitee(p_mission_id)` (un appel, cohorte de test filtrée, adhésion
///   vérifiée, noms à l'initiale) ; 42501 « Mission indisponible ou accès refusé » (liste blanche) →
///   `RefusAccesEtablissement` (jamais « session expirée ») ; mission relue ≠ demandée, ou d'un autre établissement que
///   le contexte confirmé → refus de contrat ;
/// - acceptation : `fn_traiter_candidature_planning_v1(p_candidature_id, 'ACCEPTEE', p_creneaux_confirmes, NULL)`,
///   `p_creneaux_confirmes` = **chaînes `debut`/`fin` relues telles quelles** (D26). Avant l'appel, le contrat recherché
///   et la profession de la mission sont relus sous RLS (candidature → mission de l'établissement confirmé) : hors
///   `SALARIE` ou `MEDECIN` → `.renvoiWeb`, **aucun appel RPC** (D25 : T6 reste hors B9, aucun escrow possible) ;
/// - refus : `fn_traiter_candidature_planning_v1(p_candidature_id, 'REFUSEE', NULL, 'Refusé par l''établissement')` ;
/// - issues : `RPCResponse.issueTraitementCandidature` avec `ListesBlanchesEtablissement.interceptions` (42501 RBAC →
///   message neutre, P0001 de paiement verbatim, `[CODE DU TRAVAIL]` verbatim, « Notification d'acceptation
///   impossible » jamais affichée). L'issue ne vaut pas confirmation : le modèle relit la lecture habilitée.
public struct SupabaseEtabCandidaturesGateway: EtabCandidaturesPort {
    public static let lectureRPC = "fn_lire_candidatures_mission_habilitee"
    public static let traiterRPC = "fn_traiter_candidature_planning_v1"
    public static let lectureFallback = "Impossible de charger les candidatures. Réessayez."
    public static let traiterFallback = "La candidature n'a pas pu être traitée. Réessayez."
    /// Colonnes relues sur `missions` avant une acceptation (D25), sans aucun montant.
    static let missionPerimetreSelect = "id,etablissement_id,type_contrat_recherche,profession_requise"
    static let candidatureIntrouvable = "Cette candidature n'a pas pu être relue. Rechargez les candidatures."

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Lecture habilitée

    public func lecture(missionId: String, context: EtablissementReadContext) async throws -> LectureCandidaturesHabilitee {
        try context.verifier()
        guard let uuid = SupabaseAuditGateway.uuid(missionId) else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        let reponse = try await RPCResponse.appeler(
            client, Self.lectureRPC, params: ["p_mission_id": .string(uuid)], fallback: Self.lectureFallback,
            interceptions: ListesBlanchesEtablissement.interceptions(rpc: Self.lectureRPC))
        if reponse.estAccesRefuse { throw RefusAccesEtablissement(message: reponse.erreur ?? Self.lectureFallback) }
        try reponse.leverSiErreur(fallback: Self.lectureFallback)
        guard reponse.raw.objectValue != nil, !reponse.estRefus else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        let lecture = try SupabaseEtabSessionGateway.decoder(LectureCandidaturesHabilitee.self, reponse)
        guard lecture.missionId.lowercased() == uuid,
              lecture.etablissementId.map({ $0.lowercased() == context.etablissementId.lowercased() }) ?? true else {
            throw JoleneError(.contract, "La mission retournée ne correspond pas à la demande.")
        }
        return lecture
    }

    // MARK: - Traitement

    public func accepter(candidatureId: String, creneauxConfirmes: [CreneauConfirmePayload],
                         context: EtablissementReadContext) async throws -> TraitementCandidatureOutcome {
        try context.verifier()
        guard let uuid = SupabaseAuditGateway.uuid(candidatureId), !creneauxConfirmes.isEmpty else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        if let motif = try await motifHorsPerimetre(candidatureId: uuid, context: context) {
            return .renvoiWeb(motif: motif)
        }
        let params: JSONObject = [
            "p_candidature_id": .string(uuid),
            "p_decision": .string(DecisionCandidature.acceptee.rawValue),
            // Écho exact des chaînes relues (D26) : jamais de conversion par `Date`.
            "p_creneaux_confirmes": .array(creneauxConfirmes.map { .object(["debut": .string($0.debut), "fin": .string($0.fin)]) }),
            "p_motif": .null,
        ]
        let reponse = try await RPCResponse.appeler(client, Self.traiterRPC, params: params, fallback: Self.traiterFallback,
                                                    interceptions: ListesBlanchesEtablissement.interceptions(rpc: Self.traiterRPC))
        return try reponse.issueTraitementCandidature(decision: .acceptee, fallback: Self.traiterFallback)
    }

    public func refuser(candidatureId: String, context: EtablissementReadContext) async throws -> TraitementCandidatureOutcome {
        try context.verifier()
        guard let uuid = SupabaseAuditGateway.uuid(candidatureId) else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        let params: JSONObject = [
            "p_candidature_id": .string(uuid),
            "p_decision": .string(DecisionCandidature.refusee.rawValue),
            "p_creneaux_confirmes": .null,
            "p_motif": .string(CandidaturesEtabRules.motifRefus),
        ]
        let reponse = try await RPCResponse.appeler(client, Self.traiterRPC, params: params, fallback: Self.traiterFallback,
                                                    interceptions: ListesBlanchesEtablissement.interceptions(rpc: Self.traiterRPC))
        return try reponse.issueTraitementCandidature(decision: .refusee, fallback: Self.traiterFallback)
    }

    // MARK: - Périmètre D25

    private struct LigneCandidature: Decodable {
        let id: String
        let missionId: String
        enum CodingKeys: String, CodingKey { case id, missionId = "mission_id" }
    }

    private struct LigneMission: Decodable {
        let id: String
        let etablissementId: String?
        let typeContratRecherche: String?
        let professionRequise: String?
        enum CodingKeys: String, CodingKey {
            case id
            case etablissementId = "etablissement_id"
            case typeContratRecherche = "type_contrat_recherche"
            case professionRequise = "profession_requise"
        }
    }

    /// Contrat recherché et profession relus sous RLS (`pol_cand_select`, `pol_mission_select`) juste avant l'appel ;
    /// une ligne illisible bloque l'envoi (fail-closed : jamais un salariat supposé).
    func motifHorsPerimetre(candidatureId: String, context: EtablissementReadContext) async throws -> MotifRenvoiWebCandidature? {
        let candidature: LigneCandidature?
        let mission: LigneMission?
        do {
            candidature = try await client.from("candidatures")
                .select("id,mission_id")
                .eq("id", value: candidatureId)
                .maybeSingle()
                .execute()
                .value
            guard let candidature, candidature.id.lowercased() == candidatureId else {
                throw JoleneError(.contract, Self.candidatureIntrouvable)
            }
            mission = try await client.from("missions")
                .select(Self.missionPerimetreSelect)
                .eq("id", value: candidature.missionId)
                .eq("etablissement_id", value: context.etablissementId)
                .maybeSingle()
                .execute()
                .value
        } catch let erreur as JoleneError {
            throw erreur
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.traiterFallback)
        }
        guard let mission, mission.id.lowercased() == candidature?.missionId.lowercased(),
              mission.etablissementId?.lowercased() == context.etablissementId.lowercased() else {
            throw JoleneError(.contract, Self.candidatureIntrouvable)
        }
        return CandidaturesEtabRules.motifMission(typeContratRecherche: mission.typeContratRecherche,
                                                  professionRequise: mission.professionRequise)
    }
}
