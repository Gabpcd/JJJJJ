import SwiftUI

/// Typographie : styles système (Dynamic Type respecté), arrondis pour l'identité Y2K sobre.
public enum JoleneFont {
    public static let hero = Font.system(.largeTitle, design: .rounded).weight(.bold)
    public static let title = Font.system(.title2, design: .rounded).weight(.bold)
    public static let headline = Font.system(.headline, design: .rounded)
    public static let body = Font.system(.body)
    public static let callout = Font.system(.callout)
    public static let caption = Font.system(.caption)
    public static let button = Font.system(.body, design: .rounded).weight(.semibold)
}

/// Espacements et rayons (échelle 4 pt, cartes `rounded-2xl` = 16 pt, boutons `rounded-full`).
public enum JoleneSpacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

public enum JoleneRadius {
    public static let field: CGFloat = 14
    public static let card: CGFloat = 16
    public static let button: CGFloat = 999
}
