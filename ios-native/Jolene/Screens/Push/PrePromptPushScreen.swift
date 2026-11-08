import SwiftUI
import JoleneCore
import JoleneDesign

/// Pré-prompt de notification (lot 3, T5 ; D1), surcouche de `MainTabView` : port du dialogue de
/// `src/components/DemandePermissionPush.tsx` (l.128-170). Textes soignant verbatim
/// (`PermissionCard.Content.pushSoignant` : l.20-28, l.149, l.158, l.164 ; HARD STOP n°4). Règles d'affichage et
/// d'issue : `PrePromptPushModel` (JoleneCore, `PushPolicyTests`).
///
/// Comme le dialogue modal du web : voile sur l'espace, carte centrée (largeur bornée), fermeture par le voile ou
/// le geste d'échappement de VoiceOver = « Plus tard » (`onOpenChange(false)`, l.131). La feuille système n'est
/// demandée qu'au tap sur « Activer les notifications ».
///
/// Identifiants (blueprint §3 T5) : `push-preprompt` (+ `-title`, `-message`, `-benefits`, `-footnote`),
/// `push-preprompt-activer`, `push-preprompt-plus-tard` ; voile `push-preprompt-voile`.
struct PrePromptPushScreen: View {
    @ObservedObject var model: PrePromptPushModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { model.plusTard() }
                .accessibilityHidden(true)
                .accessibilityIdentifier("push-preprompt-voile")
            // Centrée quand elle tient (paysage, grands textes : défilement plutôt que troncature).
            ViewThatFits(in: .vertical) {
                carte.frame(maxHeight: .infinity)
                ScrollView { carte }
            }
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { model.plusTard() }
        }
        .transition(.opacity)
    }

    private var carte: some View {
        PermissionCard(.pushSoignant(identifier: "push-preprompt"), isLoading: model.demandeEnCours,
                       onPrimary: { Task { await model.activer() } },
                       onSecondary: { model.plusTard() })
            .padding(JoleneSpacing.lg)
    }
}

/// Issue de l'activation (toast du web, l.103-108, l.116, l.119) : encart en haut de l'espace, annoncé à
/// l'apparition, effacé après `duree` ou au tap. Identifiant `push-preprompt-issue`.
struct IssuePrePromptPush: View {
    /// Durée d'affichage (toasts `sonner` du web : 4 s ; un peu plus pour la lecture et VoiceOver).
    nonisolated static let duree: UInt64 = 6_000_000_000

    let issue: PrePromptPushModel.Issue
    let effacer: () -> Void

    var body: some View {
        InlineNotice(issue.message, tone: issue.succes ? .success : .error, identifier: "push-preprompt-issue",
                     announcesOnAppear: true)
            .frame(maxWidth: PermissionCard.maxWidth)
            .padding(.horizontal, JoleneSpacing.lg)
            .padding(.top, JoleneSpacing.sm)
            .onTapGesture { effacer() }
            .task(id: issue) {
                do { try await Task.sleep(nanoseconds: Self.duree) } catch { return }
                effacer()
            }
    }
}
