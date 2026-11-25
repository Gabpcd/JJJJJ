import SwiftUI
import JoleneCore
import JoleneDesign

/// « Litiges & contestations » (`/soignant/litiges?tab=&litige=`, alias `/soignant/reclamations` ; L4-T8), port de
/// `LitigesContestationsSoignant.tsx` : deux onglets, « Litiges mission » (`LitigesListeView`, `LitigesModel`) et
/// « Réclamations » (`ReclamationsView`, `ReclamationsModel`). Empilé sur le Profil par `SecondaryRouter`, une fois le
/// coupe-circuit de l'onglet d'ouverture lu (`ios_natif_litiges_actif`, ou `ios_natif_reclamations_actif` pour
/// `?tab=reclamations`). Les vues n'ajoutent aucune règle : elles sont celles des modèles du cœur.
///
/// Chaque onglet a son coupe-circuit : celui de l'autre onglet est lu à sa première sélection, avant que son contenu
/// ne soit construit ; coupé, l'onglet montre le renvoi vers sa page web (texte neutre de `RenvoiWebScreen`).
///
/// Identifiants : `litiges-screen` (défilement), `litiges-onglet-litiges`, `litiges-onglet-reclamations`,
/// `litiges-onglet-lecture`, `litiges-onglet-renvoi` (+ `renvoi-web-message`, `renvoi-web-ouvrir`).
struct LitigesScreen: View {
    let contexte: ContexteSecondaire
    @StateObject private var litiges: LitigesModel
    @StateObject private var reclamations: ReclamationsModel
    @State private var selection: String
    /// Coupe-circuits lus : celui de l'onglet d'ouverture l'a été par `SecondaryRouter`.
    @State private var portes: [EcranSecondaire.OngletLitiges: PorteEcranNatif]
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    init(onglet: EcranSecondaire.OngletLitiges?, litigeId: String?, contexte: ContexteSecondaire) {
        self.contexte = contexte
        let initial = onglet ?? .litiges
        _selection = State(initialValue: initial.rawValue)
        _portes = State(initialValue: [initial: .natif])
        let controller = contexte.session.controller
        _litiges = StateObject(wrappedValue: LitigesModel(controller: controller, snapshot: contexte.snapshot, cible: litigeId))
        _reclamations = StateObject(wrappedValue: ReclamationsModel(controller: controller, snapshot: contexte.snapshot))
    }

    private var onglet: EcranSecondaire.OngletLitiges { EcranSecondaire.OngletLitiges(rawValue: selection) ?? .litiges }

    private static let options = [
        SegmentedChoice.Option(id: EcranSecondaire.OngletLitiges.litiges.rawValue, title: LitigesTextes.ongletLitiges),
        SegmentedChoice.Option(id: EcranSecondaire.OngletLitiges.reclamations.rawValue, title: LitigesTextes.ongletReclamations),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                SegmentedChoice(LitigesTextes.titreEcran, options: Self.options, selection: $selection, identifier: "litiges-onglet")
                switch portes[onglet] ?? .lecture {
                case .lecture:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .accessibilityIdentifier("litiges-onglet-lecture")
                case .renvoiWeb:
                    renvoi
                case .natif:
                    switch onglet {
                    case .litiges: LitigesListeView(model: litiges, session: contexte.session, snapshot: contexte.snapshot)
                    case .reclamations: ReclamationsView(model: reclamations, session: contexte.session)
                    }
                }
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        // Pas de fermeture du clavier par défilement : le champ de message se referme par « OK » (`boutonOKClavier`),
        // jamais pendant un glissement (DECISIONS_LOT2, « Gel iPhone CI — 16/11/2026 »).
        .refreshable { await rafraichir() }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(LitigesTextes.titreEcran)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("litiges-screen")
        // Coupe-circuit de l'onglet choisi, lu avant que son contenu ne soit construit (aucune lecture de l'onglet avant).
        .task(id: selection) { await lirePorte() }
    }

    /// Onglet coupé par son drapeau : renvoi vers sa page web, texte neutre de `RenvoiWebScreen` (aucun texte nouveau).
    private var renvoi: some View {
        VStack(spacing: JoleneSpacing.lg) {
            Text(RenvoiWebScreen.message)
                .font(JoleneFont.body)
                .foregroundStyle(JoleneColor.midnight)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("renvoi-web-message")
            if let presentateurRenvoiWeb, let url = EcranSecondaire.litiges(onglet: onglet, litigeId: nil).urlWeb {
                JoleneButton(RenvoiWebScreen.bouton, style: .secondary) { presentateurRenvoiWeb.presenter(.safari(url)) }
                    .frame(maxWidth: 320)
                    .accessibilityIdentifier("renvoi-web-ouvrir")
            }
        }
        .padding(JoleneSpacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("litiges-onglet-renvoi")
    }

    private func lirePorte() async {
        let courant = onglet
        guard portes[courant] == nil else { return }
        let flags = await contexte.session.controller.gateways(for: contexte.snapshot.epoch)?.flags
        let porte = await PorteEcranNatif.lire(EcranSecondaire.litiges(onglet: courant, litigeId: nil), flags: flags)
        guard !Task.isCancelled else { return }
        portes[courant] = porte
    }

    private func rafraichir() async {
        guard portes[onglet] == .natif else { return }
        switch onglet {
        case .litiges: await litiges.charger()
        case .reclamations: await reclamations.charger()
        }
    }
}
