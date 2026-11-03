import CoreImage
import SwiftUI

/// QR code d'une chaîne (lien de parrainage, lot 4 T6), port de `QRCodeSVG` de `src/pages/PageParrainage.tsx`
/// (l.219 : `size={140} level="M" bgColor="#FFFFFF" fgColor="#1A1A2E"`). Généré localement par CoreImage
/// (`CIQRCodeGenerator`, correction `M`), aucun réseau ; modules agrandis d'un facteur entier et affichés sans
/// lissage (`interpolation(.none)`), marge claire de 12 pt autour du code (zone de silence, `p-1` + `p-3` du web).
/// Couleurs fixes en clair comme en sombre : un code sombre sur fond clair reste lisible par tout scanner.
/// Le libellé vocalisé est fourni par l'écran (texte du parcours), le contenu encodé n'est jamais lu.
public struct QRCodeImage: View {
    nonisolated public static let correctionLevel = "M"
    nonisolated public static let foregroundHex = "#1A1A2E"
    nonisolated public static let backgroundHex = "#FFFFFF"
    nonisolated public static let defaultSide: CGFloat = 140
    nonisolated public static let quietZone: CGFloat = 12
    nonisolated public static let unavailableText = "QR code indisponible"

    /// Image du code (`scale` pixels par module, zone de silence d'un module incluse par CoreImage), `nil` si la
    /// génération échoue. Charge encodée en UTF-8. Une image déjà produite pour la même charge et le même facteur
    /// est réutilisée (`body` est réévalué à chaque rendu) ; filtres et contexte ne sont créés qu'au premier calcul.
    nonisolated public static func cgImage(for payload: String, scale: Int = 8) -> CGImage? {
        guard scale > 0 else { return nil }
        let cle = "\(scale)|\(payload)" as NSString
        if let image = Rendu.partage.images.object(forKey: cle) { return image }
        guard let image = genere(payload, scale: scale) else { return nil }
        Rendu.partage.images.setObject(image, forKey: cle)
        return image
    }

    nonisolated private static func genere(_ payload: String, scale: Int) -> CGImage? {
        guard let generateur = CIFilter(name: "CIQRCodeGenerator"),
              let couleurs = CIFilter(name: "CIFalseColor"),
              let sombre = JoleneHex.parse(foregroundHex), let clair = JoleneHex.parse(backgroundHex) else { return nil }
        generateur.setValue(Data(payload.utf8), forKey: "inputMessage")
        generateur.setValue(correctionLevel, forKey: "inputCorrectionLevel")
        guard let modules = generateur.outputImage else { return nil }
        couleurs.setValue(modules, forKey: kCIInputImageKey)
        couleurs.setValue(CIColor(red: sombre.red, green: sombre.green, blue: sombre.blue), forKey: "inputColor0")
        couleurs.setValue(CIColor(red: clair.red, green: clair.green, blue: clair.blue), forKey: "inputColor1")
        guard let colore = couleurs.outputImage else { return nil }
        let agrandi = colore.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        return Rendu.partage.contexte.createCGImage(agrandi, from: agrandi.extent.integral)
    }

    /// Contexte Core Image partagé et images déjà produites. `@unchecked Sendable` : un `CIContext` est immuable et
    /// peut être partagé entre fils (documentation Core Image), `NSCache` est sûr entre fils ; aucune autre donnée
    /// mutable. Cache borné (quelques liens de parrainage au plus).
    final class Rendu: @unchecked Sendable {
        static let partage = Rendu()
        let contexte = CIContext(options: [.useSoftwareRenderer: false])
        let images: NSCache<NSString, CGImage> = {
            let cache = NSCache<NSString, CGImage>()
            cache.countLimit = 16
            return cache
        }()
    }

    private let payload: String
    private let side: CGFloat
    private let label: String
    private let identifier: String?

    public init(_ payload: String, side: CGFloat = QRCodeImage.defaultSide, accessibilityLabel: String, identifier: String? = nil) {
        self.payload = payload; self.side = side; self.label = accessibilityLabel; self.identifier = identifier
    }

    public var body: some View {
        let code = Self.cgImage(for: payload)
        Group {
            if let image = code {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
            } else {
                Text(Self.unavailableText)
                    .font(JoleneFont.caption)
                    .foregroundStyle(Color(hex: Self.foregroundHex))
                    .multilineTextAlignment(.center)
                    .frame(width: side, height: side)
            }
        }
        .padding(Self.quietZone)
        .background(Color(hex: Self.backgroundHex))
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(code == nil ? Self.unavailableText : label)
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier(identifier ?? "")
    }
}
