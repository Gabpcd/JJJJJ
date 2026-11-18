import SwiftUI
import JoleneCore
import JoleneDesign

/// « Mes recherches sauvegardées » (`/soignant/parametres/recherches-sauvegardees`, L4-T4), port de
/// `PageRecherchesSauvegardees.tsx` (rôle SOIGNANT), empilé sur le Profil par `SecondaryRouter` une fois son
/// coupe-circuit `ios_natif_recherches_actif` lu (fail-open). Vue de `FiltresModel` (JoleneCore), qui porte les règles
/// (relecture qui confirme, refus verbatim, délai, second appui, session, epoch) ; la vue n'ajoute aucune logique.
///
/// - Liste dans l'ordre serveur (`mis_a_jour_le` décroissant) : nom, état de l'alerte, dernier passage et nombre de
///   résultats (valeurs serveur) ; cloche (bascule de l'alerte), « Modifier » (nom, alerte, fréquence ; les critères ne
///   sont pas modifiables, comme le web), « Supprimer » après confirmation, « Aller à la recherche » (critères appliqués
///   à Explorer par `BoiteRechercheExplorer`, puis onglet Explorer).
/// - Vide : « Créer une recherche » ouvre Explorer (la sauvegarde se fait par l'alerte rapide d'Explorer).
/// - Aide des alertes, lien « Paramètres → Notifications » vers les préférences natives.
///
/// Identifiants : `recherches-screen` ; `recherche-<id>`, `recherche-etat-<id>`, `recherche-alerte-<id>`,
/// `recherche-renommer-<id>`, `recherche-supprimer-<id>`, `recherche-appliquer-<id>` ; `recherches-chargement`,
/// `recherches-erreur` (+ `-reessayer`), `recherches-vide` (+ `-creer`), `recherches-action-erreur`,
/// `recherches-confirmation`, `recherches-session-check`, `recherches-aide`, `recherches-preferences` ; feuille
/// `recherche-modification` (`recherche-nom-<id>`, `recherche-alerte-edit-<id>`, `recherche-frequence-<id>`,
/// `recherche-enregistrer`, `recherche-annuler`, `recherche-modification-erreur`) ; confirmation `recherche-suppression`.
struct RecherchesScreen: View {
    let contexte: ContexteSecondaire
    @StateObject private var model: FiltresModel
    @ObservedObject private var session: SessionStore
    @State private var aModifier: FiltreSauvegarde?
    @State private var aSupprimer: FiltreSauvegarde?

