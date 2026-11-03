import SwiftUI
import UIKit

/// Les trois actions du paquet de swipe, port de `src/components/swipe/BoutonsActionSwipe.tsx` (✕ DISLIKE,
/// ⭐ FAVORI, ❤️ LIKE, dans cet ordre) et de `StackCards.tsx` (glisser à gauche = passer, à droite = vérifier
/// avant de postuler). Le favori n'a pas de geste, comme sur le web. Aucune action n'écrit quoi que ce soit :
/// l'écran (lot 4 T3b) appelle le port et retire la carte après la réponse serveur.
public enum SwipeCardAction: String, CaseIterable, Sendable {
    case passer, sauvegarder, candidater

    /// Nom de l'action d'accessibilité (rotor VoiceOver « Actions ») : blueprint lot 4 T1b.
    public var accessibilityActionName: String {
        switch self {
        case .passer: return "Passer"
        case .sauvegarder: return "Sauvegarder"
        case .candidater: return "Candidater"
        }
    }

    /// Libellé vocalisé du bouton, verbatim `aria-label` de `BoutonsActionSwipe.tsx` (l.66, l.86, l.106).
    public var buttonAccessibilityLabel: String {
        switch self {
        case .passer: return "Passer cette mission"
        case .sauvegarder: return "Sauvegarder cette mission pour y revenir"
        case .candidater: return "Vérifier le planning avant de postuler à cette mission"
        }
    }

    /// Icônes du web (`X`, `Star`, `Heart` de lucide) en SF Symbols.
    public var systemImage: String {
        switch self {
        case .passer: return "xmark"
        case .sauvegarder: return "star.fill"
        case .candidater: return "heart.fill"
        }
    }

    /// Diamètre du bouton : `h-14 w-14` (56 pt) pour ✕ et ⭐, `h-16 w-16` (64 pt) pour ❤️ ; ≥ 44 pt.
    public var buttonDiameter: CGFloat { self == .candidater ? 64 : 56 }

    /// Encre de l'icône sur le fond du bouton (`cloud`) ; `nil` pour le cœur, posé sur le dégradé hero avec
    /// l'encre `onGradient`. Pour l'étoile : contour `butter800` (≥ 3:1) sur un remplissage `butter400`.
    public var iconInkHSL: JoleneDynamicHSL? {
        switch self {
        case .passer: return JoleneColor.bubblegumHSL
        case .sauvegarder: return JoleneColor.butter800HSL
        case .candidater: return nil
        }
    }

    /// Identifiant du bouton : `<prefix>-passer`, `<prefix>-sauvegarder`, `<prefix>-candidater`.
    public func identifier(prefix: String) -> String { "\(prefix)-\(rawValue)" }
}

/// Règles pures du geste de `SwipeCardStack`, port de `StackCards.tsx` : drag établi au-delà de 8 pt sur l'axe
/// horizontal (un départ vertical est ignoré : la carte ne bouge pas), validation à 120 pt (blueprint lot 4 T1b ; le web
/// prend 30 % de la largeur, ≈ 117 px sur un iPhone de 390 pt), rotation `dx / 14` bornée à ±15°, indicateurs
/// « VÉRIFIER » / « SUIVANT » d'opacité `dx / 80`, deux cartes de fond en parallaxe.
public enum SwipeCardGesture {
    public static let threshold: CGFloat = 120
    public static let activationDistance: CGFloat = 8
    public static let maxRotationDegrees: Double = 15
    public static let rotationDivisor: Double = 14
    public static let indicatorDistance: CGFloat = 80
    /// `items.slice(1, 3)` : deux cartes visibles sous la carte du dessus.
    public static let visibleBackgroundCards = 2

    /// Axe du geste, décidé une fois au-delà de `activationDistance` (`StackCards.tsx` l.81-84) ; à égalité, vertical.
    public enum Axis: Equatable, Sendable { case undetermined, horizontal, vertical }

    public static func axis(for translation: CGSize) -> Axis {
        let dx = abs(translation.width), dy = abs(translation.height)
        guard max(dx, dy) >= activationDistance else { return .undetermined }
        return dy >= dx ? .vertical : .horizontal
    }

    /// Action au relâchement : ≥ 120 pt à droite → `candidater` (ouvre le récapitulatif), à gauche → `passer` ;
    /// en deçà, `nil` (la carte revient au centre).
    public static func decision(forHorizontalTranslation dx: CGFloat) -> SwipeCardAction? {
        guard abs(dx) >= threshold else { return nil }
        return dx > 0 ? .candidater : .passer
    }

    public static func rotationDegrees(for dx: CGFloat) -> Double {
        max(-maxRotationDegrees, min(maxRotationDegrees, Double(dx) / rotationDivisor))
    }

