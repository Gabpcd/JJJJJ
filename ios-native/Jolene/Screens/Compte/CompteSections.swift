import SwiftUI
import UIKit
import JoleneCore
import JoleneDesign

// Sections du hub « Mon compte » livrées par le lot 3, T11 (`ProfileScreen`, propriétaire du hub).

/// Thème Système / Clair / Sombre (D16) dans la section « Réglages » du hub, à la place du bouton web « Passer en
/// thème clair / sombre » (`MonCompteSoignant.tsx` l.116-122). Choix appliqué à la racine (`ThemeRacine`).
/// Identifiants : `compte-theme` (+ `-systeme`, `-clair`, `-sombre`) ; DEBUG et démo : `compte-theme-effectif`
/// (schéma de couleurs effectif lu dans l'environnement, preuve XCUITest que le choix est appliqué).
struct ThemeRow: View {
    @ObservedObject var theme: PreferenceThemeModel
    let exposerSchemaEffectif: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Label(ChoixTheme.titreGroupe, systemImage: "circle.lefthalf.filled")
                .font(JoleneFont.body)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityHidden(true)
            SegmentedChoice(ChoixTheme.titreGroupe,
                            options: ChoixTheme.allCases.map { SegmentedChoice.Option(id: $0.rawValue, title: $0.libelle) },
                            selection: Binding(get: { theme.choix.rawValue },
                                               set: { theme.choisir(ChoixTheme(rawValue: $0) ?? .systeme) }),
                            identifier: "compte-theme")
        }
        .padding(.vertical, JoleneSpacing.xs)
        #if DEBUG
        .overlay(alignment: .topTrailing) {
            if exposerSchemaEffectif { SchemaEffectifDebug() }
        }
        #endif
    }
}

#if DEBUG
/// Libellé invisible du schéma de couleurs effectif (« clair » / « sombre »), DEBUG et démo seulement.
private struct SchemaEffectifDebug: View {
    @Environment(\.colorScheme) private var schema

    var body: some View {
        Text(schema == .dark ? "sombre" : "clair")
            .font(.system(size: 1))
            .foregroundStyle(.clear)
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityIdentifier("compte-theme-effectif")
    }
}
#endif

/// Section « Mes données (RGPD) » (port de `SectionConfidentialite.tsx` l.109-134, rangée dans le hub : écart de
/// placement assumé, le web la monte dans l'onglet confidentialité du profil) : texte RGPD verbatim (tutoiement,
/// HARD STOP n°4), « Exporter JSON » / « Exporter CSV » (« Export… » pendant l'export, les deux désactivés),
/// refus serveur verbatim, succès après un partage abouti. La feuille de partage est présentée par
/// `ProfileScreen` (hors du conteneur paresseux). Identifiants : `compte-export-info`, `compte-export-json`,
/// `compte-export-csv`, `compte-export-succes`, `compte-export-erreur`, `compte-export-session-verifier`.
struct ExportRGPDSection: View {
    @ObservedObject var model: ExportRGPDModel

    private typealias Textes = ExportRGPD.Textes

    var body: some View {
        Section(Textes.titre) {
            Text(Textes.description)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.midnight)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("compte-export-info")
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                ForEach(FormatExportRGPD.allCases, id: \.self) { format in
                    JoleneButton(model.enCours == nil ? Textes.bouton(format) : Textes.enCours, style: .secondary,
                                 isLoading: model.enCours == format) {
                        Task { await model.exporter(format) }
                    }
                    .disabled(!model.peutExporter)
                    .accessibilityIdentifier("compte-export-\(format.rawValue)")
                }
                if let succes = model.succes {
                    InlineNotice(succes, tone: .success, identifier: "compte-export-succes", announcesOnAppear: true,
                                 announcementID: model.annonces)
                }
                if let erreur = model.erreur {
                    InlineNotice(erreur, tone: .error, identifier: "compte-export-erreur", announcesOnAppear: true,
                                 announcementID: model.annonces)
                    if model.sessionExpiree {
                        JoleneButton(ProfilEdition.Textes.verifierSession, style: .secondary) {
                            Task { await model.verifierSession() }
                        }
                        .accessibilityIdentifier("compte-export-session-verifier")
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: JoleneSpacing.sm, leading: 0, bottom: JoleneSpacing.sm, trailing: 0))
        }
    }
}

/// Feuille de partage iOS (`UIActivityViewController`) sur le fichier d'export : « Enregistrer dans Fichiers »,
/// AirDrop… (équivalent de `telechargerOuPartager`, `src/lib/telechargement.ts` l.37-48). `termine(complete)` est
/// appelé une fois à la fermeture (partage abouti ou annulé) : le modèle supprime alors le fichier.
struct PartageFichierView: UIViewControllerRepresentable {
    let url: URL
    let termine: @MainActor @Sendable (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controleur = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controleur.completionWithItemsHandler = { _, complete, _, _ in
            Task { @MainActor in termine(complete) }
        }
        return controleur
    }

    func updateUIViewController(_ controleur: UIActivityViewController, context: Context) {}
}

/// Section « Aide & légal » (`MonCompteSoignant.tsx` l.126-136) : pages publiques ouvertes par le présentateur
/// `.safari` (L1-T10, `DestinationLien.destination`), jamais par `openURL`. Montée seulement si le présentateur
/// est injecté : jamais un lien sans effet (verrou du gap, `DemoCompteLot3Tests` affirme son absence en
/// attendant T10). Identifiants : `compte-aide`, `compte-confidentialite`, `compte-cgu`, `compte-mentions-legales`.
struct AideEtLegalSection: View {
    let presentateur: any PresentateurRenvoiWeb

    var body: some View {
        Section(HubCompte.titreAideEtLegal) {
            ForEach(HubCompte.aideEtLegal) { lien in
                if let destination = HubCompte.destination(lien) {
                    Button { presentateur.presenter(destination) } label: {
                        Label(lien.libelle, systemImage: "safari")
                            .font(JoleneFont.body)
                            .foregroundStyle(JoleneColor.midnight)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier(lien.id)
                }
            }
        }
    }
}
