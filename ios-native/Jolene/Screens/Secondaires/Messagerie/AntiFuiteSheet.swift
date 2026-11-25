import SwiftUI
import JoleneCore
import JoleneDesign

/// Feuille éducative de l'anti-fuite (L4-T7b, HARD STOP n°4), port de `src/components/messagerie/ModaleEducativeAntiLeak.tsx` :
/// titre, sous-titre, description du type détecté et explication, textes verbatim (`MessagerieTextes.AntiFuite`).
/// Ouverte quand l'edge `messagerie-validate` refuse un message (`ANTI_LEAK_REFUSE`) ; le texte saisi reste dans le
/// composeur (« J'ai compris, je modifie mon message » referme seulement).
///
/// Identifiants : `chat-antifuite`, `chat-antifuite-titre`, `chat-antifuite-description`, `chat-antifuite-explication`,
/// `chat-antifuite-compris`.
struct AntiFuiteSheet: View {
    let type: DetectedType?
    let fermer: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: JoleneSpacing.lg) {
                VStack(spacing: JoleneSpacing.xs) {
                    Text(MessagerieTextes.AntiFuite.titre)
                        .font(JoleneFont.title)
                        .foregroundStyle(JoleneColor.midnight)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("chat-antifuite-titre")
                    Text(MessagerieTextes.AntiFuite.sousTitre)
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Image(systemName: "hand.raised")
                    .font(.system(size: 44))
                    .foregroundStyle(JoleneColor.rose800)
                    .accessibilityHidden(true)
                Text(MessagerieTextes.AntiFuite.description(type))
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.midnight)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chat-antifuite-description")
                Text(MessagerieTextes.AntiFuite.explication)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chat-antifuite-explication")
                JoleneButton(MessagerieTextes.AntiFuite.compris, action: fermer)
                    .accessibilityIdentifier("chat-antifuite-compris")
            }
            .padding(JoleneSpacing.xl)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(JoleneColor.cloud.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-antifuite")
    }
}