    /// Opacité de l'indicateur de `action` pour un décalage `dx` ; toujours 0 pour le favori (aucun geste).
    public static func indicatorOpacity(for dx: CGFloat, toward action: SwipeCardAction) -> Double {
        let brut: Double
        switch action {
        case .candidater: brut = Double(dx / indicatorDistance)
        case .passer: brut = Double(-dx / indicatorDistance)
        case .sauvegarder: return 0
        }
        return max(0, min(1, brut))
    }

    /// Carte de fond de rang `depth` (1 ou 2) : `scale(1 − 0,04 × rang) translateY(8 × rang)`, opacité `1 − 0,2 × rang`.
    public struct BackgroundStyle: Equatable, Sendable {
        public var scale: Double
        public var offsetY: CGFloat
        public var opacity: Double
    }

    public static func backgroundStyle(depth: Int) -> BackgroundStyle {
        BackgroundStyle(scale: 1 - Double(depth) * 0.04, offsetY: CGFloat(depth) * 8, opacity: 1 - Double(depth) * 0.2)
    }

    /// Ressort du retour au centre et des changements du paquet ; `nil` (aucune animation) avec « Réduire les
    /// animations » (`prefers-reduced-motion` du web : délai de sortie 0).
    public static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78)
    }

    /// Identifiant de la carte du dessus : `<prefix>-carte-<id>` (cible du test de geste réel, décision D22).
    public static func cardIdentifier(prefix: String, itemID: String) -> String { "\(prefix)-carte-\(itemID)" }

    /// Indicateur affiché pendant le glissement, décoratif (`aria-hidden`) : textes verbatim de `StackCards.tsx`
    /// (l.196, l.206). Encres relevées pour l'AA (le web : rose-700 sur rose-100, 3,54:1, grand texte).
    public struct Indicator: Equatable, Sendable {
        public var text: String
        public var systemImage: String
        public var inkHSL: JoleneDynamicHSL
        public var backgroundHSL: JoleneDynamicHSL
        public var borderHSL: JoleneDynamicHSL
    }

    public static func indicator(for action: SwipeCardAction) -> Indicator? {
        switch action {
        case .candidater:
            return Indicator(text: "VÉRIFIER", systemImage: "calendar.badge.checkmark", inkHSL: JoleneColor.rose800HSL,
                             backgroundHSL: JoleneColor.rose100HSL, borderHSL: JoleneColor.roseHSL)
        case .passer:
            return Indicator(text: "SUIVANT", systemImage: "xmark", inkHSL: JoleneColor.bubblegumHSL,
                             backgroundHSL: JoleneColor.cloudHSL, borderHSL: JoleneColor.bubblegumHSL)
        case .sauvegarder:
            return nil
        }
    }
}

/// Paquet de cartes à glisser (lot 4, Explorer › Swipe), générique sur tout élément `Identifiable` : la carte du
/// dessus suit le doigt, deux cartes de fond en parallaxe, indicateurs « VÉRIFIER » / « SUIVANT ».
///
/// Écart assumé avec le web (blueprint §2.5) : au-delà du seuil, le paquet **transmet** l'action et ramène la
/// carte au centre ; il ne la fait jamais sortir lui-même. La carte n'est retirée que lorsque l'écran retire
/// l'élément de `items`, après la réponse serveur `ok:true` ; un refus la laisse donc en tête sans mouvement à
/// défaire. Pendant l'appel (`isBusy`), geste et actions d'accessibilité sont inertes (une seule action par carte).
///
/// Accessibilité : la carte du dessus est un seul élément (contenu combiné, identifiant `<prefix>-carte-<id>`)
/// qui porte les actions « Passer », « Sauvegarder », « Candidater » ; les cartes de fond sont masquées
/// (`aria-hidden` du web). « Réduire les animations » coupe le ressort et les transitions ; la carte suit
/// toujours le doigt (manipulation directe). Les boutons équivalents sont fournis par `SwipeActionBar`.
///
/// Le geste est prioritaire sur ceux du contenu : un glissement établi annule le toucher de la carte (le web
/// supprime le clic après un drag), un simple toucher l'atteint. À monter hors d'un `ScrollView` vertical,
/// dont il capterait aussi les glissements verticaux (ignorés par le paquet).
public struct SwipeCardStack<Item: Identifiable, Card: View>: View {
    private let items: [Item]
    private let identifier: String
    private let isBusy: Bool
    private let onAction: (SwipeCardAction, Item) -> Void
    private let card: (Item) -> Card

