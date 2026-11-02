import SwiftUI

/// Feuille de confirmation, port de `src/components/ModalConfirmation.tsx` (titre, message,
/// « Annuler » / « Confirmer », variante primaire ou danger), du pied de
/// `RecapitulatifCandidatureDialog.tsx` (contenu libre au-dessus des boutons, fermeture
/// interdite pendant l'appel serveur, confirmation désactivée tant que le planning n'est pas
/// exact) et de la saisie « SUPPRIMER » de `SectionConfidentialite.tsx` (égalité stricte).
/// Aucune règle métier : la vue appelante décide quand l'action est confirmée et ne déclare
/// jamais un succès avant relecture serveur. Les textes juridiques arrivent verbatim de l'appelant.
public struct ConfirmationSheet: View {
    public enum Variant: Equatable, Sendable { case primary, danger }

    /// Partie calculable de la feuille : libellés, variante, phrase exigée et identifiants dérivés.
    public struct Configuration: Equatable, Sendable {
        public var title: String
        public var message: String
        public var confirmTitle: String
        public var cancelTitle: String
        public var variant: Variant
        /// Identifiant racine ; les contrôles reçoivent `<identifier>-title/-message/-input/-confirm/-cancel`.
        public var identifier: String
        /// Phrase à saisir à l'identique avant de confirmer (ex. « SUPPRIMER »), `nil` = aucun champ.
        public var requiredPhrase: String?
        /// Libellé du champ de saisie ; par défaut « Saisissez <phrase> pour confirmer ».
        public var phrasePrompt: String?

        public init(title: String, message: String, confirmTitle: String = "Confirmer", cancelTitle: String = "Annuler",
                    variant: Variant = .primary, identifier: String, requiredPhrase: String? = nil, phrasePrompt: String? = nil) {
            self.title = title; self.message = message; self.confirmTitle = confirmTitle; self.cancelTitle = cancelTitle
            self.variant = variant; self.identifier = identifier
            self.requiredPhrase = requiredPhrase; self.phrasePrompt = phrasePrompt
        }

        public var confirmButtonStyle: JoleneButton.Style { variant == .danger ? .destructive : .primary }
        public var titleIdentifier: String { "\(identifier)-title" }
        public var messageIdentifier: String { "\(identifier)-message" }
        public var inputIdentifier: String { "\(identifier)-input" }
        public var confirmIdentifier: String { "\(identifier)-confirm" }
        public var cancelIdentifier: String { "\(identifier)-cancel" }

        /// Libellé du champ, `nil` quand aucune phrase n'est exigée.
        public var resolvedPhrasePrompt: String? {
            guard let requiredPhrase else { return nil }
            return phrasePrompt ?? "Saisissez \(requiredPhrase) pour confirmer"
        }

        /// `RecapitulatifCandidatureDialog` : `disabled={chargement || !planning.exact}` ;
        /// `SectionConfidentialite` : `deleteConfirmText !== 'SUPPRIMER'` (sans casse ni espaces tolérés).
        public func canConfirm(isLoading: Bool, isConfirmEnabled: Bool, typedPhrase: String) -> Bool {
            guard !isLoading, isConfirmEnabled else { return false }
            guard let requiredPhrase else { return true }
            return typedPhrase == requiredPhrase
        }

        /// `RecapitulatifCandidatureDialog` : `if (!open && !chargement) onFermer()`.
        public static func canDismiss(isLoading: Bool) -> Bool { !isLoading }
    }

    /// Fermeture demandée (« Annuler ») : appliquée seulement hors chargement. Garde unique des deux
    /// variantes du modificateur `.confirmationSheet`.
    nonisolated static func requestDismiss(isLoading: Bool, close: () -> Void) {
        guard Configuration.canDismiss(isLoading: isLoading) else { return }
        close()
    }

    private let configuration: Configuration
    private let isLoading: Bool
    private let isConfirmEnabled: Bool
    private let onCancel: () -> Void
    private let onConfirm: () -> Void
    private let extra: AnyView?
    @State private var typedPhrase = ""
    @FocusState private var phraseFocused: Bool

    public init(_ configuration: Configuration, isLoading: Bool = false, isConfirmEnabled: Bool = true,
                onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        self.configuration = configuration; self.isLoading = isLoading; self.isConfirmEnabled = isConfirmEnabled
        self.onCancel = onCancel; self.onConfirm = onConfirm; self.extra = nil
    }

