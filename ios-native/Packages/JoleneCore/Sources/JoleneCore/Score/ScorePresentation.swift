import Foundation

/// Textes de « Mon score » et de la contestation d'un événement de score (L4-T9), repris mot pour mot du web, chacun à
/// sa ligne source (`EvaluationsScoreVerbatimTests`) : `src/pages/PageScoreSoignant.tsx` (route `/soignant/score`),
/// `src/components/BreakdownScore.tsx`, `BadgeNiveauV2.tsx`, `GraphiqueEvolutionScore.tsx`, `NotationsRecues.tsx` et
/// `src/components/score/ModaleReclamationScore.tsx` (motifs de contestation l.22-29). Aucun texte nouveau à portée
/// juridique ; les refus du serveur sont affichés tels quels (`ReclamationScoreOutcome.refusee`).
///
/// - Les textes tutoyés du web (`vouvoiements`) passent au vouvoiement (décision 9 du lot 1), sans autre changement.
/// - Textes sans équivalent web, non juridiques : `chargementImpossible` (le web n'affiche aucune erreur de lecture),
///   `contestationNonConfirmee` (relecture qui ne montre pas l'événement contesté, PRINCIPES §3), `reessayer`.
/// - Non portés : justificatif de contestation et son avertissement (D10 : données de santé) ; lignes de référence
///   « Argent / Or / Platine » du graphique, « Contribution : … pts » et conseils « Améliorez : … » sous 60 % (seuils et
///   calculs du navigateur ; le conseil du présentéisme cite en outre un délai en heures que refuse la garde des
///   littéraux juridiques, `scripts/mobile/check-litteraux-juridiques.mjs`) ; signalement d'une notation depuis cette
///   page (`fn_lister_notations_recues` ne sert pas `signale` : l'effet ne peut pas être relu ; le signalement vit sur
///   « Mes évaluations »).
public enum ScoreTextes {
    // MARK: Page (PageScoreSoignant.tsx)

    // source: PageScoreSoignant.tsx l.38 (`usePageTitle`)
    public static let titre = "Mon score"
    // source: l.110
    public static let enTete = "Mon score de fiabilité"
    // source: l.113 (tutoyé sur le web : `vouvoiements`)
    public static let sousTitre = "Votre fiabilité vue par les établissements. Mise à jour après chaque mission, notation ou litige."
    // source: l.122
    public static let scoreAbsent = "— / 100"
    // source: l.130
    public static let sur100 = " / 100"
    // source: l.133
    public static let periodeProbatoireIndicatif = "Période probatoire (score indicatif)"
    // source: l.146 (`calculé&nbsp;?`), l.147, l.148
    public static let calculTitre = "Comment mon score est-il calculé\u{00A0}?"
    public static let voirLeDetail = "Voir le détail"
    public static let masquer = "Masquer"
    // source: l.154-158 (la première règle est tutoyée sur le web : `vouvoiements`)
    public static let calculRegles = [
        "6 composantes pondérées : Notation reçue (35%) · Présentéisme (20%) · Ponctualité (15%) · Réactivité (10%) · Ancienneté & volume (10%) · Vous notez les étabs (10%)",
        "Malus jusqu'à -20 pts (litiges) et -30 pts (absence sans prévenir)",
        "Bonus +5 pts si plus de 50 missions terminées sur 12 mois",
        "Composantes inactives (pas assez de données) redistribuées proportionnellement",
        "Score borné [0, 100]. Niveau : Bronze (<50) · Argent (50-69) · Or (70-89) · Platine (≥90)",
    ]
    // source: l.172
    public static let notationsTitre = "Notations reçues récemment"
    // source: l.181 (tutoyé sur le web : `vouvoiements`)
    public static let evenementsTitre = "Événements impactant votre score (12 derniers mois)"
    // source: l.210
    public static let contester = "⚖️ Contester"
    // source: l.214
    public static let traitee = "Traitée"
    public static let nonContestable = "Non contestable"
    // l.223 (engagement de délai « … la pénalité sous 72h. ») : non repris par prudence, aucun mécanisme serveur ne
    // garantit ce délai ; le web l'affiche sur le profil (`SectionEvenementsScore.tsx` l.121) (`DECISIONS_LOT4.md`,
    // précision 16, motif corrigé par la revue B8 des textes de la vague D, M2).
    // source: l.231 et l.234 (tutoyés sur le web : `vouvoiements`)
    public static let aucunEvenementTitre = "Vous pensez qu'une pénalité est injuste ?"
    public static let aucunEvenementTexte = "Aucun événement impactant votre score n'a été enregistré sur les 12 derniers mois. Si vous constatez une erreur, contactez le support Jolene."

