import SwiftUI
import JoleneCore
import JoleneDesign

/// Onglet coupé par son drapeau (`ios_natif_<ecran>_actif = false`, lot 1, T9) : état honnête et
/// sortie vers jolene.app. Identifiants : `renvoi-web-<ecran>`, `-message`, `-ouvrir` ; onglet Profil :
/// `logout-button` (la déconnexion ne vit que dans cet onglet, elle reste toujours possible).
///
/// Sortie web : tant que le présentateur `.safari` n'est pas injecté (T10,
/// `PresentateurRenvoiWeb.swift`), le bouton ouvre la page d'accueil `https://jolene.app`, comme le
/// lien de `BlockingScreen` — racine hors AASA, donc servie par Safari ; un chemin `/soignant/*` ouvert
/// par `openURL` reviendrait dans l'app par lien universel, sans effet. Une fois le présentateur
/// injecté, le bouton présente directement la page web de l'onglet (`EcranNatif.urlWeb`).
struct RenvoiWebScreen: View {
    static let message = "Cet écran est momentanément indisponible dans l'application. Retrouvez-le sur jolene.app."

    let ecran: EcranNatif
    var deconnexion: (() -> Void)? = nil
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb
    @Environment(\.openURL) private var openURL

    private var identifiant: String { "renvoi-web-\(ecran.rawValue)" }

    var body: some View {
        ZStack {
            JoleneColor.lavender.ignoresSafeArea()
            ScrollView {
                VStack(spacing: JoleneSpacing.lg) {
                    Image(systemName: "safari")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(JoleneColor.heroGradient)
                        .accessibilityHidden(true)
                    Text("Disponible sur jolene.app")
                        .font(JoleneFont.title)
                        .foregroundStyle(JoleneColor.midnight)
                        .multilineTextAlignment(.center)
                    Text(Self.message)
                        .font(JoleneFont.body)
                        .foregroundStyle(JoleneColor.midnight)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("\(identifiant)-message")
                    VStack(spacing: JoleneSpacing.md) {
                        sortieWeb
                        if let deconnexion {
                            JoleneButton("Se déconnecter", style: .secondary, action: deconnexion)
                                .accessibilityIdentifier("logout-button")
                        }
                    }
                    .frame(maxWidth: 320)
                }
                .padding(JoleneSpacing.xl)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifiant)
        .navigationTitle(ecran.titre)
    }

    @ViewBuilder private var sortieWeb: some View {
        if let presentateurRenvoiWeb {
            JoleneButton("Ouvrir sur jolene.app") { presentateurRenvoiWeb.presenter(.safari(ecran.urlWeb)) }
                .accessibilityIdentifier("\(identifiant)-ouvrir")
        } else {
            JoleneButton("Ouvrir jolene.app") { openURL(BlockingScreen.siteURL) }
                .accessibilityIdentifier("\(identifiant)-ouvrir")
        }
    }
}
