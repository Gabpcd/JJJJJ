import Foundation
import JoleneCore

/// Géocodage inverse best-effort (lot 3, T10, D15) : `reverseGeocode` du web (`src/lib/geocodage.ts` l.16-34) sur l'API
/// Adresse de l'État. Une seule requête GET, en-tête `Accept: application/json` seul : ni jeton, ni clé, ni identifiant
/// d'utilisateur, ni cookie (session éphémère par défaut). Statut non 2xx, réponse illisible, délai ou réseau → nil
/// (« introuvable / réseau KO »), jamais une erreur : l'écran affiche alors « Position récupérée. ». Les coordonnées
/// ne sont jamais journalisées.
public struct ApiAdresseGeocodage: GeocodagePort {
    private let session: URLSession

    public init(session: URLSession = ApiAdresseGeocodage.sessionParDefaut) {
        self.session = session
    }

    /// Session éphémère : aucun cookie ni cache disque partagé avec le reste de l'app.
    public static var sessionParDefaut: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }

    public func adresse(lat: Double, lng: Double) async throws -> AdresseGeocodee? {
        guard let url = GeocodageInverse.url(lat: lat, lng: lng) else { return nil }
        var requete = URLRequest(url: url)
        requete.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (donnees, reponse) = try? await session.data(for: requete),
              let http = reponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return GeocodageInverse.adresse(depuis: donnees)
    }
}
