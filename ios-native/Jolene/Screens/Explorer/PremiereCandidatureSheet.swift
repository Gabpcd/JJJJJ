import SwiftUI
import JoleneCore
import JoleneDesign

/// Feuille « première candidature » de la vue Swipe (lot 4, T3b ; HARD STOP n°4, portée d'engagement), port de la
/// feuille pédagogique de `VueSwipeMissions.tsx` (l.534-566). Affichée une seule fois par compte, après le
/// récapitulatif exact et avant le premier ❤️ envoyé (`ParcoursCandidatureSwipe`).
///
/// **Aucun texte n'est écrit ici** : titre, description, paragraphe, puces et boutons sont ceux de
/// `TextesWeb.PremiereCandidature`, repris mot pour mot du web (tutoiement compris) et gardés au caractère près par
/// `tests/node/textes-juridiques-ios.node.mjs` ; `SwipeSourcesAppTests` refuse tout littéral de texte dans ce fichier.
/// Le paragraphe garde les deux passages en gras du web ; VoiceOver et les tests lisent le rendu assemblé
/// (`acceptation`).
///
/// « J'ai compris — envoyer ma candidature » envoie la candidature (bouton en attente pendant l'appel) ; « Pas
/// maintenant » referme sans rien envoyer ni mémoriser : la feuille reviendra au prochain ❤️.
///
/// Identifiants : `swipe-premiere-candidature` ; `swipe-premiere-titre`, `swipe-premiere-description`,
/// `swipe-premiere-acceptation`, `swipe-premiere-engagement-<n>`, `swipe-premiere-confirmer`, `swipe-premiere-annuler`.
struct PremiereCandidatureSheet: View {
    let envoiEnCours: Bool
    let onConfirmer: () -> Void
    let onPasMaintenant: () -> Void

    private typealias Textes = TextesWeb.PremiereCandidature

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                Text(Textes.titre)
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("swipe-premiere-titre")
                Text(Textes.description)
                    .font(JoleneFont.body)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("swipe-premiere-description")
                acceptation
                VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                    ForEach(Array(Textes.engagements.enumerated()), id: \.offset) { rang, engagement in
                        HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .padding(.top, 6)
                                .accessibilityHidden(true)
                            Text(engagement)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("swipe-premiere-engagement-\(rang + 1)")
                    }
                }
                VStack(spacing: JoleneSpacing.sm) {
                    JoleneButton(Textes.confirmer, isLoading: envoiEnCours, action: onConfirmer)
                        .disabled(envoiEnCours)
                        .accessibilityIdentifier("swipe-premiere-confirmer")
                    JoleneButton(Textes.pasMaintenant, style: .secondary, action: onPasMaintenant)
                        .disabled(envoiEnCours)
                        .accessibilityIdentifier("swipe-premiere-annuler")
                }
                .padding(.top, JoleneSpacing.sm)
            }
            .padding(JoleneSpacing.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(JoleneColor.cloud.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("swipe-premiere-candidature")
    }

    /// Paragraphe du web : gras, texte, gras, texte ; le libellé vocalisé est le rendu assemblé.
    private var acceptation: some View {
        (Text(Textes.acceptationDirecte).bold() + Text(" ") + Text(Textes.acceptationSiCas) + Text(" ")
            + Text(Textes.acceptationConfirmee).bold() + Text(" ") + Text(Textes.acceptationCompteSurToi))
            .font(JoleneFont.body)
            .foregroundStyle(JoleneColor.midnight)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(Textes.acceptation)
            .accessibilityIdentifier("swipe-premiere-acceptation")
    }
}
