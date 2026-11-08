import SwiftUI
import JoleneCore
import JoleneDesign

/// Lien `/inscription/confirmer` (lot 3, T7 ; D10) : port de `src/pages/ConfirmationInscription.tsx`. Vérification
/// du lien (une seule fois), puis `terminer(true)` : la racine relit la session (`SessionStore.start()`) et
/// l'aiguillage d'onboarding prend la suite (web : `/inscription/reprendre`). Échec : texte verbatim l.76-77 et
/// « Se connecter » (`terminer(false)`), le compte ayant pu être confirmé par `/verify` (correction 10).
/// Remplace l'écran « Inscription confirmée, continuez sur jolene.app » prévu par L1-T10 (absent de la base) ;
/// présenté par `RootView` depuis `BoiteLiensInscription`, que le coordinateur de liens alimente.
///
/// Identifiants : `confirmation-inscription-screen`, `confirmation-inscription-chargement`,
/// `confirmation-inscription-erreur`, `confirmation-inscription-se-connecter`.
struct ConfirmationInscriptionScreen: View {
    @StateObject private var model: ConfirmationInscriptionModel
    let terminer: (Bool) -> Void

    init(controller: SessionController, credentials: AuthCallbackCredentials?, terminer: @escaping (Bool) -> Void) {
        _model = StateObject(wrappedValue: ConfirmationInscriptionModel(controller: controller, credentials: credentials))
        self.terminer = terminer
    }

    private typealias T = InscriptionTextes

    var body: some View {
        ZStack {
            JoleneColor.softGradient.ignoresSafeArea()
            switch model.etat {
            case .verification, .confirme:
                ProgressView("Chargement de votre espace")
                    .tint(JoleneColor.rose700)
                    .accessibilityIdentifier("confirmation-inscription-chargement")
            case .refuse(let message):
                ScrollView {
                    VStack(alignment: .leading, spacing: JoleneSpacing.xl) {
                        Text(T.reprendreInscription)
                            .font(JoleneFont.title)
                            .foregroundStyle(JoleneColor.midnight)
                            .accessibilityAddTraits(.isHeader)
                        Text(message)
                            .font(JoleneFont.body)
                            .foregroundStyle(JoleneColor.midnight)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("confirmation-inscription-erreur")
                        JoleneButton(T.seConnecter) { terminer(false) }
                            .accessibilityIdentifier("confirmation-inscription-se-connecter")
                    }
                    .padding(JoleneSpacing.xl)
                    .padding(.top, JoleneSpacing.xl)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityIdentifier("confirmation-inscription-screen")
        .task {
            await model.confirmer()
            if model.etat == .confirme { terminer(true) }
        }
    }
}
