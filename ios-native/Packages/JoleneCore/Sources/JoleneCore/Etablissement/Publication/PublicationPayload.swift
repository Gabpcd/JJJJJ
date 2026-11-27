import Foundation

/// Charge de `fn_creer_mission_multi_jours_v4` (lot 5, T9 ; `supabase/schema/public.sql` l.27782 ; fiche
/// `docs/mobile-swift/CONTRATS_RPC_ETABLISSEMENT.md`) : **exactement** les seize paramètres de la signature SQL, aucun
/// de plus, comme l'appel du web (`FormulaireMission.tsx` l.429-446). Le périmètre natif (D8) fixe sept d'entre eux :
/// type de contrat recherché et mode de rémunération constants, rétrocession, nature de TVA et spécialité médicale
/// nulles, accueil d'internes faux. Aucun mode d'exercice n'est choisi ni calculé ici ; le serveur valide la mission et
/// son refus est affiché mot pour mot.
///
/// - `p_description` : balises `[SERIE_ID:…]` et `[CONTRAT:…]` retirées comme le web (l.415), espaces de bord retirés,
///   `null` si vide. Le serveur pose lui-même la balise de contrat (`fn_creer_mission_multi_jours_v2`, l.27634-27641) ;
///   une balise `[SERIE_ID:…]` saisie rattacherait la mission à une série (`CarteSerie.tsx`) et n'est jamais envoyée.
/// - `p_niveau_urgence` : le niveau si la mission est urgente, sinon 0 (web l.430).
/// - `p_accepte_non_specialises` : `!professionMissionExigeSpecialisationExacte(profession)` (web l.433).
/// - `p_creneaux` : `[{debut, fin}]`, instants UTC `yyyy-MM-dd'T'HH:mm:ss'Z'` sans fraction, tels que portés par le
///   brouillon (`creneaux(_:)` les dérive de `PlanningDerive.materialiserPlanning`).
public struct PublicationPayload: Equatable, Sendable {
    /// Les seize paramètres, dans l'ordre de la signature SQL.
    public static let cles = [
        "p_intitule", "p_description", "p_profession_requise", "p_service", "p_taux_horaire_base", "p_est_urgente",
        "p_niveau_urgence", "p_mode_attribution", "p_specialite_medicale_requise", "p_accepte_non_specialises",
        "p_creneaux", "p_type_contrat_recherche", "p_mode_remuneration", "p_retrocession_pct",
        "p_nature_tva_prestation", "p_accepte_internes",
    ]
    /// Seul type de contrat recherché publié en natif (D8), le même que celui de l'acceptation native (D25).
    public static let typeContratRecherche = CandidaturesEtabRules.contratAcceptableNativement
    /// Seul mode de rémunération publié en natif (D8 ; valeur du web l.437).
    public static let modeRemuneration = "TAUX_HORAIRE"

    public let valeurs: [String: ValeurJSON]

    public init(_ brouillon: PublicationMission) {
        let service = brouillon.service.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        valeurs = [
            "p_intitule": .chaine(brouillon.intitule),
            "p_description": Self.description(brouillon.description).map(ValeurJSON.chaine) ?? .null,
            "p_profession_requise": .chaine(brouillon.professionRequise),
            "p_service": service.map(ValeurJSON.chaine) ?? .null,
            "p_taux_horaire_base": .nombre(brouillon.tauxHoraireBase),
            "p_est_urgente": .booleen(brouillon.estUrgente),
            "p_niveau_urgence": .nombre(Double(brouillon.estUrgente ? brouillon.niveauUrgence : 0)),
            "p_mode_attribution": .chaine(brouillon.modeAttribution.rawValue),
            "p_specialite_medicale_requise": .null,
            "p_accepte_non_specialises": .booleen(!ProfessionHierarchy.exigeSpecialisationExacte(professionRequise: brouillon.professionRequise)),
            "p_creneaux": .tableau(brouillon.creneaux.map { .objet(["debut": .chaine($0.debut), "fin": .chaine($0.fin)]) }),
            "p_type_contrat_recherche": .chaine(Self.typeContratRecherche),
            "p_mode_remuneration": .chaine(Self.modeRemuneration),
            "p_retrocession_pct": .null,
            "p_nature_tva_prestation": .null,
            "p_accepte_internes": .booleen(false),
        ]
    }

