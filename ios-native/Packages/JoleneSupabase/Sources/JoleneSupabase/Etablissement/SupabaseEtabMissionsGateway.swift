import Foundation
import JoleneCore
import Supabase

/// `EtabMissionsPort` sur PostgREST et RPC (lot 5, T5 ; `LOT5_PLAN.md` §2.4, §3 T5), lecture seule, sous RLS
/// (`pol_mission_select` : `etablissement_id = mon_etablissement_id()` et `lecture_missions` ; `mc_select` ;
/// `pol_cand_select` : `lecture_candidatures`). Port de `ListeMissions.tsx` (l.78-170) et de la lecture de
/// `DetailMission.tsx` (l.512-600) **sans aucune colonne monétaire** (D15) :
/// - `missions` : colonnes `EtabMissionResume.clesDecodees`, filtre `etablissement_id` = établissement **confirmé**
///   par `fn_mes_permissions_etab(NULL)` (contexte, D2 — jamais le repli `user.id` du web l.82), ordre `debut_le`
///   décroissant puis `id` (pagination stable), pages cumulatives de 50 ; chaque ligne relue est contrôlée
///   (établissement du contexte, identifiant demandé) ;
/// - `mission_creneaux` : PREVISIONNEL hors pause, pager exact du lot 0 (`MissionSlotPager`) ;
/// - compteurs : `select=statut` de toutes les missions de l'établissement (web l.161-166), par pages de 1 000 avec
///   compte exact (le web s'arrête à la limite de lignes de PostgREST) ; échec → `nil`, jamais un « 0 » supposé ;
/// - candidatures `EN_ATTENTE` des missions `OUVERTE` de la page (web l.120-138), lues seulement avec la permission
///   `candidatures` (fail-closed, §2.7) ; échec → aucune pastille ;
/// - `fn_soignant_pour_etablissement(p_soignant_id)` : `null` SQL → `nil` (« Soignant indisponible »), `{error}` →
///   message serveur verbatim ; aucune exception levée par la fonction (liste blanche vide).
public struct SupabaseEtabMissionsGateway: EtabMissionsPort {
    public static let soignantRPC = "fn_soignant_pour_etablissement"
    public static let missionsFallback = "Impossible de charger les missions. Réessayez."
    public static let missionFallback = "Impossible de charger cette mission. Réessayez."
    public static let creneauxFallback = "Impossible de charger le planning détaillé. Réessayez."
    public static let soignantFallback = "Impossible de charger le soignant assigné. Réessayez."
    /// Colonnes lues sur `missions` : exactement celles que `EtabMissionResume` décode.
    public static var missionSelect: String { EtabMissionResume.clesDecodees.joined(separator: ",") }
    /// Taille d'une page de la lecture des statuts (limite usuelle de PostgREST).
    static let pageStatuts = 1_000
    /// Au-delà, les compteurs ne sont pas affichés plutôt qu'approchés.
    static let maxPagesStatuts = 20

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Liste

    public func missions(context: EtablissementReadContext, statut: String?, page: Int) async throws -> EtabMissionsPage {
        try context.verifier()
        guard page >= 0 else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        if let statut, statut.trimmingCharacters(in: .whitespaces).isEmpty {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        let limite = (page + 1) * EtabMissionsPage.taille
        let lignes: [EtabMissionResume]
        do {
            var requete = client.from("missions")
                .select(Self.missionSelect)
                .eq("etablissement_id", value: context.etablissementId)
            if let statut { requete = requete.eq("statut", value: statut) }
            lignes = try await requete
                .order("debut_le", ascending: false)
                .order("id", ascending: true)
                .range(from: 0, to: limite - 1)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.missionsFallback)
        }
        for ligne in lignes {
            guard ligne.etablissementId == context.etablissementId, statut == nil || ligne.statut == statut else {
                throw JoleneError(.contract, "Une mission retournée n'appartient pas à votre établissement.")
            }
        }
        let creneaux = try await self.creneaux(missionIds: lignes.map(\.id))
        let ouvertes = lignes.filter { $0.statut == "OUVERTE" }.map(\.id)
        async let enAttente = candidaturesEnAttente(missionIds: ouvertes, context: context)
        async let compteurs = compteurs(context: context)
        return EtabMissionsPage(missions: lignes, page: page, aSuivre: lignes.count == limite,
                                compteurs: await compteurs, candidaturesEnAttente: await enAttente, creneaux: creneaux)
    }

    // MARK: - Détail

