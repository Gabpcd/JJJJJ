import Foundation
import JoleneCore
import Supabase

/// `CandidaturePort` sur Supabase (lot 1, T6a, `docs/mobile-swift/LOT1_PLAN.md` §3 T6a), sous le JWT du
/// soignant :
/// - POSTULER, ACCEPTER, PROPOSITION : `fn_confirmer_action_planning_v1(p_mission_id, p_action,
///   p_creneaux_confirmes, p_message, p_choix_contrat, p_candidature_id)` (`public.sql` l.24525), avec
///   `p_creneaux_confirmes` = planning exact affiché (`CreneauxConfirmes.pourAction`, T2). Formes de réponse
///   de la fiche `CONTRATS_RPC_SOIGNANT.md`, lues dans l'ordre normatif du §2.4 : `choix_requis` → `code`
///   (planning à reconfirmer, ou refus verbatim) → documents requis avec `error` → `success:true` → `error`
///   seul → sinon `.contract`. Exceptions PostgREST lues avant `SupabaseErrorMapping` : `[CODE DU TRAVAIL]`
///   restituée mot pour mot (`.refusee(code: CODE_DU_TRAVAIL)`, HARD STOP n°4), `0 rows` / `déjà prise` →
///   `.missionDejaAttribuee` (modale « mission perdue » du web), toute autre → message générique.
/// - Un succès n'est annoncé qu'après relecture (PRINCIPES §3) : POSTULER relit la candidature créée
///   (`candidature_id`, statut en attente, même mission) ; ACCEPTER et PROPOSITION relisent la mission
///   (`ASSIGNEE`, `soignant_assigne_id` = session) puis écrivent l'audit `MISSION_ASSIGNATION` comme le web
///   (best-effort, décision 5 : son échec n'invalide jamais le succès relu). Une relecture qui ne confirme
///   pas est une erreur, jamais un succès ; aucun renvoi automatique (un délai ne prouve rien).
/// - Refus d'une proposition : `fn_repondre_proposition(p_candidature_id, p_accepter := false)`, puis
///   relecture `REFUSEE`. L'acceptation passe par `PROPOSITION` (comme `CarteProposition.tsx` l.268-279).
/// - Annulations : tranche T7, refusées explicitement d'ici là (gap verrouillé).
public struct SupabaseCandidatureGateway: CandidaturePort {
    public static let confirmerRPC = "fn_confirmer_action_planning_v1"
    public static let repondreRPC = "fn_repondre_proposition"
    /// Colonnes de la ligne `candidatures` relue (mêmes que Mes missions, T5).
    public static let candidatureColumns = SupabaseMesMissionsGateway.candidatureColumns
    /// Colonnes de la mission relue après ACCEPTER / PROPOSITION (preuve et détails d'audit).
    public static let attributionColumns = "id,statut,soignant_assigne_id,intitule,debut_le,fin_le,etablissement_id"

    public static let fallbackMessage = "Impossible de traiter votre réponse à cette mission. Réessayez."
    /// Le serveur a répondu mais la relecture ne le confirme pas : rien n'est renvoyé automatiquement.
    public static let relectureMessage = "Votre réponse a été envoyée mais n'a pas pu être relue. Vérifiez Mes missions avant de réessayer."
    public static let planningRequisMessage = "Le planning exact doit être confirmé avant de répondre à cette mission."
    public static let identifiantInvalideMessage = "Identifiant de mission ou de candidature invalide."

    private let client: SupabaseClient
    private let audit: any AuditPort

    public init(client: SupabaseClient, audit: (any AuditPort)? = nil) {
        self.client = client
        self.audit = audit ?? SupabaseAuditGateway(client: client)
    }

    // MARK: - Confirmer