    /// État du glissement en cours : remis à zéro par SwiftUI à la fin du geste **et** à son annulation
    /// (interruption système : « une interruption ne valide jamais une mission », `StackCards.tsx` l.121).
    private struct Glissement: Equatable {
        var actif = false
        var axe: SwipeCardGesture.Axis = .undetermined
        var dx: CGFloat = 0
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var glissement = Glissement()

    public init(_ items: [Item], identifier: String = "swipe", isBusy: Bool = false,
                onAction: @escaping (SwipeCardAction, Item) -> Void, @ViewBuilder card: @escaping (Item) -> Card) {
        self.items = items; self.identifier = identifier; self.isBusy = isBusy
        self.onAction = onAction; self.card = card
    }

    /// Transmet `action` pour `item`, sauf pendant un appel serveur (`isBusy`) : point unique des gestes, des
    /// actions d'accessibilité et des tests.
    func perform(_ action: SwipeCardAction, on item: Item) {
        guard !isBusy else { return }
        onAction(action, item)
    }

    /// Carte visible et son rang (0 = dessus). Une même carte garde son identité en passant du fond au dessus :
    /// l'échelle et le décalage s'animent au lieu d'un remplacement de vue.
    private struct Couche: Identifiable {
        let depth: Int
        let item: Item
        var id: Item.ID { item.id }
    }

