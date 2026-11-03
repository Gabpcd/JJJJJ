import SwiftUI

/// Indicateur « l'interlocuteur écrit », port de `src/pages/PageMessagerie.tsx` (l.777-786) : trois points qui
/// rebondissent avec 0, 150 et 300 ms de décalage dans une bulle d'interlocuteur, libellé vocalisé verbatim
/// « L'interlocuteur écrit ». `statusText` reprend la ligne d'en-tête du fil (« Est en train d'écrire… », l.698).
/// « Réduire les animations » : points immobiles (`animate-bounce` coupé), y compris en cours d'affichage.
/// Écart assumé : points `rose-700` (≥ 3:1 sur la bulle) au lieu de `rose-400` (2,15:1 en clair).
/// L'écran l'affiche seulement fil ouvert, sur la valeur Realtime `typing_status` (décision D7 du lot 4).
public struct TypingIndicator: View {
    nonisolated public static let accessibilityLabel = "L'interlocuteur écrit"
    nonisolated public static let statusText = "Est en train d'écrire…"
    nonisolated public static let dotDelays: [Double] = [0, 0.15, 0.3]
    nonisolated public static let dotDiameter: CGFloat = 6
    nonisolated public static let dotInkHSL = JoleneColor.rose700HSL

    nonisolated public static func animates(reduceMotion: Bool) -> Bool { !reduceMotion }

    private let identifier: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var enHaut = false

    public init(identifier: String? = nil) { self.identifier = identifier }

    public var body: some View {
        HStack(spacing: JoleneSpacing.xs) {
            ForEach(Array(Self.dotDelays.enumerated()), id: \.offset) { point in
                Circle()
                    .fill(Color(Self.dotInkHSL))
                    .frame(width: Self.dotDiameter, height: Self.dotDiameter)
                    .offset(y: enHaut ? -3 : 0)
                    .animation(Self.animates(reduceMotion: reduceMotion)
                               ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true).delay(point.element)
                               : nil,
                               value: enHaut)
            }
        }
        .padding(.horizontal, JoleneSpacing.md)
        .padding(.vertical, JoleneSpacing.sm)
        .background(JoleneColor.cloud)
        .clipShape(BubbleShape(tail: .bottomLeading))
        .overlay(BubbleShape(tail: .bottomLeading).stroke(JoleneColor.rose100, lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier(identifier ?? "")
        .onAppear { appliquer(reduceMotion: reduceMotion) }
        .onChange(of: reduceMotion) { appliquer(reduceMotion: $0) }
    }

    /// Démarre le rebond, ou fige les points sans animation (interrompt la répétition en cours).
    private func appliquer(reduceMotion: Bool) {
        if Self.animates(reduceMotion: reduceMotion) {
            enHaut = true
        } else {
            var arret = Transaction(animation: nil)
            arret.disablesAnimations = true
            withTransaction(arret) { enHaut = false }
        }
    }
}
