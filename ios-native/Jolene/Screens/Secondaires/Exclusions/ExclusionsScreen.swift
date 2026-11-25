import SwiftUI
import JoleneCore
import JoleneDesign

/// Établissements exclus (`/soignant/exclusions`, L4-T11), port de la partie « Mes exclusions » de `ExclusionsSoignant.tsx`,
/// empilé sur le Profil par `SecondaryRouter` une fois son coupe-circuit `ios_natif_exclusions_actif` lu (fail-open). Vue
/// de `ExclusionsModel` (JoleneCore) : deux onglets « Envoyées (n) » / « Reçues (n) », retrait d'une exclusion envoyée
/// après confirmation (« Exclusion supprimée. » seulement après relecture), reçues en lecture seule avec l'avis du web.
/// L'interrupteur du pool urgence que le web affiche en tête de cette page vit sur son propre écran natif (Pool urgence).
///
/// Identifiants : `exclusions-screen`, `exclusions-onglets`, `exclusion-envoyee-<exclu_id>`,
/// `exclusion-recue-<id>`, `exclusion-retirer-<exclu_id>` ; `exclusions-chargement`, `exclusions-erreur`
/// (+ `-reessayer`), `exclusions-vide-envoyees`, `exclusions-vide-recues`, `exclusions-avis-recues`,
/// `exclusions-action-erreur`, `exclusions-confirmation`, `exclusions-session-check` ; confirmation `exclusion-suppression`.
struct ExclusionsScreen: View {
    private enum Onglet: Hashable { case envoyees, recues }

    let contexte: ContexteSecondaire
    @StateObject private var model: ExclusionsModel
    @ObservedObject private var session: SessionStore
    @State private var onglet: Onglet = .envoyees
    @State private var aRetirer: Exclusion?

    init(contexte: ContexteSecondaire) {
        self.contexte = contexte
        self.session = contexte.session
        _model = StateObject(wrappedValue: ExclusionsModel(controller: contexte.session.controller, snapshot: contexte.snapshot))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                Label(ExclusionsTextes.mesExclusions, systemImage: "nosign")
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityAddTraits(.isHeader)
                if aRetirer == nil { avis }
                if model.sessionExpiree {
                    JoleneButton("Vérifier ma session", style: .secondary) { Task { await model.verifierSession(session) } }
                        .accessibilityIdentifier("exclusions-session-check")
                }
                contenu
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.charger() }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(ExclusionsTextes.titre)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("exclusions-screen")
        .task { await model.charger() }
        .confirmationSheet(isPresented: retraitPresente, configurationRetrait,
                           isLoading: aRetirer.map { model.occupe($0.excluId) } ?? false, onConfirm: confirmerRetrait) {
            if let erreur = model.erreur {
                InlineNotice(erreur, tone: .error, identifier: "exclusion-suppression-erreur", announcementID: model.jeton)
            }
        }
    }

    @ViewBuilder private var avis: some View {
        if let erreur = model.erreur {
            InlineNotice(erreur, tone: .error, identifier: "exclusions-action-erreur", announcementID: model.jeton)
        } else if let confirmation = model.confirmation {
            InlineNotice(confirmation, tone: .success, identifier: "exclusions-confirmation", announcementID: model.jeton)
        }
    }

    @ViewBuilder private var contenu: some View {
        switch model.ecran {
        case .chargement:
            SkeletonCard(identifier: "exclusions-chargement")
        case let .echec(message):
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                InlineNotice(message, tone: .error, identifier: "exclusions-erreur")
                if !model.sessionExpiree {
                    JoleneButton(ExclusionsTextes.reessayer, style: .secondary) { Task { await model.charger() } }
                        .accessibilityIdentifier("exclusions-erreur-reessayer")
                }
            }
        case let .pret(listes):
            Picker(ExclusionsTextes.mesExclusions, selection: $onglet) {
                Text("\(ExclusionsTextes.envoyees) (\(listes.envoyees.count))").tag(Onglet.envoyees)
                Text("\(ExclusionsTextes.recues) (\(listes.recues.count))").tag(Onglet.recues)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("exclusions-onglets")
            if onglet == .envoyees { envoyees(listes.envoyees) } else { recues(listes.recues) }
        }
    }

    @ViewBuilder private func envoyees(_ lignes: [Exclusion]) -> some View {
        if lignes.isEmpty {
            EmptyState(systemImage: "shield", title: ExclusionsTextes.videEnvoyeesTitre, message: ExclusionsTextes.videEnvoyeesTexte,
                       identifier: "exclusions-vide-envoyees")
        } else {
            ForEach(lignes) { exclusion in
                let nom = exclusion.etablissementNom ?? exclusion.excluId
                HStack(alignment: .center, spacing: JoleneSpacing.sm) {
                    details(nom: nom, exclusion: exclusion)
                    Spacer(minLength: 0)
                    Button { model.effacerMessages(); aRetirer = exclusion } label: {
                        Image(systemName: "trash").foregroundStyle(JoleneColor.rose700)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(model.occupe(exclusion.excluId))
                    .accessibilityLabel(ExclusionsTextes.retirerAccessibilite(nom))
                    .accessibilityIdentifier("exclusion-retirer-\(exclusion.excluId)")
                }
                .padding(JoleneSpacing.lg)
                .background(JoleneColor.cloud)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("exclusion-envoyee-\(exclusion.excluId)")
            }
        }
    }

    @ViewBuilder private func recues(_ lignes: [Exclusion]) -> some View {
        InlineNotice(ExclusionsTextes.recuesAvis, tone: .warning, identifier: "exclusions-avis-recues")
        if lignes.isEmpty {
            EmptyState(systemImage: "shield", title: ExclusionsTextes.videRecuesTitre, message: ExclusionsTextes.videRecuesTexte,
                       identifier: "exclusions-vide-recues")
        } else {
            ForEach(lignes) { exclusion in
                details(nom: exclusion.etablissementNom ?? ExclusionsTextes.etablissementInconnu, exclusion: exclusion)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(JoleneSpacing.lg)
                    .background(JoleneColor.cloud)
                    .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("exclusion-recue-\(exclusion.id)")
            }
        }
    }

    private func details(nom: String, exclusion: Exclusion) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(nom).font(JoleneFont.headline).foregroundStyle(JoleneColor.midnight)
            if let motif = exclusion.motif, !motif.isEmpty {
                Text(motif).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
            }
            if let depuis = ExclusionsRegles.depuis(exclusion.creeLe) {
                Text(depuis).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
            }
        }
    }

    private var retraitPresente: Binding<Bool> {
        Binding(get: { aRetirer != nil }, set: { if !$0 { aRetirer = nil } })
    }

    private var configurationRetrait: ConfirmationSheet.Configuration {
        ConfirmationSheet.Configuration(title: ExclusionsTextes.supprimerTitre, message: ExclusionsTextes.supprimerMessage,
                                        confirmTitle: ExclusionsTextes.supprimer, variant: .danger,
                                        identifier: "exclusion-suppression")
    }

    private func confirmerRetrait() {
        guard let cible = aRetirer else { return }
        Task {
            // La feuille ne se referme qu'après une relecture qui confirme le retrait.
            if await model.retirer(cible) { aRetirer = nil }
        }
    }
}
