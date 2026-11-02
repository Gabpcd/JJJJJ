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

    /// Luminance relative WCAG 2.x (composantes sRGB linéarisées, alpha ignoré).
    public var relativeLuminance: Double {
        func lineaire(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lineaire(red) + 0.7152 * lineaire(green) + 0.0722 * lineaire(blue)
    }

    /// Rapport de contraste WCAG 2.x, de 1 à 21, symétrique. Seuil AA du texte courant : 4,5.
    public func contrastRatio(with other: JoleneHex) -> Double {
        let (clair, sombre) = (max(relativeLuminance, other.relativeLuminance), min(relativeLuminance, other.relativeLuminance))
        return (clair + 0.05) / (sombre + 0.05)
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

/// Couleur dynamique source : variantes `:root` (clair) et `.dark` (sombre) de `src/index.css`.
/// Les jetons `JoleneColor` sont construits à partir de ces valeurs, ce qui permet aux tests de
/// vérifier les contrastes sur ce qui est réellement rendu, dans les deux thèmes.
public struct JoleneDynamicHSL: Equatable, Sendable {
    public var light: JoleneHSL
    public var dark: JoleneHSL

    public init(light: JoleneHSL, dark: JoleneHSL) {
        self.light = light; self.dark = dark
    }

    /// Les deux variantes en sRGB, clair puis sombre.
    public var variants: [JoleneHex] { [light.rgb, dark.rgb] }
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

    init(_ dynamic: JoleneDynamicHSL) {
        self.init(light: dynamic.light, dark: dynamic.dark)
    }
}

/// Palette Jolene. Source : `src/index.css` (`--jolene-*` de `:root` et de `.dark`),
/// `docs/IDENTITE_VISUELLE_JOLENE.md`. Chaque jeton `Color` est construit sur sa source `…HSL`
/// (contrastes testés sur ce qui est rendu) ; la garde `JoleneDesignLot1Tests` relit `src/index.css`
/// et compare chaque source aux deux variantes du web.
///
/// Écarts assumés du lot 0, en mode sombre seulement (valeur rendue / valeur web) : `lavender`
/// 268 38% 10% / 270 25% 16%, `cloud` 268 30% 14% / 268 25% 12%, `bubblegum` 271 20% 72% / 271 15% 68%.
/// Les aligner changerait la hiérarchie fond / carte de tous les écrans du lot 0 en sombre (décision à
/// prendre avec un contrôle visuel) ; les contrastes du texte sont vérifiés sur les deux valeurs.
public enum JoleneColor {
    // Sources HSL clair / sombre (`:root` / `.dark` de src/index.css, sauf écarts ci-dessus).
    public static let roseHSL = JoleneDynamicHSL(light: JoleneHSL(326, 100, 71), dark: JoleneHSL(326, 90, 65))       // #FF6BBE
    public static let mauveHSL = JoleneDynamicHSL(light: JoleneHSL(267, 100, 75), dark: JoleneHSL(267, 85, 70))      // #B57EFF
    public static let cyanHSL = JoleneDynamicHSL(light: JoleneHSL(192, 100, 72), dark: JoleneHSL(192, 90, 68))       // #6FE5FF
    public static let butterHSL = JoleneDynamicHSL(light: JoleneHSL(50, 100, 70), dark: JoleneHSL(50, 90, 65))       // #FFE066
    public static let rose700HSL = JoleneDynamicHSL(light: JoleneHSL(326, 75, 48), dark: JoleneHSL(326, 100, 80))
    public static let rose800HSL = JoleneDynamicHSL(light: JoleneHSL(326, 70, 38), dark: JoleneHSL(326, 100, 88))
    public static let mauve700HSL = JoleneDynamicHSL(light: JoleneHSL(267, 70, 52), dark: JoleneHSL(267, 95, 85))
    public static let mauve800HSL = JoleneDynamicHSL(light: JoleneHSL(267, 65, 42), dark: JoleneHSL(267, 100, 91))
    public static let cyan700HSL = JoleneDynamicHSL(light: JoleneHSL(192, 75, 45), dark: JoleneHSL(192, 100, 84))
    public static let cyan900HSL = JoleneDynamicHSL(light: JoleneHSL(192, 65, 25), dark: JoleneHSL(192, 100, 95))
    public static let butter700HSL = JoleneDynamicHSL(light: JoleneHSL(50, 75, 42), dark: JoleneHSL(50, 100, 82))
    public static let butter800HSL = JoleneDynamicHSL(light: JoleneHSL(50, 70, 32), dark: JoleneHSL(50, 100, 89))
    public static let rose100HSL = JoleneDynamicHSL(light: JoleneHSL(326, 100, 91), dark: JoleneHSL(326, 55, 18))
    public static let mauve100HSL = JoleneDynamicHSL(light: JoleneHSL(267, 100, 91), dark: JoleneHSL(267, 55, 18))
    public static let cyan100HSL = JoleneDynamicHSL(light: JoleneHSL(192, 100, 91), dark: JoleneHSL(192, 55, 18))
    public static let butter100HSL = JoleneDynamicHSL(light: JoleneHSL(50, 100, 91), dark: JoleneHSL(50, 55, 18))
    public static let lavenderHSL = JoleneDynamicHSL(light: JoleneHSL(270, 100, 96), dark: JoleneHSL(268, 38, 10))   // #F4EDFF (écart sombre)
    public static let cloudHSL = JoleneDynamicHSL(light: JoleneHSL(320, 100, 99), dark: JoleneHSL(268, 30, 14))      // #FFFAFF (écart sombre)
    public static let midnightHSL = JoleneDynamicHSL(light: JoleneHSL(268, 38, 18), dark: JoleneHSL(270, 30, 95))    // #2B1B3D
    public static let bubblegumHSL = JoleneDynamicHSL(light: JoleneHSL(271, 16, 43), dark: JoleneHSL(271, 20, 72))   // écart sombre

    /// Surfaces dont hérite un texte posé sans fond propre (`SectionHeader`, lignes de `SlotList`) :
    /// carte (`cloud`), fond des écrans (`lavender`), bas du `softGradient` (`rose100`). Tout texte
    /// sans fond doit atteindre 4,5:1 sur chacune, en clair et en sombre (test).
    public static let inheritedSurfacesHSL = [cloudHSL, lavenderHSL, rose100HSL]

    // Signature
    public static let rose = Color(roseHSL)
    public static let mauve = Color(mauveHSL)
    public static let cyan = Color(cyanHSL)
    public static let butter = Color(butterHSL)

    // Variantes lisibles sur fond clair (texte critique : -700 selon le doc d'identité)
    public static let rose700 = Color(rose700HSL)
    public static let mauve700 = Color(mauve700HSL)
    public static let cyan700 = Color(cyan700HSL)
    public static let butter700 = Color(butter700HSL)

    /// Encre d'un texte d'action posé sans fond propre (« Tout voir », « + N autres créneaux ») :
    /// `rose-800` de src/index.css, ≥ 4,5:1 sur `inheritedSurfacesHSL` là où `rose700` tombe à
    /// 4,12:1 (lavender) et 3,54:1 (rose100).
    public static let rose800 = Color(rose800HSL)

    // Encres des badges et encarts (`BadgeY2K` : text-jolene-mauve-800 / cyan-900 / butter-800)
    public static let mauve800 = Color(mauve800HSL)
    public static let cyan900 = Color(cyan900HSL)
    public static let butter800 = Color(butter800HSL)

    // Surfaces douces
    public static let rose100 = Color(rose100HSL)
    public static let mauve100 = Color(mauve100HSL)
    public static let cyan100 = Color(cyan100HSL)
    public static let butter100 = Color(butter100HSL)

    // Neutres
    public static let lavender = Color(lavenderHSL)
    public static let cloud = Color(cloudHSL)
    public static let midnight = Color(midnightHSL)
    public static let bubblegum = Color(bubblegumHSL)   // texte secondaire

    /// Arrêts du dégradé hero rose → mauve (bouton primaire, titres).
    public static let heroGradientStops = [roseHSL, mauveHSL]
    /// Arrêts du dégradé hero complet rose → mauve → cyan (`.bg-gradient-hero` web).
    public static let heroGradientFullStops = [roseHSL, mauveHSL, cyanHSL]

    /// Dégradé hero rose → mauve (bouton primaire, titres).
    public static let heroGradient = LinearGradient(
        colors: heroGradientStops.map { Color($0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Dégradé hero complet rose → mauve → cyan (`.bg-gradient-hero`, pastille de filtre active).
    public static let heroGradientFull = LinearGradient(
        colors: heroGradientFullStops.map { Color($0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Arrêts du dégradé doux (`.bg-gradient-soft`) : lavande → rose pâle.
    public static let softGradientStops = [lavenderHSL, rose100HSL]
    /// Dégradé doux lavande → rose pâle (`.bg-gradient-soft`), arrière-plans.
    public static let softGradient = LinearGradient(
        colors: softGradientStops.map { Color($0) }, startPoint: .top, endPoint: .bottom)

    /// Dégradé des actions irréversibles, repris de `BoutonY2K` web (variant `destructive`,
    /// `from-[#FF4D6B] to-[#FF6BBE]`). Valeurs hex exposées pour les tests.
    public static let destructiveGradientHex = ["#FF4D6B", "#FF6BBE"]
    public static let destructiveGradient = LinearGradient(
        colors: destructiveGradientHex.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Encre posée sur un dégradé clair (bouton primaire et destructif, pastille de filtre active) :
    /// `text-[#2b183d]` de `BoutonY2K` et `.bg-gradient-hero { color: #2b183d }` de `src/index.css`
    /// (« le texte blanc manque de contraste »), fixe en clair comme en sombre. Contraste ≥ 4,5:1 (AA)
    /// sur chaque arrêt des dégradés hero et destructif, là où le blanc plafonne à 2,6–3,2:1.
    public static let onGradientHex = "#2B183D"
    public static let onGradient = Color(hex: onGradientHex)
}