    // source: l.124 (`Score disponible après {n} mission{s} terminée{s} de plus.`, n = max(0, 3 − missions terminées))
    public static func scoreDisponibleApres(_ restantes: Int) -> String {
        let pluriel = restantes > 1 ? "s" : ""
        return "Score disponible après \(restantes) mission\(pluriel) terminée\(pluriel) de plus."
    }

    // source: l.197 (`✔️ Décision admin : {ev.decision_admin}`)
    public static func decisionAdmin(_ decision: String) -> String { "✔️ Décision admin : \(decision)" }

    // source: l.203 (`{pts > 0 ? '+' : ''}{pts} pts`)
    public static func points(_ points: Double) -> String {
        "\(points > 0 ? "+" : "")\(MissionPresentation.nombreJavaScript(points)) pts"
    }

    // MARK: Niveau (BadgeNiveauV2.tsx)

    // source: BadgeNiveauV2.tsx l.36
    public static let nonNote = "Non noté"
    // source: BadgeNiveauV2.tsx l.23-26 (`{s.emoji} {s.label}`, l.44)
    public static let niveaux: [(code: String, emoji: String, label: String)] = [
        ("BRONZE", "🥉", "Bronze"), ("ARGENT", "🥈", "Argent"), ("OR", "🥇", "Or"), ("PLATINE", "💎", "Platine"),
    ]

    /// « 🥇 Or » pour un niveau connu ; le code servi tel quel s'il est inconnu ; `nil` sans niveau (jamais un défaut).
    public static func niveau(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        guard let connu = niveaux.first(where: { $0.code == code }) else { return code }
        return "\(connu.emoji) \(connu.label)"
    }

    // MARK: Détail du calcul (BreakdownScore.tsx)

    // source: BreakdownScore.tsx l.88, l.90
    public static let periodeProbatoire = "Période probatoire"
    public static let periodeProbatoireTexte = "Votre score est calculé sur les composantes disponibles, mais reste indicatif tant que vous n'avez pas terminé au moins 3 missions."
    // source: BreakdownScore.tsx l.102
    public static let inactivesTitre = "Composantes inactives — poids redistribués"
    // source: BreakdownScore.tsx l.158
    public static let malusBonusTitre = "Malus & bonus"
    // source: BreakdownScore.tsx l.175
    public static let formule = "Score total = somme pondérée des composantes + malus/bonus, borné [0, 100]. Recalculé à chaque nouvelle notation, mission terminée ou litige résolu."

    // source: BreakdownScore.tsx l.44-49 (`COMPOSANTES_DEF` : label et description ; conseils non portés)
    public static func composante(_ cle: CleComposanteScore) -> (label: String, description: String) {
        switch cle {
        case .notationEtabSoignant: return ("Notation reçue (étab → vous)", "Moyenne des étoiles 4 critères, pondérée récence")
        case .presentisme: return ("Présentéisme", "% de missions terminées vs total acceptées (12 mois)")
        case .ponctualite: return ("Ponctualité", "Écart pointage arrivée vs heure prévue (12 mois)")
        case .reactivite: return ("Réactivité aux propositions", "Délai moyen pour répondre aux propositions de mission")
        case .ancienneteVolume: return ("Ancienneté & volume", "Nombre de missions terminées sur 12 mois")
        case .notationSoignantEtab: return ("Vous notez les étabs", "% de missions terminées que vous avez notées")
        }
    }

    // source: BreakdownScore.tsx l.104
    public static func inactivesTexte(_ nombre: Int) -> String {
        let pluriel = nombre > 1 ? "s" : ""
        return "\(nombre) composante\(pluriel) non comptée\(pluriel) (pas assez de données). Les autres composantes voient leur poids majoré proportionnellement."
    }

