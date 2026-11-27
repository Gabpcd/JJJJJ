import Foundation
import JoleneCore
import Supabase

/// `FavorisPort` (lot 1, T4b), port de `BoutonSauvegarderMission.tsx` et de `MesFavorisSoignant.tsx`.
///
/// Missions : PostgREST direct sur `missions_sauvegardees` sous RLS (`soignant_id = auth.uid()` en
/// lecture, insertion et suppression, `public.sql` l.78773-78781 ; politique restrictive « compte actif »
/// l.79383), avec la jointure `missions(...)` du web. L'insertion ne relit rien (`return=minimal`) :
/// la liste est relue juste après ; un conflit UNIQUE (`23505`, mission déjà sauvegardée) est un état à
/// relire, pas une erreur.
///
/// Favoris de l'inscription progressive (décision 8 du lot 1 amendée le 18/11/2026, revue B8 de T4b, M2), comme le web
/// (`MesFavorisSoignant.tsx` l.43-53, `BoutonSauvegarderMission.tsx` l.36-44 et l.61-64) : chaque lecture relit
/// aussi `parcours_inscription.donnees->missionsSauvegardees` (SELECT de cette seule clé, RLS `parcours_inscription_proprietaire`
/// l.78669 : propriétaire et compte actif ; GRANT SELECT l.86801), puis les aperçus des missions absentes de la table
/// (`missions` sous RLS, mêmes colonnes que la jointure), et fusionne les deux magasins sans doublon
/// (`FavorisRegles.fusion`). Le retrait vide les deux : `fn_modifier_favori_inscription(p_actif := false)`
/// (l.43500, SECURITY DEFINER, GRANT `authenticated` l.84072) si la mission y figure, puis la ligne de la table.
/// L'ajout n'écrit que la table, comme le web. Un échec de lecture de l'un des magasins fait échouer la lecture :
/// jamais une liste partielle présentée comme complète.
///
/// Établissements : `fn_mes_favoris_etablissements()` (tableau, ou `{error}` en HTTP 200) puis, comme le
/// veut la fiche du contrat, le nom de `fn_etablissements_safe` quand la ligne existe (lecture
/// complémentaire : en échec, le nom de la RPC reste ; session expirée et annulation propagées). Retrait
/// par `fn_toggle_favori_etablissement(p_actif := false)` puis relecture ; `p_actif = true` est refusé
/// avant tout appel (décision 8, `FavorisRegles.ajoutEtablissementNonPropose`).
///
/// Une seule requête par mutation, aucun renvoi : un refus ou une erreur de transport remonte en
/// `JoleneError` et le modèle relit (PRINCIPES §3-§4). Messages serveur verbatim.
public struct SupabaseFavorisGateway: FavorisPort {
    public static let table = "missions_sauvegardees"
    /// Colonnes de `MesFavorisSoignant.tsx` l.42-44 utiles à l'écran (montants non affichés : non lus).
    public static let selectSauvegardees =
        "id,mission_id,cree_le,missions(id,intitule,debut_le,fin_le,duree_heures,nb_creneaux,statut)"
    public static let rpcListe = "fn_mes_favoris_etablissements"
    public static let rpcBascule = "fn_toggle_favori_etablissement"
    /// `missions_sauvegardees_soignant_id_mission_id_key` (l.73531) : déjà sauvegardée.
    public static let codeConflitUnique = "23505"
    /// Magasin des favoris de l'inscription progressive (décision 8 du lot 1 amendée le 18/11/2026).
    public static let tableParcours = "parcours_inscription"
    /// Seule la clé utile du brouillon est lue (revue B8 delta de #1149, m4) : alias PostgREST de la clé JSON.
    public static let colonnesParcours = "\(FavorisRegles.cleFavorisInscription):donnees->\(FavorisRegles.cleFavorisInscription)"
    /// Aperçus des favoris de l'inscription : mêmes colonnes que la jointure de `selectSauvegardees`.
    public static let tableMissions = "missions"
    public static let colonnesApercu = "id,intitule,debut_le,fin_le,duree_heures,nb_creneaux,statut"
    public static let rpcRetraitInscription = "fn_modifier_favori_inscription"
    /// SQLSTATE métier de `fn_modifier_favori_inscription` (« Favori invalide. », l.43500) : message restitué.
    static let exceptionsRetraitInscription: Set<String> = ["22023"]
    /// Identifiants par requête `in.(…)` (longueur d'URL bornée ; 200 favoris au plus côté SQL).
    static let tailleLotApercus = 50

