import SwiftUI
import JoleneCore
import JoleneDesign

/// Entrée « Mon profil » du hub (lot 3, T9 ; libellé `MonCompteSoignant.tsx` l.59) vers l'édition native
/// (`ProfilEditionScreen`). Montée par une seule ligne de `ProfileScreen` (propriété de T11), après la
/// section « Application » : ni « Se déconnecter » ni les identifiants du lot 0 testés par les XCUITest
/// existants ne bougent. Point de fusion T11 : la section rejoint l'ordre du hub web (« Mon profil » en
/// tête), et L1-T10 ouvre le même écran pour la route `.profil` (`/soignant/profil`, alias `reputation`).
/// Navigation programmée (intégration du lot 3, revue L3-T9 m6) : lien par valeur `ProfilEditionRoute`, dont la
/// destination est enregistrée par `MainTabView` sur la pile de l'onglet Profil (hors du conteneur paresseux) ;
/// `MainTabView.presenter` pousse la même route (ligne du centre, tap push). Le coordinateur de L1-T10 / T3b
/// reprend cette présentation. Identifiant : `profil-ouvrir`.
struct ProfilEntreeSection: View {
    var body: some View {
        Section {
            NavigationLink(value: ProfilEditionRoute()) {
                Label(ProfilEdition.Textes.titre, systemImage: "person.text.rectangle")
                    .font(JoleneFont.body)
                    .foregroundStyle(JoleneColor.midnight)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("profil-ouvrir")
        }
    }
}