    // source: BreakdownScore.tsx l.108 (`• <strong>{c.label}</strong> : {c.poids_initial}% redistribué`) ; le poids initial
    // est celui du serveur (`composantes_inactives_json`), jamais une constante de l'app : sans lui, le libellé seul.
    public static func inactive(_ composante: ComposanteScore) -> String {
        let label = Self.composante(composante.cle).label
        guard let poids = composante.poidsInitial else { return "• \(label)" }
        return "• \(label) : \(MissionPresentation.nombreJavaScript(poids))% redistribué"
    }

    // source: BreakdownScore.tsx l.126 (`poids {c.poids_effectif.toFixed(0)}%`)
    public static func poids(_ poids: Double) -> String { "poids \(ScorePresentation.entier(poids))%" }

    // source: BreakdownScore.tsx l.161, l.164, l.167
    public static func litigesMalus(_ points: Double) -> String {
        "⚠️ Litiges perdus 12 mois : \(MissionPresentation.nombreJavaScript(points)) pts (cap -20)"
    }
    public static func absenceMalus(_ points: Double) -> String {
        "🚫 Absence sans prévenir : \(MissionPresentation.nombreJavaScript(points)) pts"
    }
    public static func bonusSuperActif(_ points: Double) -> String {
        "Bonus super-actif (plus de 50 missions sur 12 mois) : +\(MissionPresentation.nombreJavaScript(points)) pts"
    }

    // MARK: Évolution (GraphiqueEvolutionScore.tsx)

    // source: GraphiqueEvolutionScore.tsx l.58, l.59, l.67, l.86 (`name="Score"`)
    public static let pasEncoreDHistorique = "Pas encore d'historique."
    public static let evolutionApparaitra = "L'évolution apparaîtra après vos premiers recalculs de score."
    public static let evolutionTitre = "Évolution sur 6 mois"
    public static let serieScore = "Score"

    // source: GraphiqueEvolutionScore.tsx l.72
    public static func donneesLimitees(_ nombre: Int) -> String {
        "Données limitées : \(nombre) snapshot\(nombre > 1 ? "s" : ""). Le graphique s'enrichira avec le temps."
    }

    // MARK: Notations reçues (NotationsRecues.tsx, audience SOIGNANT)

    // source: NotationsRecues.tsx l.69
    public static let aucuneNotation = "Aucune notation reçue pour le moment."
    // source: NotationsRecues.tsx l.27 (`LABELS.SOIGNANT`, dans l'ordre des critères 1 à 4)
    public static let criteres = ["Ponctualité", "Professionnalisme", "Qualité du soin", "Communication"]
    // source: NotationsRecues.tsx l.85, l.86 (`cible = 'Établissement'`, l.75)
    public static let missionTermineeLe = "Mission terminée le "
    public static let noteePar = "Notée par : "
    public static let etablissementAnonyme = "Établissement anonyme"

    // source: NotationsRecues.tsx l.91 (`⭐ {Number(n.note_moyenne).toFixed(1)}/5`)
    public static func noteSur5(_ note: String) -> String { "⭐ \(note)/5" }

    // MARK: Contestation (ModaleReclamationScore.tsx)

    // source: ModaleReclamationScore.tsx l.115
    public static let contestationTitre = "Contester cet événement de score"
    // source: ModaleReclamationScore.tsx l.124 (les six motifs sont proposés en liste : l'option vide « — Sélectionne — »
    // du menu web, l.126, n'a pas d'équivalent)
    public static let contestationMotif = "Motif de la contestation *"
    // source: ModaleReclamationScore.tsx l.132
    public static let contestationTexte = "Explication détaillée * (min 20 caractères)"
    // source: ModaleReclamationScore.tsx l.138 (tutoyé sur le web : `vouvoiements`)
    public static let contestationPlaceholder = "Expliquez précisément la situation : que s'est-il passé, pourquoi cet événement ne devrait pas vous pénaliser..."
    // source: ModaleReclamationScore.tsx l.176 (tutoyé sur le web : `vouvoiements`)
    public static let examenParAdmin = "Votre réclamation sera examinée par un administrateur Jolene. La décision (annulation, réduction ou maintien) sera notifiée par email + push."
    // source: ModaleReclamationScore.tsx l.78 (tutoyé sur le web : `vouvoiements`), l.82
    public static let motifRequis = "Sélectionnez un motif."
    public static let texteRequis = "Texte libre min 20 caractères."
    // source: ModaleReclamationScore.tsx l.99 (repli d'un refus sans message), l.106
    public static let erreur = "Erreur"
    public static let erreurReseau = "Erreur réseau"
    // source: ModaleReclamationScore.tsx l.102
    public static let reclamationEnvoyee = "Réclamation envoyée. Un admin Jolene va l'examiner."
    // source: ModaleReclamationScore.tsx l.181, l.185
    public static let annuler = "Annuler"
    public static let envoyer = "Envoyer"

