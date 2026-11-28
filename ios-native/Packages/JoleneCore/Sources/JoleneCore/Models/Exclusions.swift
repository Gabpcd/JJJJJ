import Foundation

/// Ligne PostgREST `exclusions` envoyée par le soignant (`exclu_par = auth.uid()`, RLS `pol_exclusion_select`) :
/// colonnes lues par le web (`ExclusionsSoignant.tsx` l.43-47).
public struct LigneExclusionEnvoyee: Decodable, Equatable, Sendable {
    public var id: String
    public var excluId: String
    public var excluPar: String?
    public var motif: String?
    public var typeExcluPar: String?
    public var creeLe: String?

    enum CodingKeys: String, CodingKey {
        case id, motif
        case excluId = "exclu_id"
        case excluPar = "exclu_par"
        case typeExcluPar = "type_exclu_par"
        case creeLe = "cree_le"
    }

    public init(id: String, excluId: String, excluPar: String?, motif: String?, typeExcluPar: String?, creeLe: String?) {
        self.id = id; self.excluId = excluId; self.excluPar = excluPar; self.motif = motif
        self.typeExcluPar = typeExcluPar; self.creeLe = creeLe
    }

    /// Exclusion affichée : nom de `fn_etablissements_safe` (nil si absent : l'écran affiche l'identifiant, comme le web
    /// l.56).
    public func exclusion(nom: String?) -> Exclusion {
        Exclusion(id: id, excluId: excluId, etablissementNom: nom, motif: motif, creeLe: creeLe.flatMap(ExclusionsRegles.date))
    }
}

/// Ligne de `fn_mes_exclusions_recues` (`public.sql` l.42386-42393) : `{id, exclu_par, type_exclu_par, motif,
/// etablissement_nom, cree_le}`, triée par `cree_le` décroissant.
public struct LigneExclusionRecue: Decodable, Equatable, Sendable {
    public var id: String
    public var excluPar: String?
    public var motif: String?
    public var etablissementNom: String?
    public var creeLe: String?

    enum CodingKeys: String, CodingKey {
        case id, motif
        case excluPar = "exclu_par"
        case etablissementNom = "etablissement_nom"
        case creeLe = "cree_le"
    }

    /// `excluId` porte l'auteur (`exclu_par`) : une exclusion reçue ne se retire jamais depuis le soignant.
    public var exclusion: Exclusion {
        Exclusion(id: id, excluId: excluPar ?? "", etablissementNom: etablissementNom, motif: motif,
                  creeLe: creeLe.flatMap(ExclusionsRegles.date))
    }
}

public enum ExclusionsRegles {
    /// `p_type` de `fn_exclure_utilisateur` : type de l'AUTEUR, toujours `SOIGNANT` côté soignant (`BoutonExclusion`
    /// `typeExcluPar="SOIGNANT"`, `DetailMissionSoignant.tsx` l.1174, l.1181).
    public static let typeAuteur = "SOIGNANT"
    /// `maxLength={500}` du motif (`BoutonExclusion.tsx` l.71).
    public static let motifLongueurMax = 500

    /// Motif envoyé : sans espaces de bord, `nil` si vide (`motif.trim() || null`, l.30).
    public static func motifEnvoye(_ saisie: String) -> String? {
        let motif = String(saisie.prefix(motifLongueurMax)).trimmingCharacters(in: .whitespacesAndNewlines)
        return motif.isEmpty ? nil : motif
    }

    /// `timestamptz` PostgREST (fraction facultative) → date.
    static func date(_ iso: String) -> Date? {
        let avecFraction = ISO8601DateFormatter()
        avecFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = avecFraction.date(from: iso) { return date }
        let simple = ISO8601DateFormatter()
        simple.formatOptions = [.withInternetDateTime]
        return simple.date(from: iso)
    }

    /// « Depuis le d MMM yyyy » (`format(…, 'd MMM yyyy', { locale: fr })`, l.145, l.179), heure de Paris.
    public static func depuis(_ date: Date?) -> String? {
        guard let date else { return nil }
        let format = DateFormatter()
        format.locale = Locale(identifier: "fr_FR")
        format.timeZone = TimeZone(identifier: "Europe/Paris")
        format.dateFormat = "d MMM yyyy"
        return ExclusionsTextes.depuisPrefixe + " " + format.string(from: date)
    }
}

