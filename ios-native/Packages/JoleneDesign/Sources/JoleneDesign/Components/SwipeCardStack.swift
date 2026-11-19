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

    /// Identifiant du bouton : `<prefix>-passer`, `<prefix>-sauvegarder`, `<prefix>-candidater` (`swipe-passer`…
    /// avec le préfixe par défaut de `SwipeActionBar`, blueprint lot 4 T3b).
    public func identifier(prefix: String) -> String { "\(prefix)-\(rawValue)" }
}

/// Identifiants du paquet, alignés sur le blueprint lot 4 v2 (T3b : `swipe-deck`, `swipe-card-<missionId>`,
/// `swipe-passer`, `swipe-sauvegarder`, `swipe-candidater`) et sur la convention `mission-card-<id>` de
/// PRINCIPES §6. Chaque valeur reste injectable par l'appelant (`SwipeCardStack`, `SwipeActionBar`).
public enum SwipeDeckIdentifiers {
    /// Conteneur du paquet.
    public static let deck = "swipe-deck"
    /// Préfixe de la carte du dessus : `swipe-card-<id>`.
    public static let cardPrefix = "swipe-card"
    /// Préfixe des trois boutons de `SwipeActionBar` : `swipe-passer`, `swipe-sauvegarder`, `swipe-candidater`.
    public static let actionsPrefix = "swipe"

    /// Identifiant de la carte du dessus : `<prefix>-<id>` (cible du test de geste réel, décision D22).
    public static func card(prefix: String = cardPrefix, itemID: String) -> String { "\(prefix)-\(itemID)" }
}

