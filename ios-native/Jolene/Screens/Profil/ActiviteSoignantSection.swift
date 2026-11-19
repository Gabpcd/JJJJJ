import SwiftUI
import JoleneCore

/// Entrées du hub vers les écrans secondaires du lot 4 (L4-T1c), insérées une fois dans `ProfileScreen` après
/// « Paiements & facturation », dans l'ordre et sous les titres du hub web (`EntreesHubLot4`,
/// `src/pages/MonCompteSoignant.tsx` l.92-110). Seuls les écrans livrés ont une entrée : tant qu'aucune tranche n'a
/// livré, la section ne rend rien et le hub reste celui d'avant le lot 4. Liens par valeur (`SecondaireRoute`), servis
/// par `destinationsSecondaires` sur la pile du Profil ; le coupe-circuit de l'écran est lu par `SecondaryRouter`.
///
/// Les renvois web assumés de §1.3 (« Documents & protection » du web : Passer en libéral, Attestation d'heures,
/// Prévoyance) relèvent de T13 (`RenvoisWebHubSection`, posée juste avant).
struct ActiviteSoignantSection: View {
    var body: some View {
        ForEach(Array(EntreesHubLot4.sections().enumerated()), id: \.offset) { _, section in
            Section {
                ForEach(section.entrees, id: \.identifiant) { entree in
                    NavigationLink(value: SecondaireRoute(ecran: entree.ecran)) {
                        Text(entree.libelle)
                    }
                    .accessibilityIdentifier(entree.identifiant)
                }
            } header: {
                if let titre = section.titre { Text(titre) }
            }
        }
    }
}

/// « Documents & protection » du hub web (`MonCompteSoignant.tsx` l.80-89 : Passer en libéral, Attestation d'heures,
/// Prévoyance, selon le type d'exercice et la profession) — **stub de L4-T1c**, remplacé par T13 (renvois web assumés
/// de `LOT4_PLAN.md` §1.3) sans retoucher `ProfileScreen`. Ne rend rien avant T13.
struct RenvoisWebHubSection: View {
    @ObservedObject var session: SessionStore
    let snapshot: SessionSnapshot

    var body: some View {
        EmptyView()
    }
}
