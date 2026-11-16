import SwiftUI
import JoleneCore

/// Compte à rebours de la signature (lot 2, T9a ; `Countdown72hSignature.tsx`). Le texte est fourni par l'écran
/// (`TextesWeb.CompteARebours.texte`, HARD STOP n°4) et l'état vient de `CompteARebours72h` (JoleneCore), dérivé de
/// `cree_le` à chaque seconde : ce composant n'en fait que la couleur et l'icône du web — vert au-delà de 48 h,
/// orange de 24 à 48 h, rouge en deçà (l.53-56), triangle d'alerte à l'expiration (l.38-46). Aucune règle de délai
/// ici ; le serveur seul décide d'une expiration. Annoncé comme une valeur qui change souvent (`role="timer"`,
/// `aria-live="polite"` du web).
public struct CountdownLabel: View {
    private let texte: String
    private let etat: EtatCompteARebours72h
    private let identifier: String?

    public init(texte: String, etat: EtatCompteARebours72h, identifier: String? = nil) {
        self.texte = texte; self.etat = etat; self.identifier = identifier
    }

    /// Ton du palier (`couleur` du web) : `success` au-delà de 48 h, `warning` de 24 à 48 h, `error` en deçà.
    nonisolated public static func ton(_ etat: EtatCompteARebours72h) -> InlineNotice.Tone {
        switch etat.ton {
        case .confortable: return .success
        case .attention: return .warning
        case .urgent: return .error
        }
    }

    /// Icône du web : horloge, triangle d'alerte une fois le délai écoulé.
    nonisolated public static func symbole(_ etat: EtatCompteARebours72h) -> String {
        etat.expire ? "exclamationmark.triangle" : "clock"
    }

    /// Libellé vocalisé : le texte affiché, sans préfixe.
    nonisolated public static func libelleAccessibilite(texte: String) -> String { texte }

    public var body: some View {
        let ton = Self.ton(etat)
        HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.sm) {
            Image(systemName: Self.symbole(etat))
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(ton.foreground)
                .accessibilityHidden(true)
            Text(texte)
                .font(JoleneFont.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(JoleneColor.midnight)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, JoleneSpacing.md)
        .padding(.vertical, JoleneSpacing.sm)
        .background(ton.background)
        .overlay(RoundedRectangle(cornerRadius: JoleneRadius.field).strokeBorder(ton.foreground.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.libelleAccessibilite(texte: texte))
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier(identifier ?? "")
    }
}
