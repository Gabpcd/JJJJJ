import SwiftUI

/// Rangée de cinq étoiles **saisissable**, port de `EtoilesNotation` (`src/components/NotationRapide.tsx` l.77-101,
/// `role="radiogroup"`) : une note de 1 à 5 en un toucher, cible de 44 pt par étoile, l'étoile choisie porte le trait
/// « sélectionné ». Lot 5, T8 : note donnée par l'établissement à la validation d'une présence. `StarRow` reste le
/// composant de lecture seule.
///
/// Aucune règle métier : l'appelant reçoit la valeur choisie et décide de ce qu'il en fait ; libellés et identifiants
/// viennent de l'appelant (les textes du web vivent dans JoleneCore).
public struct StarRating: View {
    nonisolated public static let starCount = 5
    /// Côté minimal de la cible tactile d'une étoile (HIG : 44 pt).
    nonisolated public static let minimumTarget: CGFloat = 44

    /// Valeur affichée, bornée à 0...5 (0 : aucune note choisie).
    nonisolated public static func clamped(_ value: Int) -> Int {
        min(starCount, max(0, value))
    }

    /// `n <= valeur` (web l.94) : les étoiles sont pleines jusqu'à la note choisie.
    nonisolated public static func isFilled(_ rank: Int, value: Int) -> Bool {
        rank >= 1 && rank <= clamped(value)
    }

    private let value: Int
    private let size: CGFloat
    private let label: String
    private let starLabel: (Int) -> String
    private let identifier: (Int) -> String
    private let isEnabled: Bool
    private let onSelect: (Int) -> Void

    /// - Parameters:
    ///   - label: libellé vocalisé du groupe (« Note »).
    ///   - starLabel: libellé vocalisé d'une étoile (« 4 étoiles »).
    ///   - identifier: identifiant d'accessibilité d'une étoile (`etab-presence-note-4`).
    public init(value: Int, size: CGFloat = 32, label: String, starLabel: @escaping (Int) -> String,
                identifier: @escaping (Int) -> String, isEnabled: Bool = true, onSelect: @escaping (Int) -> Void) {
        self.value = value; self.size = size; self.label = label; self.starLabel = starLabel
        self.identifier = identifier; self.isEnabled = isEnabled; self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: JoleneSpacing.xs) {
            ForEach(1...Self.starCount, id: \.self) { rang in
                let pleine = Self.isFilled(rang, value: value)
                Button { onSelect(rang) } label: {
                    Image(systemName: pleine ? "star.fill" : "star")
                        .font(.system(size: size))
                        .foregroundStyle(pleine ? JoleneColor.butter700 : JoleneColor.bubblegum)
                        .frame(minWidth: Self.minimumTarget, minHeight: Self.minimumTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .accessibilityLabel(starLabel(rang))
                .accessibilityAddTraits(Self.clamped(value) == rang ? .isSelected : [])
                .accessibilityIdentifier(identifier(rang))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}
