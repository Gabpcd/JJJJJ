import Foundation

/// Géocodage inverse du profil (lot 3, T10, D15) : port de `reverseGeocode` (`src/lib/geocodage.ts` l.16-34), API
/// Adresse de l'État (`api-adresse.data.gouv.fr`, sans clé ni identifiant). Règles pures (adresse de la requête,
/// lecture de la réponse) ; le transport est `ApiAdresseGeocodage` (JoleneSupabase), la démo `DemoGeocodage`.
/// Service tiers hors Supabase : seules les coordonnées partent (comme le web), jamais un identifiant, un jeton ni
/// un en-tête d'authentification ; disponibilité constatée le 09/11/2026 (réponse 200 au format ci-dessous).
public enum GeocodageInverse {
    public static let hote = "api-adresse.data.gouv.fr"

    /// `https://api-adresse.data.gouv.fr/reverse/?lon=${encodeURIComponent(lng)}&lat=${encodeURIComponent(lat)}`
    /// (l.18) : nombres rendus comme `String(number)` en JavaScript, longitude d'abord.
    public static func url(lat: Double, lng: Double) -> URL? {
        guard lat.isFinite, lng.isFinite else { return nil }
        var composants = URLComponents()
        composants.scheme = "https"
        composants.host = hote
        composants.path = "/reverse/"
        composants.queryItems = [
            URLQueryItem(name: "lon", value: MissionPresentation.nombreJavaScript(lng)),
            URLQueryItem(name: "lat", value: MissionPresentation.nombreJavaScript(lat)),
        ]
        return composants.url
    }

    /// `data?.features?.[0]` puis `properties` : `label || ''`, `city || null`, `postcode || null` (l.22-30). Pas de
    /// première entité → nil (« introuvable »). Le libellé est affiché tel quel (« Place Bellecour 69002 Lyon… »).
    public static func adresse(depuis donnees: Data) -> AdresseGeocodee? {
        guard let racine = (try? JSONSerialization.jsonObject(with: donnees)) as? [String: Any],
              let entites = racine["features"] as? [Any], let premiere = entites.first as? [String: Any] else { return nil }
        let proprietes = premiere["properties"] as? [String: Any] ?? [:]
        func texte(_ cle: String) -> String? {
            guard let valeur = proprietes[cle] as? String, !valeur.isEmpty else { return nil }
            return valeur
        }
        return AdresseGeocodee(libelle: texte("label") ?? "", ville: texte("city"), codePostal: texte("postcode"))
    }
}