    /// Description envoyée : sans balise `[SERIE_ID:…]` ni `[CONTRAT:…]`, sans espaces de bord ; `nil` si vide
    /// (`descriptionFinale || null`, web l.425). Revue B8 sécurité de la vague D (m1) : retrait répété jusqu'à
    /// stabilité et sans tenir compte de la casse (le serveur ne retire `[CONTRAT:…]` qu'en un passage et l'ILIKE de la
    /// série ignore la casse) : une saisie imbriquée ne reconstitue jamais une balise.
    public static func description(_ saisie: String?) -> String? {
        guard let saisie else { return nil }
        var texte = saisie
        while true {
            let suivant = texte.replacingOccurrences(of: #"\[(SERIE_ID|CONTRAT):[^\]]*\]"#, with: "",
                                                     options: [.regularExpression, .caseInsensitive])
            if suivant == texte { break }
            texte = suivant
        }
        texte = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        return texte.isEmpty ? nil : texte
    }

    /// Créneaux envoyés, dérivés des créneaux matérialisés (jours travaillés, triés par début) : chaque borne réécrite
    /// en UTC sans fraction. `nil` si la liste est vide ou si une borne ne s'écrit pas sans changer l'instant
    /// (fail-closed : jamais une charge approximative).
    public static func creneaux(_ materialises: [PlanningDerive.CreneauMaterialise]) -> [CreneauConfirme]? {
        guard !materialises.isEmpty else { return nil }
        var envoyes: [CreneauConfirme] = []
        envoyes.reserveCapacity(materialises.count)
        for creneau in materialises {
            guard let debut = CreneauxConfirmes.isoUTCSansFraction(creneau.debut),
                  let fin = CreneauxConfirmes.isoUTCSansFraction(creneau.fin) else { return nil }
            envoyes.append(CreneauConfirme(debut: debut, fin: fin))
        }
        return envoyes
    }
}

/// Relecture d'une mission créée (§2.4, PRINCIPES §3) : « Publiée » n'est affiché que si la mission relue est bien celle
/// envoyée. Comparaison par **instants**, jamais par chaînes (le serveur rend `+00:00`, l'envoi porte `Z`).
public enum PublicationRelecture {
    /// Statut d'une mission qui vient d'être publiée.
    public static let statutOuverte = "OUVERTE"

    /// Vrai si la mission relue est ouverte, porte le type de contrat envoyé, le nombre de créneaux envoyés, un planning
    /// relu sans erreur dont le multi-ensemble `(début, fin)` est celui de l'envoi, et les bornes `debut_le` / `fin_le`
    /// de cet envoi. Le type de contrat relu est comparé parce qu'un trigger serveur peut le modifier en silence.
    public static func confirme(_ detail: EtabMissionDetail, envoi: [CreneauConfirme]) -> Bool {
        let mission = detail.mission
        guard !envoi.isEmpty, detail.erreurPlanning == nil, mission.statut == statutOuverte,
              mission.typeContratRecherche == PublicationPayload.typeContratRecherche,
              mission.nbCreneaux == envoi.count, detail.creneaux.count == envoi.count,
              let envoyes = bornes(envoi.map { ($0.debut, Optional($0.fin)) }),
              let relus = bornes(detail.creneaux.map { ($0.debut, $0.fin) }), envoyes == relus,
              let debut = mission.debutLe.flatMap(instant), let fin = mission.finLe.flatMap(instant),
              debut == envoyes.map(\.debut).min(), fin == envoyes.map(\.fin).max() else { return false }
        return true
    }

    private struct Bornes: Equatable, Comparable {
        var debut: Int64
        var fin: Int64
        static func < (a: Bornes, b: Bornes) -> Bool { (a.debut, a.fin) < (b.debut, b.fin) }
    }

    private static func instant(_ iso: String) -> Int64? {
        (try? DateHeureParis.instantJolene(iso)).map(DateHeureParis.millisecondes)
    }

    /// Bornes triées (multi-ensemble) ; `nil` dès qu'une borne manque ou est illisible.
    private static func bornes(_ creneaux: [(String, String?)]) -> [Bornes]? {
        var resultat: [Bornes] = []
        for (debut, fin) in creneaux {
            guard let d = instant(debut), let f = fin.flatMap(instant) else { return nil }
            resultat.append(Bornes(debut: d, fin: f))
        }
        return resultat.sorted()
    }
}
