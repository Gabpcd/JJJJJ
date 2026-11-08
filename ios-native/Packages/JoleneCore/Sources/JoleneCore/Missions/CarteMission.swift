import Foundation

/// Repère de la carte en lecture seule du détail mission (lot 1, T4a). Les coordonnées sont
/// celles de l'établissement renvoyées par `fn_etablissements_safe` : jamais géocodées ni
/// recalculées côté app. Aucune position du soignant n'est montrée (pas de demande de
/// localisation).
public struct PointCarte: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    /// Nom de l'établissement, ou le repli d'affichage « Établissement » du détail.
    public var titre: String
    /// « Code postal Ville », `nil` si les deux manquent.
    public var adresse: String?

    public init(latitude: Double, longitude: Double, titre: String, adresse: String?) {
        self.latitude = latitude; self.longitude = longitude; self.titre = titre; self.adresse = adresse
    }

    /// Légende visible sous la carte.
    public var legende: String { [titre, adresse].compactMap { $0 }.joined(separator: " · ") }

    public var accessibilityLabel: String {
        "Carte de la mission : \([titre, adresse].compactMap { $0 }.joined(separator: ", "))"
    }
}

public enum CarteMission {
    /// Étendue affichée autour du repère (mètres, nord-sud comme est-ouest).
    public static let etendueMetres: Double = 1_500
    static let titreParDefaut = "Établissement"

    /// Identité de la vue carte : les seules coordonnées. `Map(initialPosition:)` (iOS 17+) n'est lu
    /// qu'au premier rendu ; une carte non interactive dont l'établissement bouge à la relecture
    /// doit être recréée pour recentrer sa caméra, pas pour un changement de nom ou d'adresse.
    public static func cleIdentite(_ point: PointCarte) -> String {
        "\(point.latitude),\(point.longitude)"
    }

    /// Repère de la mission, ou `nil` sans coordonnées exploitables (absentes, non finies ou hors
    /// plage). Parité : la carte du web visible de tous, `CarteMissionsExploration.tsx` l.54-56,
    /// n'écarte que `lat == null || lng == null`. **Écart natif assumé** : une coordonnée exactement
    /// nulle est traitée comme absente (le point 0, 0 du golfe de Guinée signale un géocodage
    /// manquant, jamais un établissement en France) ; le web, lui, y poserait un repère.
    /// (`DetailMissionSoignant.tsx` l.1111, `adresse_lat && adresse_lng`, ne gouverne que les liens
    /// Plans / Maps / Waze du soignant assigné, pas une carte.)
    public static func point(pour mission: Mission) -> PointCarte? {
        guard let etablissement = mission.etablissement,
              let latitude = etablissement.adresseLat, let longitude = etablissement.adresseLng,
              latitude.isFinite, longitude.isFinite, latitude != 0, longitude != 0,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        let adresse = [etablissement.adresseCodePostal, etablissement.adresseVille]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return PointCarte(latitude: latitude, longitude: longitude,
                          titre: etablissement.nom.isEmpty ? titreParDefaut : etablissement.nom,
                          adresse: adresse.isEmpty ? nil : adresse)
    }
}
