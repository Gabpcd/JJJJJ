import Foundation
import JoleneCore
import Supabase

/// `SwipePort` sur Supabase (lot 4, T3a ; `docs/mobile-swift/LOT4_PLAN.md` §2.4, fiches de `CONTRATS_RPC_SOIGNANT.md`),
/// sous le JWT du soignant. Le ❤️ n'est pas ici : `CandidaturePort.confirmer(.swipeLike)` (`SupabaseCandidatureGateway`).
/// - Paquet : `fn_obtenir_missions_swipe(p_limit := 20)` → `{missions:[…]}` (pas de `success`) ;
///   `{missions:[], error:'auth_required'}` → `.unauthorized`. Puis créneaux PREVISIONNEL hors pauses par
///   `MissionSlotPager` (lots de 50, compte exact, `SupabaseMissionsGateway.slots`) : un planning illisible fait échouer
///   le paquet, comme le web (« Planning des missions indisponible »), jamais une carte au planning supposé. Nom
///   d'établissement du payload (jointure serveur), sans appel à `fn_etablissements_safe`.
/// - ✕ / ⭐ : `fn_enregistrer_swipe(p_mission_id, p_direction)` → `{ok:true, …}` ; `{ok:false, error}` : code technique
///   traduit par `SwipeRefus`, message rédigé verbatim ; `auth_required` → `.unauthorized`. ⭐ : la ligne
///   `missions_sauvegardees` posée par la RPC est relue avant `.enregistre`.
/// - Retrait : `fn_retirer_candidature(p_candidature_id)` → `{success:true}` puis candidature relue absente ; refus
///   `{success:false, error}` verbatim (« Non authentifié » → `.unauthorized`).
/// - Quiz : `swipes` en `HEAD` + `count=exact` (RLS `swipes_select_own`) ; `fn_initialiser_preferences_matching`.
/// Aucune de ces RPC ne lève d'exception métier (aucun `RAISE` dans leur corps) : interception du lot 1 seule.
/// Une seule requête par mutation, aucun renvoi automatique.
public struct SupabaseSwipeGateway: SwipePort {
    public static let paquetRPC = "fn_obtenir_missions_swipe"
    public static let enregistrerRPC = "fn_enregistrer_swipe"
    public static let retirerRPC = "fn_retirer_candidature"
    public static let preferencesRPC = "fn_initialiser_preferences_matching"
    public static let tableSwipes = "swipes"
    public static let tableSauvegardees = "missions_sauvegardees"

    public static let paquetFallback = "Les missions à parcourir n'ont pas pu être chargées. Réessayez."
    public static let retraitFallback = "Retrait impossible — la candidature a peut-être déjà été acceptée."
    public static let preferencesFallback = "Vos préférences n'ont pas pu être enregistrées."
    public static let compteFallback = "Vos réponses aux missions n'ont pas pu être comptées."
    /// Le serveur a répondu mais la relecture ne le confirme pas : rien n'est renvoyé automatiquement.
    public static let relectureFavoriMessage = "La mission a été enregistrée mais sa sauvegarde n'a pas pu être relue. Vérifiez Mes favoris."
    public static let relectureRetraitMessage = "Le retrait a été envoyé mais n'a pas pu être relu. Vérifiez Mes missions."
    public static let identifiantInvalideMessage = SupabaseCandidatureGateway.identifiantInvalideMessage

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Paquet

