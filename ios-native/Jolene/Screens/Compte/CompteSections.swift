import Combine
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
/// `ProfileScreen` (`FeuillePartageExport`, hub à l'écran seulement). Identifiants : `compte-export-info`,
/// `compte-export-json`, `compte-export-csv`, `compte-export-succes`, `compte-export-erreur`,
/// `compte-export-session-verifier` ; DEBUG et démo : `compte-export-residus` (nombre de dossiers d'export
/// présents dans le dossier temporaire, « 0 » une fois la feuille fermée : preuve XCUITest de la suppression).
struct ExportRGPDSection: View {
    @ObservedObject var model: ExportRGPDModel
    var exposerResidus = false

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
            #if DEBUG
            .overlay(alignment: .topTrailing) {
                if exposerResidus {
                    // Relu à chaque rendu (fin de partage comprise : `partage` publié après la suppression).
                    Text("\(model.residus)")
                        .font(.system(size: 1))
                        .foregroundStyle(.clear)
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("compte-export-residus")
                }
            }
            #endif
        }
    }
}

/// Feuille de partage iOS (`UIActivityViewController`) du fichier d'export : « Enregistrer dans Fichiers »,
/// AirDrop, « Copier »… (équivalent de `telechargerOuPartager`, `src/lib/telechargement.ts` l.37-48).
///
/// Revue B8 (M1) — une seule source de fin. La feuille est présentée par UIKit, depuis le contrôleur au sommet de
/// la fenêtre (popover centré sans flèche sur iPad), et non par une `.sheet` SwiftUI : quand une activité aboutit,
/// `UIActivityViewController` se ferme lui-même, et la fermeture de la `.sheet` (setter du binding) arrivait AVANT
/// `completionWithItemsHandler`, qu'elle rendait sans effet (fichier supprimé, aucun succès). Ici, la fin passe
/// UNIQUEMENT par `completionWithItemsHandler` — appelé par UIKit après la fermeture, quelle qu'en soit la cause
/// (activité aboutie, bouton de fermeture, glissement, tap hors du popover) —, relayé de façon synchrone
/// (`MainActor.assumeIsolated`) à `ExportRGPDModel.partageTermine(complete:)`. Seule autre fermeture : celle que
/// le modèle impose en retirant le fichier (fin de session) ; la feuille est alors fermée par programme, et la
/// fin tardive qu'UIKit pourrait encore signaler est sans effet.
/// DEBUG et démo : libellé `compte-export-pret` (nom du fichier) posé DANS la feuille, le contenu qu'elle recouvre
/// n'étant plus exposé à l'accessibilité.
@MainActor
final class FeuillePartageExport {
    private let model: ExportRGPDModel
    private weak var controleur: UIActivityViewController?
    private var suivi: AnyCancellable?

    private init(model: ExportRGPDModel) {
        self.model = model
    }

    /// Présente la feuille de `fichier` (le modèle la tient pour présentée avant la présentation effective : jamais
    /// deux feuilles). Sans fenêtre active pour la présenter, le partage prend fin aussitôt (fichier supprimé).
    static func presenter(_ fichier: FichierAPartager, model: ExportRGPDModel, exposerNom: Bool) {
        model.feuillePresentee(fichier)
        guard let sommet = controleurAuSommet() else {
            model.partageTermine(complete: false)
            return
        }
        let feuille = FeuillePartageExport(model: model)
        let controleur = UIActivityViewController(activityItems: [fichier.url], applicationActivities: nil)
        // Fin unique : la feuille (retenue par ce handler tant que UIKit tient le contrôleur) relaie l'issue.
        controleur.completionWithItemsHandler = { _, complete, _, _ in
            MainActor.assumeIsolated { feuille.terminer(complete: complete) }
        }
        if let popover = controleur.popoverPresentationController {
            popover.sourceView = sommet.view
            popover.sourceRect = CGRect(x: sommet.view.bounds.midX, y: sommet.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        feuille.controleur = controleur
        // Fichier retiré par le modèle (fin de session) : la feuille de l'identité partie est fermée.
        feuille.suivi = model.$partage.dropFirst().sink { [weak feuille] partage in
            if partage == nil { feuille?.fermerSiPresentee() }
        }
        sommet.present(controleur, animated: true) {
            #if DEBUG
            if exposerNom { Self.poserLibelleDebug(fichier.nom, dans: controleur.view) }
            #endif
        }
    }

    private func terminer(complete: Bool) {
        suivi = nil
        model.partageTermine(complete: complete)
    }

    private func fermerSiPresentee() {
        guard let controleur, controleur.presentingViewController != nil, !controleur.isBeingDismissed else { return }
        controleur.dismiss(animated: true)
    }

    /// Contrôleur au sommet de la fenêtre de la scène active (celui qui ne présente rien, ou rien qui se ferme).
    private static func controleurAuSommet() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let fenetre = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var sommet = fenetre?.rootViewController
        while let presente = sommet?.presentedViewController, !presente.isBeingDismissed {
            sommet = presente
        }
        return sommet
    }

    #if DEBUG
    /// Libellé invisible de 1 pt, identifiant `compte-export-pret` (preuve XCUITest, démo seulement).
    private static func poserLibelleDebug(_ nom: String, dans vue: UIView?) {
        guard let vue else { return }
        let libelle = UILabel(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        libelle.text = nom
        libelle.font = .systemFont(ofSize: 1)
        libelle.textColor = .clear
        libelle.isUserInteractionEnabled = false
        libelle.accessibilityIdentifier = "compte-export-pret"
        vue.addSubview(libelle)
    }
    #endif
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
