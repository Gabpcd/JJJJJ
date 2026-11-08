import Foundation

/// Champs modifiables par `fn_modifier_mon_profil` (`public.sql` l.43891-44018). nil = inchangé
/// (`COALESCE` côté serveur, l.43933-43985) : le natif n'envoie jamais de paramètre pour un champ non
/// modifié, et n'offre pas « effacer » (un champ vidé reste à sa valeur relue, §2.4). Déplacé de
/// `Models/Lot3Results.swift` par T9, comme prévu par T1.
///
/// Paramètres envoyés : ceux de T9 (`LOT3_PLAN.md` §3 T9) et `p_avatar_url` (T10). Jamais
/// `p_type_exercice`, `p_attestation_cumul_activite`, `p_est_cumul_activite`,
/// `p_est_salarie_etablissement` (L1222-5, HARD STOP n°4, correction 8), `p_consentement_gps` (lot 2),
/// `p_disponible_urgence`, `p_urgence_rayon_km`, `p_ville_urgence` (lot 4), `p_specialites`,
/// `p_profession`, `p_numero_adeli` (fiche `fn_modifier_mon_profil` de `CONTRATS_RPC_SOIGNANT.md`).
public struct ModificationProfil: Equatable, Sendable {
    public var prenom: String?
    public var nom: String?
    public var telephone: String?
    /// `AAAA-MM-JJ`.
    public var dateNaissance: String?
    public var numeroRpps: String?
    public var rayonDeplacementKm: Int?
    public var villeRecherche: String?
    public var tauxHoraireMinimum: Double?
    public var typesContratAcceptes: [String]?
    public var bio: String?
    public var anneesExperience: Int?
    public var avatarUrl: String?

    public init(prenom: String? = nil, nom: String? = nil, telephone: String? = nil, dateNaissance: String? = nil,
                numeroRpps: String? = nil, rayonDeplacementKm: Int? = nil, villeRecherche: String? = nil,
                tauxHoraireMinimum: Double? = nil, typesContratAcceptes: [String]? = nil, bio: String? = nil,
                anneesExperience: Int? = nil, avatarUrl: String? = nil) {
        self.prenom = prenom; self.nom = nom; self.telephone = telephone; self.dateNaissance = dateNaissance
        self.numeroRpps = numeroRpps; self.rayonDeplacementKm = rayonDeplacementKm; self.villeRecherche = villeRecherche
        self.tauxHoraireMinimum = tauxHoraireMinimum; self.typesContratAcceptes = typesContratAcceptes; self.bio = bio
        self.anneesExperience = anneesExperience; self.avatarUrl = avatarUrl
    }

    /// Aucun champ à transmettre : l'écran n'appelle pas la RPC.
    public var estVide: Bool { self == ModificationProfil() }

    /// Valeur d'un paramètre de `fn_modifier_mon_profil`, indépendante du SDK (la gateway Supabase la
    /// traduit en JSON, le monde démo l'applique à sa ligne).
    public enum Parametre: Equatable, Sendable {
        case texte(String)
        case entier(Int)
        case reel(Double)
        case textes([String])
    }

    /// Paramètres que le natif peut envoyer, dans l'ordre de la signature SQL.
    public static let parametresAutorises: [String] = [
        "p_prenom", "p_nom", "p_telephone", "p_date_naissance", "p_rayon_deplacement_km", "p_numero_rpps",
        "p_avatar_url", "p_types_contrat", "p_bio", "p_annees_experience", "p_taux_horaire_minimum",
        "p_ville_recherche",
    ]

    /// Paramètres de la signature que le natif n'envoie jamais (garde des tests).
    public static let parametresInterdits: [String] = [
        "p_adresse_rue", "p_adresse_ville", "p_adresse_code_postal", "p_adresse_lat", "p_adresse_lng",
        "p_numero_adeli", "p_specialites", "p_type_exercice", "p_ville_urgence", "p_disponible_urgence",
        "p_urgence_rayon_km", "p_attestation_cumul_activite", "p_est_cumul_activite", "p_est_salarie_etablissement",
        "p_consentement_gps", "p_types_contrat_acceptes", "p_profession",
    ]

    /// Paramètres nommés à envoyer : seuls les champs non nil.
    public var parametres: [String: Parametre] {
        var sortie: [String: Parametre] = [:]
        if let prenom { sortie["p_prenom"] = .texte(prenom) }
        if let nom { sortie["p_nom"] = .texte(nom) }
        if let telephone { sortie["p_telephone"] = .texte(telephone) }
        if let dateNaissance { sortie["p_date_naissance"] = .texte(dateNaissance) }
        if let rayonDeplacementKm { sortie["p_rayon_deplacement_km"] = .entier(rayonDeplacementKm) }
        if let numeroRpps { sortie["p_numero_rpps"] = .texte(numeroRpps) }
        if let avatarUrl { sortie["p_avatar_url"] = .texte(avatarUrl) }
        if let typesContratAcceptes { sortie["p_types_contrat"] = .textes(typesContratAcceptes) }
        if let bio { sortie["p_bio"] = .texte(bio) }
        if let anneesExperience { sortie["p_annees_experience"] = .entier(anneesExperience) }
        if let tauxHoraireMinimum { sortie["p_taux_horaire_minimum"] = .reel(tauxHoraireMinimum) }
        if let villeRecherche { sortie["p_ville_recherche"] = .texte(villeRecherche) }
        return sortie
    }