    public func paquet(context: MissionReadContext) async throws -> [CarteSwipe] {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, Self.paquetRPC, params: ["p_limit": .integer(PaquetSwipe.taille)],
                                                    fallback: Self.paquetFallback)
        guard let paquet = PointageQuery.decoder(PaquetSwipe.self, reponse) else {
            throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
        }
        if paquet.nonAuthentifie { throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage) }
        try reponse.leverSiErreur(fallback: Self.paquetFallback)
        guard reponse.valeur("missions")?.arrayValue != nil else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        guard !paquet.missions.isEmpty else { return [] }
        let creneaux = try await SupabaseMissionsGateway(client: client).slots(missionIds: paquet.missions.map(\.missionId))
        var parMission: [String: [MissionSlot]] = [:]
        for creneau in creneaux {
            guard let missionId = creneau.missionId else { continue }
            parMission[missionId, default: []].append(creneau)
        }
        return paquet.missions.map { CarteSwipe(ligne: $0, creneaux: parMission[$0.missionId] ?? []) }
    }

    // MARK: - ✕ et ⭐

    public func enregistrer(missionId: String, direction: DirectionSwipe, context: MissionReadContext) async throws -> SwipeOutcome {
        try MissionQuery.validate(context: context)
        guard let mission = SupabaseCandidatureGateway.uuid(missionId) else {
            throw JoleneError(.contract, Self.identifiantInvalideMessage)
        }
        // Comme le web : `p_choix_contrat` n'est envoyé que pour un ❤️ (jamais ici).
        let reponse = try await RPCResponse.appeler(client, Self.enregistrerRPC,
                                                    params: ["p_mission_id": .string(mission), "p_direction": .string(direction.rawValue)],
                                                    fallback: SwipeRefus.repli)
        if reponse.erreur == PaquetSwipe.erreurNonAuthentifie {
            throw JoleneError(.unauthorized, SupabaseErrorMapping.unauthorizedMessage)
        }
        if reponse.ok == false {
            let refus = SwipeRefus.traduire(reponse.erreur)
            return .refuse(code: refus.code, message: refus.message)
        }
        guard reponse.ok == true, reponse.erreur == nil else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        if direction == .favori {
            guard try await favoriRelu(missionId: mission, context: context) else {
                throw JoleneError(.contract, Self.relectureFavoriMessage)
            }
        }
        return .enregistre
    }

    // MARK: - Retrait

    public func retirer(candidatureId: String, context: MissionReadContext) async throws -> RetraitOutcome {
        try MissionQuery.validate(context: context)
        guard let id = SupabaseCandidatureGateway.uuid(candidatureId) else {
            throw JoleneError(.contract, Self.identifiantInvalideMessage)
        }
        let reponse = try await RPCResponse.appeler(client, Self.retirerRPC, params: ["p_candidature_id": .string(id)],
                                                    fallback: Self.retraitFallback)
        try reponse.leverSiErreur(fallback: Self.retraitFallback)
        if reponse.estRefus { return .refuse(message: reponse.erreur ?? Self.retraitFallback) }
        guard reponse.success == true else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        let restantes: [CandidatureRecord]
        do {
            restantes = try await client.from("candidatures")
                .select(SupabaseCandidatureGateway.candidatureColumns)
                .eq("id", value: id)
                .eq("soignant_id", value: context.userId)
                .limit(1)
                .execute()
                .value
        } catch {
            throw JoleneError(SupabaseErrorMapping.map(error, fallback: Self.relectureRetraitMessage).kind, Self.relectureRetraitMessage)
        }
        guard restantes.isEmpty else { throw JoleneError(.contract, Self.relectureRetraitMessage) }
        return .retiree
    }

    // MARK: - Quiz

    public func nombreSwipes(context: MissionReadContext) async throws -> Int {
        try MissionQuery.validate(context: context)
        let reponse: PostgrestResponse<Void>
        do {
            reponse = try await client.from(Self.tableSwipes)
                .select("id", head: true, count: .exact)
                .eq("soignant_id", value: context.userId)
                .execute()
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.compteFallback)
        }
        guard let nombre = reponse.count, nombre >= 0 else { throw JoleneError(.unknown, Self.compteFallback) }
        return nombre
    }

    public func initialiserPreferences(_ preferences: PreferencesMatching, context: MissionReadContext) async throws {
        try MissionQuery.validate(context: context)
        // Bornes serveur [0, 1] : rien n'est envoyé hors bornes.
        guard preferences.dansLesBornes else { throw JoleneError(.contract, Self.preferencesFallback) }
        let params: JSONObject = [
            "p_pref_nuit": .double(preferences.nuit),
            "p_pref_jour": .double(preferences.jour),
            "p_pref_weekend": .double(preferences.weekend),
            "p_pref_semaine": .double(preferences.semaine),
        ]
        let reponse = try await RPCResponse.appeler(client, Self.preferencesRPC, params: params, fallback: Self.preferencesFallback)
        try reponse.leverSiErreur(fallback: Self.preferencesFallback)
        if reponse.estRefus { throw JoleneError(.unknown, reponse.erreur ?? Self.preferencesFallback) }
        guard reponse.success == true else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
    }

    // MARK: - Interne

    /// Ligne `missions_sauvegardees` de la session pour cette mission (posée par `fn_enregistrer_swipe`, RLS du soignant).
    private func favoriRelu(missionId: String, context: MissionReadContext) async throws -> Bool {
        struct Ligne: Decodable { var missionId: String; enum CodingKeys: String, CodingKey { case missionId = "mission_id" } }
        let lignes: [Ligne]
        do {
            lignes = try await client.from(Self.tableSauvegardees)
                .select("mission_id")
                .eq("soignant_id", value: context.userId)
                .eq("mission_id", value: missionId)
                .limit(1)
                .execute()
                .value
        } catch {
            throw JoleneError(SupabaseErrorMapping.map(error, fallback: Self.relectureFavoriMessage).kind, Self.relectureFavoriMessage)
        }
        return lignes.contains { $0.missionId.caseInsensitiveCompare(missionId) == .orderedSame }
    }
}