/// Règles pures du geste de `SwipeCardStack`, port de `StackCards.tsx` : drag établi au-delà de 8 pt, axe figé à ce
/// moment-là (un départ vertical abandonne le geste : la carte ne bouge pas et rien n'est décidé, l.81-84), décision
/// au relâchement sur le seul décalage horizontal (l.99-110), validation à 120 pt (blueprint lot 4 T1b ; le web prend
/// 30 % de la largeur, ≈ 117 px sur un iPhone de 390 pt), rotation `dx / 14` bornée à ±15°, indicateurs
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

    /// Axe figé : tant qu'il est indéterminé, il se décide sur la translation courante ; ensuite il ne change plus,
    /// quelle que soit la suite du geste (`start.active` du web, posé une seule fois).
    public static func frozenAxis(_ current: Axis, translation: CGSize) -> Axis {
        current == .undetermined ? axis(for: translation) : current
    }

    /// Décalage horizontal suivi par la carte : `dx` sur un geste horizontal, 0 sinon (départ vertical ou indéterminé).
    public static func trackedDx(axis: Axis, translation: CGSize) -> CGFloat {
        axis == .horizontal ? translation.width : 0
    }

    /// Action pour un décalage horizontal : ≥ 120 pt à droite → `candidater` (ouvre le récapitulatif), à gauche →
    /// `passer` ; en deçà, `nil` (la carte revient au centre).
    public static func decision(forHorizontalTranslation dx: CGFloat) -> SwipeCardAction? {
        guard abs(dx) >= threshold else { return nil }
        return dx > 0 ? .candidater : .passer
    }

    /// Décision au relâchement, lue sur l'axe **figé au démarrage** et jamais recalculée sur la translation finale :
    /// un départ vertical ne décide rien, même s'il finit 150 pt de côté (le web a abandonné le geste) ; un départ
    /// horizontal décide sur `dx` seul, même s'il finit en diagonale, donc comme l'indicateur affiché.
    public static func decision(frozenAxis: Axis, translation: CGSize) -> SwipeCardAction? {
        guard frozenAxis == .horizontal else { return nil }
        return decision(forHorizontalTranslation: translation.width)
    }

    /// Décalage affiché de la carte du dessus : le doigt pendant le glissement (`liveDx`) ; après une action
    /// transmise par le geste, le décalage du relâchement (`retainedDx`) tant que l'appel serveur dure (`isBusy`),
    /// indicateur compris, pour qu'un retour au centre ne signifie qu'un refus ; sinon le centre.
    public static func displayedOffset(liveDx: CGFloat?, retainedDx: CGFloat?, isBusy: Bool) -> CGFloat {
        if let liveDx { return liveDx }
        if isBusy, let retainedDx { return retainedDx }
        return 0
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

/// Exposition de la carte du dessus à l'accessibilité.
public enum SwipeCardAccessibility: Equatable, Sendable {
    /// Un seul élément qui combine le contenu de la carte (comme la carte `role="button"` du web et son
    /// `aria-label`) et porte les actions « Passer », « Sauvegarder », « Candidater ». Les identifiants posés sur
    /// les enfants sont absorbés : un XCUITest lit alors le score dans le libellé de la carte.
    case combine
    /// Conteneur identifié dont les enfants restent des éléments distincts avec leurs propres identifiants
    /// (`swipe-score-<id>`, `swipe-pourquoi-<id>` de T3b). Les actions nommées sont posées sur ce conteneur ; selon
    /// le contenu, VoiceOver peut ne pas les proposer sur les enfants : l'équivalent toujours atteignable reste
    /// `SwipeActionBar` (à vérifier à VoiceOver par la tranche qui monte le paquet).
    case contain
}

/// Paquet de cartes à glisser (lot 4, Explorer › Swipe), générique sur tout élément `Identifiable` : la carte du
/// dessus suit le doigt, deux cartes de fond en parallaxe, indicateurs « VÉRIFIER » / « SUIVANT ».
///
/// Écart assumé avec le web (blueprint §2.5) : au-delà du seuil, le paquet **transmet** l'action ; il ne fait jamais
/// sortir la carte lui-même. Tant que l'appel serveur dure (`isBusy`), la carte reste décalée avec son indicateur ;
/// elle n'est retirée que lorsque l'écran retire l'élément de `items`, après la réponse serveur `ok:true`, et un refus
/// (`isBusy` repasse à faux, élément conservé) la ramène au centre sans mouvement à défaire. L'écran passe `isBusy` à
/// vrai **dans** l'appel de `onAction` (verrou synchrone du modèle) : sinon la carte revient aussitôt au centre,
/// comme pour « candidater », qui ouvre une feuille sans appel serveur. Pendant l'appel, le geste est inerte et les
/// actions d'accessibilité sont retirées (rien n'est annoncé qui ne ferait rien) ; une seule action par carte.
///
/// Identifiants (blueprint lot 4 v2, injectables) : conteneur `identifier` (`swipe-deck`), carte du dessus
/// `<cardIdentifierPrefix>-<id>` (`swipe-card-<missionId>`). Les cartes de fond sont masquées (`aria-hidden` du web).
/// « Réduire les animations » coupe le ressort et les transitions ; la carte suit toujours le doigt (manipulation
/// directe). Les boutons équivalents sont fournis par `SwipeActionBar`.
///
/// Défilement : le geste est prioritaire sur ceux du contenu (un glissement établi annule le toucher de la carte, le
/// web supprime le clic après un drag ; un simple toucher l'atteint) et il capte aussi les glissements verticaux,
/// qu'il ignore. Contrairement au web (`touch-pan-y`), aucun défilement vertical ne part donc de la carte : à monter
/// hors d'un `ScrollView` vertical, et l'écran (T3b) garantit que la carte tient sans défilement à toutes les tailles
/// Dynamic Type, iPhone SE et iPad paysage compris (le détail complet passant par la feuille de détail).
public struct SwipeCardStack<Item: Identifiable, Card: View>: View {
    private let items: [Item]
    private let identifier: String
    private let cardIdentifierPrefix: String
    private let cardAccessibility: SwipeCardAccessibility
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

    /// Copie de l'axe figé du geste en cours, relue au relâchement : `@GestureState` est remis à zéro à la fin du geste,
    /// donc illisible de façon sûre dans `onEnded`. Référence mutée dans `updating` (même source que l'affichage),
    /// sans provoquer de rendu ; remise à zéro au premier changement de chaque geste, annulé ou non. Lue et écrite
    /// seulement par les rappels du geste, isolés sur l'acteur principal comme la vue.
    private final class SuiviGeste {
        var axe: SwipeCardGesture.Axis = .undetermined
    }

    /// Décalage du relâchement gardé pour la carte `id` pendant l'appel serveur.
    private struct Retenue: Equatable {
        var id: Item.ID
        var dx: CGFloat
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var glissement = Glissement()
    @State private var suivi = SuiviGeste()
    @State private var retenue: Retenue?

    /// - Parameters:
    ///   - identifier: conteneur du paquet (`swipe-deck`).
    ///   - cardIdentifierPrefix: préfixe de la carte du dessus, suivi de l'identifiant de l'élément (`swipe-card-<id>`).
    ///   - cardAccessibility: `.combine` (un élément, défaut) ou `.contain` (enfants identifiés conservés).
    public init(_ items: [Item], identifier: String = SwipeDeckIdentifiers.deck,
                cardIdentifierPrefix: String = SwipeDeckIdentifiers.cardPrefix,
                cardAccessibility: SwipeCardAccessibility = .combine, isBusy: Bool = false,
                onAction: @escaping (SwipeCardAction, Item) -> Void, @ViewBuilder card: @escaping (Item) -> Card) {
        self.items = items; self.identifier = identifier; self.cardIdentifierPrefix = cardIdentifierPrefix
        self.cardAccessibility = cardAccessibility; self.isBusy = isBusy
        self.onAction = onAction; self.card = card
    }

    /// Transmet `action` pour `item`, sauf pendant un appel serveur (`isBusy`) : point unique des gestes, des
    /// actions d'accessibilité et des tests.
    func perform(_ action: SwipeCardAction, on item: Item) {
        guard !isBusy else { return }
        onAction(action, item)
    }

    /// Identifiant de la carte du dessus pour `item`.
    func cardIdentifier(for item: Item) -> String {
        SwipeDeckIdentifiers.card(prefix: cardIdentifierPrefix, itemID: String(describing: item.id))
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
        // Ressort au relâchement et à la fin de l'appel seulement : pendant le glissement, la carte suit le doigt.
        .animation(SwipeCardGesture.animation(reduceMotion: reduceMotion), value: glissement.actif)
        .animation(SwipeCardGesture.animation(reduceMotion: reduceMotion), value: isBusy)
        // Rendu qui suit la transmission : si l'écran n'a pas ouvert d'appel, la carte revient au centre.
        .onChange(of: retenue) { nouvelle in
            if nouvelle != nil, !isBusy { retenue = nil }
        }
        .onChange(of: isBusy) { occupe in
            if !occupe { retenue = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// Carte de rang `depth` : le dessus suit le doigt et porte geste, identifiant et actions d'accessibilité ;
    /// le fond est réduit, décalé, atténué, inerte et masqué à VoiceOver.
    private func carte(_ item: Item, depth: Int) -> some View {
        let dessus = depth == 0
        let style = SwipeCardGesture.backgroundStyle(depth: depth)
        let decalage = dessus ? decalageAffiche(item) : 0
        return card(item)
            .overlay(alignment: .topLeading) { indicateur(.candidater, dx: decalage) }
            .overlay(alignment: .topTrailing) { indicateur(.passer, dx: decalage) }
            // Rotation autour du centre de la carte, puis translation (`translate(dx) rotate(θ)` du web).
            .rotationEffect(.degrees(SwipeCardGesture.rotationDegrees(for: decalage)))
            .offset(x: decalage)
            .scaleEffect(style.scale)
            .offset(y: style.offsetY)
            .opacity(style.opacity)
            .highPriorityGesture(glisser(item), including: dessus && !isBusy ? .all : .subviews)
            .allowsHitTesting(dessus)
            .accessibilityElement(children: cardAccessibility == .combine ? .combine : .contain)
            .accessibilityHidden(!dessus)
            .accessibilityIdentifier(dessus ? cardIdentifier(for: item) : "")
            .accessibilityActions {
                if dessus && !isBusy {
                    ForEach(SwipeCardAction.allCases, id: \.self) { action in
                        Button(action.accessibilityActionName) { perform(action, on: item) }
                    }
                }
            }
            .transition(reduceMotion ? .identity : .opacity)
            .zIndex(Double(SwipeCardGesture.visibleBackgroundCards + 1 - depth))
    }

    private func decalageAffiche(_ item: Item) -> CGFloat {
        SwipeCardGesture.displayedOffset(liveDx: glissement.actif ? glissement.dx : nil,
                                         retainedDx: retenue?.id == item.id ? retenue?.dx : nil, isBusy: isBusy)
    }

    private func glisser(_ item: Item) -> some Gesture {
        DragGesture(minimumDistance: SwipeCardGesture.activationDistance)
            .updating($glissement) { valeur, etat, _ in
                // Premier changement d'un geste (état neuf, y compris après une annulation) : suivi remis à zéro.
                if !etat.actif { suivi.axe = .undetermined }
                // Axe figé au premier mouvement au-delà de 8 pt ; un départ vertical ne déplace jamais la carte.
                etat.axe = SwipeCardGesture.frozenAxis(etat.axe, translation: valeur.translation)
                etat.actif = true
                etat.dx = SwipeCardGesture.trackedDx(axis: etat.axe, translation: valeur.translation)
                suivi.axe = etat.axe
            }
            .onEnded { valeur in
                // Relâchement : décision sur l'axe figé au démarrage, jamais sur la translation finale.
                let axe = suivi.axe
                suivi.axe = .undetermined
                guard let decision = SwipeCardGesture.decision(frozenAxis: axe, translation: valeur.translation) else { return }
                // La carte reste décalée pendant l'appel serveur ; l'écran la retire après la réponse `ok:true`.
                retenue = Retenue(id: item.id, dx: SwipeCardGesture.trackedDx(axis: axe, translation: valeur.translation))
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
/// (`disabled` du web). Retour haptique léger / léger / moyen, comme `hapticImpact` du web. Identifiants
/// `<identifier>-passer`, `-sauvegarder`, `-candidater` (`swipe-passer`… par défaut) et `<identifier>-actions`.
public struct SwipeActionBar: View {
    private let identifier: String
    private let isDisabled: Bool
    private let onAction: (SwipeCardAction) -> Void

    public init(identifier: String = SwipeDeckIdentifiers.actionsPrefix, isDisabled: Bool = false,
                onAction: @escaping (SwipeCardAction) -> Void) {
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
