import Foundation

// Avatar et géocodage du monde démo (lot 3, T10 ; blueprint §2.7 : « image démo en ressource, `DemoGeocodage`
// (« Lyon »), upload en mémoire »). Aucun réseau, aucune feuille système. Écart assumé : le reçu démo est en mémoire
// vive (`RecusAvatarEnMemoire`, comme les reçus démo du lot 2), pas dans le trousseau, pour que le mode démo reste
// sans état entre deux lancements (le simulateur non signé de la CI n'a d'ailleurs pas d'accès fiable au trousseau).

extension DemoFixtures {
    public static let sousDossierMedia = "Resources/media-demo"

    /// Photo de démonstration (`Resources/media-demo/avatar-demo.heic`, image de synthèse 512 × 512, sans métadonnée) :
    /// source de la photothèque et de l'appareil photo en démo. HEIC à dessein : la conversion JPEG est exercée.
    public static func avatarDemo() throws -> Data {
        guard let url = Bundle.module.url(forResource: "avatar-demo", withExtension: "heic", subdirectory: sousDossierMedia)
            ?? Bundle.module.url(forResource: "avatar-demo", withExtension: "heic") else {
            throw JoleneError(.contract, "Ressource démo introuvable : avatar-demo.heic.")
        }
        return try Data(contentsOf: url)
    }
}

/// Valeurs de l'argument DEBUG `-JOLENE_DEMO_AVATAR` (lu par `AppContainer`, démo seulement).
public enum ScenarioAvatarDemo: String, CaseIterable, Sendable {
    /// Le stockage refuse le dépôt (réponse 403 simulée) : reçu `refused`, aucun `p_avatar_url`.
    case refus

    public static let argument = "-JOLENE_DEMO_AVATAR"

    public init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: Self.argument), arguments.indices.contains(index + 1),
              let scenario = ScenarioAvatarDemo(rawValue: arguments[index + 1]) else { return nil }
        self = scenario
    }
}

/// Stockage démo : objets en mémoire vive, URL signée fictive sur un hôte réservé (`demo.invalid`, jamais résolu) au
/// format Supabase (`/storage/v1/object/sign/<bucket>/<chemin>`), lue par `image(url:)` sans réseau.
public actor DemoStockageAvatar: StockageAvatarPort {
    public static let hote = "demo.invalid"

    private let scenario: ScenarioAvatarDemo?
    private var objets: [String: Data] = [:]
    /// Dépôts reçus (tests).
    public private(set) var depots: [String] = []

    public init(scenario: ScenarioAvatarDemo? = nil) {
        self.scenario = scenario
    }

    public func deposer(chemin: String, jpeg: Data, context: MissionReadContext) throws {
        try verifier(context)
        depots.append(chemin)
        if scenario == .refus { throw RefusStockageAvatar(statut: 403) }
        guard objets[chemin] == nil else { throw RefusStockageAvatar(statut: 409) } // `upsert: false`
        objets[chemin] = jpeg
    }

    public func urlSignee(chemin: String, dureeSecondes: Int, context: MissionReadContext) throws -> URL {
        try verifier(context)
        var composants = URLComponents()
        composants.scheme = "https"
        composants.host = Self.hote
        composants.path = "/storage/v1/object/sign/\(AvatarProfil.bucket)/\(chemin)"
        composants.queryItems = [URLQueryItem(name: "token", value: "demo")]
        guard objets[chemin] != nil, let url = composants.url else {
            throw JoleneError(.unknown, AvatarProfil.Textes.echecEnvoi)
        }
        return url
    }

    public func image(url: URL) -> Data? {
        guard url.host == Self.hote, let plage = url.path.range(of: "/\(AvatarProfil.bucket)/") else { return nil }
        return objets[String(url.path[plage.upperBound...])]
    }

    private func verifier(_ context: MissionReadContext) throws {
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }
}

/// Géocodage démo : toute position rend l'adresse fictive de la place Bellecour (Lyon), au format de l'API Adresse
/// (`label`, `city`, `postcode`). Aucun réseau.
public struct DemoGeocodage: GeocodagePort {
    public static let adresseDemo = AdresseGeocodee(libelle: "Place Bellecour 69002 Lyon", ville: "Lyon", codePostal: "69002")

    private let enEchec: Bool

    /// `enEchec` : aucune adresse (« Position récupérée. »), variante DEBUG `-JOLENE_DEMO_GEOCODAGE echec`.
    public init(enEchec: Bool = false) {
        self.enEchec = enEchec
    }

    public static let argumentEchec = "-JOLENE_DEMO_GEOCODAGE"

    public static func enEchec(arguments: [String]) -> Bool {
        guard let index = arguments.firstIndex(of: argumentEchec), arguments.indices.contains(index + 1) else { return false }
        return arguments[index + 1] == "echec"
    }

    public func adresse(lat: Double, lng: Double) async throws -> AdresseGeocodee? {
        enEchec ? nil : Self.adresseDemo
    }
}

extension DemoWorld {
    /// Avatar du monde démo, sur le port du profil donné : `avatar_url` écrite et relue par la même ligne démo. Horloge
    /// système pour le seul nom de l’objet (`avatar-<ms>.jpg`) : deux photos d’une même session ne portent jamais le même
    /// chemin (`upsert: false`), l’horloge fixée du monde démo reste celle des missions.
    public static func avatar(profil: ProfilPort, scenario: ScenarioAvatarDemo? = nil) -> AvatarStoragePort {
        EnvoiAvatar(stockage: DemoStockageAvatar(scenario: scenario), profil: profil, recus: RecusAvatarEnMemoire(),
                    horloge: SystemClock(), registre: RegistreEnvoisAvatar())
    }
}
