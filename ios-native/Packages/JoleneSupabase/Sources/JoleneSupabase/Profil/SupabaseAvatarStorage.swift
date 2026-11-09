import Foundation
import JoleneCore
import Supabase

/// Stockage brut de l'avatar sur Supabase Storage (lot 3, T10), comme `AvatarUpload.tsx` l.136-148 : bucket privé
/// `jolene-documents`, chemin `<uid>/avatar-<ms>.jpg` (politique `pol_storage_jolene_insert` :
/// `fn_peut_gerer_objet_jolene`, premier segment = `auth.uid()`), `contentType image/jpeg`, `upsert: false` (aucune
/// politique UPDATE/DELETE : un objet n'est jamais remplacé), URL signée de 5 ans (`createSignedURL`). L'enchaînement,
/// le reçu durable et la relecture de `avatar_url` sont ceux d'`EnvoiAvatar` (JoleneCore).
///
/// Classement des erreurs du dépôt : réponse 4xx (`StorageError.statusCode` ou statut HTTP : politique 403, MIME ou
/// taille 400/413, objet existant 409) → `RefusStockageAvatar` (refus certain, rien n'est déposé) ; tout le reste
/// (réseau, délai, 5xx, corps illisible) → `JoleneError` par `SupabaseErrorMapping` (issue inconnue). Aucun message
/// du serveur n'est affiché ni journalisé ; l'URL signée (jeton) n'est jamais journalisée.
public struct SupabaseAvatarStorage: StockageAvatarPort {
    private let client: SupabaseClient
    private let session: URLSession

    /// `session` : lecture de l'image à l'URL signée (tests : transport injecté).
    public init(client: SupabaseClient, session: URLSession = SupabaseAvatarStorage.sessionParDefaut) {
        self.client = client
        self.session = session
    }

    /// Session de lecture de l'avatar (revue B8 de T10, m11) : éphémère, SANS cache HTTP (ni disque ni mémoire), sans
    /// cookie ni identifiant mémorisé. `URLSession.shared` gardait dans le cache disque partagé l'URL signée (jeton
    /// valable 5 ans) et les octets de l'image. Une seule session pour l'app.
    public static let sessionParDefaut: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }()

    public func deposer(chemin: String, jpeg: Data, context: MissionReadContext) async throws {
        try MissionQuery.validate(context: context)
        do {
            try await client.storage.from(AvatarProfil.bucket)
                .upload(chemin, data: jpeg, options: FileOptions(contentType: AvatarProfil.contentType, upsert: false))
        } catch {
            if let statut = Self.statutRefus(error) { throw RefusStockageAvatar(statut: statut) }
            throw SupabaseErrorMapping.map(error, fallback: AvatarProfil.Textes.echecEnvoi)
        }
    }

    public func urlSignee(chemin: String, dureeSecondes: Int, context: MissionReadContext) async throws -> URL {
        try MissionQuery.validate(context: context)
        do {
            return try await client.storage.from(AvatarProfil.bucket).createSignedURL(path: chemin, expiresIn: dureeSecondes)
        } catch {
            throw SupabaseErrorMapping.map(error, fallback: AvatarProfil.Textes.echecEnvoi)
        }
    }

    /// GET de l'URL signée relue (lecture publique par jeton, aucun en-tête d'authentification ajouté). Réponse non 2xx,
    /// vide ou erreur → nil.
    public func image(url: URL) async -> Data? {
        guard url.scheme == "https" else { return nil }
        var requete = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        requete.timeoutInterval = 15
        guard let (donnees, reponse) = try? await session.data(for: requete),
              let http = reponse as? HTTPURLResponse, (200..<300).contains(http.statusCode), !donnees.isEmpty else { return nil }
        return donnees
    }

    /// Statut 4xx d'un refus du stockage, nil pour toute issue inconnue.
    static func statutRefus(_ error: Error) -> Int? {
        let statut: Int?
        if let stockage = error as? StorageError {
            statut = stockage.statusCode.flatMap { Int($0) }
        } else if let http = error as? HTTPError {
            statut = http.response.statusCode
        } else {
            statut = nil
        }
        guard let statut, (400..<500).contains(statut) else { return nil }
        return statut
    }
}
