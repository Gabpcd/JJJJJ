#if DEBUG
import SwiftUI
import UIKit

/// Recette de la garde de repos XCUITest (`JoleneUITests/GardeRepos.swift`, `DemoGardeReposTests`), DEBUG et démo
/// seulement : avec `-JOLENE_UITEST_ANIMATION_OUVERTE 1` (`SondeAnimationOuverte`), une vue de 1 pt, transparente,
/// sans interaction et hors de l'accessibilité, porte une animation UIKit répétée sans fin. XCTest compte alors une
/// animation en cours que rien ne termine, comme après le toucher « OK » du clavier sur iPad. Sans l'argument : rien.
/// Jamais compilé en Release.
struct SondeAnimationOuverteUITest: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.background(SondeVue().frame(width: 1, height: 1).allowsHitTesting(false).accessibilityHidden(true))
        } else {
            content
        }
    }

    private struct SondeVue: UIViewRepresentable {
        func makeUIView(context: Context) -> VueAnimee { VueAnimee() }
        func updateUIView(_ uiView: VueAnimee, context: Context) {}
    }

    final class VueAnimee: UIView {
        private var lancee = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            accessibilityElementsHidden = true
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) non pris en charge") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, !lancee else { return }
            lancee = true
            alpha = 0.02
            UIView.animate(withDuration: 1, delay: 0, options: [.repeat, .autoreverse, .allowUserInteraction]) {
                self.alpha = 0.01
            }
        }
    }
}
#endif
