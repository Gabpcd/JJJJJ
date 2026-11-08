import Foundation

/// Profil lu par `fn_mon_profil_soignant_complet` (`supabase/schema/public.sql` l.44659-44684), décodé
/// en LISTE BLANCHE (blueprint lot 3, correction 7, §2.6) : aucune propriété pour `numero_secu`,
/// `numero_adeli`, `siret_liberal`, `code_ape`, `assujetti_tva`, `numero_tva`, `stripe_account_id`,
/// `iban_last4` (garde `Lot3PortsTests` et `ProfilCompletTests`, par `Mirror`). Type d'exercice et
/// attestation de cumul (L1222-5) : renvoi web, jamais portés (HARD STOP n°4, correction 8).
/// `adresse_lat` / `adresse_lng` sont décodées pour la localisation (T10), jamais affichées ni
/// journalisées. Déplacé de `Models/Lot3Results.swift` par T9, comme prévu par T1.
public struct ProfilComplet: Equatable, Sendable, Identifiable {
    public var id: String
    public var prenom: String
    public var nom: String
    public var email: String?
    public var telephone: String?
    /// `AAAA-MM-JJ` (colonne `date`).
    public var dateNaissance: String?
    public var profession: String?
    public var numeroRpps: String?
    public var rppsVerifie: Bool?
    public var rayonDeplacementKm: Int?
    public var villeRecherche: String?
    public var tauxHoraireMinimum: Double?
    /// Contrats acceptés, dérivés comme `getTypesContratSoignant` (`ContratCompatibilite`).
    public var typesContratAcceptes: [String]
    public var bio: String?
    public var anneesExperience: Int?
    public var avatarUrl: String?
    public var adresseLat: Double?
    public var adresseLng: Double?

    public init(id: String, prenom: String, nom: String, email: String? = nil, telephone: String? = nil,
                dateNaissance: String? = nil, profession: String? = nil, numeroRpps: String? = nil, rppsVerifie: Bool? = nil,
                rayonDeplacementKm: Int? = nil, villeRecherche: String? = nil, tauxHoraireMinimum: Double? = nil,
                typesContratAcceptes: [String] = [], bio: String? = nil, anneesExperience: Int? = nil, avatarUrl: String? = nil,
                adresseLat: Double? = nil, adresseLng: Double? = nil) {
        self.id = id; self.prenom = prenom; self.nom = nom; self.email = email; self.telephone = telephone
        self.dateNaissance = dateNaissance; self.profession = profession; self.numeroRpps = numeroRpps
        self.rppsVerifie = rppsVerifie; self.rayonDeplacementKm = rayonDeplacementKm; self.villeRecherche = villeRecherche
        self.tauxHoraireMinimum = tauxHoraireMinimum; self.typesContratAcceptes = typesContratAcceptes; self.bio = bio
        self.anneesExperience = anneesExperience; self.avatarUrl = avatarUrl
        self.adresseLat = adresseLat; self.adresseLng = adresseLng
    }

    /// Seules clés de la ligne lues par le décodeur. `type_exercice` et `type_contrat` ne servent qu'à
    /// dériver les contrats acceptés (repli de `getTypesContratSoignant`) : jamais conservés.
    public static let clesLues: Set<String> = [
        "id", "prenom", "nom", "email", "telephone", "date_naissance", "profession", "numero_rpps", "rpps_verifie",
        "rayon_deplacement_km", "ville_recherche", "taux_horaire_minimum", "types_contrat_acceptes", "type_exercice",
        "type_contrat", "bio", "annees_experience", "avatar_url", "adresse_lat", "adresse_lng",
    ]

    /// Clés renvoyées par la RPC et JAMAIS lues (correction 7).
    public static let clesSensibles: Set<String> = [
        "numero_secu", "numero_adeli", "siret_liberal", "code_ape", "assujetti_tva", "numero_tva",
        "stripe_account_id", "iban_last4",
    ]

    /// Décode la réponse de `fn_mon_profil_soignant_complet` pour `userId`. La garde du web
    /// (`validerProfilSoignant`, `ValidationProfil`) s'applique d'abord : `{error}`, identifiant d'un
    /// autre utilisateur, clé obligatoire absente ou champ d'un type incompatible lèvent
    /// `ValidationProfil.Erreur.profilInvalide`, jamais un profil vide. Valeurs d'affichage comme
    /// `ProfilSoignant.tsx` l.169-191 : prénom et nom absents → chaîne vide (`data.prenom || ''`).
    public static func depuis(_ donnees: ValeurJSON, userId: String) throws -> ProfilComplet {
        _ = try ValidationProfil.valider(donnees, userId: userId)
        guard case .objet(let ligne) = donnees else { throw ValidationProfil.Erreur.profilInvalide }
        func texte(_ cle: String) -> String? {
            if case .chaine(let valeur)? = ligne[cle] { return valeur }
            return nil
        }
        func nombre(_ cle: String) -> Double? {
            if case .nombre(let valeur)? = ligne[cle], valeur.isFinite { return valeur }
            return nil
        }
        func entier(_ cle: String) -> Int? {
            guard let valeur = nombre(cle), abs(valeur) < 1e9 else { return nil }
            return Int(valeur.rounded())
        }
        func booleen(_ cle: String) -> Bool? {
            if case .booleen(let valeur)? = ligne[cle] { return valeur }
            return nil
        }
        let profession = texte("profession")
        let contrats = ContratCompatibilite.typesContratSoignant(SoignantProfile(
            id: userId, profession: profession ?? "", typeContrat: texte("type_contrat"),
            typesContratAcceptes: texte("types_contrat_acceptes"), typeExercice: texte("type_exercice")))
        return ProfilComplet(
            id: userId, prenom: texte("prenom") ?? "", nom: texte("nom") ?? "", email: texte("email"),
            telephone: texte("telephone"), dateNaissance: texte("date_naissance"), profession: profession,
            numeroRpps: texte("numero_rpps"), rppsVerifie: booleen("rpps_verifie"),
            rayonDeplacementKm: entier("rayon_deplacement_km"), villeRecherche: texte("ville_recherche"),
            tauxHoraireMinimum: nombre("taux_horaire_minimum"), typesContratAcceptes: contrats, bio: texte("bio"),
            anneesExperience: entier("annees_experience"), avatarUrl: texte("avatar_url"),
            adresseLat: nombre("adresse_lat"), adresseLng: nombre("adresse_lng"))
    }

    /// Identité (prénom, nom, date de naissance, RPPS) figée après le contrôle RPPS
    /// (`SectionProfilPrincipal.tsx` l.795-840, `readOnly={rppsVerifie}`).
    public var identiteVerrouillee: Bool { rppsVerifie == true }

    /// Champ RPPS proposé : masqué pour `PROFESSIONS_SANS_RPPS` hors aide-soignant
    /// (`SectionProfilPrincipal.tsx` l.640-641, `sansRPPS`), comme le web.
    public var rppsPropose: Bool {
        guard let profession, !profession.isEmpty else { return false }
        return !ProfessionsRpps.estSansRpps(profession) || profession == "AS"
    }

    /// RPPS optionnel pour l'aide-soignant seulement (`rppsOptionnel = profession === 'AS'`, l.640).
    public var rppsOptionnel: Bool { profession == "AS" }
}
