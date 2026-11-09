import SwiftUI
import JoleneCore
import JoleneDesign

/// En-tête de la carte « Adresse » de « Mon profil » (lot 3, T10), comme le bloc web (`SectionProfilPrincipal.tsx`
/// l.859-877) : titre, « Utiliser ma position actuelle » (seulement avec un port de localisation : jamais un bouton sans
/// effet), aide ou « Position enregistrée — … » (coordonnées jamais affichées), avis de la localisation. La ville de
/// recherche, posée par la position, reste le champ T9 placé juste dessous dans la même carte.
///
/// Revue B8 de T10 : bouton inactif pendant un enregistrement (`peutLocaliser`, m5) ; avis annoncé par son propre jeton
/// (`annoncesLocalisation`, m4), jamais réannoncé par « Enregistrer ».
///
/// Identifiants : `profil-adresse`, `profil-localiser`, `profil-position-aide`, `profil-localisation-avis`.
struct AdresseProfilSection: View {
    @ObservedObject var model: ProfilEditionModel

    private typealias Textes = ProfilLocalisation.Textes

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            Text(Textes.titre)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("profil-adresse")
            if model.localisationProposee {
                JoleneButton(model.localisationEnCours ? Textes.recuperationEnCours : Textes.utiliserPosition,
                             style: .secondary, isLoading: model.localisationEnCours) {
                    Task { await model.localiser() }
                }
                .disabled(!model.peutLocaliser)
                .accessibilityIdentifier("profil-localiser")
            }
            Text(model.formulaire.positionRenseignee ? Textes.positionEnregistree : Textes.aide)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("profil-position-aide")
            if let avis = model.avisLocalisation {
                switch avis {
                case let .succes(message):
                    InlineNotice(message, tone: .success, identifier: "profil-localisation-avis", announcesOnAppear: true,
                                 announcementID: model.annoncesLocalisation)
                case let .erreur(message):
                    InlineNotice(message, tone: .error, identifier: "profil-localisation-avis", announcesOnAppear: true,
                                 announcementID: model.annoncesLocalisation)
                }
            }
        }
    }
}
