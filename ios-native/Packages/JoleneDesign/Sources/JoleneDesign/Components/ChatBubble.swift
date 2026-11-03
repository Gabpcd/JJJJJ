import SwiftUI

/// Bulle d'un message de la messagerie, port du fil de `src/pages/PageMessagerie.tsx` (l.737-773) :
/// - `moi` : à droite, `bg-gradient-hero` (encre `#2B183D`), coin bas-droit réduit (`rounded-br-md`) ;
/// - `interlocuteur` : à gauche, `bg-card` bordé, coin bas-gauche réduit ;
/// - `jolene` : message d'un admin Jolene (`est_admin`), à gauche, en-tête « Admin Jolene » ;
/// - `systeme` : message système (auteur nul `000…`), centré, en italique, sans heure, sur un fond `cloud`
///   **opaque** (écart assumé : `bg-card/60` du web dépend du fond du fil ; opaque, son contraste est celui mesuré).
/// Le contenu est affiché **verbatim**, retours à la ligne conservés (`whitespace-pre-wrap`), jamais tronqué, aligné
/// à gauche dans la bulle ; seule l'heure est alignée à droite (`text-right`). L'heure arrive formatée par l'appelant
/// (cœur). L'état `nonConfirme` (décision D8 du lot 4 : envoi sans renvoi automatique, relecture par l'écran) ajoute
/// sous la bulle la mention « Envoi non confirmé », élément d'accessibilité distinct identifié `chat-non-confirme`
/// (blueprint lot 4 T7b, injectable), lu juste après le message.
/// Largeur : `max-w-[80%]` du web rendue par une marge latérale minimale de 48 pt et un plafond de 520 pt (iPad).
/// « Équipe établissement » (vue établissement) relève du lot 5.
public struct ChatBubble: View {
    public enum Kind: CaseIterable, Sendable {
        case moi, interlocuteur, jolene, systeme

        /// Alignement de la bulle dans la largeur du fil.
        public var frameAlignment: Alignment {
            switch self {
            case .moi: return .trailing
            case .interlocuteur, .jolene: return .leading
            case .systeme: return .center
            }
        }

        /// Fond `bg-gradient-hero` (seulement pour ses propres messages).
        public var usesGradient: Bool { self == .moi }

        /// Encre du contenu ; `nil` sur le dégradé (encre fixe `JoleneColor.onGradient`).
        public var textInkHSL: JoleneDynamicHSL? {
            switch self {
            case .moi: return nil
            case .interlocuteur, .jolene: return JoleneColor.midnightHSL
            case .systeme: return JoleneColor.bubblegumHSL
            }
        }

        /// Fond plein ; `nil` sur le dégradé.
        public var backgroundHSL: JoleneDynamicHSL? { self == .moi ? nil : JoleneColor.cloudHSL }

        /// Encre de l'heure (`text-muted-foreground`) ; `nil` sur le dégradé (encre du contenu) et pour un message
        /// système (sans heure).
        public var metaInkHSL: JoleneDynamicHSL? {
            switch self {
            case .interlocuteur, .jolene: return JoleneColor.bubblegumHSL
            case .moi, .systeme: return nil
            }
        }

        var tail: BubbleShape.Tail {
            switch self {
            case .moi: return .bottomTrailing
            case .interlocuteur, .jolene: return .bottomLeading
            case .systeme: return .none
            }
        }
    }

    /// Envoi confirmé par la relecture serveur, ou non confirmé (réponse perdue, délai) : jamais renvoyé seul.
    public enum Delivery: Sendable { case confirme, nonConfirme }

    /// En-tête d'un message admin, verbatim `PageMessagerie.tsx` l.760.
    nonisolated public static let jolenePrefix = "Admin Jolene"
    /// Mention d'un envoi non confirmé (DECISIONS_LOT4 D8).
    nonisolated public static let nonConfirmeText = "Envoi non confirmé"
    /// Identifiant par défaut de la mention, blueprint lot 4 T7b.
    nonisolated public static let defaultNonConfirmeIdentifier = "chat-non-confirme"
    /// Fond du message système : `cloud` opaque.
    nonisolated public static let systemBackgroundHSL = JoleneColor.cloudHSL
    nonisolated public static let systemBackgroundOpacity: Double = 1
    /// Auteur vocalisé de ses propres messages.
    nonisolated public static let selfSpokenName = "Vous"
    /// Aucune limite de lignes : `whitespace-pre-wrap break-words`.
    nonisolated public static let contentLineLimit: Int? = nil
    /// En-tête « Admin Jolene » : `text-jolene-rose-700` (4,62:1 sur la bulle `cloud`).
    nonisolated public static let jolenePrefixInkHSL = JoleneColor.rose700HSL
    /// « Envoi non confirmé », posé sous la bulle sans fond propre : rose-800, AA sur les surfaces héritées.
    nonisolated public static let nonConfirmeInkHSL = JoleneColor.rose800HSL
    nonisolated public static let maximumBubbleWidth: CGFloat = 520
    nonisolated public static let minimumSideSpacing: CGFloat = 48

