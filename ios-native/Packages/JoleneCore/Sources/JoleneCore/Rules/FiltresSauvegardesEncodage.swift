import Foundation

/// Recherches sauvegardées du soignant (L4-T4, `docs/mobile-swift/LOT4_PLAN.md` §1.1, §2.4 et §3 T4) : critères
/// d'Explorer envoyés en `p_filtres`, lecture de `fn_lister_mes_filtres_sauvegardes` et application d'une recherche à
/// Explorer. Règles pures, sans réseau ; aucune règle juridique.
///
/// - `p_filtres` : forme `CriteresAlerteMissions` du web (`src/lib/alertes-recherche-missions.ts` l.1-9), les sept clés
///   camelCase **toujours présentes** avec les valeurs d'Explorer (`ville` → `villeRecherche`, `etablissementId`
///   retiré : le validateur serveur refuse toute autre clé). Les nombres entiers partent sans décimale (gateway) : une
///   recherche créée par le web avec les mêmes critères a la même clé de comparaison (`AlerteRecherche.cle`).
/// - Validateur : port de `private.fn_filtres_recherche_missions_valides` (migration
///   `20260925093121_alertes_recherches_etablissement_exactes.sql` l.319-338), sauf l'appartenance de `profession` à
///   l'énumération `type_profession`, que seul le serveur connaît. Une recherche refusée ici n'est jamais envoyée
///   (« un gap connu reste verrouillé »).
/// - Lecture : `[{id, nom, audience, filtres, alerte_active, frequence_alerte, dernier_check_le,
///   nb_resultats_dernier_check, cree_le, mis_a_jour_le}]` trié par `mis_a_jour_le` décroissant (`public.sql`
///   l.40393-40419) ; ordre serveur conservé.
/// - Application : port de l'effet « filtres pré-stockés » de `RechercheMissions.tsx` (l.137-158) — une clé du bon type
///   remplace le critère courant, toute autre clé le laisse tel quel ; le filtre établissement est retiré (le web
///   rouvre `/soignant/recherche-missions` sans `?etablissement=`).
public enum FiltresSauvegardesEncodage {
    /// `p_audience` : toujours la recherche de missions du soignant (`filtre_audience`, `public.sql` l.53-56).
    public static let audience = "SOIGNANT_RECHERCHE_MISSIONS"
    /// Clés acceptées par le validateur serveur, dans l'ordre de `CriteresAlerteMissions`.
    public static let clesAutorisees = ["profession", "rayonKm", "tauxMin", "typeContrat", "urgentesOnly", "horaire",
                                        "villeRecherche"]
    public static let typesContrat: Set<String> = ["TOUS", "CDD", "LIBERAL"]
    public static let horaires: Set<String> = ["TOUS", "JOUR", "NUIT", "WEEKEND"]
    /// `filtres_sauvegardes_nom_check` et `fn_creer_filtre_sauvegarde` (« Nom invalide (1-100 caractères) »).
    public static let longueurNomMax = 100
    /// Limite serveur (`fn_creer_filtre_sauvegarde` : « Limite de 20 recherches sauvegardées atteinte… »).
    public static let nombreMax = 20
    /// Borne du validateur pour `rayonKm` et `tauxMin` (`v::numeric > 10000` refusé).
    public static let valeurNumeriqueMax: Double = 10000

    // MARK: - Critères envoyés

    /// Critères d'Explorer → `FiltresAlerte` (sept clés, valeurs d'Explorer telles quelles ; le rayon est entier,
    /// comme le curseur du web et `soignants.rayon_deplacement_km`).
    public static func criteres(_ filtres: ExplorerFiltres) -> FiltresAlerte {
        FiltresAlerte(profession: filtres.profession, rayonKm: Int(filtres.rayonKm.rounded()), tauxMin: filtres.tauxMin,
                      typeContrat: filtres.typeContrat.rawValue, urgentesOnly: filtres.urgentesOnly,
                      horaire: filtres.horaire.rawValue, villeRecherche: filtres.ville)
    }

    /// `p_filtres` : `{ ...criteres }` du web (les sept clés).
    public static func valeur(_ criteres: FiltresAlerte) -> ValeurJSON { AlerteRecherche.valeur(criteres) }

    /// Port de `private.fn_filtres_recherche_missions_valides`, hors liste des professions (serveur seul).
    public static func estValide(_ filtres: ValeurJSON) -> Bool {
        guard case .objet(let objet) = filtres else { return false }
        guard objet.keys.allSatisfy(clesAutorisees.contains) else { return false }
        for cle in ["profession", "typeContrat", "horaire", "villeRecherche"] {
            switch objet[cle] {
            case nil, .null?, .chaine?: continue
            default: return false
            }
        }
        if !texte(objet["typeContrat"], defaut: "TOUS", dans: typesContrat) { return false }
        if !texte(objet["horaire"], defaut: "TOUS", dans: horaires) { return false }
        switch objet["urgentesOnly"] {
        case nil, .null?, .booleen?: break
        default: return false
        }
        for cle in ["rayonKm", "tauxMin"] where !numeriqueValide(objet[cle]) { return false }
        return true
    }

