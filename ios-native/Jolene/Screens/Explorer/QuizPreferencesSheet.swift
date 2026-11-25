import SwiftUI
import JoleneCore
import JoleneDesign

/// Quiz de préférences du premier contact avec la vue Swipe (lot 4, T3b ; décisions D6 et D26), port de
/// `QuizPreferencesSwipe.tsx` : horaires, rythme, distance, taux minimum. Vue de `ReponsesQuizSwipe` et de `QuizSwipe`
/// (JoleneCore), qui portent les options, les textes et les règles (préférences dans [0, 1], critères d'Explorer
/// dérivés des réponses) ; la vue n'ajoute aucune logique.
///
/// **Sans la question « missions urgentes » du web** (D26) : le web active alors le pool urgence par une écriture
/// directe de `soignants.disponible_urgence`, sans le contrôle documentaire ni le consentement de
/// `fn_toggle_pool_urgence`. Le quiz natif n'écrit jamais cette colonne ; il propose seulement d'ouvrir l'écran Pool
/// urgence (`swipe-quiz-pool-urgence`, rendu seulement si la cible est présentable), où l'activation passe par la RPC.
///
/// « C'est parti 🚀 » envoie les préférences (au mieux, comme le web) puis applique les critères à Explorer ; « Plus
/// tard » ou la fermeture de la feuille mémorise que le quiz a été proposé : il ne revient plus.
///
/// Identifiants : `swipe-quiz` ; `swipe-quiz-horaire-<jour|nuit|tous>`, `swipe-quiz-rythme-<semaine|weekend|tous>`,
/// `swipe-quiz-rayon-<km>`, `swipe-quiz-taux-<euros>`, `swipe-quiz-pool-urgence`, `swipe-quiz-valider`,
/// `swipe-quiz-plus-tard`.
struct QuizPreferencesSheet: View {
    let envoiEnCours: Bool
    /// `nil` : cible non présentable, le renvoi vers Pool urgence n'est pas rendu (jamais un bouton sans effet).
    let ouvrirPoolUrgence: (() -> Void)?
    let onValider: (ReponsesQuizSwipe) -> Void
    let onPlusTard: () -> Void

    @State private var reponses = ReponsesQuizSwipe()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                Text(QuizSwipe.titre)
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("swipe-quiz-titre")
                Text(QuizSwipe.description)
                    .font(JoleneFont.body)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                question(QuizSwipe.questionHoraire, identifiant: "swipe-quiz-horaire") {
                    ForEach(QuizSwipe.horaires) { option in
                        FilterChip(option.titre, isSelected: reponses.horaire == option.valeur,
                                   identifier: "swipe-quiz-horaire-\(option.identifiant)") { reponses.horaire = option.valeur }
                    }
                }
                question(QuizSwipe.questionRythme, identifiant: "swipe-quiz-rythme") {
                    ForEach(QuizSwipe.rythmes) { option in
                        FilterChip(option.titre, isSelected: reponses.rythme == option.valeur,
                                   identifier: "swipe-quiz-rythme-\(option.identifiant)") { reponses.rythme = option.valeur }
                    }
                }
                question(QuizSwipe.questionRayon, identifiant: "swipe-quiz-rayon") {
                    ForEach(QuizSwipe.rayons) { option in
                        FilterChip(option.titre, isSelected: reponses.rayonKm == option.valeur,
                                   identifier: "swipe-quiz-rayon-\(option.identifiant)") { reponses.rayonKm = option.valeur }
                    }
                }
                question(QuizSwipe.questionTaux, identifiant: "swipe-quiz-taux") {
                    ForEach(QuizSwipe.taux) { option in
                        FilterChip(option.titre, isSelected: reponses.tauxMin == option.valeur,
                                   identifier: "swipe-quiz-taux-\(option.identifiant)") { reponses.tauxMin = option.valeur }
                    }
                }
                if let ouvrirPoolUrgence {
                    VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                        Text(QuizSwipe.poolUrgenceTexte)
                            .font(JoleneFont.callout)
                            .foregroundStyle(JoleneColor.bubblegum)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(QuizSwipe.poolUrgenceAction, action: ouvrirPoolUrgence)
                            .font(JoleneFont.callout.weight(.semibold))
                            .tint(JoleneColor.rose800)
                            .frame(minHeight: 44)
                            .disabled(envoiEnCours)
                            .accessibilityIdentifier("swipe-quiz-pool-urgence")
                    }
                }
                VStack(spacing: JoleneSpacing.sm) {
                    JoleneButton(QuizSwipe.valider, isLoading: envoiEnCours) { onValider(reponses) }
                        .disabled(envoiEnCours)
                        .accessibilityIdentifier("swipe-quiz-valider")
                    JoleneButton(QuizSwipe.plusTard, style: .secondary, action: onPlusTard)
                        .disabled(envoiEnCours)
                        .accessibilityIdentifier("swipe-quiz-plus-tard")
                }
                .padding(.top, JoleneSpacing.sm)
            }
            .padding(JoleneSpacing.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(JoleneColor.cloud.ignoresSafeArea())
        .interactiveDismissDisabled(envoiEnCours)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("swipe-quiz")
    }

    /// Une question et sa rangée de réponses (une seule réponse active, comme les `Chip` du web).
    private func question<Reponses: View>(_ titre: String, identifiant: String,
                                           @ViewBuilder reponses: () -> Reponses) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(titre)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .fixedSize(horizontal: false, vertical: true)
            // La rangée porte sa propre marge horizontale (défilement bord à bord) : alignée ici sur le titre.
            FilterChipRow(identifier: identifiant, content: reponses)
                .padding(.horizontal, -JoleneSpacing.lg)
        }
    }
}
