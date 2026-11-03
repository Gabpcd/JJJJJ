import Foundation
import SwiftUI

/// Rangée de cinq étoiles en lecture seule, port de `StarsRow` (`src/pages/EvaluationsSoignant.tsx` l.43-55) :
/// `i <= Math.round(note)` étoiles pleines, valeur `note.toFixed(1)` à droite. La note est la **valeur serveur**
/// décimale (`note_moyenne` des RPC filtrées du lot 4), jamais recalculée ; la rangée ne lit aucune source de
/// notation (filtre de visibilité centralisé, CLAUDE.md).
///
/// Parité exacte avec le moteur JS (vecteurs Node dans les tests) : `toFixed(1)` arrondit la valeur binaire exacte
/// et, à égalité (x = k/4, k impair : 0,25, 4,25…), garde le plus grand ; `Math.round` arrondit les demis vers +∞.
/// Le séparateur affiché est donc le point, comme le web (`4.3`) ; VoiceOver lit « Note : 4,3 sur 5 ».
/// Étoile pleine : remplissage `butter400` et contour `butter800` (≥ 3:1) ; étoile vide : contour `bubblegum`
/// (le web : `text-muted-foreground/30`, décoratif) ; les étoiles sont masquées à VoiceOver, la note est lue.
public struct StarRow: View {
    nonisolated public static let starCount = 5
    nonisolated public static let filledFillHSL = JoleneColor.butter400HSL
    nonisolated public static let filledStrokeHSL = JoleneColor.butter800HSL
    nonisolated public static let emptyStrokeHSL = JoleneColor.bubblegumHSL
    nonisolated public static let valueInkHSL = JoleneColor.midnightHSL

    /// `Math.round` : demi vers +∞ (`Math.round(2.5) === 3`, `Math.round(-2.5) === -2`), sans l'erreur de
    /// `floor(x + 0.5)` sur 0,49999999999999994.
    nonisolated static func mathRound(_ valeur: Double) -> Double {
        guard valeur.isFinite else { return valeur }
        let bas = valeur.rounded(.down)
        return valeur - bas >= 0.5 ? bas + 1 : bas
    }

    /// Nombre d'étoiles pleines (`i <= Math.round(note)` pour i de 1 à 5), borné à 0...5 ; 0 pour une valeur non finie.
    nonisolated public static func filledCount(_ note: Double) -> Int {
        guard note.isFinite else { return 0 }
        return Int(min(Double(starCount), max(0, mathRound(note))))
    }

    /// `note.toFixed(1)` ; « — » pour une valeur non finie (impossible en JSON, gardée plutôt qu'afficher « NaN »).
    nonisolated public static func texteNote(_ note: Double) -> String {
        guard note.isFinite else { return "—" }
        guard note != 0 else { return "0.0" }   // `(-0).toFixed(1) === '0.0'`
        let magnitude = abs(note)
        let corps: String
        let quarts = magnitude * 4                // exact : multiplication par une puissance de deux
        if magnitude < 1e15, quarts == quarts.rounded(.towardZero), quarts.truncatingRemainder(dividingBy: 2) == 1 {
            // Égalité exacte entre deux dixièmes : `toFixed` garde le plus grand (printf garderait le pair).
            corps = String(format: "%.1f", (magnitude * 10).rounded(.up) / 10)
        } else {
            corps = String(format: "%.1f", magnitude)   // arrondi de la valeur binaire exacte, comme `toFixed`
        }
        return note < 0 ? "-\(corps)" : corps
    }

    /// « Note : 4,3 sur 5 » (décimale française à l'oral), « Note indisponible » pour une valeur non finie.
    nonisolated public static func accessibilityLabel(_ note: Double) -> String {
        guard note.isFinite else { return "Note indisponible" }
        return "Note : \(texteNote(note).replacingOccurrences(of: ".", with: ",")) sur \(starCount)"
    }

    private let note: Double
    private let showsValue: Bool
    private let identifier: String?

    public init(note: Double, showsValue: Bool = true, identifier: String? = nil) {
        self.note = note; self.showsValue = showsValue; self.identifier = identifier
    }

    public var body: some View {
        let pleines = Self.filledCount(note)
        HStack(spacing: 2) {
            ForEach(1...Self.starCount, id: \.self) { rang in
                etoile(pleine: rang <= pleines)
            }
            if showsValue {
                Text(Self.texteNote(note))
                    .font(JoleneFont.caption.weight(.medium))
                    .foregroundStyle(Color(Self.valueInkHSL))
                    .padding(.leading, JoleneSpacing.xs)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(note))
        .accessibilityIdentifier(identifier ?? "")
    }

    @ViewBuilder private func etoile(pleine: Bool) -> some View {
        if pleine {
            ZStack {
                Image(systemName: "star.fill").foregroundStyle(Color(Self.filledFillHSL))
                Image(systemName: "star").foregroundStyle(Color(Self.filledStrokeHSL))
            }
            .font(JoleneFont.caption)
        } else {
            Image(systemName: "star")
                .font(JoleneFont.caption)
                .foregroundStyle(Color(Self.emptyStrokeHSL))
        }
    }
}
