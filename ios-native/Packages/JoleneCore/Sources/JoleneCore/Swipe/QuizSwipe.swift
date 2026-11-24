import Foundation

/// Réponses du quiz de préférences du premier contact (lot 4, T3b ; décisions D6 et D26 de `DECISIONS_LOT4.md`), port
/// de `ReponsesQuiz` de `src/components/swipe/QuizPreferencesSwipe.tsx`, **sans** `dispoUrgence` : le web active alors
/// le pool urgence par un `UPDATE soignants SET disponible_urgence = true` direct, sans le contrôle documentaire de
/// `fn_toggle_pool_urgence` ni le texte de consentement du pool (correction 17 de `LOT4_PLAN.md`). Gap verrouillé : le
/// quiz natif ne porte pas cette question et n'écrit jamais cette colonne ; il renvoie à l'écran Pool urgence (T11).
/// Valeurs par défaut du web : horaires et rythme « Les deux », 20 km, taux « Peu importe ».
public struct ReponsesQuizSwipe: Equatable, Sendable {
    public var horaire: PreferencesMatching.Horaire
    public var rythme: PreferencesMatching.Rythme
    public var rayonKm: Double
    public var tauxMin: Double

    public init(horaire: PreferencesMatching.Horaire = .tous, rythme: PreferencesMatching.Rythme = .tous,
                rayonKm: Double = 20, tauxMin: Double = 0) {
        self.horaire = horaire; self.rythme = rythme; self.rayonKm = rayonKm; self.tauxMin = tauxMin
    }

    /// Préférences horaires amorcées côté serveur (`fn_initialiser_preferences_matching`, bornes [0, 1]).
    public var preferences: PreferencesMatching { .depuisQuiz(horaire: horaire, rythme: rythme) }

    /// `appliquerQuiz` de `RechercheMissions.tsx` : rayon et taux repris tels quels ; une seule dimension d'horaire dans
    /// les filtres — l'horaire jour / nuit s'il est choisi, sinon le week-end si le rythme l'est (le scoring, lui,
    /// reçoit les deux dimensions). Les autres critères d'Explorer sont conservés.
    public func appliquees(a filtres: ExplorerFiltres) -> ExplorerFiltres {
        var copie = filtres
        copie.rayonKm = rayonKm
        copie.tauxMin = tauxMin
        switch horaire {
        case .jour: copie.horaire = .jour
        case .nuit: copie.horaire = .nuit
        case .tous: if rythme == .weekend { copie.horaire = .weekend }
        }
        return copie
    }
}

/// Textes et options du quiz (`QuizPreferencesSwipe.tsx`, rôle SOIGNANT). Aucun texte juridique ; les textes tutoyés du
/// web passent au vouvoiement (décision 9 du lot 1 : seule la personne change), et le titre annonce quatre questions au
/// lieu de cinq, la question « missions urgentes » n'étant pas portée (D26). Textes sans équivalent web : le renvoi
/// vers Pool urgence (`poolUrgence*`), neutre, sans promesse (ni « mieux payées », ni activation depuis le quiz).
public enum QuizSwipe {
    // source: QuizPreferencesSwipe.tsx l.99 (vouvoyé : « qui te ressemble » ; quatre questions, D26)
    public static let titre = "4 questions pour un deck qui vous ressemble"
    // source: l.101 (vouvoyé : « de chacun de tes swipes »)
    public static let description = "30 secondes — et le deck apprendra ensuite de chacun de vos swipes."
    // source: l.107 (vouvoyé : « Tu préfères travailler… »)
    public static let questionHoraire = "Vous préférez travailler…"
    // source: l.116
    public static let questionRythme = "Plutôt…"
    // source: l.125
    public static let questionRayon = "Jusqu'à quelle distance ?"
    // source: l.134
    public static let questionTaux = "Taux horaire minimum ?"
    // source: l.155, l.158
    public static let valider = "C'est parti 🚀"
    public static let plusTard = "Plus tard"
    // source: l.89 (vouvoyé : « ton deck »)
    public static let confirmation = "C'est noté — votre deck est personnalisé ✨"

    /// Renvoi vers l'écran Pool urgence, à la place de la cinquième question du web (D26). Texte natif, non juridique.
    public static let poolUrgenceTexte = "La disponibilité pour les missions urgentes se règle dans l'écran Pool urgence."
    public static let poolUrgenceAction = "Ouvrir Pool urgence"

    public struct Option<Valeur: Equatable & Sendable>: Equatable, Sendable, Identifiable {
        public var valeur: Valeur
        public var titre: String
        /// Suffixe d'identifiant d'accessibilité (`swipe-quiz-<question>-<identifiant>`), jamais déduit du libellé.
        public var identifiant: String
        public var id: String { identifiant }
    }

    // source: l.109-111
    public static let horaires: [Option<PreferencesMatching.Horaire>] = [
        Option(valeur: .jour, titre: "☀️ De jour", identifiant: "jour"),
        Option(valeur: .nuit, titre: "🌙 De nuit", identifiant: "nuit"),
        Option(valeur: .tous, titre: "Les deux", identifiant: "tous"),
    ]

    // source: l.118-120
    public static let rythmes: [Option<PreferencesMatching.Rythme>] = [
        Option(valeur: .semaine, titre: "Semaine", identifiant: "semaine"),
        Option(valeur: .weekend, titre: "Week-end", identifiant: "weekend"),
        Option(valeur: .tous, titre: "Les deux", identifiant: "tous"),
    ]

    // source: l.127-129 (`[5, 10, 20, 50]`, « {km} km »)
    public static let rayons: [Option<Double>] = ([5, 10, 20, 50] as [Double]).map {
        Option(valeur: $0, titre: "\(MissionPresentation.nombreJavaScript($0)) km", identifiant: MissionPresentation.nombreJavaScript($0))
    }

    // source: l.136-139 (« Peu importe », puis `[25, 30, 35]` : « ≥ {t} €/h »)
    public static let taux: [Option<Double>] = [Option(valeur: 0, titre: "Peu importe", identifiant: "0")] + ([25, 30, 35] as [Double]).map {
        Option(valeur: $0, titre: "≥ \(MissionPresentation.nombreJavaScript($0)) €/h", identifiant: MissionPresentation.nombreJavaScript($0))
    }
}