    init(contexte: ContexteSecondaire) {
        self.contexte = contexte
        self.session = contexte.session
        _model = StateObject(wrappedValue: FiltresModel(controller: contexte.session.controller, snapshot: contexte.snapshot))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                Text(FiltresTextes.sousTitre)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                if aModifier == nil && aSupprimer == nil { avis }
                if model.sessionExpiree {
                    JoleneButton("Vérifier ma session", style: .secondary) { Task { await model.verifierSession(session) } }
                        .accessibilityIdentifier("recherches-session-check")
                }
                contenu
                aide
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.charger() }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(FiltresTextes.titre)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("recherches-screen")
        // À chaque apparition, comme le web au montage.
        .task { await model.charger() }
        .sheet(item: $aModifier) { recherche in
            RechercheModificationSheet(recherche: recherche, model: model) { aModifier = nil }
        }
        .confirmationSheet(isPresented: suppressionPresentee, configurationSuppression, isLoading: suppressionEnCours,
                           onConfirm: confirmerSuppression) {
            if let erreur = model.erreur {
                InlineNotice(erreur, tone: .error, identifier: "recherche-suppression-erreur", announcementID: model.jeton)
            }
        }
    }

    // MARK: - Contenu

    @ViewBuilder private var avis: some View {
        if let erreur = model.erreur {
            InlineNotice(erreur, tone: .error, identifier: "recherches-action-erreur", announcementID: model.jeton)
        } else if let confirmation = model.confirmation {
            InlineNotice(confirmation, tone: .success, identifier: "recherches-confirmation", announcementID: model.jeton)
        }
    }

    @ViewBuilder private var contenu: some View {
        switch model.liste {
        case .chargement:
            SkeletonCard(identifier: "recherches-chargement")
        case let .echec(message):
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                InlineNotice(message, tone: .error, identifier: "recherches-erreur")
                if !model.sessionExpiree {
                    JoleneButton(FiltresTextes.reessayer, style: .secondary) { Task { await model.charger() } }
                        .accessibilityIdentifier("recherches-erreur-reessayer")
                }
            }
        case let .prete(recherches) where recherches.isEmpty:
            VStack(spacing: JoleneSpacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityHidden(true)
                Text(FiltresTextes.vide)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("recherches-vide")
                JoleneButton(FiltresTextes.creerRecherche) { contexte.ouvrir(.explorer) }
                    .accessibilityIdentifier("recherches-vide-creer")
            }
            .padding(JoleneSpacing.xl)
            .frame(maxWidth: .infinity)
            .background(JoleneColor.cloud)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        case let .prete(recherches):
            ForEach(recherches) { carte($0) }
        }
    }

    private func carte(_ recherche: FiltreSauvegarde) -> some View {
        let occupe = model.occupe(recherche.id)
        return VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    Text(recherche.nom)
                        .font(JoleneFont.headline)
                        .foregroundStyle(JoleneColor.midnight)
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                    Text(meta(recherche))
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("recherche-etat-\(recherche.id)")
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    // Cloche : `p_alerte_active` seul (revue B8 de #1167, m2), fréquence serveur conservée.
                    icone(recherche.alerteActive ? "bell.fill" : "bell.slash",
                          libelle: recherche.alerteActive ? FiltresTextes.desactiverAlertes : FiltresTextes.activerAlertes,
                          identifiant: "recherche-alerte-\(recherche.id)", desactive: occupe) {
                        Task { await model.basculerAlerte(recherche) }
                    }
                    .accessibilityValue(recherche.alerteActive ? "Activées" : "Désactivées")
                    // « Modifier » envoie la fréquence choisie : proposé seulement si celle du serveur est lisible.
                    if recherche.frequence != nil {
                        icone("pencil", libelle: FiltresTextes.modifier, identifiant: "recherche-renommer-\(recherche.id)",
                              desactive: occupe) {
                            model.effacerMessages()
                            aModifier = recherche
                        }
                    }
                    icone("trash", libelle: FiltresTextes.supprimer, identifiant: "recherche-supprimer-\(recherche.id)",
                          desactive: occupe, teinte: JoleneColor.rose700) {
                        model.effacerMessages()
                        aSupprimer = recherche
                    }
                }
            }
            JoleneButton(FiltresTextes.allerRecherche, style: .secondary) { allerALaRecherche(recherche) }
                .accessibilityIdentifier("recherche-appliquer-\(recherche.id)")
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recherche-\(recherche.id)")
    }

    /// Ligne d'état du web (l.164-178) : alerte • dernier passage • résultats.
    private func meta(_ recherche: FiltreSauvegarde) -> String {
        [FiltresPresentation.etatAlerte(recherche), FiltresPresentation.dernierCheck(recherche),
         FiltresPresentation.resultats(recherche)].compactMap { $0 }.joined(separator: " • ")
    }

    private func icone(_ systemImage: String, libelle: String, identifiant: String, desactive: Bool,
                       teinte: Color = JoleneColor.rose800, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(JoleneFont.headline)
                .foregroundStyle(teinte)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(desactive)
        .accessibilityLabel(libelle)
        .accessibilityIdentifier(identifiant)
    }

    /// Web : `sessionStorage` puis `/soignant/recherche-missions` ; natif : boîte de l'app puis onglet Explorer.
    private func allerALaRecherche(_ recherche: FiltreSauvegarde) {
        contexte.container.rechercheExplorer.deposer(recherche, userId: contexte.snapshot.user.id)
        contexte.ouvrir(.explorer)
    }

    // MARK: - Aide

    private var aide: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(FiltresTextes.aideTitre)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
            Text(FiltresTextes.aideIntro)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.midnight)
            ForEach(Array(FiltresTextes.aideFrequences.enumerated()), id: \.offset) { _, ligne in
                (Text("• ") + Text(ligne.titre).bold() + Text(" — \(ligne.texte)"))
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(FiltresTextes.aideEnvoi)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.midnight)
                .fixedSize(horizontal: false, vertical: true)
            Text(FiltresTextes.aideDesactivation)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.midnight)
                .fixedSize(horizontal: false, vertical: true)
            Button(FiltresTextes.aideLienPreferences) { contexte.ouvrir(.preferences) }
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.rose800)
                .frame(minHeight: 44)
                .accessibilityIdentifier("recherches-preferences")
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.mauve100)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recherches-aide")
    }

    // MARK: - Suppression

    private var suppressionPresentee: Binding<Bool> {
        Binding(get: { aSupprimer != nil }, set: { if !$0 { aSupprimer = nil } })
    }

    private var suppressionEnCours: Bool { aSupprimer.map { model.occupe($0.id) } ?? false }

    private var configurationSuppression: ConfirmationSheet.Configuration {
        ConfirmationSheet.Configuration(
            title: FiltresTextes.confirmationSuppression(nom: aSupprimer?.nom ?? ""),
            message: aSupprimer.map(FiltresPresentation.etatAlerte) ?? "",
            confirmTitle: FiltresTextes.supprimer,
            variant: .danger,
            identifier: "recherche-suppression")
    }

    private func confirmerSuppression() {
        guard let cible = aSupprimer else { return }
        Task {
            // La feuille ne se referme qu'après une relecture qui confirme la suppression.
            if await model.supprimer(cible) { aSupprimer = nil }
        }
    }
}

