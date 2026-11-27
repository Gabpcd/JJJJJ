import Foundation
import JoleneCore
import Supabase

/// `EtabPresencesPort` sur Supabase (lot 5, T8, **B9 paiements/escrow** ; `LOT5_PLAN.md` §2.4-§2.5, §3 T8 ; fiches
/// `CONTRATS_RPC_ETABLISSEMENT.md`), sous le JWT du membre de l'établissement. La validation d'une présence déclenche
/// côté serveur la libération du séquestre (`trg_escrow_release_on_validation`) : cette gateway n'appelle que les RPC
/// existantes, telles quelles, **une requête par action, jamais renvoyée**, et ne rend un succès qu'après relecture.
/// Aucun montant ni aucune durée n'est lu, calculé ou envoyé.
///
/// - lecture : `presences` (colonnes `PresenceEtab.clesDecodees` — jamais `arrivee_lat/lng`, `depart_lat/lng`,
///   `coherence_incidents`, `duree_heures`) avec l'embed `missions!inner(…)` filtré sur l'établissement **confirmé** du
///   contexte, arrivée pointée, plus récente d'abord (`PresencesEtablissement.tsx` l.66-81) ; créneaux hors pause
///   (PREVISIONNEL et EFFECTIF) par lots, compte exact exigé (`chargerCreneauxMissionsPagines`, l.127) ;
/// - `fn_valider_presence(p_presence_id)` → relecture `valide_par_etablissement == true` et `valide_le` non nul, sinon
///   erreur ; « Déjà validée » → relecture puis état validé ;
/// - `fn_valider_presences_lot(p_ids)` → relecture de chaque identifiant : le compte rendu est celui des lignes relues,
///   jamais `nb_validees` ;
/// - `fn_contester_presence(p_presence_id, p_motif)` (motif de 3 caractères au moins, comme le serveur) → relecture de
///   `motif_litige` ;
/// - `fn_creer_notation_mission(p_mission_id, 'ETAB_VERS_SOIGNANT', note ×4, NULL)` : écriture seule, « déjà notée » =
///   succès (`NotationRapide.tsx` l.61), jamais bloquante ;
/// - `fn_declarer_fin_retroactive(p_mission_id, p_heure_fin, p_raison)` : succès **sans clé `success`**
///   (`creneau_effectif_id` exigé, aucune autre clé lue), heure future refusée avant l'envoi (D28), puis relecture
///   `fn_etat_pointage_mission.segment_ouvert == false` (seule clé lue de cette réponse) ;
/// - refus : `ListesBlanchesEtablissement.interceptions` — 42501 du trigger RBAC → message neutre (`.accesRefuse`,
///   l'écran relit les permissions), P0001/P0002/23503/23514 de la liste → texte serveur mot pour mot.
public struct SupabaseEtabPresencesGateway: EtabPresencesPort {
    public static let validerRPC = "fn_valider_presence"
    public static let lotRPC = "fn_valider_presences_lot"
    public static let contesterRPC = "fn_contester_presence"
    public static let noterRPC = "fn_creer_notation_mission"
    public static let cloturerRPC = "fn_declarer_fin_retroactive"
    public static let etatRPC = PointageQuery.rpcEtat
    /// Sens de l'établissement vers le soignant (`SensNotation`, `NotationRapide.tsx` l.27).
    public static let sens = "ETAB_VERS_SOIGNANT"
    // source: supabase/schema/public.sql l.66035 (fn_valider_presence)
    static let dejaValidee = "Déjà validée"
    // source: supabase/schema/public.sql l.26350 (fn_contester_presence)
    static let motifObligatoire = "Le motif est obligatoire (3 caractères min.)"
    /// Refus « déjà notée » du serveur (`public.sql` l.27930), reconnu comme le web (`includes('déjà notée')`).
    static let marqueDejaNotee = "déjà notée"
    static let longueurMinMotif = 3
    public static let lectureFallback = "Impossible de charger les présences. Réessayez."
    public static let actionFallback = "L'action n'a pas pu être enregistrée. Réessayez."
    public static let noteFallback = "La note n'a pas pu être enregistrée."
    /// Réponse serveur positive que la relecture ne confirme pas : jamais un succès annoncé.
    public static let nonConfirmee = "L'action n'a pas pu être confirmée par une relecture. Vérifiez les présences avant de recommencer."
    /// Verrou D28 (`docs/mobile-swift/DECISIONS_LOT5.md`) : le serveur accepterait une heure de fin future.
    static let heureFutureRefusee = "Heure de fin postérieure à l'heure actuelle : refusée avant l'envoi (DECISIONS_LOT5.md, D28)."
    /// Colonnes de l'embed de la mission, sans `duree_heures` ni aucun montant.
    static var presenceSelect: String {
        PresenceEtab.clesDecodees.joined(separator: ",") + ",missions!inner(" + MissionPresenceEtab.clesDecodees.joined(separator: ",") + ")"
    }
    /// Relecture d'une présence après mutation : état de validation et motif seulement.
    static let relectureSelect = "id,mission_id,valide_par_etablissement,valide_le,motif_litige,missions!inner(id,etablissement_id)"
    /// Missions terminées (web l.89), sans aucun montant.
    static let termineesSelect = "id,intitule,service,debut_le,fin_le,soignant_assigne_id,statut,etablissement_id"
    static let lotRelecture = 100

