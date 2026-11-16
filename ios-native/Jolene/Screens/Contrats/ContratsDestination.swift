import SwiftUI
import JoleneCore
import JoleneDesign

/// Destinations natives des contrats (lot 2, T9a), pour les points d'entrée des autres tranches, une ligne chacune
/// (consigne T9a de `DECISIONS_LOT2.md`) : « Mes contrats » du Profil (T4a, `EspaceSoignantSection`), onglet Contrats
/// de « Mes documents » (T7, `presentation: .onglet`), « Voir le contrat » du bloc de pointage (T4a,
/// `BlocPointageView`), liens `/contrat/:id` et `/contrat/:id/certificat` (L2-T10, `MonEspaceRoute`).
///
/// Seul point de construction des écrans de contrat : il lit le coupe-circuit `ios_natif_contrats_actif` (D-FLAGS de
/// `DECISIONS_LOT2.md`, à la charge de L2-T10 ; fail-open comme `ios_natif_presences_actif` et
/// `ios_natif_documents_actif`). À faux, l'écran devient un renvoi web : `/contrat/<id>`, `/contrat/<id>/certificat` ou
/// `/soignant/mes-documents?tab=contrats` (routes forcées web de `ContratPresentation`, ces chemins étant natifs depuis
/// T10), texte du lot 0 et « Voir sur jolene.app » repris de « Mes documents », bouton seulement avec le présentateur des
/// renvois web (jamais un bouton sans effet). Identifiants : `contrats-desactive-renvoi`, `contrats-desactive-web`.
///
/// Écart consigné (L2-T10) : `?statut=` (`FiltreContrat.initial(statut:)`) n'est porté par aucun lien. L'alias web
/// `/soignant/contrats` le perd (`Navigate` à cible fixe, `src/App.tsx` l.407) et aucun lien du web ne pose
/// `/soignant/mes-documents?tab=contrats&statut=` ; la liste s'ouvre donc sur « Tous », comme le web.
enum ContratsDestination {
    @MainActor
    static func liste(session: SessionStore, snapshot: SessionSnapshot, filtreInitial: FiltreContrat = .tous,
                      presentation: ContratsListeView.Presentation = .ecran) -> some View {
        PorteContrats(session: session, snapshot: snapshot, renvoi: ContratPresentation.renvoiListe,
                      titre: presentation == .ecran ? LibellesWeb.Contrats.titre : nil) {
            ContratsListeView(session: session, snapshot: snapshot, filtreInitial: filtreInitial, presentation: presentation)
        }
    }

    @MainActor
    static func contrat(session: SessionStore, snapshot: SessionSnapshot, contratId: String) -> some View {
        PorteContrats(session: session, snapshot: snapshot, renvoi: ContratPresentation.renvoiContrat(contratId: contratId),
                      titre: nil) {
            ContratScreen(session: session, snapshot: snapshot, contratId: contratId)
        }
    }

    @MainActor
    static func certificat(session: SessionStore, snapshot: SessionSnapshot, contratId: String) -> some View {
        PorteContrats(session: session, snapshot: snapshot, renvoi: ContratPresentation.renvoiCertificat(contratId: contratId),
                      titre: nil) {
            CertificatRoute(session: session, snapshot: snapshot, contratId: contratId)
        }
    }
}

/// Coupe-circuit `ios_natif_contrats_actif` (L2-T10) : lu à l'apparition (fail-open tant qu'il n'est pas lu, comme
/// `PresencesScreen` et `MesDocumentsScreen`) ; à faux, le contenu est remplacé par son renvoi web.
struct PorteContrats<Contenu: View>: View {
    let session: SessionStore
    let snapshot: SessionSnapshot
    let renvoi: JoleneRoute?
    /// Titre de navigation du renvoi (écran « Mes contrats » seulement ; l'onglet de « Mes documents » n'en impose pas).
    let titre: String?
    @ViewBuilder let contenu: () -> Contenu
    @State private var ecranActif = true
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    var body: some View {
        Group {
            if ecranActif { contenu() } else { renvoiDesactive }
        }
        .task { ecranActif = await Self.drapeau(session: session, snapshot: snapshot) }
    }

    private static func drapeau(session: SessionStore, snapshot: SessionSnapshot) async -> Bool {
        guard let gateways = await session.controller.gateways(for: snapshot.epoch) else { return true }
        return await gateways.flags.ecranActif(.contrats)
    }

    @ViewBuilder
    private var renvoiDesactive: some View {
        let page = ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                InlineNotice(LibellesJustificatifs.espaceNonDisponible, tone: .info, identifier: "contrats-desactive-renvoi")
                if let presentateurRenvoiWeb, let renvoi {
                    JoleneButton(LibellesJustificatifs.voirSurJoleneApp, style: .secondary) { presentateurRenvoiWeb.presenter(renvoi) }
                        .accessibilityIdentifier("contrats-desactive-web")
                }
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(JoleneColor.lavender.ignoresSafeArea())
        if let titre {
            page.navigationTitle(titre)
        } else {
            page
        }
    }
}
