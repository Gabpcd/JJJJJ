import SwiftUI
import UIKit

/// Nature d'un champ de saisie, portée de `src/lib/inputMobile.ts` (`PROPS_INPUT_*`).
/// Chaque cas fixe clavier, autocomplétion iOS, capitalisation et touche Entrée.
public enum JoleneInputKind: String, CaseIterable, Sendable {
    case email, telephone, otp, montant, entier, nir, siret, codePostal, recherche, nom, prenom, motDePasse, nouveauMotDePasse
}

/// Touche Entrée (`enterKeyHint` web), indépendante de SwiftUI pour rester comparable en test.
public enum JoleneSubmitLabel: Equatable, Sendable {
    case next, go, search, done

    public var swiftUI: SubmitLabel {
        switch self {
        case .next: return .next
        case .go: return .go
        case .search: return .search
        case .done: return .done
        }
    }
}

/// Traits de clavier résolus pour un `JoleneInputKind`. Structure pure, testable sans vue.
public struct JoleneInputTraits: Equatable, Sendable {
    public var keyboard: UIKeyboardType
    public var contentType: UITextContentType?
    public var autocapitalization: UITextAutocapitalizationType
    public var autocorrection: Bool
    public var submitLabel: JoleneSubmitLabel
    public var isSecure: Bool
    public var maxLength: Int?

    public static func resolve(_ kind: JoleneInputKind) -> JoleneInputTraits {
        switch kind {
        case .email:
            return .init(keyboard: .emailAddress, contentType: .emailAddress, autocapitalization: .none, autocorrection: false, submitLabel: .next, isSecure: false, maxLength: nil)
        case .telephone:
            return .init(keyboard: .phonePad, contentType: .telephoneNumber, autocapitalization: .none, autocorrection: false, submitLabel: .next, isSecure: false, maxLength: nil)
        case .otp:
            return .init(keyboard: .numberPad, contentType: .oneTimeCode, autocapitalization: .none, autocorrection: false, submitLabel: .go, isSecure: false, maxLength: 6)
        case .montant:
            return .init(keyboard: .decimalPad, contentType: nil, autocapitalization: .none, autocorrection: false, submitLabel: .next, isSecure: false, maxLength: nil)
        case .entier:
            return .init(keyboard: .numberPad, contentType: nil, autocapitalization: .none, autocorrection: false, submitLabel: .next, isSecure: false, maxLength: nil)
        case .nir:
            return .init(keyboard: .numberPad, contentType: nil, autocapitalization: .none, autocorrection: false, submitLabel: .next, isSecure: false, maxLength: 18)
        case .siret:
            return .init(keyboard: .numberPad, contentType: nil, autocapitalization: .none, autocorrection: false, submitLabel: .next, isSecure: false, maxLength: 17)
        case .codePostal:
            return .init(keyboard: .numberPad, contentType: .postalCode, autocapitalization: .none, autocorrection: false, submitLabel: .next, isSecure: false, maxLength: 5)
        case .recherche:
            return .init(keyboard: .webSearch, contentType: nil, autocapitalization: .sentences, autocorrection: true, submitLabel: .search, isSecure: false, maxLength: nil)
        case .nom:
            return .init(keyboard: .default, contentType: .familyName, autocapitalization: .words, autocorrection: false, submitLabel: .next, isSecure: false, maxLength: nil)
        case .prenom:
            return .init(keyboard: .default, contentType: .givenName, autocapitalization: .words, autocorrection: false, submitLabel: .next, isSecure: false, maxLength: nil)
        case .motDePasse:
            return .init(keyboard: .default, contentType: .password, autocapitalization: .none, autocorrection: false, submitLabel: .go, isSecure: true, maxLength: nil)
        case .nouveauMotDePasse:
            return .init(keyboard: .default, contentType: .newPassword, autocapitalization: .none, autocorrection: false, submitLabel: .next, isSecure: true, maxLength: nil)
        }
    }
}

/// Champ de saisie Jolene : libellé au-dessus, bordure rose au focus, 16 pt minimum (pas de zoom iOS).
public struct JoleneTextField: View {
    private let label: String
    private let placeholder: String
    private let kind: JoleneInputKind
    private let identifier: String?
    @Binding private var text: String
    @FocusState private var focused: Bool
    private let onSubmit: () -> Void

    public init(_ label: String, text: Binding<String>, kind: JoleneInputKind, placeholder: String = "",
                identifier: String? = nil, onSubmit: @escaping () -> Void = {}) {
        self.label = label; self._text = text; self.kind = kind; self.placeholder = placeholder
        self.identifier = identifier; self.onSubmit = onSubmit
    }

    public var body: some View {
        let traits = JoleneInputTraits.resolve(kind)
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(label).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
            field(traits)
                .font(.system(size: 16))
                .keyboardType(traits.keyboard)
                .textContentType(traits.contentType)
                .textInputAutocapitalization(autocap(traits.autocapitalization))
                .autocorrectionDisabled(!traits.autocorrection)
                .submitLabel(traits.submitLabel.swiftUI)
                .focused($focused)
                .onSubmit(onSubmit)
                .onChange(of: text) { value in
                    if let max = traits.maxLength, value.count > max { text = String(value.prefix(max)) }
                }
                .padding(.horizontal, JoleneSpacing.lg)
                .frame(minHeight: 48)
                .background(JoleneColor.cloud)
                .overlay(
                    RoundedRectangle(cornerRadius: JoleneRadius.field)
                        .strokeBorder(focused ? JoleneColor.rose : JoleneColor.bubblegum.opacity(0.35), lineWidth: focused ? 2 : 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier ?? "")
        }
    }

    @ViewBuilder private func field(_ traits: JoleneInputTraits) -> some View {
        if traits.isSecure {
            SecureField(placeholder, text: $text)
        } else {
            TextField(placeholder, text: $text)
        }
    }

    private func autocap(_ value: UITextAutocapitalizationType) -> TextInputAutocapitalization {
        switch value {
        case .words: return .words
        case .sentences: return .sentences
        case .allCharacters: return .characters
        default: return .never
        }
    }
}