    public static let lectureMissionsFallback = "Vos missions sauvegardées n'ont pas pu être chargées. Réessayez."
    public static let sauvegardeFallback = "La mission n'a pas pu être sauvegardée. Réessayez."
    public static let retraitFallback = "La mission n'a pas pu être retirée de vos favoris. Réessayez."
    public static let lectureEtablissementsFallback = "Vos établissements favoris n'ont pas pu être chargés. Réessayez."
    public static let retraitEtablissementFallback = "L'établissement n'a pas pu être retiré de vos favoris. Réessayez."

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Missions sauvegardées

    /// Deux magasins relus en parallèle (web : `Promise.all`), puis fusionnés (`FavorisRegles.fusion`).
    public func missionsSauvegardees(context: MissionReadContext) async throws -> [MissionSauvegardee] {
        try MissionQuery.validate(context: context)
        async let table = lignesTable(context: context)
        async let inscription = idsInscription(context: context)
        let (lignes, ids) = try await (table, inscription)
        let lues = Set(lignes.filter { $0.mission != nil }.map(\.missionId))
        let apercus = try await apercus(ids: ids.filter { !lues.contains($0) })
        return FavorisRegles.fusion(sauvegardees: lignes, inscription: ids, apercus: apercus)
    }

    private func lignesTable(context: MissionReadContext) async throws -> [MissionSauvegardee] {
        do {
            return try await client.from(Self.table)
                .select(Self.selectSauvegardees)
                .eq("soignant_id", value: context.userId)
                .order("cree_le", ascending: false)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.lectureMissionsFallback)
        }
    }

    /// `parcours_inscription.donnees.missionsSauvegardees` du soignant (web : `chargerFavorisInscription`) ; aucune
    /// ligne (inscription terminée sans parcours conservé) : aucun favori d'inscription.
    private func idsInscription(context: MissionReadContext) async throws -> [String] {
        let lignes: [ValeurJSON]
        do {
            lignes = try await client.from(Self.tableParcours)
                .select(Self.colonnesParcours)
                .eq("user_id", value: context.userId)
                .limit(1)
                .execute()
                .value
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.lectureMissionsFallback)
        }
        // La ligne porte la seule clé `missionsSauvegardees` : même lecture que `donnees` complet.
        return FavorisRegles.idsInscription(lignes.first)
    }

    /// Aperçus des missions de l'inscription sous RLS, par lots. Seuls les UUID sont demandés (le SQL n'écrit que
    /// `p_mission_id::text`) : un identifiant d'une autre forme ne correspond à aucune mission, il reste sans aperçu
    /// (étoile allumée, mission non listée) au lieu de faire échouer la requête (`22P02`).
    private func apercus(ids: [String]) async throws -> [String: MissionSauvegardee.Apercu] {
        let valides = ids.filter { UUID(uuidString: $0) != nil }
        guard !valides.isEmpty else { return [:] }
        var resultat: [String: MissionSauvegardee.Apercu] = [:]
        do {
            for debut in stride(from: 0, to: valides.count, by: Self.tailleLotApercus) {
                let lot = Array(valides[debut..<min(debut + Self.tailleLotApercus, valides.count)])
                let lus: [MissionSauvegardee.Apercu] = try await client.from(Self.tableMissions)
                    .select(Self.colonnesApercu)
                    .in("id", values: lot)
                    .execute()
                    .value
                for apercu in lus where lot.contains(apercu.id) { resultat[apercu.id] = apercu }
            }
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.lectureMissionsFallback)
        }
        return resultat
    }

    public func sauvegarder(missionId: String, context: MissionReadContext) async throws -> [MissionSauvegardee] {
        try MissionQuery.validate(context: context)
        let id = try Self.identifiant(missionId)
        do {
            try await client.from(Self.table)
                .insert(["mission_id": id, "soignant_id": context.userId], returning: .minimal)
                .execute()
        } catch let erreur as PostgrestError where erreur.code == Self.codeConflitUnique {
            // Déjà sauvegardée (autre appareil, double appui) : la relecture fait foi.
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.sauvegardeFallback)
        }
        return try await missionsSauvegardees(context: context)
    }

    /// Retrait des deux magasins, dans l'ordre du web : favori de l'inscription d'abord (seulement s'il y figure, comme
    /// `chargerFavorisInscription().includes(missionId)`), puis la ligne de la table ; chaque refus remonte tel quel,
    /// sans renvoi, et le modèle relit.
    public func retirer(missionId: String, context: MissionReadContext) async throws -> [MissionSauvegardee] {
        try MissionQuery.validate(context: context)
        let id = try Self.identifiant(missionId)
        if try await idsInscription(context: context).contains(id) {
            let issue = try await RPCResponse.appelerSansCorps(
                client, Self.rpcRetraitInscription,
                params: ["p_mission_id": .string(id), "p_actif": .bool(false)],
                fallback: Self.retraitFallback, exceptionsMetier: Self.exceptionsRetraitInscription)
            if case let .refus(reponse) = issue { throw JoleneError(.unknown, reponse.erreur ?? Self.retraitFallback) }
        }
        do {
            try await client.from(Self.table)
                .delete(returning: .minimal)
                .eq("mission_id", value: id)
                .eq("soignant_id", value: context.userId)
                .execute()
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: Self.retraitFallback)
        }
        return try await missionsSauvegardees(context: context)
    }

    // MARK: - Établissements suivis

    public func etablissementsFavoris(context: MissionReadContext) async throws -> [EtablissementFavori] {
        try MissionQuery.validate(context: context)
        let reponse = try await RPCResponse.appeler(client, Self.rpcListe, fallback: Self.lectureEtablissementsFallback)
        var favoris = try Self.liste(reponse)
        let noms = try await nomsSurs(ids: favoris.map(\.id))
        for index in favoris.indices {
            if let nom = noms[favoris[index].id] { favoris[index].nom = nom }
        }
        return favoris
    }

    public func basculerEtablissement(id: String, actif: Bool, context: MissionReadContext) async throws -> [EtablissementFavori] {
        try MissionQuery.validate(context: context)
        guard !actif else { throw JoleneError(.contract, FavorisRegles.ajoutEtablissementNonPropose) }
        let etablissementId = try Self.identifiant(id)
        let reponse = try await RPCResponse.appeler(
            client, Self.rpcBascule,
            params: ["p_etablissement_id": .string(etablissementId), "p_actif": .bool(false)],
            fallback: Self.retraitEtablissementFallback)
        try reponse.leverSiErreur(fallback: Self.retraitEtablissementFallback)
        // `{success:false, error}` (« Établissement introuvable ») : refus verbatim, jamais un succès supposé.
        if reponse.estRefus { throw JoleneError(.unknown, reponse.erreur ?? Self.retraitEtablissementFallback) }
        guard reponse.estSucces else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        return try await etablissementsFavoris(context: context)
    }

    // MARK: - Interprétation

    /// Corps de `fn_mes_favoris_etablissements` : un tableau (élément sans `etablissement_id` écarté
    /// seul), sinon `{error}` (« Non authentifié » → session expirée, autre message → verbatim) ; tout
    /// autre corps est un refus de contrat.
    static func liste(_ reponse: RPCResponse) throws -> [EtablissementFavori] {
        if let elements = reponse.raw.arrayValue {
            return elements.compactMap { try? $0.decode(as: EtablissementFavori.self) }
        }
        try reponse.leverSiErreur(fallback: lectureEtablissementsFallback)
        if reponse.estRefus { throw JoleneError(.unknown, reponse.erreur ?? lectureEtablissementsFallback) }
        throw JoleneError(.contract, SupabaseErrorMapping.contractMessage)
    }

    /// Noms par `fn_etablissements_safe` (seule source du nom d'établissement côté natif, `LOT1_PLAN.md`
    /// §2.6). Lecture complémentaire : en échec, le nom de `fn_mes_favoris_etablissements` reste.
    private func nomsSurs(ids: [String]) async throws -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        do {
            return try await SupabaseMissionsGateway(client: client).etablissements(ids: ids).mapValues(\.nom)
        } catch let erreur as JoleneError where erreur.kind == .unauthorized || erreur.kind == .cancelled {
            throw erreur
        } catch {
            if Task.isCancelled { throw CancellationError() }
            return [:]
        }
    }

    /// Identifiant qui conditionne la requête : vide → refus de contrat avant tout appel.
    static func identifiant(_ valeur: String) throws -> String {
        let id = valeur.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw JoleneError(.contract, SupabaseErrorMapping.contractMessage) }
        return id
    }
}