    /// Différence entre le formulaire relu (`initial`) et la saisie : seuls les champs que l'utilisateur
    /// a changés partent (aucune valeur dérivée ni défaut écrit en silence, principe « État dérivé »).
    /// - prénom et nom : un champ vidé est envoyé vide, pour que le serveur le refuse avec son message
    ///   (`{error:'Le prénom ne peut pas être vide'}`, l.43906) au lieu d'un faux succès ;
    /// - téléphone, ville, RPPS, bio : un champ vidé n'est pas envoyé (`COALESCE`, rien n'est effacé) ;
    /// - identité figée après le contrôle RPPS : prénom, nom, date de naissance et RPPS jamais envoyés ;
    /// - RPPS envoyé seulement si le champ est proposé pour la profession et contient des chiffres.
    public static func depuis(initial: FormulaireProfil, saisi: FormulaireProfil, profil: ProfilComplet) -> ModificationProfil {
        var modification = ModificationProfil()
        let identiteLibre = !profil.identiteVerrouillee
        if identiteLibre {
            let prenom = saisi.prenom.nettoye
            if prenom != initial.prenom.nettoye { modification.prenom = prenom }
            let nom = saisi.nom.nettoye
            if nom != initial.nom.nettoye { modification.nom = nom }
            if saisi.dateNaissance != initial.dateNaissance, let date = saisi.dateNaissance { modification.dateNaissance = date }
            if profil.rppsPropose {
                let rpps = FormulaireProfil.filtrerRpps(saisi.numeroRpps)
                if !rpps.isEmpty, rpps != FormulaireProfil.filtrerRpps(initial.numeroRpps) { modification.numeroRpps = rpps }
            }
        }
        modification.telephone = changeNonVide(saisi.telephone, initial.telephone)
        modification.villeRecherche = changeNonVide(saisi.villeRecherche, initial.villeRecherche)
        if saisi.rayonDeplacementKm != initial.rayonDeplacementKm {
            modification.rayonDeplacementKm = FormulaireProfil.borner(saisi.rayonDeplacementKm, FormulaireProfil.bornesRayon)
        }
        if let taux = saisi.tauxHoraireMinimum, taux > 0, taux != initial.tauxHoraireMinimum {
            modification.tauxHoraireMinimum = taux
        }
        if saisi.typesContrat != initial.typesContrat, !saisi.typesContrat.isEmpty {
            modification.typesContratAcceptes = saisi.typesContrat
        }
        if saisi.bio != initial.bio, !saisi.bio.nettoye.isEmpty { modification.bio = FormulaireProfil.limiterBio(saisi.bio) }
        if saisi.anneesExperience != initial.anneesExperience {
            modification.anneesExperience = FormulaireProfil.borner(saisi.anneesExperience, FormulaireProfil.bornesExperience)
        }
        return modification
    }

    private static func changeNonVide(_ saisi: String, _ initial: String) -> String? {
        let valeur = saisi.nettoye
        return valeur.isEmpty || valeur == initial.nettoye ? nil : valeur
    }
}

/// Saisie de l'écran d'édition, initialisée depuis le profil relu (valeurs d'affichage du web :
/// `ProfilSoignant.tsx` l.169-191 — rayon 30 km et 0 année d'expérience par défaut).
public struct FormulaireProfil: Equatable, Sendable {
    public var prenom: String
    public var nom: String
    public var telephone: String
    /// `AAAA-MM-JJ` ; nil = non renseignée.
    public var dateNaissance: String?
    public var numeroRpps: String
    public var rayonDeplacementKm: Int
    public var villeRecherche: String
    /// nil ou ≤ 0 : « Non défini » (`tauxHoraireMinimum ? … : 'Non défini'`).
    public var tauxHoraireMinimum: Double?
    public var typesContrat: [String]
    public var bio: String
    public var anneesExperience: Int

    /// `setRayon(data.rayon_deplacement_km ?? 30)`.
    public static let rayonParDefaut = 30
    /// Curseurs et champs du web (`SectionPreferences.tsx` l.88-90 et l.110-111, `SectionBio.tsx` l.64-71).
    public static let bornesRayon = 5...100
    public static let bornesTaux = 10...100
    public static let bornesExperience = 0...50
    public static let longueurBio = 500
    public static let longueurRpps = 11

    public init(profil: ProfilComplet) {
        prenom = profil.prenom
        nom = profil.nom
        telephone = profil.telephone ?? ""
        dateNaissance = profil.dateNaissance.flatMap { $0.isEmpty ? nil : $0 }
        numeroRpps = profil.numeroRpps ?? ""
        rayonDeplacementKm = profil.rayonDeplacementKm ?? Self.rayonParDefaut
        villeRecherche = profil.villeRecherche ?? ""
        tauxHoraireMinimum = profil.tauxHoraireMinimum
        typesContrat = profil.typesContratAcceptes
        bio = profil.bio ?? ""
        anneesExperience = profil.anneesExperience ?? 0
    }

    /// Taux défini (`tauxHoraireMinimum ?` du web : 0 et nil valent « Non défini »).
    public var tauxDefini: Bool { (tauxHoraireMinimum ?? 0) > 0 }

    /// `e.target.value.replace(/\D/g, '').slice(0, 11)` (`SectionProfilPrincipal.tsx` l.248).
    public static func filtrerRpps(_ saisie: String) -> String {
        String(saisie.unicodeScalars.filter { ("0"..."9").contains($0) }.map(Character.init).prefix(longueurRpps))
    }

    /// `e.target.value.slice(0, 500)` (`SectionBio.tsx` l.56).
    public static func limiterBio(_ saisie: String) -> String { String(saisie.prefix(longueurBio)) }

    static func borner(_ valeur: Int, _ bornes: ClosedRange<Int>) -> Int {
        min(bornes.upperBound, max(bornes.lowerBound, valeur))
    }
}

private extension String {
    var nettoye: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
