import Foundation
import JoleneCore
import Supabase

/// `EtabPublicationPort` sur Supabase (lot 5, T9 ; `LOT5_PLAN.md` §2.4-§2.5, §3 T9 ; fiche
/// `CONTRATS_RPC_ETABLISSEMENT.md`), sous le JWT du membre de l'établissement :
/// - envoi : `fn_creer_mission_multi_jours_v4` avec **exactement** les seize paramètres de `PublicationPayload`
///   (périmètre natif D8), une seule requête, aucun renvoi. Le serveur agit sur `mon_etablissement_id()` : aucun
///   identifiant d'établissement n'est envoyé. Brouillon structurellement invalide, profession renvoyée au web ou
///   liste de créneaux vide : refus avant tout appel ;
/// - `{error: CODE, message}` de `fn_blocage_publication_etab` → `.blocageEtablissement`, `message` mot pour mot
///   (la clé `error` porte alors un code, jamais affiché) ;
/// - tout autre refus (`{success:false, error}`, `code` éventuel ; `{error}` sans drapeau) → `.refusee`, texte serveur
///   mot pour mot ; « Non authentifié » et l'exception `28000` de la liste blanche → `.unauthorized` ;
/// - `{success:true, mission_id}` ne vaut pas confirmation : la mission est relue (`missions` : statut, nombre de
///   créneaux, bornes, type de contrat, sans aucun montant ; `mission_creneaux` PREVISIONNEL hors pause par le pager
///   exact de T5) et comparée à l'envoi par `PublicationRelecture.confirme` ; relecture impossible ou différente →
///   `.nonConfirmee`, jamais un succès. Une réponse sans `mission_id` exploitable est un refus de contrat.
public struct SupabaseEtabPublicationGateway: EtabPublicationPort {
    public static let rpc = "fn_creer_mission_multi_jours_v4"
    /// Repli du web quand le serveur ne rend aucun texte (`FormulaireMission.tsx` l.457).
    public static let fallback = "Erreur lors de la création de la mission."

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func publier(_ brouillon: PublicationMission, context: EtablissementReadContext) async throws -> PublicationOutcome {
        try context.verifier()
        guard PublicationRules.champsInvalides(brouillon).isEmpty, !brouillon.creneaux.isEmpty else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        let charge = PublicationPayload(brouillon)
        guard Set(charge.valeurs.keys) == Set(PublicationPayload.cles) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        let params: JSONObject = charge.valeurs.mapValues(SupabaseFiltresGateway.json)
        let reponse = try await RPCResponse.appeler(client, Self.rpc, params: params, fallback: Self.fallback,
                                                    interceptions: ListesBlanchesEtablissement.interceptions(rpc: Self.rpc))
        if let blocage = reponse.blocagePublication {
            return .blocageEtablissement(code: blocage.code, message: blocage.message)
        }
        if let erreur = reponse.erreur, RPCResponse.estNonAuthentifie(erreur) {
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        }
        if reponse.estRefus || reponse.valeur("error") != nil {
            return .refusee(code: reponse.code, message: reponse.erreur ?? Self.fallback)
        }
        guard reponse.estSucces, let missionId = SupabaseAuditGateway.uuid(try reponse.requiredString("mission_id")) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        // Relecture (PRINCIPES §3) : la mission existe côté serveur ; un échec ici n'est jamais un succès ni une
        // invitation à renvoyer.
        let relue: EtabMissionDetail?
        do {
            relue = try await relire(missionId: missionId, context: context)
        } catch let erreur as JoleneError where erreur.kind == .cancelled {
            throw erreur
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .nonConfirmee(missionId: missionId)
        }
        guard let relue, PublicationRelecture.confirme(relue, envoi: brouillon.creneaux) else {
            return .nonConfirmee(missionId: missionId)
        }
        return .publiee(missionId: missionId)
    }

    /// Colonnes relues sur `missions` après la création : celles que `PublicationRelecture` compare, sans aucun montant.
    static let relectureSelect = "id,etablissement_id,statut,nb_creneaux,debut_le,fin_le,type_contrat_recherche"

    /// Mission créée relue sous le JWT courant (`pol_mission_select`, établissement **confirmé** du contexte) et ses
    /// créneaux PREVISIONNEL hors pause (pager exact de T5). `nil` si la ligne est illisible ou n'est pas celle demandée.
    func relire(missionId: String, context: EtablissementReadContext) async throws -> EtabMissionDetail? {
        let ligne: EtabMissionResume?
        do {
            ligne = try await client.from("missions")
                .select(Self.relectureSelect)
                .eq("id", value: missionId)
                .eq("etablissement_id", value: context.etablissementId)
                .maybeSingle()
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: SupabaseEtabMissionsGateway.missionFallback)
        }
        guard let ligne, ligne.id.lowercased() == missionId, ligne.etablissementId == context.etablissementId else { return nil }
        let creneaux = try await SupabaseEtabMissionsGateway(client: client).creneaux(missionIds: [ligne.id])[ligne.id] ?? []
        return EtabMissionDetail(mission: ligne, creneaux: creneaux, soignantAssigneId: nil)
    }
}