    public func confirmer(action: ActionPlanning, missionId: String, creneaux: [CreneauConfirmePayload], message: String?,
                          choixContrat: String?, candidatureId: String?, context: MissionReadContext) async throws -> CandidatureOutcome {
        try MissionQuery.validate(context: context)
        // Lot 1 : trois actions. SWIPE_LIKE et URGENCE (lot 4) ont leur propre relecture : refusées ici.
        guard action == .postuler || action == .accepter || action == .proposition else {
            throw JoleneError(.contract, "Action \(action.rawValue) non servie au lot 1.")
        }
        guard let mission = Self.uuid(missionId) else { throw JoleneError(.contract, Self.identifiantInvalideMessage) }
        var proposition: String?
        if action == .proposition {
            guard let id = candidatureId.flatMap(Self.uuid) else { throw JoleneError(.contract, Self.identifiantInvalideMessage) }
            proposition = id
        }
        // Fail-closed : un planning non exact n'est jamais envoyé (`CreneauxConfirmes` rend nil, l'écran bloque).
        guard !creneaux.isEmpty else { throw JoleneError(.contract, Self.planningRequisMessage) }

        let params: JSONObject = [
            "p_mission_id": .string(mission),
            "p_action": .string(action.rawValue),
            "p_creneaux_confirmes": .array(creneaux.map { .object(["debut": .string($0.debut), "fin": .string($0.fin)]) }),
            "p_message": Self.texteOuNul(message),
            "p_choix_contrat": Self.texteOuNul(choixContrat),
            "p_candidature_id": proposition.map(AnyJSON.string) ?? .null,
        ]
        let reponse: RPCResponse
        switch try await Self.executer({ try await client.rpc(Self.confirmerRPC, params: params).execute().value }) {
        case .missionDejaAttribuee:
            return .missionDejaAttribuee
        case let .corps(corps):
            reponse = corps
        }
        if let refus = reponse.issueCandidatureRefusee(fallback: Self.fallbackMessage) { return refus }
        try reponse.leverSiErreur(fallback: Self.fallbackMessage)
        guard reponse.success == true else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }

