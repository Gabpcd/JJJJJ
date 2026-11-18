import Foundation
import JoleneCore
import Supabase

/// `FiltresSauvegardesPort` (L4-T4), port de `PageRecherchesSauvegardees.tsx` et de l'alerte rapide de
/// `RechercheMissions.tsx` (l.172-226). Quatre RPC SECURITY DEFINER, GRANT `authenticated` (`public.sql` l.83737,
/// l.82694, l.84077, l.85499 ; manifeste `RPC_UTILISATEUR_AUTH_INTERNE`), identité `auth.uid()` lue en interne, sur la
/// table `filtres_sauvegardes` (RLS `fs_*_own` et restrictive « compte actif », l.78405-78417, l.79081 ; jamais lue en
/// direct) :
/// - `fn_lister_mes_filtres_sauvegardes(p_audience)` — toujours `SOIGNANT_RECHERCHE_MISSIONS` ; tableau trié par
///   `mis_a_jour_le` décroissant, `[]` sans session (l.40401) ; une réponse qui n'est pas un tableau lisible est une
///   erreur (`FiltresSauvegardesEncodage.liste`), jamais une liste vide ;
/// - `fn_creer_filtre_sauvegarde(p_nom, p_audience, p_filtres, p_alerte_active, p_frequence_alerte)` — `p_audience`
///   obligatoire ; `p_filtres` = les sept clés camelCase d'Explorer, nombres entiers sans décimale ; des critères que
///   le validateur serveur refuserait (`FiltresSauvegardesEncodage.estValide`) ne partent jamais (`.contract`) ;
/// - `fn_modifier_filtre_sauvegarde(p_id, p_nom, p_alerte_active, p_frequence_alerte)` — `filtres` non modifiable ;
/// - `fn_supprimer_filtre_sauvegarde(p_id)`.
/// Réponses des mutations : `{success:true}` (et `id` à la création) puis relecture de la liste (`IssueFiltre.relue`) ;
/// refus `{error}` en HTTP 200 restitué verbatim (`IssueFiltre.refusee`), sauf « Non authentifié » → session expirée ;
/// toute autre forme → `.contract`. Aucune exception PostgREST métier déclarée par ces RPC : le mapping des lots 0-1
/// s'applique (`RPCResponse.appeler`). Une seule requête par appel, aucun renvoi.
public struct SupabaseFiltresGateway: FiltresSauvegardesPort {
    public static let rpcLister = "fn_lister_mes_filtres_sauvegardes"
    public static let rpcCreer = "fn_creer_filtre_sauvegarde"
    public static let rpcModifier = "fn_modifier_filtre_sauvegarde"
    public static let rpcSupprimer = "fn_supprimer_filtre_sauvegarde"

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func lister(context: MissionReadContext) async throws -> [FiltreSauvegarde] {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, Self.rpcLister,
                                                    params: ["p_audience": .string(FiltresSauvegardesEncodage.audience)],
                                                    fallback: FiltresTextes.chargementImpossible)
        try reponse.leverSiErreur(fallback: FiltresTextes.chargementImpossible)
        guard let liste = FiltresSauvegardesEncodage.liste(try Self.valeur(reponse.raw)) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        return liste
    }

    public func creer(nom: String, filtres: FiltresAlerte, alerte: Bool, frequence: FrequenceAlerte,
                      context: MissionReadContext) async throws -> IssueFiltre {
        try MissionQuery.validate(context: context)
        let criteres = FiltresSauvegardesEncodage.valeur(filtres)
        // Gap verrouillé : des critères hors validateur ne sont jamais envoyés (le serveur les refuserait d'un message
        // générique, « Compte ou critères de recherche invalides. »).
        guard FiltresSauvegardesEncodage.estValide(criteres) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        let params: JSONObject = [
            "p_nom": .string(nom),
            "p_audience": .string(FiltresSauvegardesEncodage.audience),
            "p_filtres": Self.json(criteres),
            "p_alerte_active": .bool(alerte),
            "p_frequence_alerte": .string(frequence.rawValue),
        ]
        return try await muter(Self.rpcCreer, params: params, fallback: FiltresTextes.alerteCreationImpossible, context: context)
    }

    public func modifier(id: String, nom: String, alerte: Bool, frequence: FrequenceAlerte,
                         context: MissionReadContext) async throws -> IssueFiltre {
        try MissionQuery.validate(context: context)
        let params: JSONObject = [
            "p_id": .string(id),
            "p_nom": .string(nom),
            "p_alerte_active": .bool(alerte),
            "p_frequence_alerte": .string(frequence.rawValue),
        ]
        return try await muter(Self.rpcModifier, params: params, fallback: FiltresTextes.erreurMiseAJour, context: context)
    }

    public func supprimer(id: String, context: MissionReadContext) async throws -> IssueFiltre {
        try MissionQuery.validate(context: context)
        return try await muter(Self.rpcSupprimer, params: ["p_id": .string(id)], fallback: FiltresTextes.erreurSuppression,
                               context: context)
    }

    // MARK: - Interne

    private func muter(_ fonction: String, params: JSONObject, fallback: String,
                       context: MissionReadContext) async throws -> IssueFiltre {
        let reponse = try await RPCResponse.appeler(client, fonction, params: params, fallback: fallback)
        if let erreur = reponse.erreur {
            if RPCResponse.estNonAuthentifie(erreur) {
                throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
            }
            return .refusee(message: erreur)
        }
        guard reponse.estSucces else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        return .relue(try await lister(context: context))
    }

    /// `ValeurJSON` → corps JSON : un nombre entier part sans décimale (`25`, jamais `25.0`), comme `JSON.stringify`.
    static func json(_ valeur: ValeurJSON) -> AnyJSON {
        switch valeur {
        case .null: return .null
        case .booleen(let booleen): return .bool(booleen)
        case .nombre(let nombre):
            if nombre.isFinite, nombre == nombre.rounded(), abs(nombre) < 1e15 { return .integer(Int(nombre)) }
            return .double(nombre)
        case .chaine(let texte): return .string(texte)
        case .tableau(let elements): return .array(elements.map(json))
        case .objet(let objet): return .object(objet.mapValues(json))
        }
    }

    /// Réponse RPC (`AnyJSON` du SDK) relue en `ValeurJSON`, sans perte de type (booléen ≠ nombre).
    static func valeur(_ json: AnyJSON) throws -> ValeurJSON {
        do {
            return try JSONDecoder().decode(ValeurJSON.self, from: JSONEncoder().encode(json))
        } catch {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
    }
}
