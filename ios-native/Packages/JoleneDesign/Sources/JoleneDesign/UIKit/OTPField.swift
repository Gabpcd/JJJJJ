import SwiftUI
import UIKit

/// Champ OTP UIKit (six chiffres, clavier numérique, `oneTimeCode`), repris du témoin
/// `mobile-native/ios-ui-tests/UIKitOtpReference/UIKitOtpReference.swift` : UIKit n'a pas
/// de longueur maximale, le délégué refuse tout remplacement qui dépasserait six caractères
/// sans tronquer. Non branché à un écran au lot 0 (signature de contrat, lot 2).
public struct OTPField: UIViewRepresentable {
    nonisolated public static let maximumLength = 6

    @Binding private var code: String
    private let identifier: String
    private let onComplete: (String) -> Void

    public init(code: Binding<String>, identifier: String = "contract-otp", onComplete: @escaping (String) -> Void = { _ in }) {
        self._code = code; self.identifier = identifier; self.onComplete = onComplete
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.accessibilityIdentifier = identifier
        field.accessibilityLabel = "Code de signature, six chiffres"
        field.placeholder = "6 chiffres"
        field.borderStyle = .roundedRect
        field.keyboardType = .numberPad
        field.textContentType = .oneTimeCode
        field.autocorrectionType = .no
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