    // source: ModaleReclamationScore.tsx l.23-28 (`MOTIFS` : valeur → libellé)
    public static func libelle(_ motif: MotifContestationScore) -> String {
        switch motif {
        case .urgenceMedicale: return "🏥 Urgence médicale"
        case .deuil: return "🕊️ Deuil"
        case .forceMajeure: return "⚡ Force majeure"
        case .erreurJolene: return "🔧 Erreur Jolene"
        case .contexteParticulier: return "📝 Contexte particulier"
        case .autre: return "❓ Autre"
        }
    }

    // source: ModaleReclamationScore.tsx l.120 (`{evenementInfo.points} pts`)
    public static func pointsEvenement(_ points: Double) -> String { "\(MissionPresentation.nombreJavaScript(points)) pts" }

    // source: ModaleReclamationScore.tsx l.140 (`{texte.length} / 20+`)
    public static func compteurTexte(_ longueur: Int) -> String { "\(longueur) / 20+" }

    // MARK: Textes natifs (non juridiques, sans équivalent web)

    /// Lecture impossible de la page (le web n'affiche rien) : libellé technique, vouvoiement sobre (D24).
    public static let chargementImpossible = "Votre score n’a pas pu être chargé."
    public static let reessayer = "Réessayer"
    /// Relecture qui ne montre pas l'événement contesté (PRINCIPES §3) : jamais un succès annoncé.
    public static let contestationNonConfirmee = "La contestation n’a pas pu être confirmée. Réessayez."

    /// Textes tutoyés du web et leur forme vouvoyée (décision 9 du lot 1), dans l'ordre des sources de
    /// `EvaluationsScoreVerbatimTests`.
    public static let vouvoiements: [(web: String, natif: String)] = [
        ("Ta fiabilité vue par les établissements. Mise à jour après chaque mission, notation ou litige.", sousTitre),
        ("6 composantes pondérées : Notation reçue (35%) · Présentéisme (20%) · Ponctualité (15%) · Réactivité (10%) · Ancienneté & volume (10%) · Tu notes les étabs (10%)",
         calculRegles[0]),
        ("Événements impactant ton score (12 derniers mois)", evenementsTitre),
        ("Tu penses qu'une pénalité est injuste ?", aucunEvenementTitre),
        ("Aucun événement impactant ton score n'a été enregistré sur les 12 derniers mois. Si tu constates une erreur, contacte le support Jolene.",
         aucunEvenementTexte),
        ("Sélectionne un motif.", motifRequis),
        ("Explique précisément la situation : que s'est-il passé, pourquoi cet événement ne devrait pas te pénaliser...",
         contestationPlaceholder),
        ("Ta réclamation sera examinée par un administrateur Jolene. La décision (annulation, réduction ou maintien) sera notifiée par email + push.",
         examenParAdmin),
    ]
}

/// Mise en forme de « Mon score » : règles d'affichage du web, valeurs serveur écrites telles quelles. Aucun calcul de
/// score, de contribution ni de niveau.
public enum ScorePresentation {
    /// `totalMissions < 3` (`PageScoreSoignant.tsx` l.100) : sous ce nombre de missions terminées, le web n'affiche pas
    /// le score (« Non noté »).
    public static let missionsAvantScore = 3
    /// Longueur minimale de l'explication (`texte.trim().length < 20`, `ModaleReclamationScore.tsx` l.81).
    public static let longueurTexteMin = 20

    /// `nonNote` du web : `Number(sg?.total_missions_terminees ?? 0) < 3` (l.89, l.100).
    public static func nonNote(_ breakdown: BreakdownScore) -> Bool {
        (breakdown.totalMissionsTerminees ?? 0) < missionsAvantScore
    }

