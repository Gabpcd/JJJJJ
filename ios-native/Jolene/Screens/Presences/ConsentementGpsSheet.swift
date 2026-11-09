import SwiftUI
import JoleneCore
import JoleneDesign

/// Feuille de consentement à la géolocalisation (lot 2, T4b ; décision 4), port de `ConsentementGPS.tsx` l.16-71 :
/// textes verbatim de `TextesWeb.ConsentementGps` (HARD STOP n°4, tranche TL), dans l'ordre du web (titre, description,
/// « Ce que nous faisons », « Ce que nous ne faisons pas », base légale, « Je refuse », « Autoriser la localisation »).
/// Ouverte avant le premier pointage quand `soignants.consentement_gps` est NULL (décision 4 ; écart assumé et consigné,
/// seconde revue fraîche de T4b, m4 : le web vivant ne la présente jamais, `pointerArrivee` qui l'ouvre, l.306-313, n'est
/// pas appelé, et `PointageRotatifSoignant.tsx` l.123 pointe sans GPS) ; aucune autorisation iOS n'est demandée
/// avant un « Autoriser » (le modèle la demande après la relecture). Choix explicite exigé : la feuille ne se ferme pas
/// d'un glissement (écart assumé : le dialogue web traite une fermeture comme un refus, l.18 ; ici aucun choix n'est
/// enregistré sans un bouton). Identifiants : `gps-consent-sheet`, `gps-consent-accepter`, `gps-consent-refuser`.
struct ConsentementGpsSheet: View {
    private typealias T = TextesWeb.ConsentementGps

    let enCours: Bool
    let accepter: () -> Void
    let refuser: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                Image(systemName: "mappin.and.ellipse")
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.rose700)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                Text(T.titre)
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(T.description)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                liste(titre: T.ceQueNousFaisonsTitre, elements: T.ceQueNousFaisons, fond: JoleneColor.mauve100)
                liste(titre: T.ceQueNousNeFaisonsPasTitre, elements: T.ceQueNousNeFaisonsPas, fond: JoleneColor.rose100)
                Text(T.baseLegale)
                    .font(JoleneFont.caption.italic())
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: JoleneSpacing.md) { boutons }
                    VStack(spacing: JoleneSpacing.sm) { boutons }
                }
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .interactiveDismissDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gps-consent-sheet")
    }

    @ViewBuilder private var boutons: some View {
        JoleneButton(T.refuser, style: .secondary) { refuser() }
            .disabled(enCours)
            .accessibilityIdentifier("gps-consent-refuser")
        JoleneButton(T.accepter, isLoading: enCours) { accepter() }
            .disabled(enCours)
            .accessibilityIdentifier("gps-consent-accepter")
    }

    private func liste(titre: String, elements: [String], fond: Color) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(titre)
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.midnight)
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.xs) {
                    Text(verbatim: "•").accessibilityHidden(true)
                    Text(element).fixedSize(horizontal: false, vertical: true)
                }
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
            }
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: JoleneRadius.card).fill(fond))
    }
}
