import SwiftUI
import JoleneCore
import JoleneDesign

/// Bloc « actions » du détail de mission (lot 1, T6b) : POSTULER, ACCEPTER, proposition, soft-gate du profil, planning
/// non exact, mission déjà attribuée. État dérivé par `CandidatureEcran` (JoleneCore) de la mission relue, de la
/// candidature relue côté serveur et du profil relu ; aucune issue n'est annoncée avant la relecture
/// (`CandidatureModel`). Les refus serveur (Code du travail compris) sont affichés verbatim dans `candidature-error`.
/// Textes : `LibellesCandidature`. Les annulations (« Annuler ma participation ») appartiennent à T7.
struct CandidatureSection: View {
    let mission: Mission
    let session: SessionStore
    let snapshot: SessionSnapshot
    /// Relecture de la mission par l'écran (`MissionDetailModel.load`) après chaque issue serveur.
    let relireMission: () async -> Void

    @StateObject private var model: CandidatureModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb
    /// Revue B8 m3 : renvois web fermés ; à la fermeture du renvoi ouvert ici, candidature et mission sont relues.
    @Environment(\.fermeturesRenvoiWeb) private var fermeturesRenvoiWeb
    @Environment(\.fabriqueEcransCandidature) private var fabrique
    @State private var retourWebAttendu: Int?
    @State private var recapOuvert = false
    @State private var actionRecap: ActionPlanning = .accepter
    @State private var choixSelectionne: String?

    private typealias L = LibellesCandidature

    /// Tableau de bord web, seul lieu où une proposition salariée s'accepte au lot 1 (`CarteProposition`) :
    /// `CandidatureVerrou.cheminProposition` (verrou de T6a).
    static let tableauDeBordWeb = URL(string: "https://jolene.app" + CandidatureVerrou.cheminProposition)!

    init(mission: Mission, session: SessionStore, snapshot: SessionSnapshot, relireMission: @escaping () async -> Void) {
        self.mission = mission
        self.session = session
        self.snapshot = snapshot
        self.relireMission = relireMission
        _model = StateObject(wrappedValue: CandidatureModel(missionId: mission.id, controller: session.controller, snapshot: snapshot))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            if let etat = model.etat(mission) {
                contenu(etat)
            } else {
                ProgressView().tint(JoleneColor.rose700).accessibilityIdentifier("candidature-loading")
            }
            issue
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("candidature-bloc")
        .task { await model.charger() }
        .onChange(of: fermeturesRenvoiWeb) { fermetures in
            guard let attendu = retourWebAttendu, fermetures > attendu else { return }
            retourWebAttendu = nil
            Task {
                await model.charger()
                await relireMission()
            }
        }
        .confirmationSheet(isPresented: $recapOuvert, recapConfiguration, isLoading: model.enCours,
                           isConfirmEnabled: planning.exact, onConfirm: confirmerRecap) {
            // Revue B8 m5 : lignes du planning candidat du web (année, « (lendemain) », durée).
            SlotList(planning: planning, identifier: "candidature-recap-planning", libelle: MissionPresentation.creneauCandidat)
            if planning.exact {
                // HARD STOP n°4 (revue B8 P2) : phrase d'engagement reprise à l'identique (`TextesWeb.Candidature`).
                Text(L.recapEngagement(actionRecap))
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("candidature-recap-engagement")
            }
        }
        .sheet(isPresented: choixOuvert) { choixContrat }
    }

    // MARK: - États