    public var body: some View {
        let visibles = Array(items.prefix(1 + SwipeCardGesture.visibleBackgroundCards))
        // Du fond vers le dessus : la carte de rang 0 est dessinée en dernier.
        let couches = visibles.enumerated().map { Couche(depth: $0.offset, item: $0.element) }.reversed()
        ZStack {
            ForEach(Array(couches)) { couche in
                carte(couche.item, depth: couche.depth)
            }
        }
        .animation(SwipeCardGesture.animation(reduceMotion: reduceMotion), value: visibles.map(\.id))
        // Ressort au relâchement seulement : pendant le glissement, la carte suit le doigt sans animation.
        .animation(SwipeCardGesture.animation(reduceMotion: reduceMotion), value: glissement.actif)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// Carte de rang `depth` : le dessus suit le doigt et porte geste, identifiant et actions d'accessibilité ;
    /// le fond est réduit, décalé, atténué, inerte et masqué à VoiceOver.
    private func carte(_ item: Item, depth: Int) -> some View {
        let dessus = depth == 0
        let style = SwipeCardGesture.backgroundStyle(depth: depth)
        let decalage = dessus ? glissement.dx : 0
        return card(item)
            .overlay(alignment: .topLeading) { indicateur(.candidater, dx: decalage) }
            .overlay(alignment: .topTrailing) { indicateur(.passer, dx: decalage) }
            .offset(x: decalage)
            .rotationEffect(.degrees(SwipeCardGesture.rotationDegrees(for: decalage)))
            .scaleEffect(style.scale)
            .offset(y: style.offsetY)
            .opacity(style.opacity)
            .highPriorityGesture(glisser(item), including: dessus && !isBusy ? .all : .subviews)
            .allowsHitTesting(dessus)
            .accessibilityElement(children: .combine)
            .accessibilityHidden(!dessus)
            .accessibilityIdentifier(dessus ? SwipeCardGesture.cardIdentifier(prefix: identifier, itemID: String(describing: item.id)) : "")
            .accessibilityAction(named: Text(SwipeCardAction.passer.accessibilityActionName)) { perform(.passer, on: item) }
            .accessibilityAction(named: Text(SwipeCardAction.sauvegarder.accessibilityActionName)) { perform(.sauvegarder, on: item) }
            .accessibilityAction(named: Text(SwipeCardAction.candidater.accessibilityActionName)) { perform(.candidater, on: item) }
            .transition(reduceMotion ? .identity : .opacity)
            .zIndex(Double(SwipeCardGesture.visibleBackgroundCards + 1 - depth))
    }

    private func glisser(_ item: Item) -> some Gesture {
        DragGesture(minimumDistance: SwipeCardGesture.activationDistance)
            .updating($glissement) { valeur, etat, _ in
                // Axe figé au premier mouvement au-delà de 8 pt ; un départ vertical ne déplace jamais la carte.
                if etat.axe == .undetermined { etat.axe = SwipeCardGesture.axis(for: valeur.translation) }
                etat.actif = true
                etat.dx = etat.axe == .horizontal ? valeur.translation.width : 0
            }
            .onEnded { valeur in
                // Relâchement : décalage horizontal dominant d'au moins 120 pt. La carte revient au centre (remise
                // à zéro du glissement) ; l'écran la retire après la réponse serveur.
                guard SwipeCardGesture.axis(for: valeur.translation) == .horizontal,
                      let decision = SwipeCardGesture.decision(forHorizontalTranslation: valeur.translation.width) else { return }
                perform(decision, on: item)
            }
    }

    @ViewBuilder private func indicateur(_ action: SwipeCardAction, dx: CGFloat) -> some View {
        if let indicateur = SwipeCardGesture.indicator(for: action) {
            let opacite = SwipeCardGesture.indicatorOpacity(for: dx, toward: action)
            HStack(spacing: JoleneSpacing.sm) {
                Image(systemName: indicateur.systemImage)
                Text(indicateur.text)
            }
            .font(.system(.title2, design: .rounded).weight(.heavy))
            .foregroundStyle(Color(indicateur.inkHSL))
            .padding(.horizontal, JoleneSpacing.lg)
            .padding(.vertical, JoleneSpacing.sm)
            .background(Color(indicateur.backgroundHSL).opacity(0.9))
            .overlay(RoundedRectangle(cornerRadius: JoleneRadius.card).strokeBorder(Color(indicateur.borderHSL), lineWidth: 4))
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
            .rotationEffect(.degrees(action == .candidater ? -12 : 12))
            .scaleEffect(0.8 + opacite * 0.2)
            .opacity(opacite)
            .padding(JoleneSpacing.xxl)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Barre des trois boutons ✕ / ⭐ / ❤️ (`BoutonsActionSwipe.tsx`), équivalents des gestes et seule voie du
/// favori ; couverture XCUITest par ces boutons (décision D22). `isDisabled` pendant un appel serveur
/// (`disabled` du web). Retour haptique léger / léger / moyen, comme `hapticImpact` du web.
public struct SwipeActionBar: View {
    private let identifier: String
    private let isDisabled: Bool
    private let onAction: (SwipeCardAction) -> Void

    public init(identifier: String = "swipe", isDisabled: Bool = false, onAction: @escaping (SwipeCardAction) -> Void) {
        self.identifier = identifier; self.isDisabled = isDisabled; self.onAction = onAction
    }

    public var body: some View {
        HStack(spacing: JoleneSpacing.lg) {
            ForEach(SwipeCardAction.allCases, id: \.self) { action in
                SwipeActionButton(action: action, prefix: identifier, isDisabled: isDisabled) { onAction(action) }
            }
        }
        .padding(.horizontal, JoleneSpacing.lg)
        .padding(.vertical, JoleneSpacing.md)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(identifier)-actions")
    }
}

/// Bouton rond d'une action du paquet, diamètre fixe (`buttonDiameter`, ≥ 44 pt) quelle que soit la taille de
/// texte ; icône de taille fixe et visionneuse de grand contenu pour les tailles d'accessibilité.
struct SwipeActionButton: View {
    let action: SwipeCardAction
    let prefix: String
    let isDisabled: Bool
    let run: () -> Void

    init(action: SwipeCardAction, prefix: String, isDisabled: Bool, run: @escaping () -> Void) {
        self.action = action; self.prefix = prefix; self.isDisabled = isDisabled; self.run = run
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: action == .candidater ? .medium : .light).impactOccurred()
            run()
        } label: {
            icone
                .frame(width: action.buttonDiameter, height: action.buttonDiameter)
                .background(fond)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(bordure, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityLabel(action.buttonAccessibilityLabel)
        .accessibilityIdentifier(action.identifier(prefix: prefix))
        .accessibilityShowsLargeContentViewer {
            Image(systemName: action.systemImage)
            Text(action.buttonAccessibilityLabel)
        }
    }

    private var tailleIcone: CGFloat { action == .candidater ? 30 : 26 }

    @ViewBuilder private var icone: some View {
        switch action {
        case .passer:
            Image(systemName: action.systemImage)
                .font(.system(size: tailleIcone, weight: .bold))
                .foregroundStyle(Color(JoleneColor.bubblegumHSL))
        case .sauvegarder:
            ZStack {
                Image(systemName: "star.fill").foregroundStyle(JoleneColor.butter400)
                Image(systemName: "star").foregroundStyle(JoleneColor.butter800)
            }
            .font(.system(size: tailleIcone, weight: .semibold))
        case .candidater:
            Image(systemName: action.systemImage)
                .font(.system(size: tailleIcone, weight: .bold))
                .foregroundStyle(JoleneColor.onGradient)
        }
    }

    @ViewBuilder private var fond: some View {
        if action == .candidater { JoleneColor.heroGradientFull } else { JoleneColor.cloud }
    }

    private var bordure: Color {
        switch action {
        case .passer: return JoleneColor.rose200
        case .sauvegarder: return JoleneColor.butter400
        case .candidater: return .clear
        }
    }
}
