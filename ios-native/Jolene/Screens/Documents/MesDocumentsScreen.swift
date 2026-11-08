import SwiftUI
import JoleneCore
import JoleneDesign

/// « Mes documents » (lot 2 T7), port de `src/pages/MesDocuments.tsx` : trois onglets dans l'ordre du web (Justificatifs,
/// Contrats, DPAE), Justificatifs par défaut (l.24). Contrats : renvoi web jusqu'à T9a ; DPAE : renvoi web (décision 16).
/// Ouvert depuis Profil › Mon espace (`EspaceSoignantSection`) ; T10 y routera `/soignant/mes-documents?tab=` (`ongletInitial`).
///
/// Drapeau `ios_natif_documents_actif` (D-FLAGS, fail-open) : lu à l'apparition ; à faux, l'écran entier devient un
/// renvoi web. Le modèle des justificatifs vit avec l'écran (`@StateObject`) : changer d'onglet ne relance ni ne perd un
/// envoi en vol (registre `EssaisDocumentsEnVol` du processus).
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
                    renvoi(identifiant: "documents-contrats", lien: Self.lienContrats)
                case .dpae:
                    renvoi(identifiant: "documents-dpae", lien: Self.lienDpae)
                }
            } else {
                renvoi(identifiant: "documents-desactive", lien: DocumentsModel.renvoiWeb)
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

    /// Contrats : onglet natif à T9a (`/soignant/contrats`, alias du web, App.tsx l.404). DPAE : `/soignant/dpae` (renvoi
    /// web, décision 16 ; App.tsx l.402).
    static let lienContrats = "/soignant/contrats"
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
    /// bouton sans effet : verrou du gap de `PresentateurRenvoiWeb`) et si le lien n'est pas devenu natif.
    private func renvoi(identifiant: String, lien: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                InlineNotice(LibellesJustificatifs.espaceNonDisponible, tone: .info, identifier: "\(identifiant)-renvoi")
                if let presentateurRenvoiWeb, let route = AccueilPresentation.renvoiWeb(lien) {
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
