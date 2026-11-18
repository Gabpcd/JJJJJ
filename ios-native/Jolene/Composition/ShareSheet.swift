import SwiftUI
import UIKit
import JoleneDesign

/// Partage système du lot 4 (L4-T1c, `docs/mobile-swift/LOT4_PLAN.md` §2.1) : `UIActivityViewController`, posé une fois
/// pour T6 (lien de parrainage, message verbatim du web) et T10 (copie de bulletin, fichier temporaire protégé supprimé
/// au retour), qui l'utilisent en parallèle sans le modifier. Aucun appelant tant que ces tranches ne sont pas livrées.
///
/// Démo : double sans effet ni réseau qui journalise les éléments (`partage-demo`, `partage-demo-elements`, valeur =
/// descriptions jointes par un saut de ligne) et se ferme (`partage-demo-fermer`) ; jamais de partage réel en démo.
/// Choix posé à la racine, comme les pages web (`presentationPageWeb` : `.doubleDemo` en démo).
struct ElementsPartage: Identifiable {
    let id = UUID()
    /// Éléments remis à `UIActivityViewController` : texte, `URL` d'un lien ou d'un fichier local.
    let elements: [Any]

    /// Description montrable (démo) : texte tel quel, lien par son URL, fichier local par son nom (jamais son chemin).
    var descriptions: [String] {
        elements.map { element in
            if let url = element as? URL { return url.isFileURL ? url.lastPathComponent : url.absoluteString }
            return String(describing: element)
        }
    }
}

extension View {
    /// Présente la feuille de partage tant que `partage` n'est pas nil ; `fin` est appelé à sa fermeture (partage fait
    /// ou abandonné), pour que l'écran supprime un fichier temporaire.
    func feuillePartage(_ partage: Binding<ElementsPartage?>, fin: @escaping () -> Void = {}) -> some View {
        modifier(FeuillePartage(partage: partage, fin: fin))
    }
}

private struct FeuillePartage: ViewModifier {
    @Binding var partage: ElementsPartage?
    let fin: () -> Void
    @Environment(\.presentationPageWeb) private var presentation

    func body(content: Content) -> some View {
        content.sheet(item: $partage, onDismiss: fin) { elements in
            switch presentation {
            case .doubleDemo:
                PartageDemo(elements: elements) { partage = nil }
            case .safari:
                PartageSysteme(elements: elements) { partage = nil }
                    .ignoresSafeArea()
            }
        }
    }
}

/// `UIActivityViewController` : la fin de l'activité (partagée ou annulée) ferme la feuille.
private struct PartageSysteme: UIViewControllerRepresentable {
    let elements: ElementsPartage
    let fermer: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controleur = UIActivityViewController(activityItems: elements.elements, applicationActivities: nil)
        // Appelé par UIKit sur le fil principal.
        controleur.completionWithItemsHandler = { _, _, _, _ in fermer() }
        return controleur
    }

    func updateUIViewController(_ controleur: UIActivityViewController, context: Context) {}
}

/// Double démo du partage : éléments journalisés, lus par les XCUITest, aucun effet.
private struct PartageDemo: View {
    let elements: ElementsPartage
    let fermer: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                ForEach(Array(elements.descriptions.enumerated()), id: \.offset) { _, description in
                    Text(description)
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.midnight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("partage-demo-elements")
            .accessibilityValue(elements.descriptions.joined(separator: "\n"))
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(JoleneColor.softGradient.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", action: fermer)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("partage-demo-fermer")
                }
            }
        }
        .accessibilityIdentifier("partage-demo")
    }
}