/// Libellés non juridiques des exclusions (`ExclusionsSoignant.tsx`, `BoutonExclusion.tsx`), tutoiement du web passé au
/// vouvoiement (décision 9 du lot 1). Le bouton, la confirmation et l'effet annoncé de l'exclusion sont dans
/// `TextesWeb.Exclusion` (HARD STOP n°4).
public enum ExclusionsTextes {
    // source: src/pages/ExclusionsSoignant.tsx:28 (`usePageTitle`)
    public static let titre = "Exclusions"
    // source: src/pages/ExclusionsSoignant.tsx:105
    public static let mesExclusions = "Mes exclusions"
    // source: src/pages/ExclusionsSoignant.tsx:118 (« Envoyées (n) »)
    public static let envoyees = "Envoyées"
    // source: src/pages/ExclusionsSoignant.tsx:128 (« Reçues (n) »)
    public static let recues = "Reçues"
    // source: src/pages/ExclusionsSoignant.tsx:136
    public static let videEnvoyeesTitre = "Aucune exclusion"
    // source: src/pages/ExclusionsSoignant.tsx:136 (vouvoyé : « Tu n'as »)
    public static let videEnvoyeesTexte = "Vous n'avez bloqué personne."
    // source: src/pages/ExclusionsSoignant.tsx:165 (vouvoyé : « avec toi », « ne te sont »)
    public static let recuesAvis = "Ces établissements ont choisi de ne plus travailler avec vous. Leurs missions ne vous sont plus proposées."
    // source: src/pages/ExclusionsSoignant.tsx:171
    public static let videRecuesTitre = "Aucune exclusion reçue"
    // source: src/pages/ExclusionsSoignant.tsx:171 (vouvoyé : « ne t'a exclu »)
    public static let videRecuesTexte = "Aucun établissement ne vous a exclu." // revue B8 textes, mineur 14 : seule la personne change
    // source: src/pages/ExclusionsSoignant.tsx:176
    public static let etablissementInconnu = "Établissement inconnu"
    // source: src/pages/ExclusionsSoignant.tsx:145, l.179
    public static let depuisPrefixe = "Depuis le"
    // source: src/pages/ExclusionsSoignant.tsx:192
    public static let supprimerTitre = "Supprimer cette exclusion ?"
    // source: src/pages/ExclusionsSoignant.tsx:193 (vouvoyé : « te proposer »)
    public static let supprimerMessage = "L'établissement pourra à nouveau vous proposer des missions."
    // source: src/pages/ExclusionsSoignant.tsx:194
    public static let supprimer = "Supprimer"
    // source: src/pages/ExclusionsSoignant.tsx:79
    public static let supprimee = "Exclusion supprimée."
    // source: src/components/BoutonExclusion.tsx:65
    public static let motifLibelle = "Motif (optionnel)"
    // source: src/components/BoutonExclusion.tsx:69
    public static let motifPlaceholder = "Indiquez un motif si vous le souhaitez..."
    // source: src/components/BoutonExclusion.tsx:75
    public static let annuler = "Annuler"
    // source: src/components/BoutonExclusion.tsx:77
    public static let enCours = "En cours..."
    // source: src/components/BoutonExclusion.tsx:37 (repli d'un refus sans message)
    public static let erreurInconnue = "Erreur inconnue"
    /// Texte opérationnel hors web : lecture impossible.
    public static let chargementImpossible = "Impossible de charger vos exclusions. Réessayez."
    /// Texte opérationnel hors web : l'action a été envoyée mais la relecture ne la confirme pas (PRINCIPES §3).
    public static let nonConfirmee = "La modification n'a pas pu être relue. Vérifiez la liste avant de réessayer."
    public static let reessayer = "Réessayer"

    /// « Retirer l’exclusion de {nom} » (`aria-label`, l.148).
    public static func retirerAccessibilite(_ nom: String) -> String { "Retirer l’exclusion de \(nom)" }
}