    private let client: SupabaseClient
    private let maintenant: @Sendable () -> Date

    public init(client: SupabaseClient, maintenant: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.maintenant = maintenant
    }

    // MARK: - Lectures

    public func presences(context: EtablissementReadContext) async throws -> [PresenceEtab] {
        try context.verifier()
        var lignes: [PresenceEtab]
        do {
            lignes = try await client.from("presences")
                .select(Self.presenceSelect)
                .eq("missions.etablissement_id", value: context.etablissementId)
                .not("pointage_arrivee_le", operator: .is, value: "null")
                .order("pointage_arrivee_le", ascending: false)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.lectureFallback)
        }
        for ligne in lignes {
            guard ligne.mission?.etablissementId?.lowercased() == context.etablissementId.lowercased(),
                  ligne.mission?.id.lowercased() == ligne.missionId.lowercased() else {
                throw JoleneError(.contract, "Une présence retournée n'appartient pas à votre établissement.")
            }
        }
        let creneaux = try await lireCreneaux(missionIds: lignes.map(\.missionId))
        for index in lignes.indices { lignes[index].creneaux = creneaux[lignes[index].missionId] ?? [] }
        return lignes
    }

    public func missionsTerminees(context: EtablissementReadContext) async throws -> [EtabMissionResume] {
        try context.verifier()
        let lignes: [EtabMissionResume]
        do {
            lignes = try await client.from("missions")
                .select(Self.termineesSelect)
                .eq("etablissement_id", value: context.etablissementId)
                .eq("type_contrat_applique", value: "SALARIE")
                .eq("statut", value: "TERMINEE")
                .not("soignant_assigne_id", operator: .is, value: "null")
                .order("fin_le", ascending: false)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.lectureFallback)
        }
        guard lignes.allSatisfy({ $0.etablissementId?.lowercased() == context.etablissementId.lowercased() }) else {
            throw JoleneError(.contract, "Une mission retournée n'appartient pas à votre établissement.")
        }
        return lignes
    }

    public func creneaux(missionId: String, context: EtablissementReadContext) async throws -> [MissionSlot] {
        let uuid = try Self.verifier(missionId, context)
        return try await lireCreneaux(missionIds: [uuid])[uuid] ?? []
    }

    /// Créneaux hors pause de tous types, par lots de 50 missions et pages de 500, compte exact obligatoire et stable
    /// (mêmes erreurs d'intégrité que `MissionSlotPager`) : un planning tronqué n'est jamais présenté comme exact.
    func lireCreneaux(missionIds: [String]) async throws -> [String: [MissionSlot]] {
        var parMission: [String: [MissionSlot]] = [:]
        var vus = Set<String>()
        for lot in MissionSlotPager.batches(missionIds) {
            var attendu: Int?
            var position = 0
            while attendu.map({ position < $0 }) ?? true {
                try Task.checkCancellation()
                let page: PostgrestResponse<[MissionSlot]>
                do {
                    page = try await client.from("mission_creneaux")
                        .select(MissionQuery.slotSelect, count: .exact)
                        .in("mission_id", values: lot)
                        .eq("est_pause", value: false)
                        .order("mission_id", ascending: true)
                        .order("debut", ascending: true)
                        .order("id", ascending: true)
                        .range(from: position, to: position + MissionQuery.slotPageSize - 1)
                        .execute()
                } catch {
                    throw SupabaseErrorMapping.map(error, fallback: Self.lectureFallback)
                }
                guard let compte = page.count, compte >= 0 else { throw MissionSlotPager.countUnavailable }
                if let attendu, attendu != compte { throw MissionSlotPager.planningChanged }
                attendu = compte
                if page.value.isEmpty, position < compte { throw MissionSlotPager.planningIncomplete }
                for creneau in page.value {
                    guard let id = creneau.id, !id.isEmpty, let mission = creneau.missionId, lot.contains(mission),
                          !creneau.estPause, vus.insert(id).inserted else { throw MissionSlotPager.planningInconsistent }
                    parMission[mission, default: []].append(creneau)
                }
                position += page.value.count
                if position > compte { throw MissionSlotPager.planningInconsistent }
            }
        }
        return parMission
    }

    /// Présences relues par identifiant, bornées à l'établissement confirmé (une ligne étrangère n'est jamais comptée).
    func relire(ids: [String], context: EtablissementReadContext) async throws -> [PresenceEtab] {
        var relues: [PresenceEtab] = []
        for debut in stride(from: 0, to: ids.count, by: Self.lotRelecture) {
            let lot = Array(ids[debut..<min(debut + Self.lotRelecture, ids.count)])
            let lignes: [PresenceEtab]
            do {
                lignes = try await client.from("presences")
                    .select(Self.relectureSelect)
                    .in("id", values: lot)
                    .eq("missions.etablissement_id", value: context.etablissementId)
                    .execute()
                    .value
            } catch {
                throw SupabaseErrorMapping.map(error, fallback: Self.nonConfirmee)
            }
            relues.append(contentsOf: lignes.filter { lot.contains($0.id.lowercased()) })
        }
        return relues
    }

    // MARK: - Validation

    public func valider(presenceId: String, context: EtablissementReadContext) async throws -> ValidationPresenceOutcome {
        let uuid = try Self.verifier(presenceId, context)
        let reponse = try await appeler(Self.validerRPC, ["p_presence_id": .string(uuid)])
        if let refus = Self.refus(reponse) {
            // « Déjà validée » : l'état est relu, jamais supposé.
            guard case let .metier(message) = refus, message == Self.dejaValidee,
                  let valideLe = try await relire(ids: [uuid], context: context).first.flatMap(Self.valideLe) else {
                return refus.validation
            }
            return .validee(valideLe: valideLe)
        }
        guard reponse.estSucces else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        guard let valideLe = try await relire(ids: [uuid], context: context).first.flatMap(Self.valideLe) else {
            throw JoleneError(.unknown, Self.nonConfirmee)
        }
        return .validee(valideLe: valideLe)
    }

    public func validerLot(ids: [String], context: EtablissementReadContext) async throws -> ValidationLotOutcome {
        try context.verifier()
        let uuids = ids.compactMap(SupabaseAuditGateway.uuid)
        guard !uuids.isEmpty, uuids.count == ids.count, Set(uuids).count == uuids.count else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        let reponse = try await appeler(Self.lotRPC, ["p_ids": .array(uuids.map(AnyJSON.string))])
        if let refus = Self.refus(reponse) { return refus.lot }
        guard reponse.estSucces else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        let validees = try await relire(ids: uuids, context: context).filter { Self.valideLe($0) != nil }
        return .traitee(validees: Set(validees.map { $0.id.lowercased() }).count, selectionnees: uuids.count)
    }

    // MARK: - Contestation

    public func contester(presenceId: String, motif: String, context: EtablissementReadContext) async throws -> ContestationOutcome {
        let uuid = try Self.verifier(presenceId, context)
        let propre = motif.trimmingCharacters(in: .whitespacesAndNewlines)
        // Même borne que le serveur (`length(trim(p_motif)) < 3`), son message, aucune requête.
        guard propre.count >= Self.longueurMinMotif else { return .refusee(message: Self.motifObligatoire) }
        let reponse = try await appeler(Self.contesterRPC, ["p_presence_id": .string(uuid), "p_motif": .string(propre)])
        if let refus = Self.refus(reponse) { return refus.contestation }
        guard reponse.estSucces else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        guard let relu = try await relire(ids: [uuid], context: context).first?.motifLitige,
              !relu.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw JoleneError(.unknown, Self.nonConfirmee)
        }
        return .contestee(motifLitige: relu)
    }

    // MARK: - Note

    public func noter(missionId: String, note: Int, context: EtablissementReadContext) async throws -> NotationOutcome {
        let uuid = try Self.verifier(missionId, context)
        guard (1...5).contains(note) else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        var params: JSONObject = ["p_mission_id": .string(uuid), "p_sens": .string(Self.sens), "p_commentaire": .null]
        for rang in 1...4 { params["p_critere_\(rang)"] = .integer(note) }
        let reponse = try await RPCResponse.appeler(client, Self.noterRPC, params: params, fallback: Self.noteFallback,
                                                    interceptions: ListesBlanchesEtablissement.interceptions(rpc: Self.noterRPC))
        if reponse.success == true, reponse.erreur == nil { return .enregistree }
        guard let erreur = reponse.erreur else { return .nonEnregistree(message: nil) }
        if RPCResponse.estNonAuthentifie(erreur) { throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage) }
        return erreur.contains(Self.marqueDejaNotee) ? .enregistree : .nonEnregistree(message: erreur)
    }

    // MARK: - Clôture rétroactive

    public func cloturerSegment(missionId: String, heureFin: Date, context: EtablissementReadContext) async throws -> ClotureOutcome {
        let uuid = try Self.verifier(missionId, context)
        guard heureFin <= maintenant() else { throw JoleneError(.contract, Self.heureFutureRefusee) }
        let reponse = try await appeler(Self.cloturerRPC, [
            "p_mission_id": .string(uuid),
            "p_heure_fin": .string(DateHeureParis.isoUTC(heureFin)), // `toISOString()` du web (l.184)
            "p_raison": .string(ClotureSegment.raison),
        ])
        if let refus = Self.refus(reponse) { return refus.cloture }
        // Succès sans clé `success` (correction 17) : seul l'identifiant du créneau fermé est exigé ; le code de
        // pointage suivant, s'il était servi, n'est jamais lu.
        _ = try reponse.requiredString("creneau_effectif_id")
        let etat = try await RPCResponse.appeler(client, Self.etatRPC, params: ["p_mission_id": .string(uuid)],
                                                 fallback: Self.nonConfirmee)
        guard etat.erreur == nil, etat.bool("segment_ouvert") == false else { throw JoleneError(.unknown, Self.nonConfirmee) }
        return .cloturee
    }

    // MARK: - Appels et refus

    private func appeler(_ rpc: String, _ params: JSONObject) async throws -> RPCResponse {
        let reponse = try await RPCResponse.appeler(client, rpc, params: params, fallback: Self.actionFallback,
                                                    interceptions: ListesBlanchesEtablissement.interceptions(rpc: rpc))
        try reponse.leverSiErreur(fallback: Self.actionFallback)
        return reponse
    }

    /// Refus d'une mutation : refus de droit intercepté (message neutre du trigger RBAC ou texte serveur), ou refus
    /// métier (jsonb `success:false`, exception de la liste blanche), texte serveur mot pour mot.
    enum Refus: Equatable {
        case acces(String)
        case metier(String)

        var validation: ValidationPresenceOutcome {
            switch self {
            case let .acces(message): return .accesRefuse(message: message)
            case let .metier(message): return .refusee(message: message)
            }
        }

        var lot: ValidationLotOutcome {
            switch self {
            case let .acces(message): return .accesRefuse(message: message)
            case let .metier(message): return .refusee(message: message)
            }
        }

        var contestation: ContestationOutcome {
            switch self {
            case let .acces(message): return .accesRefuse(message: message)
            case let .metier(message): return .refusee(message: message)
            }
        }

        var cloture: ClotureOutcome {
            switch self {
            case let .acces(message): return .accesRefuse(message: message)
            case let .metier(message): return .refusee(message: message)
            }
        }
    }

    static func refus(_ reponse: RPCResponse) -> Refus? {
        guard reponse.estRefus else { return nil }
        let message = reponse.erreur ?? actionFallback
        return reponse.estAccesRefuse ? .acces(message) : .metier(message)
    }

    /// `valide_le` d'une présence relue validée ; `nil` si la relecture ne confirme pas la validation.
    static func valideLe(_ presence: PresenceEtab) -> String? {
        guard presence.valideParEtablissement, let valideLe = presence.valideLe, !valideLe.isEmpty else { return nil }
        return valideLe
    }

    /// Contexte cohérent et identifiant canonique exigés avant tout appel réseau.
    private static func verifier(_ identifiant: String, _ context: EtablissementReadContext) throws -> String {
        try context.verifier()
        guard let uuid = SupabaseAuditGateway.uuid(identifiant) else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        return uuid
    }
}
