import Foundation

extension DemoFixtures {
    /// `demo-profil-complet.json` (exporté par `scripts/mobile/export-demo-fixtures.mjs`) : réponse de
    /// `fn_mon_profil_soignant_complet` du profil fictif, réduite à la liste blanche (aucune clé de
    /// `ProfilComplet.clesSensibles`, garde `DemoProfilGatewayTests`).
    public struct ProfilCompletFile: Decodable, Sendable {
        public var fixedNow: String
        public var profil: ValeurJSON
        enum CodingKeys: String, CodingKey { case fixedNow = "fixed_now", profil }
    }

    public static func loadProfilComplet() throws -> ProfilCompletFile { try load("demo-profil-complet") }
}

/// Ligne `soignants` du monde démo, en mémoire pour la durée du jeu de ports (perdue au relancement).
actor DemoProfilStore {
    private var ligne: [String: ValeurJSON]?
    private let charger: @Sendable () throws -> ValeurJSON

    init(charger: @escaping @Sendable () throws -> ValeurJSON) { self.charger = charger }

    func lire() throws -> [String: ValeurJSON] {
        if let ligne { return ligne }
        guard case .objet(let initiale) = try charger() else {
            throw JoleneError(.contract, "Fixture démo illisible : demo-profil-complet.json.")
        }
        ligne = initiale
        return initiale
    }

    func remplacer(_ nouvelle: [String: ValeurJSON]) { ligne = nouvelle }
}

/// `ProfilPort` du monde démo, sans réseau. Applique à sa ligne les règles de `fn_modifier_mon_profil`
/// (`public.sql` l.43904-43985) — refus verbatim d'un prénom ou d'un nom vide, `COALESCE` (un paramètre
/// absent ne change rien), RPPS figé après vérification, contrats écrits `array_to_string(…, ',')` —
/// puis relit par le même décodeur en liste blanche que le monde Supabase : aucun succès fabriqué.
/// Refuse tout contexte qui n'est pas celui du profil fictif (`.demoOnly`).
public struct DemoProfilGateway: ProfilPort {
    private let store: DemoProfilStore

    public init(fixture: @escaping @Sendable () throws -> ValeurJSON = { try DemoFixtures.loadProfilComplet().profil }) {
        store = DemoProfilStore(charger: fixture)
    }

    /// Profil démo dans une variante de recette (`VarianteProfilDemo`) : même fixture, une seule clé changée.
    public init(variante: VarianteProfilDemo) {
        self.init(fixture: { variante.appliquer(try DemoFixtures.loadProfilComplet().profil) })
    }

    public func profil(context: MissionReadContext) async throws -> ProfilComplet {
        try verifier(context)
        return try Self.relire(try await store.lire(), userId: context.userId)
    }

    public func modifier(_ champs: ModificationProfil, context: MissionReadContext) async throws -> ProfilComplet {
        try verifier(context)
        var ligne = try await store.lire()
        let parametres = champs.parametres
        // Refus certains (`{error}` en HTTP 200, l.43906-43909), même type que la gateway Supabase.
        if case .texte(let prenom)? = parametres["p_prenom"], prenom.estVideSQL {
            throw RefusEnregistrementProfil("Le prénom ne peut pas être vide")
        }
        if case .texte(let nom)? = parametres["p_nom"], nom.estVideSQL {
            throw RefusEnregistrementProfil("Le nom ne peut pas être vide")
        }
        let rppsVerifie = ligne["rpps_verifie"] == .booleen(true)
        for (nom, valeur) in parametres {
            guard let colonne = Self.colonnes[nom] else { continue }
            if nom == "p_numero_rpps", rppsVerifie { continue }
            switch valeur {
            case .texte(let texte):
                ligne[colonne] = .chaine((nom == "p_prenom" || nom == "p_nom") ? texte.btrimSQL : texte)
            case .entier(let entier): ligne[colonne] = .nombre(Double(entier))
            case .reel(let reel): ligne[colonne] = .nombre(reel)
            case .textes(let textes): ligne[colonne] = .chaine(textes.joined(separator: ","))
            }
        }
        await store.remplacer(ligne)
        return try Self.relire(try await store.lire(), userId: context.userId)
    }

    /// Paramètre → colonne (`UPDATE public.soignants SET …`, l.43933-43985).
    static let colonnes: [String: String] = [
        "p_prenom": "prenom", "p_nom": "nom", "p_telephone": "telephone", "p_date_naissance": "date_naissance",
        "p_rayon_deplacement_km": "rayon_deplacement_km", "p_numero_rpps": "numero_rpps", "p_avatar_url": "avatar_url",
        "p_types_contrat": "types_contrat_acceptes", "p_bio": "bio", "p_annees_experience": "annees_experience",
        "p_taux_horaire_minimum": "taux_horaire_minimum", "p_ville_recherche": "ville_recherche",
        "p_adresse_lat": "adresse_lat", "p_adresse_lng": "adresse_lng", // T10
    ]

    private func verifier(_ context: MissionReadContext) throws {
        try MissionBusiness.validateContext(context)
        guard context.userId == DemoWorld.context.userId else {
            throw JoleneError(.demoOnly, DemoWorld.messageDemoSeulement)
        }
    }

    private static func relire(_ ligne: [String: ValeurJSON], userId: String) throws -> ProfilComplet {
        do {
            return try ProfilComplet.depuis(.objet(ligne), userId: userId)
        } catch {
            throw JoleneError(.contract, "Fixture démo illisible : demo-profil-complet.json.")
        }
    }
}

/// Variantes DEBUG du profil démo, pour la recette niveau 2 des états que la fixture ne montre pas. Lues par
/// `AppContainer` dans la variable d'environnement du processus `JOLENE_DEMO_PROFIL` (build DEBUG seulement,
/// comme `JOLENE_FORCE_ACCUEIL_ECHEC`) ; jamais en Release.
/// - `identite-verrouillee` : `rpps_verifie = true` (identité figée après le contrôle RPPS : prénom, nom, date
///   de naissance et RPPS en lecture seule) ; aucun numéro RPPS fictif n'est inventé ;
/// - `sans-date-naissance` : `date_naissance = null` (bouton « Date de naissance », aucune date écrite sans choix).
public enum VarianteProfilDemo: String, Sendable, CaseIterable {
    case identiteVerrouillee = "identite-verrouillee"
    case sansDateNaissance = "sans-date-naissance"

    public static let variableEnvironnement = "JOLENE_DEMO_PROFIL"

    /// Ligne de la fixture modifiée par la variante (une ligne non objet est rendue telle quelle : le décodeur
    /// la refusera comme la fixture d'origine).
    public func appliquer(_ ligne: ValeurJSON) -> ValeurJSON {
        guard case .objet(var objet) = ligne else { return ligne }
        switch self {
        case .identiteVerrouillee: objet["rpps_verifie"] = .booleen(true)
        case .sansDateNaissance: objet["date_naissance"] = .null
        }
        return .objet(objet)
    }
}

private extension String {
    /// `btrim(x)` sans second argument : retire les seules espaces U+0020 aux deux bords (ni tabulation, ni
    /// espace insécable).
    var btrimSQL: String { trimmingCharacters(in: CharacterSet(charactersIn: " ")) }

    /// `NULLIF(btrim(x), '') IS NULL` : vide ou seulement des espaces.
    var estVideSQL: Bool { btrimSQL.isEmpty }
}
