import Foundation
import JoleneCore
import Supabase

/// `NotationPort` sur Supabase (blueprint lot 2 §2.3-§2.4, tranche T5a), avec le JWT du soignant.
///
/// - `fn_creer_notation_mission` par ses sept clés exactes (`NotationRapide.tsx` l.48-53) : `p_sens: 'SOIGNANT_VERS_ETAB'`,
///   quatre critères (note globale répliquée sans détail, l.47), `p_commentaire: null` (aucun commentaire au départ). Une
///   seule requête POST (jamais rejouée par le SDK). Succès `{success:true, id, tardive}` → `.enregistree` ;
///   « Mission déjà notée pour ce sens » → `.dejaNotee` (silencieux, l.58-61) ; tout autre `{success:false, error}` →
///   `.refusee` verbatim ; « Non authentifié » → `.unauthorized` ; exception `P0001` (audit refusé, transaction annulée,
///   `public.sql` l.27425, l.27439) → `.refusee` verbatim (`ExceptionsMetierLot2.creerNotationMission`).
/// - Écriture seule : `notations_missions` n'est jamais lue (double-aveugle D8, filtre centralisé `evaluations_publiees`,
///   CLAUDE.md « Publication différée ») ; la réponse ne porte aucune note (définition live relue le 9 novembre 2026).
/// - `finPrevue` : `missions?select=fin_le&id=eq.<mission>` (`PointageRotatifSoignant.tsx` l.156).
public struct SupabaseNotationGateway: NotationPort {
    public static let rpc = "fn_creer_notation_mission"
    /// Sens du soignant vers l'établissement (`SensNotation`, l.27).
    public static let sens = "SOIGNANT_VERS_ETAB"
    /// Refus « déjà notée » du serveur (`public.sql` l.27399), reconnu comme le web (`includes('déjà notée')`, l.61).
    public static let marqueDejaNotee = "déjà notée"

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func noter(missionId: String, note: Int, criteres: CriteresNotation?,
                      context: MissionReadContext) async throws -> IssueNotation {
        try MissionQuery.validate(context: context)
        let valeurs = (criteres ?? CriteresNotation.repliques(note: note)).valeurs
        var params: JSONObject = [
            "p_mission_id": .string(missionId),
            "p_sens": .string(Self.sens),
            "p_commentaire": .null,
        ]
        for (index, valeur) in valeurs.enumerated() {
            params["p_critere_\(index + 1)"] = .integer(valeur)
        }
        let reponse = try await RPCResponse.appeler(client, Self.rpc, params: params,
                                                    fallback: LibellesDetailPresences.Notation.erreurEnregistrement,
                                                    exceptionsMetier: ExceptionsMetierLot2.creerNotationMission)
        if reponse.success == true, reponse.erreur == nil { return .enregistree }
        guard let erreur = reponse.erreur else {
            return .refusee(message: LibellesDetailPresences.Notation.erreurEnregistrement)
        }
        if RPCResponse.estNonAuthentifie(erreur) {
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        }
        if erreur.contains(Self.marqueDejaNotee) { return .dejaNotee }
        return .refusee(message: erreur)
    }

    public func finPrevue(missionId: String, context: MissionReadContext) async throws -> String? {
        try MissionQuery.validate(context: context)
        do {
            let lignes: [LigneFinPrevue] = try await client.from("missions").select("fin_le")
                .eq("id", value: missionId)
                .limit(1)
                .execute().value
            return lignes.first?.finLe
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: PointageQuery.fallbackDetail)
        }
    }
}

private struct LigneFinPrevue: Decodable {
    let finLe: String?

    enum CodingKeys: String, CodingKey { case finLe = "fin_le" }
}
