import SwiftUI
import UIKit
import WebKit
import JoleneCore

/// Lecteur isolé de l'original d'un contrat (lot 2, T9a ; décision 17, `LOT2_PLAN.md` §3 T9a). Affiche les octets
/// contrôlés (`OriginalContrat.html` : SHA-256 = `hash_document` = objet Storage), isolés par les règles pures de
/// `LecteurContrat` (JoleneCore, testées par `LecteurContratTests`) :
/// - aucun script (`allowsContentJavaScript = false`), aucun détecteur de données, aucun aperçu de lien ;
/// - aucune ressource : règle `WKContentRuleList` (`LecteurContrat.regleBlocage`) installée AVANT le chargement, et
///   politique CSP `default-src 'none'; style-src 'unsafe-inline'` injectée en tête du document ;
/// - aucune donnée gardée (`websiteDataStore = .nonPersistent()`) ;
/// - `loadHTMLString(_, baseURL: nil)` puis toute navigation annulée, nouvelle fenêtre refusée, lien jamais ouvert.
/// Si la règle ne peut pas être compilée, rien n'est chargé (échec fermé) : le lecteur reste vide.
///
/// Ce n'est pas la WebView bornée de la décision 3 (jamais d'URL chargée). La vue ne défile pas elle-même : sa
/// hauteur suit celle du document (`scrollView.contentSize`), et seul l'écran défile.
@MainActor
final class LecteurContratReference {
    /// Vue du lecteur affiché, pour l'impression (`imprimer(nomTache:)`).
    weak var vue: WKWebView?

    nonisolated init() {}

    /// Impression du lecteur par la feuille système (`UIPrintInteractionController`, `viewPrintFormatter`) ; faux si
    /// aucun lecteur n'est affiché.
    @discardableResult
    func imprimer(nomTache: String) -> Bool {
        guard let vue, vue.window != nil else { return false }
        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.jobName = nomTache
        let controleur = UIPrintInteractionController.shared
        controleur.printInfo = info
        controleur.printFormatter = vue.viewPrintFormatter()
        if vue.traitCollection.userInterfaceIdiom == .pad, let fenetre = vue.window {
            let centre = CGRect(x: fenetre.bounds.midX, y: fenetre.bounds.midY, width: 1, height: 1)
            return controleur.present(from: centre, in: fenetre, animated: true, completionHandler: nil)
        }
        return controleur.present(animated: true, completionHandler: nil)
    }
}

struct ContratReaderView: UIViewRepresentable {
    /// Original contrôlé, rendu tel quel (en-tête d'isolement mis à part).
    let html: String
    let reference: LecteurContratReference
    @Binding var hauteur: CGFloat

    func makeCoordinator() -> Coordinateur { Coordinateur(hauteur: $hauteur) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.dataDetectorTypes = []
        configuration.allowsInlineMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let vue = WKWebView(frame: .zero, configuration: configuration)
        vue.navigationDelegate = context.coordinator
        vue.uiDelegate = context.coordinator
        vue.allowsLinkPreview = false
        vue.allowsBackForwardNavigationGestures = false
        vue.scrollView.isScrollEnabled = false
        vue.scrollView.bounces = false
        vue.isOpaque = false
        vue.backgroundColor = .clear
        vue.accessibilityIdentifier = "contrat-lecteur"
        reference.vue = vue
        context.coordinator.observer(vue)
        context.coordinator.charger(html, dans: vue)
        return vue
    }

    func updateUIView(_ vue: WKWebView, context: Context) {
        reference.vue = vue
        context.coordinator.hauteur = $hauteur
        if context.coordinator.htmlCharge != html { context.coordinator.charger(html, dans: vue) }
    }

    static func dismantleUIView(_ vue: WKWebView, coordinator: Coordinateur) {
        coordinator.arreter()
        vue.stopLoading()
        vue.navigationDelegate = nil
        vue.uiDelegate = nil
    }

    @MainActor
    final class Coordinateur: NSObject, WKNavigationDelegate, WKUIDelegate {
        var hauteur: Binding<CGFloat>
        private(set) var htmlCharge: String?
        private var chargementInitialFait = false
        private var observation: NSKeyValueObservation?

        init(hauteur: Binding<CGFloat>) {
            self.hauteur = hauteur
        }

        /// La hauteur de l'écran suit celle du document (la vue ne défile pas).
        func observer(_ vue: WKWebView) {
            observation = vue.scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, changement in
                guard let taille = changement.newValue else { return }
                let hauteur = taille.height
                Task { @MainActor [weak self] in self?.ajuster(hauteur) }
            }
        }

        func arreter() {
            observation?.invalidate()
            observation = nil
        }

        private func ajuster(_ hauteurDocument: CGFloat) {
            let cible = max(ContratReaderView.hauteurMinimale, hauteurDocument.rounded(.up))
            if abs(hauteur.wrappedValue - cible) >= 1 { hauteur.wrappedValue = cible }
        }

        /// Règle de blocage compilée puis installée, et seulement ensuite le document isolé chargé ; sans règle,
        /// rien n'est chargé (échec fermé).
        func charger(_ html: String, dans vue: WKWebView) {
            htmlCharge = html
            chargementInitialFait = false
            let document = LecteurContrat.documentIsole(html)
            Task { @MainActor [weak self, weak vue] in
                let liste: WKContentRuleList? = try? await WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: LecteurContrat.identifiantRegles, encodedContentRuleList: LecteurContrat.regleBlocage)
                guard let self, let vue, let liste, self.htmlCharge == html else { return }
                vue.configuration.userContentController.removeAllContentRuleLists()
                vue.configuration.userContentController.add(liste)
                vue.loadHTMLString(document, baseURL: nil)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            let autorisee = navigationAction.targetFrame?.isMainFrame == true
                && LecteurContrat.navigationAutorisee(url: navigationAction.request.url, chargementInitialFait: chargementInitialFait)
            if autorisee { chargementInitialFait = true }
            return autorisee ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil
        }
    }

    /// Hauteur avant la mesure du document.
    static let hauteurMinimale: CGFloat = 240
}