/// « Modifier la recherche » (`ModalEditPage`, `PageRecherchesSauvegardees.tsx` l.236-325) : nom (100 caractères au
/// plus, espaces de bord retirés), alertes email, fréquence si l'alerte est active. Se referme sur une relecture qui
/// confirme ; sinon le message reste affiché et la feuille ouverte.
struct RechercheModificationSheet: View {
    let recherche: FiltreSauvegarde
    @ObservedObject var model: FiltresModel
    let fermer: () -> Void
    @State private var nom: String
    @State private var alerte: Bool
    @State private var frequence: FrequenceAlerte

    init(recherche: FiltreSauvegarde, model: FiltresModel, fermer: @escaping () -> Void) {
        self.recherche = recherche
        self.model = model
        self.fermer = fermer
        _nom = State(initialValue: recherche.nom)
        _alerte = State(initialValue: recherche.alerteActive)
        _frequence = State(initialValue: recherche.frequence ?? .quotidienne)
    }

    private var enCours: Bool { model.occupe(recherche.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                Text(FiltresTextes.modifierTitre)
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityAddTraits(.isHeader)
                Text(FiltresTextes.modifierDescription)
                    .font(JoleneFont.body)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                JoleneTextField(FiltresTextes.nom, text: $nom, kind: .nom, identifier: "recherche-nom-\(recherche.id)")
                    .onChange(of: nom) { saisie in
                        // `maxLength={100}` du champ web.
                        if saisie.count > FiltresSauvegardesEncodage.longueurNomMax {
                            nom = String(saisie.prefix(FiltresSauvegardesEncodage.longueurNomMax))
                        }
                    }
                ToggleRow(FiltresTextes.alertesEmail, isOn: $alerte, isDisabled: enCours,
                          identifier: "recherche-alerte-edit-\(recherche.id)")
                if alerte {
                    VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                        Text(FiltresTextes.frequence).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
                        Picker(FiltresTextes.frequence, selection: $frequence) {
                            ForEach(FrequenceAlerte.allCases, id: \.self) { valeur in
                                Text(FiltresPresentation.libelle(valeur)).tag(valeur)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(JoleneColor.rose800)
                        .disabled(enCours)
                        .accessibilityIdentifier("recherche-frequence-\(recherche.id)")
                    }
                }
                if let erreur = model.erreur {
                    InlineNotice(erreur, tone: .error, identifier: "recherche-modification-erreur", announcementID: model.jeton)
                }
                VStack(spacing: JoleneSpacing.sm) {
                    JoleneButton(FiltresTextes.enregistrer, isLoading: enCours) {
                        Task {
                            if await model.enregistrer(recherche, nom: nom, alerte: alerte, frequence: frequence) { fermer() }
                        }
                    }
                    .disabled(enCours)
                    .accessibilityIdentifier("recherche-enregistrer")
                    JoleneButton(FiltresTextes.annuler, style: .secondary, action: fermer)
                        .disabled(enCours)
                        .accessibilityIdentifier("recherche-annuler")
                }
                .padding(.top, JoleneSpacing.sm)
            }
            .padding(JoleneSpacing.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(JoleneColor.cloud.ignoresSafeArea())
        .interactiveDismissDisabled(enCours)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recherche-modification")
    }
}