    /// Libellé vocalisé de la bulle (un élément par message, identifiant de l'appelant, `chat-message-<id>` en T7b) :
    /// « Vous : Bonjour, 14:32 », « Clinique Démo : Bonjour, 09:05 », « Admin Jolene : … » ; message système :
    /// contenu seul. L'état « Envoi non confirmé » n'y figure pas : il est porté par son propre élément, juste après.
    nonisolated public static func accessibilityLabel(contenu: String, kind: Kind, auteur: String?, heure: String?) -> String {
        let nom: String?
        switch kind {
        case .moi: nom = selfSpokenName
        case .interlocuteur: nom = auteur
        case .jolene: nom = jolenePrefix
        case .systeme: nom = nil
        }
        var texte = nom.map { "\($0) : \(contenu)" } ?? contenu
        if kind != .systeme, let heure { texte += ", \(heure)" }
        return texte
    }

    private let contenu: String
    private let kind: Kind
    private let heure: String?
    private let auteur: String?
    private let delivery: Delivery
    private let identifier: String?
    private let nonConfirmeIdentifier: String

    /// - Parameters:
    ///   - heure: heure déjà formatée par le cœur (`HH:mm` de Paris), absente pour un message système.
    ///   - auteur: nom vocalisé de l'interlocuteur (jamais affiché dans la bulle, comme le web).
    ///   - identifier: identifiant de la bulle (`chat-message-<id>`).
    ///   - nonConfirmeIdentifier: identifiant de la mention « Envoi non confirmé » (`chat-non-confirme`).
    public init(_ contenu: String, kind: Kind, heure: String? = nil, auteur: String? = nil, delivery: Delivery = .confirme,
                identifier: String? = nil, nonConfirmeIdentifier: String = ChatBubble.defaultNonConfirmeIdentifier) {
        self.contenu = contenu; self.kind = kind; self.heure = heure; self.auteur = auteur
        self.delivery = delivery; self.identifier = identifier; self.nonConfirmeIdentifier = nonConfirmeIdentifier
    }

