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

    public func profil(context: MissionReadContext) async throws -> ProfilComplet {
        try verifier(context)
        return try Self.relire(try await store.lire(), userId: context.userId)
    }

    public func modifier(_ champs: ModificationProfil, context: MissionReadContext) async throws -> ProfilComplet {
        try verifier(context)
        var ligne = try await store.lire()
        let parametres = champs.parametres
        if case .texte(let prenom)? = parametres["p_prenom"], prenom.estVideSQL {
            throw JoleneError(.unknown, "Le prénom ne peut pas être vide")
        }
        if case .texte(let nom)? = parametres["p_nom"], nom.estVideSQL {
            throw JoleneError(.unknown, "Le nom ne peut pas être vide")
        }
        let rppsVerifie = ligne["rpps_verifie"] == .booleen(true)
        for (nom, valeur) in parametres {
            guard let colonne = Self.colonnes[nom] else { continue }
            if nom == "p_numero_rpps", rppsVerifie { continue }
            switch valeur {
            case .texte(let texte):
                let trimmed = (nom == "p_prenom" || nom == "p_nom") ? texte.trimmingCharacters(in: .whitespaces) : texte
                ligne[colonne] = .chaine(trimmed)
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

private extension String {
    /// `NULLIF(btrim(x), '') IS NULL` : vide ou seulement des espaces.
    var estVideSQL: Bool { trimmingCharacters(in: .whitespaces).isEmpty }
}
