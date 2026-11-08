import SwiftUI
import JoleneCore
import JoleneDesign

/// Écran de fin affiché par la racine après une suppression de compte (lot 1, T8) ou une déconnexion
/// forcée par un refus 503 qui laisse le compte banni ou anonymisé (message serveur verbatim). Il
/// remplace l'écran de connexion tant que l'avis n'est pas acquitté : la fin de session consécutive à
/// la suppression n'est jamais présentée comme « Votre session a expiré ».
/// Identifiants : `compte-supprime` (+ `-titre`, `-message`, `-continuer`).
struct CompteSupprimeScreen: View {
    let fin: FinDeCompte
    let continuer: () -> Void

    var body: some View {
        ZStack {
            JoleneColor.softGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: JoleneSpacing.xl) {
                    Image(systemName: fin == .supprime ? "checkmark.circle" : "person.crop.circle.badge.xmark")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(JoleneColor.heroGradient)
                        .accessibilityHidden(true)
                    Text(fin.titre)
                        .font(JoleneFont.title)
                        .foregroundStyle(JoleneColor.midnight)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("compte-supprime-titre")
                    Text(fin.message)
                        .font(JoleneFont.body)
                        .foregroundStyle(JoleneColor.midnight)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("compte-supprime-message")
                    JoleneButton(CompteSuppression.Textes.finContinuer, action: continuer)
                        .accessibilityIdentifier("compte-supprime-continuer")
                }
                .padding(JoleneSpacing.xl)
                .padding(.top, JoleneSpacing.xxl)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("compte-supprime")
    }
}