    /// Variante avec contenu libre entre le message et les boutons (ex. `SlotList` du récapitulatif).
    public init<Extra: View>(_ configuration: Configuration, isLoading: Bool = false, isConfirmEnabled: Bool = true,
                             onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void,
                             @ViewBuilder extra: () -> Extra) {
        self.configuration = configuration; self.isLoading = isLoading; self.isConfirmEnabled = isConfirmEnabled
        self.onCancel = onCancel; self.onConfirm = onConfirm; self.extra = AnyView(extra())
    }

    public var body: some View {
        let peutConfirmer = configuration.canConfirm(isLoading: isLoading, isConfirmEnabled: isConfirmEnabled,
                                                     typedPhrase: typedPhrase)
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
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(configuration.messageIdentifier)
                if let extra { extra }
                if let prompt = configuration.resolvedPhrasePrompt, let phrase = configuration.requiredPhrase {
                    phraseField(prompt: prompt, placeholder: phrase)
                }
                VStack(spacing: JoleneSpacing.sm) {
                    JoleneButton(configuration.confirmTitle, style: configuration.confirmButtonStyle, isLoading: isLoading) {
                        // Double garde : le bouton est déjà désactivé, la règle est revérifiée au tap.
                        guard configuration.canConfirm(isLoading: isLoading, isConfirmEnabled: isConfirmEnabled,
                                                       typedPhrase: typedPhrase) else { return }
                        onConfirm()
                    }
                    .disabled(!peutConfirmer)
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
        .scrollDismissesKeyboard(.interactively)
        .background(JoleneColor.cloud.ignoresSafeArea())
        .interactiveDismissDisabled(!Configuration.canDismiss(isLoading: isLoading))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(configuration.identifier)
    }

    /// Champ de la phrase exigée : majuscules, sans correction ni suggestion (aucun `textContentType`),
    /// 16 pt minimum (pas de zoom iOS), bordure rose au focus comme `JoleneTextField`.
    private func phraseField(prompt: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(prompt).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
            TextField(placeholder, text: $typedPhrase)
                .font(.system(size: 16))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .submitLabel(.done)
                .focused($phraseFocused)
                .disabled(isLoading)
                .padding(.horizontal, JoleneSpacing.lg)
                .frame(minHeight: 48)
                .background(JoleneColor.lavender)
                .overlay(
                    RoundedRectangle(cornerRadius: JoleneRadius.field)
                        .strokeBorder(phraseFocused ? JoleneColor.rose : JoleneColor.bubblegum.opacity(0.35),
                                      lineWidth: phraseFocused ? 2 : 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                .accessibilityLabel(prompt)
                .accessibilityIdentifier(configuration.inputIdentifier)
        }
    }
}

public extension View {
    /// Présente une `ConfirmationSheet` en feuille modale. `onConfirm` ne ferme pas la feuille :
    /// l'appelant la referme (`isPresented = false`) après la réponse serveur, ou affiche l'erreur.
    /// Fermeture (« Annuler », geste) interdite pendant le chargement.
    func confirmationSheet(isPresented: Binding<Bool>, _ configuration: ConfirmationSheet.Configuration,
                           isLoading: Bool = false, isConfirmEnabled: Bool = true,
                           onConfirm: @escaping () -> Void) -> some View {
        sheet(isPresented: isPresented) {
            ConfirmationSheet(configuration, isLoading: isLoading, isConfirmEnabled: isConfirmEnabled,
                              onCancel: { ConfirmationSheet.requestDismiss(isLoading: isLoading) { isPresented.wrappedValue = false } },
                              onConfirm: onConfirm)
        }
    }

    /// Variante avec contenu libre entre le message et les boutons (ex. `SlotList` du récapitulatif
    /// de candidature), même garde de fermeture pendant le chargement.
    func confirmationSheet<Extra: View>(isPresented: Binding<Bool>, _ configuration: ConfirmationSheet.Configuration,
                                        isLoading: Bool = false, isConfirmEnabled: Bool = true,
                                        onConfirm: @escaping () -> Void,
                                        @ViewBuilder extra: @escaping () -> Extra) -> some View {
        sheet(isPresented: isPresented) {
            ConfirmationSheet(configuration, isLoading: isLoading, isConfirmEnabled: isConfirmEnabled,
                              onCancel: { ConfirmationSheet.requestDismiss(isLoading: isLoading) { isPresented.wrappedValue = false } },
                              onConfirm: onConfirm, extra: extra)
        }
    }
}
