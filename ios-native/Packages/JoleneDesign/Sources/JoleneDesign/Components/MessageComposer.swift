import SwiftUI

/// Champ d'envoi d'un message, port de `src/components/messagerie/InputMessage.tsx` : saisie multiligne
/// (jusqu'à 5 lignes, `max-height 100px` du web), 4 000 caractères au plus, compteur « N caractères restants »
/// affiché à partir de 3 500 (`InputMessage.tsx` l.30-31, l.150), en alerte sous 100, bouton d'envoi désactivé
/// pendant l'appel et sur un texte vide après `trim()`. Conversation archivée : le champ est remplacé par la
/// mention verbatim « Conversation archivée — lecture seule. ». Textes repris du web, gardés par les tests.
///
/// Le composant n'envoie rien : `onSend` laisse l'écran (lot 4 T7b) appeler l'edge `messagerie-validate` avec
/// `MessageComposer.trimmed(text)` puis vider le champ après relecture. `onActivity` signale focus, saisie et
/// perte de focus pour l'indicateur de saisie (`fn_typing_start` / `fn_typing_stop`, cadence portée par T7b).
///
/// Comptage : unités UTF-16, comme `texte.length` et `slice(0, 4000)` du web (« 👩‍⚕️ » compte 5). Écart
/// assumé : là où `slice` coupe une paire de substitution, le natif retire le caractère entier. Écart assumé :
/// la touche Retour insère une ligne (le web envoie sur Entrée sans Maj.) ; l'envoi passe par le bouton.
/// Comme sur le web (`disabled={envoi}`), le champ est désactivé pendant l'envoi puis le focus est rendu.
public struct MessageComposer: View {
    public enum Activity: Equatable, Sendable { case focus, change, blur }

    /// Identifiants dérivés : `<base>-champ`, `-envoyer`, `-compteur`, `-archivee`.
    public struct Identifiers: Equatable, Sendable {
        public var base: String
        public init(_ base: String) { self.base = base }
        public var field: String { "\(base)-champ" }
        public var send: String { "\(base)-envoyer" }
        public var counter: String { "\(base)-compteur" }
        public var archived: String { "\(base)-archivee" }
    }

    nonisolated public static let maxLength = 4000
    nonisolated public static let warnThreshold = 3500
    /// `restantes < 100 ? 'text-destructive'` : encre d'alerte.
    nonisolated public static let urgentBelow = 100
    nonisolated public static let placeholder = "Votre message…"
    nonisolated public static let fieldAccessibilityLabel = "Saisir un message"
    nonisolated public static let sendAccessibilityLabel = "Envoyer le message"
    nonisolated public static let archivedText = "Conversation archivée — lecture seule."
    nonisolated public static let minimumTapTarget: CGFloat = 44
    nonisolated public static let maximumVisibleLines = 5
    nonisolated public static let archivedInkHSL = JoleneColor.bubblegumHSL

    /// Encre du compteur : bubblegum (`text-muted-foreground`), rose-800 en alerte (le web : `text-destructive`).
    nonisolated public static func counterInkHSL(urgent: Bool) -> JoleneDynamicHSL {
        urgent ? JoleneColor.rose800HSL : JoleneColor.bubblegumHSL
    }

    /// Longueur au sens de JavaScript (`String.prototype.length`) : unités UTF-16.
    nonisolated public static func length(_ text: String) -> Int { text.utf16.count }

    /// Texte borné à `maxLength` unités UTF-16, sans jamais couper un caractère.
    nonisolated public static func limited(_ text: String) -> String {
        guard length(text) > maxLength else { return text }
        var unites = 0
        var fin = text.startIndex
        for index in text.indices {
            let suivant = text.index(after: index)
            let taille = text.utf16.distance(from: index, to: suivant)
            guard unites + taille <= maxLength else { break }
            unites += taille
            fin = suivant
        }
        return String(text[..<fin])
    }

    /// `String.prototype.trim()` : WhiteSpace (U+0009, U+000B, U+000C, U+0020, U+00A0, U+FEFF, catégorie Zs) et
    /// LineTerminator (U+000A, U+000D, U+2028, U+2029). U+0085, U+180E et U+200B ne sont pas rognés, comme en JS.
    nonisolated public static func trimmed(_ text: String) -> String {
        let scalaires = text.unicodeScalars
        guard let debut = scalaires.firstIndex(where: { !estEspaceJS($0) }) else { return "" }
        let fin = scalaires.lastIndex(where: { !estEspaceJS($0) }) ?? debut
        return String(String.UnicodeScalarView(scalaires[debut...fin]))
    }

