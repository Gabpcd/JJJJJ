import SwiftUI

/// Code de pointage présenté en plein écran au soignant (lot 5, T7 ; `LOT5_PLAN.md` §3 T7) : chiffres groupés en grand
/// (monospace) et QR de la valeur brute (`QRCodeImage`, correction `M`, sans lissage), au plus grand côté que l'écran
/// permet (`proportionQR` du petit côté), en portrait comme en paysage. Fond clair fixe en clair comme en sombre : un
/// code sombre sur fond clair reste lisible par tout scanner. Le contenu est fourni par l'écran (valeur relue au serveur,
/// jamais calculée ici) ; la mise en veille est gérée par l'écran (`IdleTimerController`), pas par ce composant.
public struct FullScreenCodeView: View {
    nonisolated public static let proportionQR: CGFloat = 0.7

    /// Identifiants d'accessibilité du plein écran.
    public struct Identifiants: Sendable {
        public var vue: String
        public var code: String
        public var qr: String
        public var fermer: String

        public init(vue: String, code: String, qr: String, fermer: String) {
            self.vue = vue; self.code = code; self.qr = qr; self.fermer = fermer
        }
    }

    private let chiffres: String
    private let valeur: String
    private let consigne: String?
    private let libelleQR: String
    private let libelleFermer: String
    private let identifiants: Identifiants
    private let onClose: () -> Void

    /// `chiffres` : code affiché (« 123 456 ») ; `valeur` : chaîne encodée dans le QR (« 123456 ») ; `consigne` : ligne
    /// optionnelle sous le code (prochain pointage attendu).
    public init(chiffres: String, valeur: String, consigne: String?, libelleQR: String, libelleFermer: String,
                identifiants: Identifiants, onClose: @escaping () -> Void) {
        self.chiffres = chiffres; self.valeur = valeur; self.consigne = consigne; self.libelleQR = libelleQR
        self.libelleFermer = libelleFermer; self.identifiants = identifiants; self.onClose = onClose
    }

    /// Côté du QR (zone de silence comprise) pour une surface donnée : `proportionQR` du petit côté, borné par la place
    /// laissée au code en paysage.
    nonisolated public static func coteQR(pour taille: CGSize) -> CGFloat {
        let petit = min(taille.width, taille.height)
        guard petit.isFinite, petit > 0 else { return 0 }
        return (petit * proportionQR).rounded(.down)
    }

    public var body: some View {
        GeometryReader { geometrie in
            let paysage = geometrie.size.width > geometrie.size.height
            let cote = Self.coteQR(pour: geometrie.size)
            let qr = QRCodeImage(valeur, side: max(0, cote - 2 * QRCodeImage.quietZone), accessibilityLabel: libelleQR,
                                 identifier: identifiants.qr)
            ZStack(alignment: .topTrailing) {
                Color(hex: QRCodeImage.backgroundHex).ignoresSafeArea()
                Group {
                    if paysage {
                        HStack(spacing: JoleneSpacing.xl) {
                            qr
                            texte
                        }
                    } else {
                        VStack(spacing: JoleneSpacing.xl) {
                            texte
                            qr
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Button(action: onClose) {
                    Text(libelleFermer)
                        .font(JoleneFont.button)
                        .foregroundStyle(Color(hex: QRCodeImage.foregroundHex))
                        .padding(.horizontal, JoleneSpacing.lg)
                        .frame(minHeight: 44)
                        .background(Capsule().strokeBorder(Color(hex: QRCodeImage.foregroundHex), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(JoleneSpacing.lg)
                .accessibilityIdentifier(identifiants.fermer)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifiants.vue)
    }

    private var texte: some View {
        VStack(spacing: JoleneSpacing.md) {
            Text(chiffres)
                .font(.system(.largeTitle, design: .monospaced).weight(.black))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(Color(hex: QRCodeImage.foregroundHex))
                .accessibilityIdentifier(identifiants.code)
            if let consigne {
                Text(consigne)
                    .font(JoleneFont.headline)
                    .foregroundStyle(Color(hex: QRCodeImage.foregroundHex))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, JoleneSpacing.lg)
    }
}
