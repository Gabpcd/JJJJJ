import SwiftUI
import UIKit

/// Analyse d'une couleur hexadécimale (`#RRGGBB`, `RRGGBB`, `#RRGGBBAA`), sans SwiftUI,
/// pour rester testable unitairement.
public struct JoleneHex: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    /// Retourne `nil` pour toute chaîne qui n'est pas 6 ou 8 chiffres hexadécimaux.
    public static func parse(_ text: String) -> JoleneHex? {
        var digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6 || digits.count == 8,
              digits.allSatisfy({ $0.isHexDigit }),
              let value = UInt64(digits, radix: 16) else { return nil }
        let hasAlpha = digits.count == 8
        let r = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? Double(value & 0xFF) / 255 : 1
        return JoleneHex(red: r, green: g, blue: b, alpha: a)
    }
}

/// Conversion HSL (notation CSS `H S% L%` de `src/index.css`) vers sRGB.
public struct JoleneHSL: Equatable, Sendable {
    public var hue: Double
    public var saturation: Double
    public var lightness: Double

    public init(_ hue: Double, _ saturation: Double, _ lightness: Double) {
        self.hue = hue; self.saturation = saturation; self.lightness = lightness
    }

    public var rgb: JoleneHex {
        let s = saturation / 100, l = lightness / 100
        let c = (1 - abs(2 * l - 1)) * s
        let hPrime = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hPrime.truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r, g, b): (Double, Double, Double)
        switch hPrime {
        case 0..<1: (r, g, b) = (c, x, 0)
        case 1..<2: (r, g, b) = (x, c, 0)
        case 2..<3: (r, g, b) = (0, c, x)
        case 3..<4: (r, g, b) = (0, x, c)
        case 4..<5: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return JoleneHex(red: r + m, green: g + m, blue: b + m)
    }
}

public extension Color {
    /// `Color(hex: "#FF6BBE")`. Une chaîne invalide donne `.clear`, jamais un plantage.
    init(hex: String) {
        guard let parsed = JoleneHex.parse(hex) else { self = .clear; return }
        self.init(.sRGB, red: parsed.red, green: parsed.green, blue: parsed.blue, opacity: parsed.alpha)
    }

    init(_ hsl: JoleneHSL) {
        let rgb = hsl.rgb
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    /// Couleur dynamique clair / sombre (les deux jeux de variables de `src/index.css`).
    init(light: JoleneHSL, dark: JoleneHSL) {
        self.init(uiColor: UIColor { traits in
            let value = (traits.userInterfaceStyle == .dark ? dark : light).rgb
            return UIColor(red: value.red, green: value.green, blue: value.blue, alpha: 1)
        })
    }
}

/// Palette Jolene. Source : `src/index.css` (`:root` et `.dark`), `docs/IDENTITE_VISUELLE_JOLENE.md`.
public enum JoleneColor {
    // Signature
    public static let rose = Color(light: JoleneHSL(326, 100, 71), dark: JoleneHSL(326, 90, 65))       // #FF6BBE
    public static let mauve = Color(light: JoleneHSL(267, 100, 75), dark: JoleneHSL(267, 85, 70))      // #B57EFF
    public static let cyan = Color(light: JoleneHSL(192, 100, 72), dark: JoleneHSL(192, 90, 68))       // #6FE5FF
    public static let butter = Color(light: JoleneHSL(50, 100, 70), dark: JoleneHSL(50, 90, 65))       // #FFE066

    // Variantes lisibles sur fond clair (texte critique : -700 selon le doc d'identité)
    public static let rose700 = Color(light: JoleneHSL(326, 75, 48), dark: JoleneHSL(326, 100, 80))
    public static let mauve700 = Color(light: JoleneHSL(267, 70, 52), dark: JoleneHSL(267, 95, 85))
    public static let cyan700 = Color(light: JoleneHSL(192, 75, 45), dark: JoleneHSL(192, 100, 84))
    public static let butter700 = Color(light: JoleneHSL(50, 75, 42), dark: JoleneHSL(50, 95, 75))

    // Surfaces douces
    public static let rose100 = Color(light: JoleneHSL(326, 100, 91), dark: JoleneHSL(326, 55, 18))
    public static let mauve100 = Color(light: JoleneHSL(267, 100, 91), dark: JoleneHSL(267, 55, 18))
    public static let butter100 = Color(light: JoleneHSL(50, 100, 91), dark: JoleneHSL(50, 55, 18))

    // Neutres
    public static let lavender = Color(light: JoleneHSL(270, 100, 96), dark: JoleneHSL(268, 38, 10))   // #F4EDFF
    public static let cloud = Color(light: JoleneHSL(320, 100, 99), dark: JoleneHSL(268, 30, 14))      // #FFFAFF
    public static let midnight = Color(light: JoleneHSL(268, 38, 18), dark: JoleneHSL(320, 100, 97))   // #2B1B3D
    public static let bubblegum = Color(light: JoleneHSL(271, 16, 43), dark: JoleneHSL(271, 20, 72))   // texte secondaire

    /// Dégradé hero rose → mauve (bouton primaire, titres).
    public static let heroGradient = LinearGradient(
        colors: [rose, mauve], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Dégradé hero complet rose → mauve → cyan (`.bg-gradient-hero`).
    public static let heroGradientFull = LinearGradient(
        colors: [rose, mauve, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Dégradé doux lavande → rose pâle (`.bg-gradient-soft`), arrière-plans.
    public static let softGradient = LinearGradient(
        colors: [lavender, rose100], startPoint: .top, endPoint: .bottom)
}