    /// `Math.max(0, 3 - totalMissions)` (l.124), seulement quand le compte est servi : sans `total_missions_terminees`,
    /// `nil` (« Non noté » seul), jamais un nombre tiré d'un 0 par défaut (revue B8 des textes de la vague D, mineur 13).
    public static func missionsRestantes(_ breakdown: BreakdownScore) -> Int? {
        breakdown.totalMissionsTerminees.map { max(0, missionsAvantScore - $0) }
    }

    /// `Math.round(Number(breakdown.score_total))` (l.98) ; `nil` sans score servi (jamais 50).
    public static func score(_ breakdown: BreakdownScore) -> String? {
        breakdown.score.map(entier)
    }

    /// `{Math.round(c.pct ?? 0)}%` (`BreakdownScore.tsx` l.125) d'une composante active.
    public static func pourcentage(_ pct: Double) -> String { "\(entier(pct))%" }

    /// Part de la barre de progression (`Math.min(100, c.pct ?? 0)`, l.134), entre 0 et 1.
    public static func progression(_ pct: Double) -> Double { min(100, max(0, pct)) / 100 }

    /// `malusActifs || bonusActif` (l.78-79) : lignes de malus et de bonus à afficher, valeurs serveur.
    public static func malusEtBonus(_ breakdown: BreakdownScore) -> [String] {
        var lignes: [String] = []
        if let litiges = breakdown.litigesMalus, litiges < 0 { lignes.append(ScoreTextes.litigesMalus(litiges)) }
        if let absence = breakdown.absenceSansPrevenirMalus, absence < 0 { lignes.append(ScoreTextes.absenceMalus(absence)) }
        if let bonus = breakdown.bonusSuperActif, bonus > 0 { lignes.append(ScoreTextes.bonusSuperActif(bonus)) }
        return lignes
    }

    /// `ev.decision_admin ? 'Traitée' : 'Non contestable'` (`PageScoreSoignant.tsx` l.214) d'un événement non contestable.
    public static func etatNonContestable(_ evenement: EvenementScore) -> String {
        (evenement.decisionAdmin ?? "").isEmpty ? ScoreTextes.nonContestable : ScoreTextes.traitee
    }

    /// `format(new Date(ev.cree_le), "d MMMM yyyy 'à' HH:mm", { locale: fr })` (l.193), en heure de Paris.
    public static func dateEvenement(_ brut: String?) -> String? {
        guard let brut, let instant = try? DateHeureParis.instantJolene(brut) else { return nil }
        return DateHeureParis.format(instant, "d MMMM yyyy 'à' HH:mm")
    }

    /// `Mission terminée le {d MMM yyyy} · Notée par : Établissement anonyme · {d MMM}` (`NotationsRecues.tsx` l.85-87) ;
    /// une date illisible est omise avec son libellé.
    public static func metaNotation(_ notation: NotationRecue) -> String {
        var parties: [String] = []
        if let fin = notation.missionFinLe, let instant = try? DateHeureParis.instantJolene(fin) {
            parties.append(ScoreTextes.missionTermineeLe + DateHeureParis.format(instant, "d MMM yyyy"))
        }
        parties.append(ScoreTextes.noteePar + ScoreTextes.etablissementAnonyme)
        if let cree = notation.creeLe, let instant = try? DateHeureParis.instantJolene(cree) {
            parties.append(DateHeureParis.format(instant, "d MMM"))
        }
        return parties.joined(separator: " · ")
    }

    /// `texte.trim()` du web, ou `nil` s'il compte moins de vingt caractères (aucun appel alors).
    public static func texteValide(_ saisie: String) -> String? {
        let texte = saisie.trimmingCharacters(in: .whitespacesAndNewlines)
        return texte.count >= longueurTexteMin ? texte : nil
    }

    /// `Math.round` (demi vers +∞), écrit en entier — aussi `toFixed(0)` pour une valeur positive.
    static func entier(_ valeur: Double) -> String {
        guard valeur.isFinite, abs(valeur) < 1e15 else { return MissionPresentation.nombreJavaScript(valeur) }
        let bas = valeur.rounded(.down)
        return String(Int(valeur - bas >= 0.5 ? bas + 1 : bas))
    }
}
