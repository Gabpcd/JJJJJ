import SwiftUI
import UIKit

/// Champ de saisie d'un code à six chiffres (blueprint lot 2 §2.1, tranche T4b : code rotatif de pointage), port de
/// l'`input` de `PointageRotatifSoignant.tsx` l.216-225 (`inputMode="numeric"`, `maxLength={6}`, police à chasse fixe,
/// centré). Distinct d'`OTPField` : clavier `.numberPad` SANS `oneTimeCode` (un code affiché par l'établissement n'est
/// jamais un SMS reçu, iOS ne doit pas le proposer). Comme le web (`replace(/\D/g, '').slice(0, 6)`), toute saisie est
/// réduite à ses chiffres ASCII puis tronquée à six (un collage n'est jamais refusé, il est filtré). Aucun texte ici :
/// libellé vocalisé et indication viennent de l'écran (`LibellesWeb.Pointage`). 16 pt minimum (pas de zoom iOS).
public struct NumericCodeField: View {
    nonisolated public static let longueur = 6

    @Binding private var code: String
    private let libelle: String
    private let placeholder: String
    private let identifier: String
    @FocusState private var focused: Bool

    public init(code: Binding<String>, libelle: String, placeholder: String, identifier: String) {
        self._code = code; self.libelle = libelle; self.placeholder = placeholder; self.identifier = identifier
    }

    public var body: some View {
        TextField(placeholder, text: $code)
            .keyboardType(.numberPad)
            .textContentType(nil)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .font(.system(.title2, design: .monospaced).weight(.semibold))
            .multilineTextAlignment(.center)
            .focused($focused)
            .onChange(of: code) { valeur in
                let filtre = Self.filtrer(valeur)
                if filtre != valeur { code = filtre }
            }
            .padding(.horizontal, JoleneSpacing.md)
            .frame(minHeight: 48)
            .background(JoleneColor.cloud)
            .overlay(
                RoundedRectangle(cornerRadius: JoleneRadius.field)
                    .strokeBorder(focused ? JoleneColor.rose : JoleneColor.bubblegum.opacity(0.35), lineWidth: focused ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
            .accessibilityLabel(libelle)
            .accessibilityIdentifier(identifier)
    }

    /// Chiffres ASCII de la saisie, dans l'ordre, tronqués à six (règle de l'`onChange` du web, l.222).
    nonisolated public static func filtrer(_ saisie: String) -> String {
        var chiffres = ""
        for scalaire in saisie.unicodeScalars where ("0"..."9").contains(scalaire) {
            guard chiffres.unicodeScalars.count < longueur else { break }
            chiffres.unicodeScalars.append(scalaire)
        }
        return chiffres
    }

    /// Vrai pour exactement six chiffres : seul un code complet active le bouton (web l.250 `code.length !== 6`).
    nonisolated public static func estComplet(_ code: String) -> Bool {
        code.count == longueur && filtrer(code) == code
    }
}
