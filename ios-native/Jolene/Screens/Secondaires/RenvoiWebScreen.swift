import SwiftUI
import JoleneCore
import JoleneDesign

/// Renvoi web d'un écran secondaire du lot 4 (L4-T1c) : coupe-circuit `ios_natif_<ecran>_actif` coupé
/// (`SecondaryRouter`), ou stub d'un écran dont la tranche n'a pas livré (jamais atteint : sa destination reste le renvoi
/// web canonique). Texte neutre, non juridique (`LOT4_PLAN.md` §3 T1c) ; le bouton présente la page web de l'écran
/// (`EcranSecondaire.urlWeb`, identifiants compris) par le présentateur `.safari` (`SFSafariViewController`, double démo
/// `renvoi-web-demo`), jamais `openURL` : les chemins `/soignant/*` reviendraient dans l'app par lien universel. Sans
/// présentateur (aperçus), aucun bouton : jamais un bouton sans effet.
///
/// Contenu définitif (L4-T13, intégration de la vague D, décision f) : titre de la page web de l'écran
/// (`RenvoisWebLot4.titreEcran`, aucun titre si la page web n'en a pas), phrase neutre, bouton. Aucun texte juridique,
/// aucun jeton transmis.
///
/// Identifiants : `secondaire-<nom du coupe-circuit>` (l'écran), `renvoi-web-message`, `renvoi-web-ouvrir`.
struct RenvoiWebScreen: View {
    static let message = "Cet écran est disponible sur jolene.app."
    static let bouton = "Voir sur jolene.app"

    let ecran: EcranSecondaire
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    var body: some View {
        ScrollView {
            VStack(spacing: JoleneSpacing.lg) {
                Image(systemName: "safari")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(JoleneColor.heroGradient)
                    .accessibilityHidden(true)
                Text(Self.message)
                    .font(JoleneFont.body)
                    .foregroundStyle(JoleneColor.midnight)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("renvoi-web-message")
                if let presentateurRenvoiWeb, let url = ecran.urlWeb {
                    JoleneButton(Self.bouton, style: .secondary) { presentateurRenvoiWeb.presenter(.safari(url)) }
                        .frame(maxWidth: 320)
                        .accessibilityIdentifier("renvoi-web-ouvrir")
                }
            }
            .padding(JoleneSpacing.xl)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("secondaire-\(ecran.nom.rawValue)")
        .navigationTitle(RenvoisWebLot4.titreEcran(ecran.nom) ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}