    nonisolated static func estEspaceJS(_ scalaire: Unicode.Scalar) -> Bool {
        switch scalaire.value {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }

    nonisolated public static func remaining(_ text: String) -> Int { maxLength - length(text) }

    /// « {restantes} caractères restants » (verbatim, sans accord) dès `warnThreshold`, sinon `nil`.
    nonisolated public static func counterText(for text: String) -> String? {
        length(text) >= warnThreshold ? "\(remaining(text)) caractères restants" : nil
    }

    nonisolated public static func isCounterUrgent(for text: String) -> Bool { remaining(text) < urgentBelow }

    /// `disabled={envoi || !texte.trim()}`, et aucun envoi sur une conversation archivée.
    nonisolated public static func canSend(text: String, isSending: Bool, isArchived: Bool) -> Bool {
        !isArchived && !isSending && !trimmed(text).isEmpty
    }

    @Binding private var text: String
    private let isSending: Bool
    private let isArchived: Bool
    private let identifiers: Identifiers
    private let onActivity: ((Activity) -> Void)?
    private let onSend: () -> Void
    @FocusState private var isFocused: Bool
    @State private var refocusAfterSend = false

    public init(text: Binding<String>, isSending: Bool = false, isArchived: Bool = false, identifier: String = "message-composer",
                onActivity: ((Activity) -> Void)? = nil, onSend: @escaping () -> Void) {
        self._text = text; self.isSending = isSending; self.isArchived = isArchived
        self.identifiers = Identifiers(identifier); self.onActivity = onActivity; self.onSend = onSend
    }

    public var body: some View {
        if isArchived {
            Text(Self.archivedText)
                .font(JoleneFont.caption.italic())
                .foregroundStyle(Color(Self.archivedInkHSL))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, JoleneSpacing.lg)
                .padding(.vertical, JoleneSpacing.md)
                .background(JoleneColor.lavender)
                .accessibilityIdentifier(identifiers.archived)
        } else {
            VStack(alignment: .trailing, spacing: JoleneSpacing.xs) {
                HStack(alignment: .bottom, spacing: JoleneSpacing.sm) {
                    champ
                    SendButton(isEnabled: Self.canSend(text: text, isSending: isSending, isArchived: isArchived), isSending: isSending,
                               identifier: identifiers.send, action: envoyer)
                }
                if let compteur = Self.counterText(for: text) {
                    Text(compteur)
                        .font(Font.system(.caption2))
                        .foregroundStyle(Color(Self.counterInkHSL(urgent: Self.isCounterUrgent(for: text))))
                        .accessibilityIdentifier(identifiers.counter)
                }
            }
            .padding(.horizontal, JoleneSpacing.md)
            .padding(.vertical, JoleneSpacing.md)
            .background(JoleneColor.cloud)
            .overlay(alignment: .top) { Rectangle().fill(JoleneColor.rose100).frame(height: 1) }
            .onChange(of: isFocused) { onActivity?($0 ? .focus : .blur) }
            .onChange(of: isSending) { enCours in
                if !enCours, refocusAfterSend {
                    refocusAfterSend = false
                    isFocused = true
                }
            }
        }
    }

    private var champ: some View {
        TextField(Self.placeholder, text: saisie, axis: .vertical)
            .lineLimit(1...Self.maximumVisibleLines)
            .font(JoleneFont.body)
            .foregroundStyle(JoleneColor.midnight)
            .focused($isFocused)
            .disabled(isSending)
            .padding(.horizontal, JoleneSpacing.lg)
            .padding(.vertical, 10)
            .frame(minHeight: Self.minimumTapTarget)
            .background(JoleneColor.lavender)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
            .overlay(RoundedRectangle(cornerRadius: JoleneRadius.field).strokeBorder(JoleneColor.rose100, lineWidth: 1))
            .accessibilityLabel(Self.fieldAccessibilityLabel)
            .accessibilityIdentifier(identifiers.field)
    }

    /// Saisie bornée à 4 000 unités UTF-16 (`setTexte(e.target.value.slice(0, MAX_LENGTH))`), activité signalée.
    private var saisie: Binding<String> {
        Binding(get: { text }, set: { nouveau in
            text = Self.limited(nouveau)
            onActivity?(.change)
        })
    }

    private func envoyer() {
        guard Self.canSend(text: text, isSending: isSending, isArchived: isArchived) else { return }
        refocusAfterSend = isFocused
        onSend()
    }

    /// Bouton d'envoi rond (`!min-h-11 !min-w-11` du web), 44 pt au moins, indicateur pendant l'envoi.
    struct SendButton: View {
        let isEnabled: Bool
        let isSending: Bool
        let identifier: String
        let action: () -> Void

        init(isEnabled: Bool, isSending: Bool, identifier: String, action: @escaping () -> Void) {
            self.isEnabled = isEnabled; self.isSending = isSending; self.identifier = identifier; self.action = action
        }

        var body: some View {
            Button(action: action) {
                Group {
                    if isSending {
                        ProgressView().tint(JoleneColor.onGradient)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(JoleneColor.onGradient)
                    }
                }
                .frame(width: MessageComposer.minimumTapTarget, height: MessageComposer.minimumTapTarget)
                .background(JoleneColor.heroGradientFull)
                .clipShape(Circle())
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled || isSending ? 1 : 0.45)
            .accessibilityLabel(MessageComposer.sendAccessibilityLabel)
            .accessibilityIdentifier(identifier)
            .accessibilityShowsLargeContentViewer {
                Image(systemName: "paperplane.fill")
                Text(MessageComposer.sendAccessibilityLabel)
            }
        }
    }
}
