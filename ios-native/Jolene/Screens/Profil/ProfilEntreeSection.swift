import SwiftUI
import JoleneCore
import JoleneDesign

/// Entrée « Mon profil » du hub (lot 3, T9 ; libellé `MonCompteSoignant.tsx` l.59) vers l'édition native
/// (`ProfilEditionScreen`). Montée par une seule ligne de `ProfileScreen` (propriété de T11), après la
/// section « Application » : ni « Se déconnecter » ni les identifiants du lot 0 testés par les XCUITest
/// existants ne bougent. Point de fusion T11 : la section rejoint l'ordre du hub web (« Mon profil » en
/// tête), et L1-T10 ouvre le même écran pour la route `.profil` (`/soignant/profil`, alias `reputation`).
/// Point de fusion T11/T3b (`DECISIONS_LOT3.md`, T9) : ce lien à fermeture ne se pousse pas par programme.
/// Pour que le coordinateur de liens ouvre l'édition : T3b rend `JoleneRoute` `Hashable` (`JoleneRoute.swift`,
/// fichier de T3) et pousse `.profil` sur la pile de l'onglet Profil ; T11 (propriétaire du hub) remplace ce
/// lien par `NavigationLink(value: JoleneRoute.profil)` et pose `.navigationDestination(for: JoleneRoute.self)`
/// sur la `List` de `ProfileScreen`, hors du conteneur paresseux (comme `MissionRoute` pour Accueil et Explorer).
/// Identifiant : `profil-ouvrir`.
struct ProfilEntreeSection: View {
    @ObservedObject var session: SessionStore
    let snapshot: SessionSnapshot

    var body: some View {
        Section {
            NavigationLink {
                ProfilEditionScreen(session: session, snapshot: snapshot)
            } label: {
                Label(ProfilEdition.Textes.titre, systemImage: "person.text.rectangle")
                    .font(JoleneFont.body)
                    .foregroundStyle(JoleneColor.midnight)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("profil-ouvrir")
        }
    }
}
