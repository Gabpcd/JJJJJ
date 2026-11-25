import SwiftUI
import JoleneCore
import JoleneDesign

/// Point d'entrée des disponibilités dans Explorer (intégration de la vague D, décision d, `DECISIONS_LOT4.md`
/// précision 18) : l'icône calendrier du web (`RechercheMissions.tsx` l.309-316, `aria-label` « Mes disponibilités »),
/// en tête de la rangée de chips d'Explorer, sur tous les formats (la barre de navigation tient déjà la cloche de
/// l'alerte rapide, « Mes favoris » et « Filtres »). Ouvre `.secondaire(.disponibilites)` par `contexteSecondaire.ouvrir`
/// (écran empilé sur le Profil, coupe-circuit lu par `SecondaryRouter`). Rien n'est rendu hors de l'espace prêt ou si
/// l'écran n'est pas livré.
///
/// Identifiant : `explorer-disponibilites`.
struct ExplorerDisponibilitesButton: View {
    static let libelle = "Mes disponibilités"

    @Environment(\.contexteSecondaire) private var contexte

    var body: some View {
        if let contexte, EcranSecondaire.disponibilites.estLivre {
            Button { contexte.ouvrir(.secondaire(.disponibilites)) } label: {
                Image(systemName: "calendar")
                    .foregroundStyle(JoleneColor.rose700)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(ExplorerActions.Pastille())
            .accessibilityLabel(Self.libelle)
            .accessibilityIdentifier("explorer-disponibilites")
        }
    }
}
