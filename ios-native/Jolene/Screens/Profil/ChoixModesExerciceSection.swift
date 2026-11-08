import SwiftUI
import JoleneCore
import JoleneDesign

/// Rendu de `ChoixModesExercice` (port de `src/components/ChoixModesExercice.tsx`) : une case par mode
/// proposé, messages verbatim du web. Aucune règle ici : l'état vient du port pur et de la réponse de
/// `fn_types_exercice_autorises`. Point de fusion T8 : la complétion de l'inscription réutilise cette vue.
/// Identifiants : `<prefixe>-mode-salarie`, `<prefixe>-mode-liberal`, `<prefixe>-modes-chargement`,
/// `<prefixe>-modes-indisponible`, `<prefixe>-modes-reessayer`, `<prefixe>-modes-liberal-non-propose`,
/// `<prefixe>-modes-ancienne-preference`, `<prefixe>-modes-aucun`.
struct ChoixModesExerciceSection: View {
    let choix: ChoixModesExercice
    let prefixe: String
    let basculer: (PreferenceModeExercice, Bool) -> Void
    /// nil : aucune nouvelle tentative possible (référentiel non câblé), le bouton n'est pas affiché.
    let reessayer: (() -> Void)?

    private typealias Textes = ChoixModesExercice.Textes

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(Textes.titre)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
            Text(Textes.aide)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
            ForEach(choix.options) { option in
                ToggleRow(option.libelle,
                          isOn: Binding(get: { option.selectionne }, set: { basculer(option.mode, $0) }),
                          identifier: "\(prefixe)-mode-\(option.mode == .salarie ? "salarie" : "liberal")")
            }
            if choix.chargement {
                message(Textes.chargement, identifiant: "modes-chargement")
            }
            if choix.indisponible {
                message(Textes.indisponible, identifiant: "modes-indisponible")
                if let reessayer {
                    Button(Textes.reessayer, action: reessayer)
                        .font(JoleneFont.callout.weight(.semibold))
                        .foregroundStyle(JoleneColor.rose800)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("\(prefixe)-modes-reessayer")
                }
            }
            if choix.liberalNonPropose {
                message(Textes.liberalNonPropose, identifiant: "modes-liberal-non-propose")
            }
            if choix.anciennePreference {
                message(Textes.anciennePreference, identifiant: "modes-ancienne-preference", ton: JoleneColor.rose700)
            }
            if choix.aucunMode {
                message(Textes.aucunMode, identifiant: "modes-aucun")
            }
        }
    }

    private func message(_ texte: String, identifiant: String, ton: Color = JoleneColor.bubblegum) -> some View {
        Text(texte)
            .font(JoleneFont.caption)
            .foregroundStyle(ton)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("\(prefixe)-\(identifiant)")
    }
}