    public var body: some View {
        VStack(alignment: kind == .moi ? .trailing : .leading, spacing: JoleneSpacing.xs) {
            HStack(spacing: 0) {
                if kind != .interlocuteur && kind != .jolene { Spacer(minLength: Self.minimumSideSpacing) }
                BubbleWidthLayout(maximum: Self.maximumBubbleWidth) { bulle }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.accessibilityLabel(contenu: contenu, kind: kind, auteur: auteur, heure: heure))
                    .accessibilityIdentifier(identifier ?? "")
                if kind != .moi { Spacer(minLength: Self.minimumSideSpacing) }
            }
            if delivery == .nonConfirme {
                Label(Self.nonConfirmeText, systemImage: "exclamationmark.circle")
                    .font(JoleneFont.caption.weight(.semibold))
                    .foregroundStyle(Color(Self.nonConfirmeInkHSL))
                    .frame(maxWidth: .infinity, alignment: kind == .moi ? .trailing : .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.nonConfirmeText)
                    .accessibilityIdentifier(nonConfirmeIdentifier)
            }
        }
        .frame(maxWidth: .infinity, alignment: kind.frameAlignment)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var bulle: some View {
        if kind == .systeme {
            Text(contenu)
                .font(JoleneFont.caption.italic())
                .foregroundStyle(Color(JoleneColor.bubblegumHSL))
                .multilineTextAlignment(.center)
                .lineLimit(Self.contentLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, JoleneSpacing.md)
                .padding(.vertical, JoleneSpacing.xs)
                .background(Color(Self.systemBackgroundHSL).opacity(Self.systemBackgroundOpacity))
                .clipShape(Capsule())
        } else {
            // En-tête et contenu à gauche, heure à droite (`text-right`), sans élargir la bulle : la colonne prend la
            // largeur de son plus large enfant (contenu, en-tête ou heure).
            BubbleColumnLayout(spacing: 2) {
                if kind == .jolene {
                    Label(Self.jolenePrefix, systemImage: "shield")
                        .font(Font.system(.caption2).weight(.bold))
                        .foregroundStyle(Color(Self.jolenePrefixInkHSL))
                }
                Text(contenu)
                    .font(JoleneFont.callout)
                    .foregroundStyle(encre)
                    .multilineTextAlignment(.leading)
                    .lineLimit(Self.contentLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                if let heure {
                    Text(heure)
                        .font(Font.system(.caption2))
                        .foregroundStyle(kind.metaInkHSL.map { Color($0) } ?? encre)
                        .layoutValue(key: BubbleColumnLayout.AlignedTrailing.self, value: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, JoleneSpacing.sm)
            .background(fond)
            .clipShape(BubbleShape(tail: kind.tail))
            .overlay(BubbleShape(tail: kind.tail).stroke(kind.usesGradient ? Color.clear : JoleneColor.rose100, lineWidth: 1))
        }
    }

    private var encre: Color { kind.textInkHSL.map { Color($0) } ?? JoleneColor.onGradient }

    @ViewBuilder private var fond: some View {
        if kind.usesGradient { JoleneColor.heroGradientFull } else { JoleneColor.cloud }
    }
}

/// Plafonne la largeur proposée à son unique enfant sans l'élargir (contrairement à `frame(maxWidth:)`, qui
/// remplit la proposition) : une bulle courte reste courte, une bulle longue s'arrête à `maximum` sur iPad.
struct BubbleWidthLayout: Layout {
    var maximum: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let enfant = subviews.first else { return .zero }
        let largeur = proposal.width.map { min($0, maximum) } ?? maximum
        return enfant.sizeThatFits(ProposedViewSize(width: largeur, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let enfant = subviews.first else { return }
        enfant.place(at: bounds.origin, proposal: ProposedViewSize(width: min(bounds.width, maximum), height: bounds.height))
    }
}

/// Colonne de la bulle : chaque enfant à sa taille idéale dans la largeur proposée, empilés ; la colonne prend la
/// largeur du plus large. Enfants alignés à gauche, sauf ceux marqués `AlignedTrailing` (l'heure, `text-right`),
/// alignés à droite. Contrairement à `VStack(alignment: .trailing)`, un contenu court reste à gauche sous un
/// en-tête « Admin Jolene » ou une heure plus larges ; contrairement à un cadre `maxWidth: .infinity`, la bulle
/// n'est pas élargie.
struct BubbleColumnLayout: Layout {
    struct AlignedTrailing: LayoutValueKey {
        static let defaultValue = false
    }

    var spacing: CGFloat

    /// Abscisse d'un enfant de largeur `width` dans une colonne `bounds` : bord gauche, ou bord droit s'il est marqué.
    static func originX(width: CGFloat, in bounds: CGRect, alignedTrailing: Bool) -> CGFloat {
        alignedTrailing ? bounds.maxX - width : bounds.minX
    }

    private func tailles(_ subviews: Subviews, width: CGFloat?) -> [CGSize] {
        subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let mesures = tailles(subviews, width: proposal.width)
        let largeur = mesures.map(\.width).max() ?? 0
        let hauteur = mesures.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, mesures.count - 1))
        return CGSize(width: proposal.width.map { min($0, largeur) } ?? largeur, height: hauteur)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for (enfant, taille) in zip(subviews, tailles(subviews, width: bounds.width)) {
            let largeur = min(taille.width, bounds.width)
            let x = Self.originX(width: largeur, in: bounds, alignedTrailing: enfant[AlignedTrailing.self])
            enfant.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: largeur, height: taille.height))
            y += taille.height + spacing
        }
    }
}

/// Bulle arrondie à 16 pt dont un coin bas est réduit à 6 pt (`rounded-2xl rounded-br-md` / `rounded-bl-md`),
/// partagée avec `TypingIndicator`. `UnevenRoundedRectangle` n'existe qu'à partir d'iOS 17.
struct BubbleShape: Shape {
    enum Tail: Sendable { case bottomLeading, bottomTrailing, none }

    var tail: Tail
    var radius: CGFloat = 16
    var tailRadius: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let plafond = min(rect.width, rect.height) / 2
        let grand = min(radius, plafond), petit = min(tailRadius, plafond)
        let basDroit = tail == .bottomTrailing ? petit : grand
        let basGauche = tail == .bottomLeading ? petit : grand
        var chemin = Path()
        chemin.move(to: CGPoint(x: rect.minX + grand, y: rect.minY))
        chemin.addLine(to: CGPoint(x: rect.maxX - grand, y: rect.minY))
        chemin.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + grand), radius: grand)
        chemin.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - basDroit))
        chemin.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - basDroit, y: rect.maxY),
                      radius: basDroit)
        chemin.addLine(to: CGPoint(x: rect.minX + basGauche, y: rect.maxY))
        chemin.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - basGauche),
                      radius: basGauche)
        chemin.addLine(to: CGPoint(x: rect.minX, y: rect.minY + grand))
        chemin.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + grand, y: rect.minY), radius: grand)
        chemin.closeSubpath()
        return chemin
    }
}
