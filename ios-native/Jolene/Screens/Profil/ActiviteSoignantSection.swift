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

/// « Documents & protection » du hub web (`MonCompteSoignant.tsx` l.80-89), L4-T13 (intégration de la vague D, décision
/// f) : renvois web assumés de `LOT4_PLAN.md` §1.3, table `RenvoisWebLot4.entreesDocumentsProtection` — « Prévoyance »
/// seule, la ligne que le web montre à tous ; « Passer en libéral » et « Attestation d'heures » dépendent de
/// l'éligibilité au libéral, règle juridique jamais recalculée en natif (voir `RenvoisWebLot4`). Chaque ligne présente sa
/// page web par le présentateur `.safari` (`SFSafariViewController`, double `renvoi-web-demo` en démo), jamais
/// `openURL` ; sans présentateur, la section ne rend rien (jamais un bouton sans effet).
///
/// Identifiants : `hub-renvoi-<clé>` (valeur = URL présentée).
struct RenvoisWebHubSection: View {
    @ObservedObject var session: SessionStore
    let snapshot: SessionSnapshot
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    var body: some View {
        if let presentateurRenvoiWeb, !RenvoisWebLot4.entreesDocumentsProtection.isEmpty {
            Section {
                ForEach(RenvoisWebLot4.entreesDocumentsProtection, id: \.identifiant) { entree in
                    Button { presentateurRenvoiWeb.presenter(.safari(entree.url)) } label: {
                        Label(entree.libelle, systemImage: "safari")
                    }
                    .accessibilityIdentifier(entree.identifiant)
                    .accessibilityValue(entree.url.absoluteString)
                }
            } header: {
                Text(RenvoisWebLot4.titreDocumentsProtection)
            }
        }
    }
}
