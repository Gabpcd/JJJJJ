import Foundation

/// Textes de « Mes évaluations » (L4-T9), repris mot pour mot de `src/pages/EvaluationsSoignant.tsx` (route
/// `/soignant/evaluations`), chacun à sa ligne source (`EvaluationsScoreVerbatimTests`). Aucun texte nouveau à portée
/// juridique ; les refus du serveur sont affichés tels quels (`IssueSignalement.refuse`).
///
/// - Le seul texte tutoyé de la page (`vouvoiements`) passe au vouvoiement (décision 9 du lot 1), sans autre changement.
/// - Feuille de signalement : textes de la modale jumelle `ModaleSignaler` de `src/components/NotationsRecues.tsx`
///   (même action, même RPC `fn_signaler_notation`), **déjà vouvoyée** sur le web : repris tels quels, plutôt que de
///   transposer la modale tutoyée de `EvaluationsSoignant.tsx` (l.452-517). Le texte qui dit ce que fera
///   l'administrateur n'est donc ni reformulé ni transposé.
/// - Textes sans équivalent web, non juridiques : `signalementNonConfirme` (relecture qui ne montre pas le
///   signalement, PRINCIPES §3), `noteIndisponible` (note absente de la réponse : jamais « 0.0 »).
/// - Non porté : bouton « Éditer » (chemin mort du web, D11).
public enum EvaluationsTextes {
    // source: EvaluationsSoignant.tsx l.58 (`usePageTitle`)
    public static let titre = "Mes évaluations"
    // source: l.117
    public static let enTete = "Mes évaluations reçues"
    // source: l.120 (tutoyé sur le web : `vouvoiements`)
    public static let sousTitre = "Notes laissées par les établissements après vos missions."
    // source: l.128, l.135, l.139, l.143, l.148, l.155
    public static let noteMoyenne = "Note moyenne"
    public static let pasEncoreDEvaluation = "Pas encore d'évaluation"
    public static let totalEvaluations = "Total évaluations"
    public static let pct5Etoiles = "% 5 étoiles"
    public static let evolution6m = "Évolution 6m"
    public static let dernierMois = "dernier mois"
    // source: l.164
    public static let graphiqueTitre = "Note moyenne 6 derniers mois"
    // source: l.191, l.202, l.213 (`aria-label` des trois filtres)
    public static let filtrePeriode = "Filtrer par période"
    public static let filtreNote = "Filtrer par note minimum"
    public static let filtreEtablissement = "Filtrer par établissement"
    // source: l.204 et l.215 (option sans filtre)
    public static let toutesNotes = "Toutes notes"
    public static let tousEtablissements = "Tous établissements"
    // source: l.240
    public static let videTitre = "Aucune évaluation"
    public static let videDescription = "Les évaluations reçues apparaîtront ici."
    // source: l.321 (carte mobile)
    public static let dejaSignalee = "Déjà signalée"
    public static let signalerCetteEvaluation = "Signaler cette évaluation"
    // source: l.334, l.335
    public static let precedent = "Précédent"
    public static let suivant = "Suivant"
    // source: l.93 (repli du toast d'échec de lecture)
    public static let erreurChargement = "Erreur chargement."
    public static let reessayer = "Réessayer"

    // MARK: Feuille de signalement (NotationsRecues.tsx, `ModaleSignaler`)

    // source: NotationsRecues.tsx l.165
    public static let signalementTitre = "Signaler cette évaluation"
    // source: NotationsRecues.tsx l.177 puis l.178 (deux lignes JSX jointes par une espace)
    public static let signalementExplicationDebut = "Si vous pensez que cette évaluation est abusive, inappropriée ou injuste, signalez-la."
    public static let signalementExplicationFin = "Un administrateur Jolene examinera votre signalement et pourra masquer la notation si justifiée."
    public static let signalementExplication = signalementExplicationDebut + " " + signalementExplicationFin
    // source: NotationsRecues.tsx l.182
    public static let signalementMotif = "Motif du signalement * (min 10 caractères)"
    // source: NotationsRecues.tsx l.188
    public static let signalementPlaceholder = "Expliquez pourquoi cette évaluation vous paraît abusive…"
    // source: NotationsRecues.tsx l.139
    public static let signalementMotifRequis = "Veuillez expliquer le motif (min 10 caractères)."
    // source: NotationsRecues.tsx l.154 (repli d'un refus sans message)
    public static let erreurSignalement = "Erreur signalement."
    // source: NotationsRecues.tsx l.157
    public static let signalementTransmis = "Signalement transmis à l'administrateur Jolene."
    // source: NotationsRecues.tsx l.195, l.198
    public static let annuler = "Annuler"
    public static let signaler = "Signaler"

    /// Relecture qui ne montre pas la notation signalée (PRINCIPES §3) : jamais un succès annoncé.
    public static let signalementNonConfirme = "Le signalement n’a pas pu être confirmé. Réessayez."
    /// Note absente de la réponse du serveur : jamais une valeur fabriquée.
    public static let noteIndisponible = "—"

    /// Texte tutoyé du web et sa forme vouvoyée (décision 9 du lot 1 ; non juridique).
    public static let vouvoiements: [(web: String, natif: String)] = [
        ("Notes laissées par les établissements après tes missions.", sousTitre),
    ]

