import Foundation
import JoleneCore

/// Constantes et fonctions pures de la lecture des missions, portées de
/// `mobile-native/src/data/supabaseGateway.ts` et `src/lib/profession-hierarchy.ts`.
/// Aucune règle juridique ni montant n'est calculé ici : ce sont des projections serveur.
public enum MissionQuery {
    /// `MISSION_SELECT` du pilote, à l'identique (ordre inclus).
    public static let missionSelect = [
        "id", "intitule", "description", "service", "profession_requise",
        "specialite_medicale_requise", "accepte_non_specialises", "debut_le", "fin_le",
        "duree_heures", "nb_creneaux", "taux_horaire_base", "taux_rist_plafonne",
        "rist_plafond_applique", "total_brut", "net_a_payer", "est_urgente",
        "niveau_urgence", "statut", "etablissement_id", "type_contrat_recherche",
        "boostee_le", "mode_remuneration", "retrocession_pct",
    ].joined(separator: ",")

    /// `PROFILE_SELECT` du pilote.
    public static let profileSelect = "id,profession,adresse_lat,adresse_lng,rayon_deplacement_km,tous_documents_valides,type_contrat,types_contrat_acceptes,type_exercice,taux_horaire_minimum"

    public static let slotSelect = "id,mission_id,debut,fin,est_pause,type_creneau"
    public static let missionLimit = 500
    public static let slotBatchSize = 50
    public static let slotPageSize = 500
    public static let openStatus = "OUVERTE"
    public static let forecastSlotType = "PREVISIONNEL"
    public static let etablissementsRPC = "fn_etablissements_safe"

    /// Port de `getMissionsCompatiblesFilter` : IBODE et IADE peuvent candidater aux missions
    /// IDE, sans drapeau. Retourne l'argument de `.or(...)` PostgREST, ou `nil` quand le
    /// filtre strict `.eq("profession_requise", profession)` suffit.
    public static func compatibleProfessionFilter(_ profession: String?) -> String? {
        guard let profession, !profession.isEmpty else { return nil }
        if profession == "IBODE" || profession == "IADE" {
            return "profession_requise.eq.\(profession),profession_requise.eq.IDE"
        }
        return nil
    }

    /// Horodatage ISO 8601 UTC avec millisecondes, comme `Date.prototype.toISOString()`.
    /// Délègue à `DateHeureParis.isoUTC` (JoleneCore) : une seule implémentation du modèle
    /// `Date` JavaScript dans l'app.
    public static func isoTimestamp(_ date: Date) -> String {
        DateHeureParis.isoUTC(date)
    }

    /// Port de `calculerDistanceKm` (`src/lib/geo.ts`). Délègue à `Geo.distanceKm`
    /// (JoleneCore) : une seule Haversine dans l'app, conservée ici pour les appelants
    /// de JoleneSupabase.
    public static func distanceKm(lat1: Double?, lng1: Double?, lat2: Double?, lng2: Double?) -> Double? {
        Geo.distanceKm(lat1: lat1, lng1: lng1, lat2: lat2, lng2: lng2)
    }

    /// Vérification de `validateContext` du pilote : la session et le profil doivent coïncider.
    public static func validate(context: MissionReadContext) throws {
        guard !context.userId.isEmpty, context.profile.id == context.userId, !context.profile.profession.isEmpty else {
            throw JoleneError(.unauthorized, "Le profil soignant ne correspond pas à la session. Reconnectez-vous.")
        }
    }

    /// Filtres appliqués côté serveur : `defaultFilters(profile)` du pilote recouverts par la
    /// saisie (`tauxMin` par défaut = `taux_horaire_minimum` du profil, sinon 0). Les filtres
    /// de présentation (ville, rayon, contrat, horaire) restent du ressort de l'enrichisseur.
    public struct ServerFilters: Equatable, Sendable {
        public var profession: String?
        public var tauxMin: Double
        public var urgentesOnly: Bool
        public var etablissementId: String?

        public init(profession: String?, tauxMin: Double, urgentesOnly: Bool, etablissementId: String?) {
            self.profession = profession; self.tauxMin = tauxMin; self.urgentesOnly = urgentesOnly
            self.etablissementId = etablissementId
        }
    }

    public static func serverFilters(_ filters: MissionFilters, profile: SoignantProfile) -> ServerFilters {
        let profession = (filters.profession?.isEmpty == false) ? filters.profession : nil
        let etablissementId = (filters.etablissementId?.isEmpty == false) ? filters.etablissementId : nil
        return ServerFilters(
            profession: profession,
            tauxMin: filters.tauxMin ?? (profile.tauxHoraireMinimum ?? 0),
            urgentesOnly: filters.urgentesOnly ?? false,
            etablissementId: etablissementId
        )
    }

    /// Point d'extension de l'enrichissement : reçoit le contexte, les lignes serveur, les
    /// établissements par id et les créneaux prévisionnels, rend les `Mission` enrichies.
    /// Le filtrage de présentation (ville, rayon, contrat, horaire, cohorte Playwright) n'est
    /// PAS du ressort de l'enrichisseur : `SupabaseMissionsGateway.listMissions` applique
    /// `MissionBusiness.filter` après l'enrichissement, comme `filterMissions` du pilote.
    public typealias Enricher = @Sendable (
        _ context: MissionReadContext,
        _ records: [MissionRecord],
        _ etablissements: [String: EtablissementSummary],
        _ slots: [MissionSlot]
    ) -> [Mission]

    /// Enrichissement par défaut = `MissionBusiness.enrich` (port de `enrichMission` du
    /// pilote) : établissement par id, distance Haversine depuis l'adresse du profil, créneaux
    /// de la mission triés par début puis id, planning candidat dérivé (`planningExact` =
    /// `construirePlanningCandidat(...).exact`, donc `nb_creneaux` confronté aux créneaux
    /// reçus, jamais « créneaux présents »). Ordre serveur conservé.
    public static let defaultEnrich: Enricher = { context, records, etablissements, slots in
        var slotsByMission: [String: [MissionSlot]] = [:]
        for slot in slots {
            guard let missionId = slot.missionId else { continue }
            slotsByMission[missionId, default: []].append(slot)
        }
        return records.map { record in
            let missionSlots = (slotsByMission[record.id] ?? []).sorted {
                ($0.debut, $0.id ?? "") < ($1.debut, $1.id ?? "")
            }
            return MissionBusiness.enrich(record: record, context: context,
                                          etablissement: etablissements[record.etablissementId], slots: missionSlots)
        }
    }
}