    public func mission(id: String, context: EtablissementReadContext) async throws -> EtabMissionDetail? {
        try context.verifier()
        // Uuid canonique exigé avant tout appel (intégration de la vague C, revue B8 de #1162, m4) : un lien
        // `/etablissement/missions/abc` est « Mission introuvable », jamais un refus 22P02 de PostgREST affiché
        // « Impossible de charger la mission » avec « Réessayer » en boucle. Même règle que `soignant(id:)`.
        guard let uuid = SupabaseAuditGateway.uuid(id) else { return nil }
        // Relecture sous le JWT courant : l'état de navigation n'est jamais une autorisation.
        let ligne: EtabMissionResume?
        do {
            ligne = try await client.from("missions")
                .select(Self.missionSelect)
                .eq("id", value: uuid)
                .eq("etablissement_id", value: context.etablissementId)
                .maybeSingle()
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.missionFallback)
        }
        guard let ligne else { return nil }
        guard ligne.id.lowercased() == uuid, ligne.etablissementId == context.etablissementId else {
            throw JoleneError(.contract, "La mission retournée ne correspond pas à la demande.")
        }
        let missionLue = ligne.id
        var erreurPlanning: String?
        var creneaux: [MissionSlot] = []
        do {
            creneaux = try await self.creneaux(missionIds: [missionLue])[missionLue] ?? []
        } catch let erreur as JoleneError where erreur.kind != .cancelled {
            // Lecture secondaire (web l.555) : la mission reste affichée, le planning est « indisponible ».
            erreurPlanning = erreur.message
        }
        var enAttente: Int?
        if context.permissions.candidatures, ligne.statut == "OUVERTE", ligne.modeAttribution == "CANDIDATURE" {
            enAttente = await nombreCandidaturesEnAttente(missionId: missionLue)
        }
        return EtabMissionDetail(mission: ligne, creneaux: creneaux, soignantAssigneId: ligne.soignantAssigneId,
                                 candidaturesEnAttente: enAttente, erreurPlanning: erreurPlanning)
    }

    public func soignant(id: String, context: EtablissementReadContext) async throws -> SoignantPourEtab? {
        try context.verifier()
        // Identifiant canonique exigé (jamais l'uuid nul) : refusé avant réseau.
        guard let uuid = SupabaseAuditGateway.uuid(id) else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        let reponse = try await RPCResponse.appeler(
            client, Self.soignantRPC, params: ["p_soignant_id": .string(uuid)], fallback: Self.soignantFallback,
            interceptions: ListesBlanchesEtablissement.interceptions(rpc: Self.soignantRPC))
        if case .null = reponse.raw { return nil }
        try reponse.leverSiErreur(fallback: Self.soignantFallback)
        guard reponse.raw.objectValue != nil, !reponse.estRefus else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        let soignant = try SupabaseEtabSessionGateway.decoder(SoignantPourEtab.self, reponse)
        guard soignant.id.lowercased() == uuid else {
            throw JoleneError(.contract, "Le soignant retourné ne correspond pas à la demande.")
        }
        return soignant
    }

    // MARK: - Lectures secondaires

    /// Créneaux PREVISIONNEL hors pause, par mission, avec les contrôles d'intégrité de `MissionSlotPager`.
    func creneaux(missionIds: [String]) async throws -> [String: [MissionSlot]] {
        var parMission: [String: [MissionSlot]] = [:]
        for lot in MissionSlotPager.batches(missionIds) {
            var pager = MissionSlotPager(batch: lot)
            while pager.needsMore {
                try Task.checkCancellation()
                let reponse: PostgrestResponse<[MissionSlot]>
                do {
                    reponse = try await client.from("mission_creneaux")
                        .select(MissionQuery.slotSelect, count: .exact)
                        .in("mission_id", values: lot)
                        .eq("type_creneau", value: MissionQuery.forecastSlotType)
                        .eq("est_pause", value: false)
                        .order("mission_id", ascending: true)
                        .order("debut", ascending: true)
                        .order("id", ascending: true)
                        .range(from: pager.offset, to: pager.offset + MissionQuery.slotPageSize - 1)
                        .execute()
                } catch {
                    throw SupabaseErrorMapping.map(error, fallback: Self.creneauxFallback)
                }
                try pager.ingest(page: reponse.value, count: reponse.count)
            }
            for creneau in try pager.finish() { parMission[creneau.missionId ?? "", default: []].append(creneau) }
        }
        return parMission
    }

    private struct LigneStatut: Decodable { let statut: String? }
    private struct LigneCandidature: Decodable {
        let missionId: String
        enum CodingKeys: String, CodingKey { case missionId = "mission_id" }
    }

    /// Statuts de toutes les missions de l'établissement, comptés ; `nil` sur tout échec (rendu partiel).
    func compteurs(context: EtablissementReadContext) async -> EtabMissionsCompteurs? {
        var statuts: [String?] = []
        var attendu: Int?
        do {
            for _ in 0..<Self.maxPagesStatuts {
                let debut = statuts.count
                let reponse: PostgrestResponse<[LigneStatut]> = try await client.from("missions")
                    .select("statut", count: .exact)
                    .eq("etablissement_id", value: context.etablissementId)
                    .order("id", ascending: true)
                    .range(from: debut, to: debut + Self.pageStatuts - 1)
                    .execute()
                guard let compte = reponse.count, compte >= 0, attendu == nil || attendu == compte else { return nil }
                attendu = compte
                statuts.append(contentsOf: reponse.value.map(\.statut))
                if statuts.count >= compte { return statuts.count == compte ? EtabMissionsCompteurs(statuts: statuts) : nil }
                if reponse.value.isEmpty { return nil }
            }
        } catch {
            return nil
        }
        return nil
    }

    /// Candidatures `EN_ATTENTE` par mission ouverte ; jamais lues sans la permission `candidatures`.
    func candidaturesEnAttente(missionIds: [String], context: EtablissementReadContext) async -> [String: Int] {
        guard context.permissions.candidatures, !missionIds.isEmpty else { return [:] }
        let demandees = Set(missionIds)
        do {
            let lignes: [LigneCandidature] = try await client.from("candidatures")
                .select("mission_id")
                .in("mission_id", values: missionIds)
                .eq("statut", value: "EN_ATTENTE")
                .execute()
                .value
            var compte: [String: Int] = [:]
            for ligne in lignes where demandees.contains(ligne.missionId) { compte[ligne.missionId, default: 0] += 1 }
            return compte
        } catch {
            return [:]
        }
    }

    /// Compte exact des candidatures `EN_ATTENTE` d'une mission (web l.590-596, `head`) ; `nil` sur échec.
    func nombreCandidaturesEnAttente(missionId: String) async -> Int? {
        do {
            let reponse = try await client.from("candidatures")
                .select("id", head: true, count: .exact)
                .eq("mission_id", value: missionId)
                .eq("statut", value: "EN_ATTENTE")
                .execute()
            return reponse.count
        } catch {
            return nil
        }
    }
}
