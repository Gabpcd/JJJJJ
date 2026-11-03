import Foundation

/// Mission telle que l'historique la lit : identifiant et établissement rattaché.
public struct MissionHistorique: Equatable, Sendable {
    public var id: String
    /// `etablissement_id` ; `nil` ou vide : aucun établissement résolu.
    public var etablissementId: String?

    public init(id: String, etablissementId: String?) {
        self.id = id; self.etablissementId = etablissementId
    }

    public init(record: MissionRecord) {
        self.init(id: record.id, etablissementId: record.etablissementId)
    }
}

/// Ligne d'historique reconstruite depuis les segments EFFECTIF (port du modèle d'affichage de
/// `construireHistoriqueEffectifsSansPresence`). Ce n'est jamais une présence validable : aucun
/// identifiant métier, jamais validée, aucune méthode de pointage. `Etablissement` est la valeur
/// résolue par l'appelant (`fn_etablissements_safe` uniquement, lot 2 §2.7).
public struct LigneHistoriqueEffectifs<Etablissement>: Identifiable {
    /// `effectifs-mission-<mission_id>`.
    public let id: String
    public let missionId: String
    public let soignantId: String
    /// Début du premier segment fermé (par début).
    public let pointageArriveeLe: String
    /// Fin du dernier segment fermé par début (pas la plus tardive des fins).
    public let pointageDepartLe: String?
    public let valideParEtablissement: Bool
    public let valideLe: String?
    public let methodePointageArrivee: String?
    public let methodePointageDepart: String?
    public let origineEffectifsSansPresence: Bool
    public let etablissement: Etablissement?
    /// Tous les créneaux lus pour la mission (prévus et effectifs).
    public let creneaux: [MissionSlot]
}

extension LigneHistoriqueEffectifs: Equatable where Etablissement: Equatable {}
extension LigneHistoriqueEffectifs: Sendable where Etablissement: Sendable {}

/// Port de `src/lib/presencesSoignantUi.ts`.
///
/// La construction des listes de présences (aujourd'hui, à venir, actives, historique :
/// `PresencesSoignant.tsx` l.208-276) sera portée par la tranche T2b dans `ListesPresences.swift`,
/// avec ses vecteurs golden, après la PR web W1 qui l'extrait vers `src/lib/presences-soignant-listes.ts`.
public enum HistoriquePresences {
    /// Une ligne par mission sans présence legacy qui a au moins un segment EFFECTIF fermé.
    /// `missionsAvecPresence` : `mission_id` des présences lues (nuls et vides ignorés).
    public static func construireEffectifsSansPresence<Etablissement>(
        missions: [MissionHistorique],
        missionsAvecPresence: [String?],
        creneauxParMission: [String: [MissionSlot]],
        etablissements: [String: Etablissement],
        soignantId: String
    ) -> [LigneHistoriqueEffectifs<Etablissement>] {
        let avecPresence = Set(missionsAvecPresence.compactMap { $0 }.filter { !$0.isEmpty })
        return missions.compactMap { mission in
            guard !avecPresence.contains(mission.id) else { return nil }
            let creneaux = creneauxParMission[mission.id] ?? []
            let effectifs = triStableCroissant(creneaux.filter {
                $0.typeCreneau == "EFFECTIF" && !$0.estPause && !($0.fin ?? "").isEmpty
            }) { DisponibilitePointage.temps($0.debut) }
            guard let premier = effectifs.first else { return nil }
            let etablissement = (mission.etablissementId ?? "").isEmpty ? nil : etablissements[mission.etablissementId ?? ""]
            return LigneHistoriqueEffectifs(
                id: "effectifs-mission-\(mission.id)",
                missionId: mission.id,
                soignantId: soignantId,
                pointageArriveeLe: premier.debut,
                pointageDepartLe: effectifs.last?.fin,
                valideParEtablissement: false,
                valideLe: nil,
                methodePointageArrivee: nil,
                methodePointageDepart: nil,
                origineEffectifsSansPresence: true,
                etablissement: etablissement,
                creneaux: creneaux
            )
        }
    }

    /// Une absence n'est pas une distance nulle : mesure finie et positive ou nulle seulement.
    public static func mesureGpsDisponible(_ valeur: Double?) -> Bool {
        guard let valeur else { return false }
        return valeur.isFinite && valeur >= 0
    }
}
