import SwiftUI
import JoleneDesign

/// Écran de connexion (plan §11 jours 4-5) : `login-scroll`, `login-email`,
/// `login-password`, `login-submit`, `login-error`, `login-retry-restore`. Le mot de passe
/// reste local à la vue, n'est jamais journalisé et est effacé à chaque réapparition de l'écran.
/// `retryRestore` (non nul après une restauration échouée pour cause transitoire) relance
/// `session.start()` : la session Keychain intacte ne redemande pas le mot de passe.
struct LoginScreen: View {
    @Binding var email: String
    let errorMessage: String?
    let isDemo: Bool
    var retryRestore: (() async -> Void)? = nil
    let submit: (String, String) async -> Void

    @State private var password = ""
    @State private var isSubmitting = false
    @State private var isRetrying = false
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isSubmitting
    }

    var body: some View {
        ZStack {
            JoleneColor.softGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: JoleneSpacing.xl) {
                    header
                    if isDemo { demoBanner }
                    VStack(spacing: JoleneSpacing.lg) {
                        JoleneTextField("Adresse email", text: $email, kind: .email, placeholder: "vous@exemple.fr",
                                        identifier: "login-email") { focusedField = .password }
                            .focused($focusedField, equals: .email)
                        JoleneTextField("Mot de passe", text: $password, kind: .motDePasse, placeholder: "Votre mot de passe",
                                        identifier: "login-password") { if canSubmit { send() } }
                            .focused($focusedField, equals: .password)
                    }
                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(JoleneFont.callout)
                            .foregroundStyle(JoleneColor.rose700)
                            .padding(JoleneSpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(JoleneColor.rose100)
                            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                            .accessibilityIdentifier("login-error")
                    }
                    if let retryRestore {
                        JoleneButton("Réessayer sans mot de passe", style: .secondary, isLoading: isRetrying) {
                            guard !isRetrying else { return }
                            isRetrying = true
                            Task {
                                await retryRestore()
                                isRetrying = false
                            }
                        }
                        .accessibilityIdentifier("login-retry-restore")
                    }
                    JoleneButton("Se connecter", isLoading: isSubmitting) { send() }
                        .disabled(!canSubmit)
                        .accessibilityIdentifier("login-submit")
                    Text("Pas encore de compte ? L'inscription se fait sur jolene.app.")
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                }
                .padding(JoleneSpacing.xl)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("login-scroll")
        }
        .onAppear { password = "" }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text("Jolene")
                .font(JoleneFont.hero)
                .foregroundStyle(JoleneColor.heroGradient)
                .accessibilityAddTraits(.isHeader)
            Text("Connectez-vous pour consulter les missions.")
                .font(JoleneFont.body)
                .foregroundStyle(JoleneColor.midnight)
        }
        .padding(.top, JoleneSpacing.xl)
    }

    private var demoBanner: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text("Démo · données fictives")
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.mauve700)
            Text("Aucune requête réseau. Connectez-vous avec demonstration@example.invalid et un mot de passe quelconque.")
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.midnight)
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.mauve100)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("login-demo-banner")
    }

    private func send() {
        guard canSubmit else { return }
        let typedEmail = email.trimmingCharacters(in: .whitespaces)
        let typedPassword = password
        isSubmitting = true
        focusedField = nil
        Task {
            await submit(typedEmail, typedPassword)
            isSubmitting = false
            password = ""
        }
    }
}
