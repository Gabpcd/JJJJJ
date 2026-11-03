import SwiftUI
import JoleneCore
import JoleneDesign

/// Écran affiché à la place d'un écran établissement dont la permission servie manque (§2.7,
/// fail-closed ; le serveur reste l'autorité). « Revérifier mes droits » relit le périmètre une fois
/// (`SessionStore.refreshEtablissementScope`, D12) : un rôle élargi entre-temps rouvre l'écran.
/// Identifiants : `etab-acces-refuse` (+ `-message`, `-actualiser`).
struct EtabAccesRefuseScreen: View {
    static let message = "Votre rôle dans cet établissement ne permet pas d'accéder à cet écran."

    @ObservedObject var session: SessionStore
    var titre: String = "Accès non autorisé"
    @State private var relecture = false

    var body: some View {
        ZStack {
            JoleneColor.lavender.ignoresSafeArea()
            ScrollView {
                VStack(spacing: JoleneSpacing.lg) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(JoleneColor.heroGradient)
                        .accessibilityHidden(true)
                    Text("Accès non autorisé")
                        .font(JoleneFont.title)
                        .foregroundStyle(JoleneColor.midnight)
                        .multilineTextAlignment(.center)
                    Text(Self.message)
                        .font(JoleneFont.body)
                        .foregroundStyle(JoleneColor.midnight)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("etab-acces-refuse-message")
                    JoleneButton("Revérifier mes droits", style: .secondary, isLoading: relecture) {
                        guard !relecture else { return }
                        relecture = true
                        Task {
                            await session.refreshEtablissementScope()
                            relecture = false
                        }
                    }
                    .frame(maxWidth: 320)
                    .accessibilityIdentifier("etab-acces-refuse-actualiser")
                }
                .padding(JoleneSpacing.xl)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etab-acces-refuse")
        .navigationTitle(titre)
    }
}
