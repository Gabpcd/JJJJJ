import Foundation

/// Port de `src/lib/geo.ts` : distance Haversine arrondie au dixième de kilomètre.
public enum Geo {
    /// Rayon terrestre moyen utilisé par le web (km).
    public static let rayonTerreKm: Double = 6371

    /// Retourne `nil` dès qu'une coordonnée manque, comme `calculerDistanceKm`.
    public static func distanceKm(lat1: Double?, lng1: Double?, lat2: Double?, lng2: Double?) -> Double? {
        guard let lat1, let lng1, let lat2, let lng2 else { return nil }
        let dLat = (lat2 - lat1) * Double.pi / 180
        let dLng = (lng2 - lng1) * Double.pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * Double.pi / 180) * cos(lat2 * Double.pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        // `Math.round(x * 10) / 10` : arrondi au plus proche, .5 vers le haut.
        return (rayonTerreKm * c * 10).rounded(.toNearestOrAwayFromZero) / 10
    }

    /// Port de `formaterDistance`.
    public static func formaterDistance(_ km: Double?) -> String {
        guard let km else { return "Distance inconnue" }
        if km < 1 { return "\(Int((km * 1000).rounded(.toNearestOrAwayFromZero)))m" }
        return "\(MissionPresentation.nombreJavaScript(km)) km"
    }
}