    /// `coalesce(p->>k, defaut) IN (…)` : absent ou `null` vaut le défaut.
    private static func texte(_ valeur: ValeurJSON?, defaut: String, dans valeurs: Set<String>) -> Bool {
        switch valeur {
        case nil, .null?: return valeurs.contains(defaut)
        case .chaine(let texte)?: return valeurs.contains(texte)
        default: return false
        }
    }

    /// `rayonKm` / `tauxMin` : absent ou `null` accepté ; sinon nombre ou texte de la forme `^[0-9]+([.][0-9]+)?$`,
    /// 20 caractères au plus, au plus 10000. Un nombre JSON négatif, non fini ou au-delà de la borne est refusé.
    private static func numeriqueValide(_ valeur: ValeurJSON?) -> Bool {
        switch valeur {
        case nil, .null?:
            return true
        case .nombre(let nombre)?:
            return nombre.isFinite && nombre >= 0 && nombre <= valeurNumeriqueMax
        case .chaine(let texte)?:
            guard texte.count <= 20, texte.range(of: #"^[0-9]+([.][0-9]+)?$"#, options: .regularExpression) != nil,
                  let nombre = Double(texte) else { return false }
            return nombre <= valeurNumeriqueMax
        default:
            return false
        }
    }

    /// Nom envoyé : espaces de bord retirés (`nom.trim()` du web) ; `nil` s'il est vide (« Nom requis »). La borne de
    /// 100 caractères reste vérifiée par le serveur (message verbatim).
    public static func nomSaisi(_ saisie: String) -> String? {
        let nom = saisie.trimmingCharacters(in: .whitespacesAndNewlines)
        return nom.isEmpty ? nil : nom
    }

    // MARK: - Lecture

    /// Réponse de `fn_lister_mes_filtres_sauvegardes` ; `nil` si elle n'est pas un tableau (le web lève alors
    /// « Réponse de recherches invalide ») ou si une ligne n'a pas d'identifiant, de nom ou d'état d'alerte lisibles
    /// (aucune ligne plausible fabriquée). Une ligne d'une autre audience est écartée ; `filtres` absent ou `null`
    /// vaut `{}` (`recherche.filtres ?? {}`), une fréquence inconnue `nil`.
    public static func liste(_ reponse: ValeurJSON) -> [FiltreSauvegarde]? {
        guard case .tableau(let lignes) = reponse else { return nil }
        var recherches: [FiltreSauvegarde] = []
        for ligne in lignes {
            guard case .objet(let objet) = ligne,
                  case .chaine(let id)? = objet["id"], !id.isEmpty,
                  case .chaine(let nom)? = objet["nom"],
                  case .booleen(let alerte)? = objet["alerte_active"] else { return nil }
            if case .chaine(let audience)? = objet["audience"], audience != Self.audience { continue }
            var frequence: FrequenceAlerte?
            if case .chaine(let brute)? = objet["frequence_alerte"] { frequence = FrequenceAlerte(rawValue: brute) }
            var dernierCheck: String?
            if case .chaine(let horodatage)? = objet["dernier_check_le"] { dernierCheck = horodatage }
            var resultats = 0
            if case .nombre(let nombre)? = objet["nb_resultats_dernier_check"], nombre.isFinite, nombre >= 0,
               nombre == nombre.rounded(), nombre < 1e9 {
                resultats = Int(nombre)
            }
            let filtres: ValeurJSON
            switch objet["filtres"] {
            case nil, .null?: filtres = .objet([:])
            case let valeur?: filtres = valeur
            }
            recherches.append(FiltreSauvegarde(id: id, nom: nom, filtres: filtres, alerteActive: alerte, frequence: frequence,
                                               dernierCheckLe: dernierCheck, nbResultatsDernierCheck: resultats))
        }
        return recherches
    }

    // MARK: - Application à Explorer

    /// « Aller à la recherche » : critères d'Explorer après application de la recherche sur `precedent`. Une valeur
    /// d'énumération inconnue (contrat, horaires) laisse le critère courant (Explorer n'a pas d'état pour elle).
    public static func explorer(depuis filtres: ValeurJSON, precedent: ExplorerFiltres) -> ExplorerFiltres {
        var resultat = precedent
        resultat.etablissementId = nil
        guard case .objet(let objet) = filtres else { return resultat }
        if case .chaine(let profession)? = objet["profession"] { resultat.profession = profession }
        if case .nombre(let rayon)? = objet["rayonKm"], rayon.isFinite { resultat.rayonKm = rayon }
        if case .nombre(let taux)? = objet["tauxMin"], taux.isFinite { resultat.tauxMin = taux }
        if case .chaine(let brut)? = objet["typeContrat"], let contrat = MissionFilters.TypeContrat(rawValue: brut) {
            resultat.typeContrat = contrat
        }
        if case .booleen(let urgentes)? = objet["urgentesOnly"] { resultat.urgentesOnly = urgentes }
        if case .chaine(let brut)? = objet["horaire"], let horaire = MissionFilters.Horaire(rawValue: brut) {
            resultat.horaire = horaire
        }
        if case .chaine(let ville)? = objet["villeRecherche"] { resultat.ville = ville }
        return resultat
    }
}
