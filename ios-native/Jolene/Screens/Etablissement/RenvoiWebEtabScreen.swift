import SwiftUI
import JoleneCore
import JoleneDesign

/// Écran établissement coupé par son drapeau (`ios_natif_etab_<ecran>_actif = false`, D14) : état
/// honnête et sortie vers jolene.app, l'écran natif n'étant jamais monté. Le texte annonce la
/// reconnexion web : la session de l'app n'est pas partagée avec Safari (D16).
/// Identifiants : `etab-renvoi-web` (valeur : clé de l'écran), `etab-renvoi-web-message`,
/// `etab-renvoi-web-ouvrir` (valeur : URL du renvoi), `logout-button` sur le compte.
///
/// Sortie web : tant que le présentateur `.safari` du lot 1 (T10, `PresentateurRenvoiWeb.swift`) n'est
/// pas injecté, le bouton ouvre la page d'accueil `https://jolene.app`, racine hors AASA donc servie par
/// Safari — un chemin `/etablissement/*` ouvert par `openURL` reviendrait dans l'app par lien universel,
/// sans effet. Une fois le présentateur injecté, le bouton présente directement `url` dans Safari.
struct RenvoiWebEtabScreen: View {
    static let message = "Cet écran est momentanément indisponible dans l'application. Retrouvez-le sur jolene.app, où une nouvelle connexion peut vous être demandée."

    let titre: String
    let cle: String
    let url: URL
    var deconnexion: (() -> Void)? = nil
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb
    @Environment(\.openURL) private var openURL

    init(ecran: EcranNatifEtablissement, deconnexion: (() -> Void)? = nil) {
        self.titre = ecran.titre; self.cle = ecran.cle; self.url = ecran.urlWeb; self.deconnexion = deconnexion
    }

    init(destination: EtabDestination) {
        self.titre = destination.drapeau.titre; self.cle = destination.drapeau.cle; self.url = destination.urlWeb
    }

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
                        .accessibilityIdentifier("etab-renvoi-web-message")
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
        .accessibilityIdentifier("etab-renvoi-web")
        .accessibilityValue(cle)
        .navigationTitle(titre)
    }

    @ViewBuilder private var sortieWeb: some View {
        if let presentateurRenvoiWeb {
            JoleneButton("Ouvrir sur jolene.app") { presentateurRenvoiWeb.presenter(.etablissement(url)) }
                .accessibilityIdentifier("etab-renvoi-web-ouvrir")
                .accessibilityValue(url.absoluteString)
        } else {
            JoleneButton("Ouvrir jolene.app") { openURL(BlockingScreen.siteURL) }
                .accessibilityIdentifier("etab-renvoi-web-ouvrir")
                .accessibilityValue(url.absoluteString)
        }
    }
}