    // source: l.193-196 (`<option>` de la période)
    public static func libelle(_ periode: PeriodeEvaluations) -> String {
        switch periode {
        case .tout: return "Toutes périodes"
        case .troisMois: return "3 derniers mois"
        case .sixMois: return "6 derniers mois"
        case .douzeMois: return "12 derniers mois"
        }
    }

    /// Notes minimales proposées (l.205-207), de la plus haute à la plus basse.
    public static let notesMin = [5, 4, 3]

    // source: l.204-207 (`<option>` de la note minimale)
    public static func libelle(noteMin: Int?) -> String {
        switch noteMin {
        case 5?: return "5 étoiles"
        case 4?: return "4 étoiles et +"
        case 3?: return "3 étoiles et +"
        default: return toutesNotes
        }
    }

    // source: l.223 (`{total} évaluation{total > 1 ? 's' : ''}`)
    public static func compte(_ total: Int) -> String { "\(total) évaluation\(total > 1 ? "s" : "")" }

    // source: l.332 (`Page {page + 1} / {totalPages}`)
    public static func page(_ page: Int, sur total: Int) -> String { "Page \(page + 1) / \(total)" }

    // source: l.251, l.299 (`« {n.commentaire} »`)
    public static func commentaire(_ texte: String) -> String { "« \(texte) »" }

    // source: NotationsRecues.tsx l.173 (`Note moyenne : {Number(notation.note_moyenne).toFixed(1)}/5`)
    public static func noteMoyenneSur5(_ note: String) -> String { "Note moyenne : \(note)/5" }

    // source: NotationsRecues.tsx l.191 (`{motif.length} / 10+`)
    public static func compteurMotif(_ longueur: Int) -> String { "\(longueur) / 10+" }
}

/// Mise en forme de « Mes évaluations » : dates en heure de Paris, valeurs serveur écrites comme le web (`toFixed(1)`,
/// nombre JavaScript), sans aucun calcul sur les notes.
public enum EvaluationsPresentation {
    /// Longueur minimale du motif d'un signalement (`motif.trim().length < 10`, l.458).
    public static let longueurMotifMin = 10

    /// `motif.trim()` du web, ou `nil` s'il compte moins de dix caractères (aucun appel alors).
    public static func motifValide(_ saisie: String) -> String? {
        let motif = saisie.trimmingCharacters(in: .whitespacesAndNewlines)
        return motif.count >= longueurMotifMin ? motif : nil
    }

    /// `Math.ceil(total / PAR_PAGE)` (l.110).
    public static func nombreDePages(total: Int) -> Int {
        guard total > 0 else { return 0 }
        return (total + EvaluationsDecodage.parPage - 1) / EvaluationsDecodage.parPage
    }

    /// `note.toFixed(1)` (l.52, l.131) : la valeur serveur, un chiffre après le point ; `noteIndisponible` sans valeur.
    public static func note(_ valeur: Double?) -> String {
        guard let valeur else { return EvaluationsTextes.noteIndisponible }
        return fixe1(valeur)
    }

    /// `{stats.pct_5_etoiles}%` (l.144) : nombre JavaScript, tel que servi (`25`, `33.3`).
    public static func pourcentage(_ valeur: Double?) -> String {
        guard let valeur else { return EvaluationsTextes.noteIndisponible }
        return "\(MissionPresentation.nombreJavaScript(valeur))%"
    }

    /// Note du dernier mois servi (l.151-153) : `evolution[evolution.length - 1].note_moyenne.toFixed(1)`, « — » sans point.
    public static func noteDernierMois(_ evolution: [PointEvolutionNotes]) -> String {
        note(evolution.last?.noteMoyenne)
    }

    /// `format(new Date(n.cree_le), 'd MMM yyyy', { locale: fr })` (l.254, l.291), en heure de Paris ; `nil` si illisible.
    public static func date(_ brut: String?) -> String? {
        guard let brut, let instant = try? DateHeureParis.instantJolene(brut) else { return nil }
        return DateHeureParis.format(instant, "d MMM yyyy")
    }

    /// `format(new Date(p.mois + '-01'), 'MMM', { locale: fr })` (l.176) : abréviation du mois d'un `YYYY-MM` ; le
    /// texte brut si le mois n'est pas lisible.
    public static func moisCourt(_ mois: String) -> String {
        let parties = mois.split(separator: "-")
        guard parties.count == 2, let numero = Int(parties[1]), (1...12).contains(numero) else { return mois }
        return DateHeureParis.moisCourts[numero - 1]
    }

    /// `Number.prototype.toFixed(1)` pour une valeur finie : arrondi de la valeur binaire exacte, demi exact vers le haut.
    static func fixe1(_ valeur: Double) -> String {
        guard valeur.isFinite else { return EvaluationsTextes.noteIndisponible }
        guard valeur != 0 else { return "0.0" }
        let magnitude = abs(valeur)
        let quarts = magnitude * 4
        let corps: String
        if magnitude < 1e15, quarts == quarts.rounded(.towardZero), quarts.truncatingRemainder(dividingBy: 2) == 1 {
            corps = String(format: "%.1f", (magnitude * 10).rounded(.up) / 10)
        } else {
            corps = String(format: "%.1f", magnitude)
        }
        return valeur < 0 ? "-\(corps)" : corps
    }
}