        if action == .postuler {
            let id = try reponse.requiredString("candidature_id")
            let relue = try await relireCandidature(id: id, context: context)
            guard CandidatureRules.candidaturePoseeRelue(relue, id: id, missionId: mission) else {
                throw JoleneError(.contract, Self.relectureMessage)
            }
            return .confirmed(candidatureId: id, contratId: nil)
        }
        let contrat = try reponse.requiredString("contrat_id")
        let relue = try await relireAttribution(missionId: mission)
        guard let relue, relue.id == mission,
              CandidatureRules.assignationRelue(statut: relue.statut, soignantAssigneId: relue.soignantAssigneId,
                                                userId: context.userId) else {
            throw JoleneError(.contract, Self.relectureMessage)
        }
        await auditerAssignation(relue, context: context)
        return .confirmed(candidatureId: proposition, contratId: contrat)
    }

    // MARK: - Proposition refusée

    public func refuserProposition(candidatureId: String, context: MissionReadContext) async throws {
        try MissionQuery.validate(context: context)
        guard let id = Self.uuid(candidatureId) else { throw JoleneError(.contract, Self.identifiantInvalideMessage) }
        let reponse = try await RPCResponse.appeler(client, Self.repondreRPC,
                                                    params: ["p_candidature_id": .string(id), "p_accepter": .bool(false)],
                                                    fallback: Self.fallbackMessage)
        try reponse.leverSiErreur(fallback: Self.fallbackMessage)
        // `fn_repondre_proposition` ne pose aucun refus structuré : un drapeau faux n'est jamais un succès.
        if reponse.estRefus { throw JoleneError(.unknown, reponse.erreur ?? Self.fallbackMessage) }
        guard reponse.success == true else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        guard CandidatureRules.refusRelu(try await relireCandidature(id: id, context: context), id: id) else {
            throw JoleneError(.contract, Self.relectureMessage)
        }
    }

    // MARK: - Lecture

    /// Candidature la plus récente du soignant sur cette mission (RLS + filtre explicite sur la session),
    /// relue côté serveur : l'écran ne transporte jamais un identifiant de candidature par la route.
    public func candidature(missionId: String, context: MissionReadContext) async throws -> CandidatureRecord? {
        try MissionQuery.validate(context: context)
        guard let mission = Self.uuid(missionId) else { return nil }
        let lignes: [CandidatureRecord]
        do {
            lignes = try await client.from("candidatures")
                .select(Self.candidatureColumns)
                .eq("mission_id", value: mission)
                .eq("soignant_id", value: context.userId)
                .order("cree_le", ascending: false, nullsFirst: true) // NULLS FIRST de PostgreSQL, comme le web
                .limit(1)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.fallbackMessage)
        }
        guard let ligne = lignes.first else { return nil }
        guard ligne.missionId.caseInsensitiveCompare(mission) == .orderedSame else {
            throw JoleneError(.contract, "La candidature retournée ne correspond pas à la mission demandée.")
        }
        return ligne
    }

    // MARK: - Annulations (T7)

    public func annulerCandidature(id: String, motif: String, texte: String, justificatifPath: String?,
                                   context: MissionReadContext) async throws -> AnnulationOutcome {
        throw UnwiredPorts.erreur(port: "annulation", tranche: "T7")
    }

    public func annulerMission(id: String, motif: String?, context: MissionReadContext) async throws -> AnnulationOutcome {
        throw UnwiredPorts.erreur(port: "annulation", tranche: "T7")
    }

    // MARK: - Interne

    /// Issue du transport de `fn_confirmer_action_planning_v1`.
    enum Transport {
        case corps(RPCResponse)
        case missionDejaAttribuee
    }

    /// Une seule requête, aucun renvoi. Ordre du web (`DetailMissionSoignant.tsx` l.804-810) : Code du
    /// travail, puis mission déjà prise, puis `SupabaseErrorMapping` (message générique).
    static func executer(_ requete: () async throws -> AnyJSON) async throws -> Transport {
        do {
            return .corps(RPCResponse(try await requete()))
        } catch let erreur as PostgrestError where RPCResponse.estRefusCodeDuTravail(erreur.message) {
            return .corps(RPCResponse.refusCodeDuTravail(erreur.message))
        } catch let erreur as PostgrestError where CandidatureRules.estMissionDejaAttribuee(erreur.message) {
            return .missionDejaAttribuee
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: fallbackMessage)
        }
    }

    private func relireCandidature(id: String, context: MissionReadContext) async throws -> CandidatureRecord? {
        let lignes: [CandidatureRecord]
        do {
            lignes = try await client.from("candidatures")
                .select(Self.candidatureColumns)
                .eq("id", value: id)
                .eq("soignant_id", value: context.userId)
                .limit(1)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.relectureMessage)
        }
        return lignes.first
    }

    /// Mission relue après une attribution.
    struct Attribution: Decodable, Equatable {
        var id: String
        var statut: String?
        var soignantAssigneId: String?
        var intitule: String?
        var debutLe: String?
        var finLe: String?
        var etablissementId: String?

        enum CodingKeys: String, CodingKey {
            case id, statut, intitule
            case soignantAssigneId = "soignant_assigne_id"
            case debutLe = "debut_le"
            case finLe = "fin_le"
            case etablissementId = "etablissement_id"
        }
    }

    private func relireAttribution(missionId: String) async throws -> Attribution? {
        let lignes: [Attribution]
        do {
            lignes = try await client.from("missions")
                .select(Self.attributionColumns)
                .eq("id", value: missionId)
                .limit(1)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.relectureMessage)
        }
        return lignes.first
    }

    /// `MISSION_ASSIGNATION` comme le web (l.824-836) : `p_details = {intitule, etablissement, debut, fin}`,
    /// établissement par `fn_etablissements_safe` (jamais `fn_etablissement_public`). Best-effort : toute
    /// erreur est avalée (l'attribution relue reste un succès, `AuditPort`).
    private func auditerAssignation(_ mission: Attribution, context: MissionReadContext) async {
        var details: [String: String] = [:]
        if let intitule = mission.intitule { details["intitule"] = intitule }
        if let debut = mission.debutLe { details["debut"] = debut }
        if let fin = mission.finLe { details["fin"] = fin }
        if let etablissementId = mission.etablissementId,
           let nom = try? await SupabaseMissionsGateway(client: client).etablissements(ids: [etablissementId])[etablissementId]?.nom {
            details["etablissement"] = nom
        }
        _ = try? await audit.ecrire(action: .missionAssignation, typeRessource: "mission", idRessource: mission.id,
                                    details: details, context: context)
    }

    /// Uuid canonique en minuscules ; nil pour une valeur vide ou invalide (binding uuid PostgREST).
    static func uuid(_ valeur: String) -> String? {
        UUID(uuidString: valeur.trimmingCharacters(in: .whitespacesAndNewlines))?.uuidString.lowercased()
    }

    /// `|| null` du web : un texte vide ou absent est envoyé à null, tout autre texte tel quel.
    static func texteOuNul(_ valeur: String?) -> AnyJSON {
        guard let valeur, !valeur.isEmpty else { return .null }
        return .string(valeur)
    }
}
