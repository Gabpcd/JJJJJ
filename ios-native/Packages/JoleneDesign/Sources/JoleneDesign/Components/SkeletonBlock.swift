import SwiftUI

/// Bloc de chargement, port de `src/components/ui/skeleton.tsx` (`role="status"` → élément
/// d'accessibilité explicite libellé « Chargement en cours », `aria-busy` → trait
/// `.updatesFrequently` ; tailles `h-3` / `h-4` / `h-6`). Pulsation d'opacité coupée quand
/// « Réduire les animations » est actif, y compris si le réglage change pendant l'affichage.
/// Un squelette n'est jamais un contenu : il disparaît dès la réponse serveur (succès ou
/// erreur), il ne remplace pas un message d'erreur.
public struct SkeletonBlock: View {
    public enum Size: CaseIterable, Sendable {
        case sm, md, lg

        public var height: CGFloat {
            switch self {
            case .sm: return 12
            case .md: return 16
            case .lg: return 24
            }
        }
    }

    nonisolated public static let accessibilityLabel = "Chargement en cours"

    /// `src/index.css` (`prefers-reduced-motion`) : `.animate-pulse { animation: none }`.
    nonisolated public static func animates(reduceMotion: Bool) -> Bool { !reduceMotion }

    private let size: Size
    private let width: CGFloat?
    private let cornerRadius: CGFloat
    private let identifier: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    public init(size: Size = .md, width: CGFloat? = nil, cornerRadius: CGFloat = 6, identifier: String? = nil) {
        self.size = size; self.width = width; self.cornerRadius = cornerRadius; self.identifier = identifier
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(JoleneColor.mauve100)
            .frame(width: width, height: size.height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .opacity(dimmed ? 0.45 : 1)
            .onAppear { appliquerPulsation(reduceMotion: reduceMotion) }
            .onChange(of: reduceMotion) { appliquerPulsation(reduceMotion: $0) }
            .accessibilityElement()
            .accessibilityLabel(Self.accessibilityLabel)
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier(identifier ?? "")
    }

    /// Démarre la pulsation, ou l'arrête net (opacité pleine, sans animation : interrompt la
    /// répétition en cours) quand « Réduire les animations » est actif.
    private func appliquerPulsation(reduceMotion: Bool) {
        if Self.animates(reduceMotion: reduceMotion) {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dimmed = true }
        } else {
            var arret = Transaction(animation: nil)
            arret.disablesAnimations = true
            withTransaction(arret) { dimmed = false }
        }
    }
}

/// Carte squelette (titre + deux lignes) pour les listes en attente de première réponse.
public struct SkeletonCard: View {
    private let identifier: String?

    public init(identifier: String? = nil) { self.identifier = identifier }

    public var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            SkeletonBlock(size: .lg, width: 180)
            SkeletonBlock(size: .md)
            SkeletonBlock(size: .sm, width: 120)
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SkeletonBlock.accessibilityLabel)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier(identifier ?? "")
    }
}
