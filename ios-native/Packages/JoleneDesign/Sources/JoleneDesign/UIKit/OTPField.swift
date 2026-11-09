import SwiftUI
import UIKit

/// Champ OTP UIKit (six chiffres, clavier numérique, `oneTimeCode`), repris du témoin
/// `mobile-native/ios-ui-tests/UIKitOtpReference/UIKitOtpReference.swift` : UIKit n'a pas
/// de longueur maximale, le délégué refuse tout remplacement qui dépasserait six caractères
/// sans tronquer. Branché par la signature de contrat (lot 2, T9b) : libellé d'accessibilité fourni par l'écran (texte
/// du web), champ désactivé quand l'environnement SwiftUI l'est (`.disabled`).
public struct OTPField: UIViewRepresentable {
    nonisolated public static let maximumLength = 6

    /// Libellé d'accessibilité du lot 0, quand l'écran n'en fournit pas.
    nonisolated public static let libelleParDefaut = "Code de signature, six chiffres"

    @Binding private var code: String
    private let identifier: String
    private let accessibilityLabel: String
    private let onComplete: (String) -> Void

    public init(code: Binding<String>, identifier: String = "contract-otp", accessibilityLabel: String = OTPField.libelleParDefaut,
                onComplete: @escaping (String) -> Void = { _ in }) {
        self._code = code; self.identifier = identifier; self.accessibilityLabel = accessibilityLabel; self.onComplete = onComplete
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.accessibilityIdentifier = identifier
        field.accessibilityLabel = accessibilityLabel
        field.placeholder = "6 chiffres"
        field.borderStyle = .roundedRect
        field.keyboardType = .numberPad
        field.textContentType = .oneTimeCode
        field.autocorrectionType = .no
        // Aucun apprentissage ni correction du code (jamais gardé hors de la mémoire de la session).
        field.spellCheckingType = .no
        field.smartInsertDeleteType = .no
        field.isSecureTextEntry = false
        field.clearsOnInsertion = false
        field.returnKeyType = .default
        field.font = .monospacedDigitSystemFont(ofSize: 24, weight: .semibold)
        field.textAlignment = .center
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    public func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != code { field.text = code }
        field.accessibilityLabel = accessibilityLabel
        // `.disabled(true)` de SwiftUI n'atteint pas un `UITextField` enveloppé : l'état vient de l'environnement.
        let actif = context.environment.isEnabled
        if field.isEnabled != actif {
            field.isEnabled = actif
            if !actif, field.isFirstResponder { field.resignFirstResponder() }
        }
    }

    @MainActor public final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: OTPField
        init(_ parent: OTPField) { self.parent = parent }

        public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                              replacementString string: String) -> Bool {
            Self.allows(current: textField.text ?? "", range: range, replacement: string)
        }

        /// Règle pure du témoin : refuse (ne tronque pas) un remplacement qui dépasserait six chiffres.
        nonisolated static func allows(current: String, range: NSRange, replacement: String) -> Bool {
            let length = current.utf16.count
            let validRange = range.location <= length && range.length <= length - range.location
            let nextLength = validRange ? length - range.length + replacement.utf16.count : -1
            let digitsOnly = replacement.allSatisfy { $0.isNumber }
            return validRange && digitsOnly && nextLength <= OTPField.maximumLength
        }

        @objc func editingChanged(_ field: UITextField) {
            let value = field.text ?? ""
            parent.code = value
            if value.count == OTPField.maximumLength { parent.onComplete(value) }
        }
    }
}
