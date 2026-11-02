import SwiftUI

/// Feuille de confirmation, port de `src/components/ModalConfirmation.tsx` (titre, message,
/// « Annuler » / « Confirmer », variante primaire ou danger) et du pied de
/// `RecapitulatifCandidatureDialog.tsx` (contenu libre au-dessus des boutons, fermeture
/// interdite pendant l'appel serveur). Aucune règle métier : la vue appelante décide quand
/// l'action est confirmée et ne déclare jamais un succès avant relecture serveur.
public struct ConfirmationSheet: View {
    public enum Variant: Equatable, Sendable { case primary, danger }

    /// Partie calculable de la feuille : libellés, variante et identifiants dérivés.
    public struct Configuration: Equatable, Sendable {
        public var title: String
        public var message: String
        public var confirmTitle: String
        public var cancelTitle: String
        public var variant: Variant
        /// Identifiant racine ; les contrôles reçoivent `<identifier>-title/-message/-confirm/-cancel`.
        public var identifier: String

        public init(title: String, message: String, confirmTitle: String = "Confirmer", cancelTitle: String = "Annuler",
                    variant: Variant = .primary, identifier: String) {
            self.title = title; self.message = message; self.confirmTitle = confirmTitle; self.cancelTitle = cancelTitle
            self.variant = variant; self.identifier = identifier
        }

        public var confirmButtonStyle: JoleneButton.Style { variant == .danger ? .destructive : .primary }
        public var titleIdentifier: String { "\(identifier)-title" }
        public var messageIdentifier: String { "\(identifier)-message" }
        public var confirmIdentifier: String { "\(identifier)-confirm" }
        public var cancelIdentifier: String { "\(identifier)-cancel" }

        /// `RecapitulatifCandidatureDialog` : `if (!open && !chargement) onFermer()`.
        public static func canDismiss(isLoading: Bool) -> Bool { !isLoading }
    }

    private let configuration: Configuration
    private let isLoading: Bool
    private let onCancel: () -> Void
    private let onConfirm: () -> Void
    private let extra: AnyView?

    public init(_ configuration: Configuration, isLoading: Bool = false,
                onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        self.configuration = configuration; self.isLoading = isLoading
        self.onCancel = onCancel; self.onConfirm = onConfirm; self.extra = nil
    }

    /// Variante avec contenu libre entre le message et les boutons (ex. `SlotList` du récapitulatif).
    public init<Extra: View>(_ configuration: Configuration, isLoading: Bool = false,
                             onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void,
                             @ViewBuilder extra: () -> Extra) {
        self.configuration = configuration; self.isLoading = isLoading
        self.onCancel = onCancel; self.onConfirm = onConfirm; self.extra = AnyView(extra())
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                Text(configuration.title)
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(configuration.titleIdentifier)
                Text(configuration.message)
                    .font(JoleneFont.body)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier(configuration.messageIdentifier)
                if let extra { extra }
                VStack(spacing: JoleneSpacing.sm) {
                    JoleneButton(configuration.confirmTitle, style: configuration.confirmButtonStyle, isLoading: isLoading, action: onConfirm)
                        .accessibilityIdentifier(configuration.confirmIdentifier)
                    JoleneButton(configuration.cancelTitle, style: .secondary, action: onCancel)
                        .disabled(!Configuration.canDismiss(isLoading: isLoading))
                        .accessibilityIdentifier(configuration.cancelIdentifier)
                }
                .padding(.top, JoleneSpacing.sm)
            }
            .padding(JoleneSpacing.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(JoleneColor.cloud.ignoresSafeArea())
        .interactiveDismissDisabled(!Configuration.canDismiss(isLoading: isLoading))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(configuration.identifier)
    }
}

public extension View {
    /// Présente une `ConfirmationSheet` en feuille modale. `onConfirm` ne ferme pas la feuille :
    /// l'appelant la referme (`isPresented = false`) après la réponse serveur, ou affiche l'erreur.
    func confirmationSheet(isPresented: Binding<Bool>, _ configuration: ConfirmationSheet.Configuration,
                           isLoading: Bool = false, onConfirm: @escaping () -> Void) -> some View {
        sheet(isPresented: isPresented) {
            ConfirmationSheet(configuration, isLoading: isLoading,
                              onCancel: { if ConfirmationSheet.Configuration.canDismiss(isLoading: isLoading) { isPresented.wrappedValue = false } },
                              onConfirm: onConfirm)
        }
    }
}
