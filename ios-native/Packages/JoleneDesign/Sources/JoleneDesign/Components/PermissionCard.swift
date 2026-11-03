import SwiftUI

/// Carte de demande d'autorisation, port du dialogue de `src/components/DemandePermissionPush.tsx`
/// (l.130-170) : pastille d'icône `Bell` (`bg-primary/10 text-primary`), titre, description, encart des
/// avantages (`bg-muted/50`, coches) et note, puis « Activer les notifications » / « Plus tard ». Sert au
/// pré-prompt push (T5, D1 : jamais au login, à partir du 2e lancement) et, sans avantages ni action
/// secondaire, à la carte d'état d'autorisation des préférences (T6). La carte ne demande rien au système :
/// l'écran appelle le port d'autorisation **au tap seulement** et décide quand l'afficher.
///
/// Textes : `Content.pushSoignant` reprend `TEXTES.soignant` verbatim (l.20-28, note l.149, boutons l.158 et
/// l.164 ; garde de dérive dans les tests). Toute autre carte reçoit ses textes de l'écran (web ou serveur
/// verbatim, HARD STOP n°4). Écarts de présentation assumés : boutons empilés, action principale en haut
/// (comme `ConfirmationSheet`) au lieu de « Plus tard » à gauche ; coche SF Symbol au lieu de l'emoji ✅ ;
/// note en `bubblegum` plein (le `text-muted-foreground/70` du web passerait sous 4,5:1).
public struct PermissionCard: View {
    public struct Content: Equatable, Sendable {
        public var title: String
        public var message: String
        public var benefits: [String]
        public var footnote: String?
        public var primaryTitle: String
        public var secondaryTitle: String?
        public var systemImage: String
        /// Identifiant racine ; les éléments reçoivent `-title`, `-message`, `-benefits`, `-benefit-<n>`,
        /// `-footnote`, `-primary`, `-secondary`.
        public var identifier: String

        public init(title: String, message: String, benefits: [String] = [], footnote: String? = nil, primaryTitle: String,
                    secondaryTitle: String? = nil, systemImage: String = "bell", identifier: String) {
            self.title = title; self.message = message; self.benefits = benefits; self.footnote = footnote
            self.primaryTitle = primaryTitle; self.secondaryTitle = secondaryTitle; self.systemImage = systemImage
            self.identifier = identifier
        }

        /// Pré-prompt soignant, verbatim `DemandePermissionPush.tsx` (`TEXTES.soignant`, l.20-28 ; l.149 ; l.158 ; l.164).
        public static func pushSoignant(identifier: String) -> Content {
            Content(title: "Recevoir les alertes missions ?",
                    message: "Jolene vous envoie des notifications pour les nouvelles missions, les rappels de pointage et les mises à jour de vos contrats.",
                    benefits: ["Nouvelles missions correspondant à votre profil", "Rappels de pointage avant vos missions",
                               "Mises à jour de contrats et paiements"],
                    footnote: "Vous pouvez désactiver les notifications à tout moment depuis les réglages de votre téléphone.",
                    primaryTitle: "Activer les notifications", secondaryTitle: "Plus tard", systemImage: "bell",
                    identifier: identifier)
        }

        public var titleIdentifier: String { "\(identifier)-title" }
        public var messageIdentifier: String { "\(identifier)-message" }
        public var benefitsIdentifier: String { "\(identifier)-benefits" }
        public var footnoteIdentifier: String { "\(identifier)-footnote" }
        public var primaryIdentifier: String { "\(identifier)-primary" }
        public var secondaryIdentifier: String { "\(identifier)-secondary" }
        public func benefitIdentifier(index: Int) -> String { "\(identifier)-benefit-\(index + 1)" }
    }

    /// Pas de double demande : l'action principale est bloquée pendant l'appel.
    nonisolated public static func isPrimaryEnabled(isLoading: Bool) -> Bool { !isLoading }
    /// « Plus tard » attend aussi la fin de la demande système en cours.
    nonisolated public static func isSecondaryEnabled(isLoading: Bool) -> Bool { !isLoading }

    nonisolated public static let surfaceHSL = JoleneColor.cloudHSL
    nonisolated public static let benefitsSurfaceHSL = JoleneColor.lavenderHSL
    nonisolated public static let iconInkHSL = JoleneColor.rose700HSL
    nonisolated public static let iconBackgroundHSL = JoleneColor.rose100HSL
    nonisolated public static let titleInkHSL = JoleneColor.midnightHSL
    nonisolated public static let secondaryInkHSL = JoleneColor.bubblegumHSL
    nonisolated public static let benefitIconInkHSL = JoleneColor.cyan900HSL

    private let content: Content
    private let isLoading: Bool
    private let onPrimary: () -> Void
    private let onSecondary: (() -> Void)?

    public init(_ content: Content, isLoading: Bool = false, onPrimary: @escaping () -> Void, onSecondary: (() -> Void)? = nil) {
        self.content = content; self.isLoading = isLoading; self.onPrimary = onPrimary; self.onSecondary = onSecondary
    }

    public var body: some View {
        VStack(spacing: JoleneSpacing.lg) {
            Image(systemName: content.systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color(Self.iconInkHSL))
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color(Self.iconBackgroundHSL)))
                .accessibilityHidden(true)
            VStack(spacing: JoleneSpacing.sm) {
                Text(content.title)
                    .font(JoleneFont.headline)
                    .foregroundStyle(Color(Self.titleInkHSL))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(content.titleIdentifier)
                Text(content.message)
                    .font(JoleneFont.callout)
                    .foregroundStyle(Color(Self.secondaryInkHSL))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(content.messageIdentifier)
            }
            if !content.benefits.isEmpty || content.footnote != nil {
                benefitsBox
            }
            VStack(spacing: JoleneSpacing.sm) {
                JoleneButton(content.primaryTitle, style: .primary, isLoading: isLoading) {
                    guard Self.isPrimaryEnabled(isLoading: isLoading) else { return }
                    onPrimary()
                }
                .disabled(!Self.isPrimaryEnabled(isLoading: isLoading))
                .accessibilityIdentifier(content.primaryIdentifier)
                if let secondaryTitle = content.secondaryTitle, let onSecondary {
                    JoleneButton(secondaryTitle, style: .secondary) {
                        guard Self.isSecondaryEnabled(isLoading: isLoading) else { return }
                        onSecondary()
                    }
                    .disabled(!Self.isSecondaryEnabled(isLoading: isLoading))
                    .accessibilityIdentifier(content.secondaryIdentifier)
                }
            }
        }
        .padding(JoleneSpacing.xl)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .background(Color(Self.surfaceHSL))
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(content.identifier)
    }

    private var benefitsBox: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            ForEach(Array(content.benefits.enumerated()), id: \.offset) { index, avantage in
                HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(Self.benefitIconInkHSL))
                        .accessibilityHidden(true)
                    Text(avantage)
                        .foregroundStyle(Color(Self.secondaryInkHSL))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(JoleneFont.caption)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(content.benefitIdentifier(index: index))
            }
            if let footnote = content.footnote {
                Text(footnote)
                    .font(JoleneFont.caption.italic())
                    .foregroundStyle(Color(Self.secondaryInkHSL))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, content.benefits.isEmpty ? 0 : JoleneSpacing.xs)
                    .accessibilityIdentifier(content.footnoteIdentifier)
            }
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(Self.benefitsSurfaceHSL))
        .overlay(RoundedRectangle(cornerRadius: JoleneRadius.field).strokeBorder(JoleneColor.rose100, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(content.benefitsIdentifier)
    }
}