    @ViewBuilder
    private func contenu(_ etat: CandidatureEcran) -> some View {
        switch etat {
        case .masque:
            EmptyView()
        case .assignee:
            ligneSucces(L.assignee, identifier: "candidature-assignee")
        case .dejaAttribuee:
            Text(L.dejaAttribuee).font(JoleneFont.body).foregroundStyle(JoleneColor.bubblegum)
                .accessibilityIdentifier("candidature-deja-attribuee")
            JoleneButton(L.voirAutresMissions, style: .secondary) { dismiss() }
                .accessibilityIdentifier("candidature-voir-autres")
        case let .proposition(id):
            JoleneButton(L.propositionAccepter, isLoading: model.enCours) { ouvrirRecap(.proposition) }
                .disabled(model.enCours)
                .accessibilityIdentifier("proposition-accepter-\(id)")
            boutonRefus(id)
        case let .propositionWeb(id):
            InlineNotice(L.propositionWeb, tone: .info, identifier: "proposition-web-\(id)-texte")
            if let presentateurRenvoiWeb {
                JoleneButton(L.propositionWebAction) {
                    retourWebAttendu = fermeturesRenvoiWeb
                    presentateurRenvoiWeb.presenter(.safari(Self.tableauDeBordWeb))
                }
                    .accessibilityIdentifier("proposition-web-\(id)")
            }
            boutonRefus(id)
        case .envoyee:
            ligneSucces(L.envoyee, identifier: "candidature-sent")
            if model.profil?.tousDocumentsValides == true {
                Text(L.envoyeeProfil).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
            } else {
                Text(L.envoyeeDocuments).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
                // Revue B8 m4 : « 📄 Valider mes documents (2 min) » vers « Mes documents » natif (lot 2).
                if let fabrique {
                    NavigationLink { fabrique.documents(session: session, snapshot: snapshot) } label: { libelleBouton(L.validerDocuments) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("candidature-documents")
                }
            }
        case let .profilIncomplet(manquants):
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                if !manquants.isEmpty {
                    Text(L.manquants(manquants.count)).font(JoleneFont.headline).foregroundStyle(JoleneColor.midnight)
                    ForEach(manquants, id: \.self) { libelle in
                        Text("• " + libelle).font(JoleneFont.body).foregroundStyle(JoleneColor.midnight)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("candidature-profil-incomplet")
            NavigationLink {
                // Revue B8 m2 : mêmes injections que l'onglet Profil (localisation, photo démo).
                if let fabrique {
                    fabrique.editionProfil(session: session, snapshot: snapshot)
                } else {
                    ProfilEditionScreen(session: session, snapshot: snapshot)
                }
            } label: {
                libelleBouton(L.completerProfil)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("candidature-profil-completer")
        case let .planningBloque(action, message):
            InlineNotice(message, title: SlotList.titrePlanningNonExact, tone: .warning, identifier: "candidature-planning-blocked")
            JoleneButton(action == .postuler ? L.postuler : L.accepter) {}
                .disabled(true)
                .accessibilityIdentifier("candidature-submit")
            if action == .accepter { mentionAccepter }
        case .ouverte(.postuler):
            champMessage
            JoleneButton(model.enCours ? L.postulerEnCours : L.postuler, isLoading: model.enCours) { ouvrirRecap(.postuler) }
                .accessibilityIdentifier("candidature-submit")
            Text(L.postulerAide).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
        case let .ouverte(action):
            JoleneButton(model.enCours ? L.accepterEnCours : L.accepter, isLoading: model.enCours) { ouvrirRecap(action) }
                .accessibilityIdentifier("candidature-submit")
            mentionAccepter
        }
    }

    @ViewBuilder
    private var issue: some View {
        switch model.issue {
        case let .erreur(message)?:
            InlineNotice(message, tone: .error, identifier: "candidature-error", announcesOnAppear: true)
        case let .planningAReconfirmer(message)?:
            InlineNotice(message, tone: .warning, identifier: "candidature-planning-reconfirmer", announcesOnAppear: true)
        case .propositionRefusee?:
            InlineNotice(L.propositionRefuseeTexte, title: L.propositionRefuseeTitre, tone: .info, identifier: "proposition-refusee",
                         announcesOnAppear: true)
        case nil:
            EmptyView()
        }
    }

    private var champMessage: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(L.messageLibelle).font(JoleneFont.caption).foregroundStyle(JoleneColor.midnight)
            TextField(L.messagePlaceholder, text: $model.message, axis: .vertical)
                .font(.system(size: 16))
                .lineLimit(3...6)
                .padding(JoleneSpacing.md)
                .background(JoleneColor.lavender)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                .accessibilityLabel(L.messageLibelle)
                .accessibilityIdentifier("candidature-message")
            Text(L.compteur(model.message)).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("candidature-message-compteur")
        }
    }

    /// HARD STOP n°4 (revue B8 P2) : mention sous « ★ Accepter cette mission », reprise à l'identique du web (l.1373).
    private var mentionAccepter: some View {
        Text(TextesWeb.Candidature.mentionAccepter)
            .font(JoleneFont.caption)
            .foregroundStyle(JoleneColor.bubblegum)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("candidature-mention-accepter")
    }

    private func libelleBouton(_ titre: String) -> some View {
        Text(titre).font(JoleneFont.button).foregroundStyle(JoleneColor.onGradient)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 48).background(JoleneColor.heroGradient).clipShape(Capsule())
    }

    private func ligneSucces(_ texte: String, identifier: String) -> some View {
        Text(texte)
            .font(JoleneFont.headline)
            .foregroundStyle(JoleneColor.midnight)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(JoleneSpacing.md)
            .background(JoleneColor.lavender)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
            .accessibilityIdentifier(identifier)
    }

    private func boutonRefus(_ id: String) -> some View {
        JoleneButton(L.propositionRefuser, style: .secondary) {
            Task {
                if await model.refuserProposition(mission) { await relireMission() }
            }
        }
        .disabled(model.enCours)
        .accessibilityIdentifier("proposition-refuser-\(id)")
    }

    // MARK: - Récapitulatif et choix de contrat

    private var planning: PlanningCandidat {
        PlanningCandidatRules.construirePlanningCandidat(PlanningCandidatInput(mission: mission))
    }

    private var recapConfiguration: ConfirmationSheet.Configuration {
        .init(title: L.recapTitre, message: L.recapDescription(intitule: mission.record.intitule),
              confirmTitle: actionRecap == .postuler ? L.recapEnvoyer : L.recapAccepter, cancelTitle: L.recapAnnuler,
              identifier: "candidature-recap")
    }

    private func ouvrirRecap(_ action: ActionPlanning) {
        model.effacerIssue()
        actionRecap = action
        recapOuvert = true
    }

    private func confirmerRecap() {
        let action = actionRecap
        Task {
            let relire = action == .proposition ? await model.accepterProposition(mission) : await model.confirmer(mission)
            recapOuvert = false
            if relire { await relireMission() }
        }
    }

    private var choixOuvert: Binding<Bool> {
        Binding(get: { !model.optionsContrat.isEmpty && !recapOuvert },
                set: { if !$0 { model.optionsContrat = []; choixSelectionne = nil } })
    }

    private var choixContrat: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                Text(L.choixTitre).font(JoleneFont.title).foregroundStyle(JoleneColor.midnight).accessibilityAddTraits(.isHeader)
                Text(L.choixDescription).font(JoleneFont.body).foregroundStyle(JoleneColor.bubblegum)
                ForEach(model.optionsContrat, id: \.value) { option in
                    FilterChip(option.label, isSelected: choixSelectionne == option.value,
                               identifier: "choix-contrat-\(option.value)") { choixSelectionne = option.value }
                }
                JoleneButton(L.choixConfirmer, isLoading: model.enCours) {
                    guard let choix = choixSelectionne else { return }
                    Task {
                        let relire = await model.confirmer(mission, choixContrat: choix)
                        choixSelectionne = nil
                        if relire { await relireMission() }
                    }
                }
                .disabled(choixSelectionne == nil || model.enCours)
                .accessibilityIdentifier("choix-contrat-confirmer")
                JoleneButton(L.recapAnnuler, style: .secondary) { model.optionsContrat = []; choixSelectionne = nil }
                    .disabled(model.enCours)
                    .accessibilityIdentifier("choix-contrat-annuler")
            }
            .padding(JoleneSpacing.xl)
        }
        .background(JoleneColor.cloud.ignoresSafeArea())
        .interactiveDismissDisabled(model.enCours)
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("choix-contrat")
    }
}
