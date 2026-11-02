import SwiftUI

/// Carte mission de la liste Explorer. Reçoit des chaînes déjà formatées : la
/// rémunération et la période viennent des valeurs serveur formatées par le cœur
/// (`MissionPresentation`), jamais recalculées ici.
public struct MissionCard: View {
    public struct Content: Equatable, Sendable {
        public var titre: String
        public var etablissement: String
        public var lieu: String?
        public var periode: String
        public var remuneration: String
        public var estUrgente: Bool
        public var typeContrat: String?

        public init(titre: String, etablissement: String, lieu: String? = nil, periode: String,
                    remuneration: String, estUrgente: Bool = false, typeContrat: String? = nil) {
            self.titre = titre; self.etablissement = etablissement; self.lieu = lieu; self.periode = periode
            self.remuneration = remuneration; self.estUrgente = estUrgente; self.typeContrat = typeContrat
        }
    }

    private let content: Content

    public init(_ content: Content) { self.content = content }

    public var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                Text(content.titre)
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.midnight)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if content.estUrgente {
                    JoleneBadge("Urgente", tone: .warning)
                }
            }
            Text([content.etablissement, content.lieu].compactMap { $0 }.joined(separator: " · "))
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.bubblegum)
            HStack(spacing: JoleneSpacing.sm) {
                Label(content.periode, systemImage: "calendar")
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.midnight)
                Spacer(minLength: 0)
                if let typeContrat = content.typeContrat { JoleneBadge(typeContrat, tone: .info) }
            }
            Text(content.remuneration)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.rose700)
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .overlay(RoundedRectangle(cornerRadius: JoleneRadius.card).strokeBorder(JoleneColor.rose100, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Ouvre le détail de la mission")
    }

    private var accessibilityText: String {
        var parts = [content.titre, content.etablissement]
        if let lieu = content.lieu { parts.append(lieu) }
        parts.append(content.periode)
        parts.append(content.remuneration)
        if content.estUrgente { parts.append("Urgente") }
        return parts.joined(separator: ", ")
    }
}

/// Pastille d'état, calquée sur `BadgeY2K` (success / warning / error / info).
public struct JoleneBadge: View {
    public enum Tone: Sendable { case success, warning, error, info }

    private let text: String
    private let tone: Tone

    public init(_ text: String, tone: Tone = .info) { self.text = text; self.tone = tone }

    public var body: some View {
        Text(text)
            .font(JoleneFont.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, JoleneSpacing.sm)
            .padding(.vertical, JoleneSpacing.xs)
            .background(background)
            .clipShape(Capsule())
    }

    private var foreground: Color {
        switch tone {
        case .success: return JoleneColor.cyan700
        case .warning: return JoleneColor.butter700
        case .error: return JoleneColor.rose700
        case .info: return JoleneColor.mauve700
        }
    }

    private var background: Color {
        switch tone {
        case .success: return JoleneColor.cyan.opacity(0.18)
        case .warning: return JoleneColor.butter100
        case .error: return JoleneColor.rose100
        case .info: return JoleneColor.mauve100
        }
    }
}
