import SwiftUI

/// Vignette de profil, port d'`AvatarDisplay` et du rendu d'`AvatarUpload` (`src/components/AvatarUpload.tsx`) :
/// photo recadrée, sinon initiales blanches sur une couleur de repli tirée du nom (`FALLBACK_COLORS`,
/// `hashName`, `getInitials`, l.10-31), taille 40 pt par défaut, coins `rounded-full` ou `rounded-xl`,
/// voile `bg-black/50` + indicateur pendant un téléversement. Les règles portées sont vérifiées contre des
/// vecteurs produits par le code web sous Node et relues dans le fichier source (garde de dérive).
///
/// **Aucun réseau ici** (module sans accès réseau) : la vue reçoit une `Image` déjà chargée ; la lecture de
/// l'URL signée (`avatar_url`, 5 ans) et le téléversement relèvent de l'écran et de son port (T9, T10).
/// Le bouton « changer la photo » est posé par l'écran, avec le libellé web `changePhotoLabel`.
///
/// Écarts assumés : initiales prises au premier **scalaire** Unicode (identique au web, qui prend la première
/// unité UTF-16, sur tout le plan multilingue de base ; le web afficherait « � » pour un emoji) ; seuils de
/// police d'`AvatarDisplay` (l.78) pour toutes les tailles (`AvatarUpload` l.117 garde 14 pt sous 32 pt, taille
/// jamais utilisée en téléversement). Contraste des initiales : ≥ 4,87:1 sur chaque couleur de repli (test).
public struct AvatarView: View {
    /// `rounded: 'full' | 'lg'` du web (`rounded-full` / `rounded-xl`).
    public enum Rounding: Sendable { case full, large }

    nonisolated public static let defaultSize: CGFloat = 40
    nonisolated public static let largeCornerRadius: CGFloat = 12
    /// `FALLBACK_COLORS` (l.10-17), dans l'ordre : rose Jolene, indigo, rose, ambre, émeraude, violet.
    nonisolated public static let fallbackColorsHSL: [JoleneHSL] = [
        JoleneHSL(330, 85, 40), JoleneHSL(243, 75, 59), JoleneHSL(330, 81, 44),
        JoleneHSL(38, 92, 30), JoleneHSL(152, 69, 30), JoleneHSL(263, 70, 58),
    ]
    /// `text-white` des initiales, fixe en clair comme en sombre (les couleurs de repli ne changent pas).
    nonisolated public static let initialsInkHex = "#FFFFFF"
    /// `aria-label` du bouton de téléversement soignant (l.179), verbatim.
    nonisolated public static let changePhotoLabel = "Changer ma photo de profil"

    /// `getInitials` : première lettre du prénom puis du nom, en majuscules ; « ? » si rien.
    nonisolated public static func initials(prenom: String?, nom: String?) -> String {
        func premiere(_ texte: String?) -> String { texte?.unicodeScalars.first.map { String($0) } ?? "" }
        let initiales = (premiere(prenom) + premiere(nom)).uppercased()
        return initiales.isEmpty ? "?" : initiales
    }

    /// `hashName` : `h = ((h << 5) - h + charCodeAt(i)) | 0` sur les unités UTF-16, puis `Math.abs(h)`.
    nonisolated public static func hashName(_ name: String) -> Int {
        var h: Int32 = 0
        for unite in name.utf16 { h = (h &<< 5) &- h &+ Int32(unite) }
        return magnitude(h)
    }

    /// `Math.abs` d'un entier 32 bits : la valeur minimale donne 2 147 483 648 (aucun débordement).
    nonisolated static func magnitude(_ value: Int32) -> Int { Int(value.magnitude) }

    /// `getFallbackColor((prenom || '') + (nom || ''))` : index dans `fallbackColorsHSL`.
    nonisolated public static func fallbackColorIndex(prenom: String?, nom: String?) -> Int {
        hashName((prenom ?? "") + (nom ?? "")) % fallbackColorsHSL.count
    }

    /// `size >= 64 ? 'text-2xl' : size >= 32 ? 'text-sm' : 'text-xs'` (24, 14, 12 pt). Taille fixe : les
    /// initiales suivent la vignette, pas Dynamic Type.
    nonisolated public static func initialsFontSize(for size: CGFloat) -> CGFloat {
        size >= 64 ? 24 : (size >= 32 ? 14 : 12)
    }

    nonisolated public static func cornerRadius(for rounding: Rounding, size: CGFloat) -> CGFloat {
        rounding == .full ? size / 2 : largeCornerRadius
    }

    /// `alt={`${prenom || ''} ${nom || ''}`}`, espaces de bord retirés ; `nil` = vignette décorative.
    nonisolated public static func accessibilityLabel(prenom: String?, nom: String?) -> String? {
        let libelle = "\(prenom ?? "") \(nom ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
        return libelle.isEmpty ? nil : libelle
    }

    /// Valeur vocalisée pendant un téléversement (spinner du web), libellé de `SkeletonBlock`.
    nonisolated public static func loadingAccessibilityValue(isLoading: Bool) -> String? {
        isLoading ? SkeletonBlock.accessibilityLabel : nil
    }

    private let image: Image?
    private let prenom: String?
    private let nom: String?
    private let size: CGFloat
    private let rounding: Rounding
    private let isLoading: Bool
    private let identifier: String?

    public init(image: Image? = nil, prenom: String?, nom: String?, size: CGFloat = AvatarView.defaultSize,
                rounding: Rounding = .full, isLoading: Bool = false, identifier: String? = nil) {
        self.image = image; self.prenom = prenom; self.nom = nom; self.size = size
        self.rounding = rounding; self.isLoading = isLoading; self.identifier = identifier
    }

    public var body: some View {
        let forme = RoundedRectangle(cornerRadius: Self.cornerRadius(for: rounding, size: size))
        let libelle = Self.accessibilityLabel(prenom: prenom, nom: nom)
        ZStack {
            if let image {
                image.resizable().scaledToFill()
            } else {
                Color(Self.fallbackColorsHSL[Self.fallbackColorIndex(prenom: prenom, nom: nom)])
                Text(Self.initials(prenom: prenom, nom: nom))
                    .font(.system(size: Self.initialsFontSize(for: size), weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: Self.initialsInkHex))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            if isLoading {
                Color.black.opacity(0.5)
                ProgressView().tint(Color(hex: Self.initialsInkHex))
            }
        }
        .frame(width: size, height: size)
        .clipShape(forme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelle ?? "")
        .accessibilityValue(Self.loadingAccessibilityValue(isLoading: isLoading) ?? "")
        .accessibilityAddTraits(.isImage)
        .accessibilityHidden(libelle == nil && !isLoading)
        .accessibilityIdentifier(identifier ?? "")
    }
}
