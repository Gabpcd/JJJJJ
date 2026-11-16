import SwiftUI
import JoleneCore
import JoleneDesign

/// « Mes documents » (lot 2 T7), port de `src/pages/MesDocuments.tsx` : trois onglets dans l'ordre du web (Justificatifs,
/// Contrats, DPAE), Justificatifs par défaut (l.24). Contrats : liste native de T9a (`ContratsListeView`, présentation
/// onglet, branchée à l'intégration) ; DPAE : renvoi web (décision 16).
/// Ouvert depuis Profil › Mon espace (`EspaceSoignantSection`) et par les liens `/soignant/mes-documents?tab=`,
/// `/soignant/documents` et `/soignant/contrats` (L2-T10, `ongletInitial`, `MonEspaceRoute.documents`).
///
/// Drapeau `ios_natif_documents_actif` (D-FLAGS, fail-open) : lu à l'apparition ; à faux, l'écran entier devient un
/// renvoi web vers « Mes documents » sur l'onglet de l'écran (celui du lien, ou celui choisi avant la lecture du
/// drapeau ; revue B8 n°1 de L2-T10, m4). Le modèle des justificatifs vit avec l'écran (`@StateObject`) : changer d'onglet
/// ne relance ni ne perd un envoi en vol (registre `EssaisDocumentsEnVol` du processus).
///
/// Identifiants : `documents-screen`, `documents-tab-justificatifs`, `documents-tab-contrats`, `documents-tab-dpae`,
/// `documents-<onglet>-renvoi` (+ `-web` quand un présentateur de renvoi web est injecté).
struct MesDocumentsScreen: View {
    @ObservedObject private var session: SessionStore
    private let snapshot: SessionSnapshot
    private let mediaDemo: DemoMediaPicker?
    @StateObject private var model: DocumentsModel
    @State private var onglet: OngletDocuments
    @State private var ecranActif = true
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    init(container: AppContainer, session: SessionStore, snapshot: SessionSnapshot, ongletInitial: OngletDocuments = .justificatifs) {
        self.session = session
        self.snapshot = snapshot
        self.mediaDemo = container.mediaDemo
        _model = StateObject(wrappedValue: DocumentsModel(controller: session.controller, snapshot: snapshot,
                                                          recus: container.recusJustificatifs))
        _onglet = State(initialValue: ongletInitial)
    }

    var body: some View {
        VStack(spacing: 0) {
            if ecranActif {
                barreOnglets
                switch onglet {
                case .justificatifs:
                    JustificatifsView(model: model, session: session, snapshot: snapshot, mediaDemo: mediaDemo)
                case .contrats:
                    ContratsDestination.liste(session: session, snapshot: snapshot, presentation: .onglet)
                case .dpae:
                    renvoi(identifiant: "documents-dpae", route: AccueilPresentation.renvoiWeb(Self.lienDpae))
                }
            } else {
                // Route forcée web (L2-T10) : `/soignant/mes-documents` ouvre cet écran depuis T10. L'onglet du lien est
                // conservé (revue B8 n°1 de L2-T10, m4) : `?tab=contrats` mène à l'onglet Contrats du web.
                renvoi(identifiant: "documents-desactive", route: DocumentsModel.routeRenvoiWeb(onglet: onglet))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(JoleneColor.lavender.ignoresSafeArea())
        // Conteneur nommé : sans `.contain`, l'identifiant serait recopié sur chaque élément enfant.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("documents-screen")
        .navigationTitle(LibellesJustificatifs.titre)
        .navigationBarTitleDisplayMode(.inline)
        .task { ecranActif = await Self.drapeau(session: session, snapshot: snapshot) }
    }

    /// DPAE : `/soignant/dpae` (renvoi web, décision 16 ; App.tsx l.402). L'onglet Contrats est natif depuis T9a.
    static let lienDpae = "/soignant/dpae"

    private static func drapeau(session: SessionStore, snapshot: SessionSnapshot) async -> Bool {
        guard let gateways = await session.controller.gateways(for: snapshot.epoch) else { return true }
        return await gateways.flags.ecranActif(.documents)
    }

    private var barreOnglets: some View {
        HStack(spacing: JoleneSpacing.xs) {
            ForEach(OngletDocuments.allCases, id: \.self) { candidat in
                let actif = candidat == onglet
                Button { onglet = candidat } label: {
                    Text(candidat.libelle)
                        .font(JoleneFont.callout.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(actif ? JoleneColor.onGradient : JoleneColor.midnight)
                        .background(actif ? AnyShapeStyle(JoleneColor.heroGradient) : AnyShapeStyle(JoleneColor.cloud))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(actif ? .isSelected : [])
                .accessibilityIdentifier("documents-tab-\(candidat.rawValue)")
            }
        }
        .padding(.horizontal, JoleneSpacing.lg)
        .padding(.vertical, JoleneSpacing.sm)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    /// Renvoi web d'un onglet sans version native : texte du lot 0, bouton seulement si un présentateur est injecté (aucun
    /// bouton sans effet : verrou du gap de `PresentateurRenvoiWeb`) et si la route existe (DPAE : résolue par le routeur,
    /// nil s'il devenait natif ; écran désactivé : route forcée web, L2-T10).
    private func renvoi(identifiant: String, route: JoleneRoute?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                InlineNotice(LibellesJustificatifs.espaceNonDisponible, tone: .info, identifier: "\(identifiant)-renvoi")
                if let presentateurRenvoiWeb, let route {
                    JoleneButton(LibellesJustificatifs.voirSurJoleneApp, style: .secondary) { presentateurRenvoiWeb.presenter(route) }
                        .accessibilityIdentifier("\(identifiant)-web")
                }
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }
}
