import SwiftUI
import JoleneCore
import JoleneDesign

/// Détail de série (`/soignant/missions/serie/:serieId`, L4-T12, report de la décision 11 du lot 1), port de
/// `DetailSerieSoignant.tsx`, empilé sur le Profil par `SecondaryRouter` une fois son coupe-circuit
/// `ios_natif_serie_actif` lu (fail-open). Vue de `SerieModel` (JoleneCore), qui porte la lecture, la sélection
/// (`SelectionSerieCandidat`) et la boucle d'acceptation ; la vue n'ajoute aucune règle.
///
/// - En-tête du pack, liste des missions (case à cocher pour une mission ouverte au planning exact, planning de la
///   mission, rémunération serveur), action « ★ Accepter la sélection (n) » puis récapitulatif des créneaux à confirmer.
/// - Après la boucle : bilan, une issue par mission ; un refus du serveur est affiché **tel que servi**, seul, sans
///   titre ni reformulation (HARD STOP n°4, décision 2 du lot 1). Le refus de conformité sur lequel la boucle s'arrête
///   est repris à part (`serie-code-travail`), suivi d'une phrase qui dit seulement que la suite n'a pas été envoyée.
/// - Non portés (décision 2 du lot 1, PRINCIPES §3) : le bloc « Vérification de compatibilité » du web et ses articles,
///   la modale d'explication d'un article, les totaux par régime, le lien « Voir dans mon planning ».
///
/// Identifiants : `serie-screen` ; `serie-entete`, `serie-disponibles` ; `serie-mission-<id>`, `serie-selection-<id>`,
/// `serie-planning-<id>`, `serie-statut-<id>`, `serie-conflit-<id>`, `serie-resultat-<id>`, `serie-detail-<id>`,
/// `serie-envoi-<id>` ; `serie-accepter` ; `serie-bilan`, `serie-code-travail`, `serie-arret`, `serie-contrats`,
/// `serie-action-erreur`, `serie-session-check` ; `serie-chargement`, `serie-erreur` (+ `-reessayer`), `serie-introuvable`
/// (+ `-explorer`) ; feuille `serie-confirmation` (`-title`, `-message`, `-confirm`, `-cancel`, `serie-confirmation-mission-<id>`).
struct SerieDetailScreen: View {
    let serieId: String
    let contexte: ContexteSecondaire
    @StateObject private var model: SerieModel
    @ObservedObject private var session: SessionStore
    @State private var confirmationOuverte = false

    private typealias T = SerieTextes

    init(serieId: String, contexte: ContexteSecondaire) {
        self.serieId = serieId
        self.contexte = contexte
        self.session = contexte.session
        _model = StateObject(wrappedValue: SerieModel(serieId: serieId, controller: contexte.session.controller,
                                                      snapshot: contexte.snapshot))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                if model.sessionExpiree {
                    JoleneButton("Vérifier ma session", style: .secondary) { Task { await model.verifierSession(session) } }
                        .accessibilityIdentifier("serie-session-check")
                }
                contenu
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.recharger() }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(T.titre)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("serie-screen")
        // À chaque apparition : première lecture, puis relecture qui garde la sélection et les issues affichées.
        .task { await model.charger() }
        .confirmationSheet(isPresented: $confirmationOuverte, configurationConfirmation, isLoading: model.enCours,
                           isConfirmEnabled: model.peutAccepter, onConfirm: confirmer) {
            // Créneaux exacts de chaque mission sélectionnée (web l.548-553).
            ForEach(model.analyse.missionsSelectionnees) { mission in
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    Text(mission.record.intitule)
                        .font(JoleneFont.headline)
                        .foregroundStyle(JoleneColor.midnight)
                    SlotList(planning: planning(mission), identifier: "serie-confirmation-planning-\(mission.id)",
                             libelle: MissionPresentation.creneauCandidat, mentionJoursNonTravailles: false)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("serie-confirmation-mission-\(mission.id)")
            }
        }
    }

    // MARK: - Contenu

    @ViewBuilder private var contenu: some View {
        switch model.etat {
        case .chargement:
            SkeletonCard(identifier: "serie-chargement")
        case let .echec(message):
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                InlineNotice(message, title: T.indisponibleTitre, tone: .error, identifier: "serie-erreur")
                if !model.sessionExpiree {
                    JoleneButton(T.reessayer, style: .secondary) { Task { await model.recharger() } }
                        .accessibilityIdentifier("serie-erreur-reessayer")
                }
            }
        case .introuvable:
            VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                Text(T.introuvableTitre)
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityAddTraits(.isHeader)
                Text(T.introuvableTexte)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                JoleneButton(T.explorer) { contexte.ouvrir(.explorer) }
                    .accessibilityIdentifier("serie-introuvable-explorer")
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JoleneColor.cloud)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("serie-introuvable")
        case let .prete(missions):
            entete(missions)
            avis
            liste(missions)
            action
        }
    }

    /// En-tête du pack (web l.357-374) : intitulé et établissement de la première mission, période, missions ouvertes.
    private func entete(_ missions: [Mission]) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(T.pastille)
                .font(JoleneFont.caption.weight(.semibold))
                .foregroundStyle(JoleneColor.rose800)
            if let premiere = missions.first, let derniere = missions.last {
                Text(premiere.record.intitule)
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let etablissement = premiere.etablissement {
                    Text(T.etablissement(nom: etablissement.nom, ville: etablissement.adresseVille))
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.bubblegum)
                }
                Text(T.periode(debut: premiere.record.debutLe, fin: derniere.record.debutLe))
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
            }
            Text(T.disponibles(model.ouvertes.count, sur: missions.count))
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityIdentifier("serie-disponibles")
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("serie-entete")
    }

    /// Message d'action, bilan de la boucle et, à part, le refus de conformité tel que servi par le serveur.
    @ViewBuilder private var avis: some View {
        if let erreur = model.erreur {
            InlineNotice(erreur, tone: .error, identifier: "serie-action-erreur", announcementID: model.jeton)
        }
        if let bilan = model.bilan {
            InlineNotice(bilan.texte, tone: ton(bilan.ton), identifier: "serie-bilan", announcesOnAppear: true,
                         announcementID: model.jeton)
            if bilan.acceptees > 0 {
                JoleneButton(T.voirContrats, style: .secondary) { contexte.ouvrir(.documents(onglet: .contrats)) }
                    .accessibilityIdentifier("serie-contrats")
            }
        }
        if let refus = model.refusConformite {
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                // HARD STOP n°4 : texte du serveur, seul et mot pour mot.
                InlineNotice(refus.message, tone: .error, identifier: "serie-code-travail", announcesOnAppear: true,
                             announcementID: model.jeton)
                Text(T.arret)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("serie-arret")
            }
        }
    }

    private func liste(_ missions: [Mission]) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(T.creneaux)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
            ForEach(missions) { ligne($0) }
        }
    }

    /// Ligne d'une mission (web l.434-495) : case à cocher, planning, statut ou rémunération, envoi en cours, issue.
    private func ligne(_ mission: Mission) -> some View {
        let ouverte = mission.record.statut == SerieRegles.statutOuverte
        return VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                if model.selectionnable(mission) {
                    caseACocher(mission, cochee: model.estSelectionnee(mission.id))
                }
                details(mission, ouverte: ouverte)
                Spacer(minLength: 0)
                marge(mission, ouverte: ouverte)
            }
            if model.missionEnCours == mission.id {
                ProgressView()
                    .tint(JoleneColor.rose700)
                    .accessibilityIdentifier("serie-envoi-\(mission.id)")
            }
            if let issue = model.resultats[mission.id] {
                resultat(issue.ligne(intitule: mission.record.intitule), mission: mission)
            }
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("serie-mission-\(mission.id)")
    }

    /// Case à cocher d'une mission ouverte au planning exact (web l.447-455), cible tactile de 44 pt.
    private func caseACocher(_ mission: Mission, cochee: Bool) -> some View {
        Button {
            model.basculer(mission.id)
        } label: {
            Image(systemName: cochee ? "checkmark.square.fill" : "square")
                .font(JoleneFont.title)
                .foregroundStyle(cochee ? JoleneColor.rose800 : JoleneColor.bubblegum)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.enCours)
        .accessibilityLabel(T.selectionner(debut: mission.record.debutLe))
        .accessibilityAddTraits(cochee ? .isSelected : [])
        .accessibilityIdentifier("serie-selection-\(mission.id)")
    }

    /// Planning de la mission (trois créneaux au plus, web l.461-466), statut d'une mission fermée, conflit.
    @ViewBuilder
    private func details(_ mission: Mission, ouverte: Bool) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            if SerieModel.planningExact(mission) {
                SlotList(planning: planning(mission), identifier: "serie-planning-\(mission.id)",
                         libelle: MissionPresentation.creneauCandidat, limit: 3, mentionJoursNonTravailles: false)
            } else if ouverte {
                Text(T.planningIndisponible)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.rose700)
                    .accessibilityIdentifier("serie-planning-\(mission.id)")
            }
            if !ouverte {
                Text(T.statutFerme(mission))
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("serie-statut-\(mission.id)")
            }
            if ouverte, model.idsConflit.contains(mission.id) {
                Text(T.conflit)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.rose700)
                    .accessibilityIdentifier("serie-conflit-\(mission.id)")
            }
        }
    }

    /// Mission ouverte : rémunération serveur de la mission, jamais un total calculé (PRINCIPES §3) ; sinon son statut.
    @ViewBuilder
    private func marge(_ mission: Mission, ouverte: Bool) -> some View {
        if ouverte {
            Text(MissionPresentation.remuneration(mission))
                .font(JoleneFont.caption.weight(.semibold))
                .foregroundStyle(JoleneColor.midnight)
                .multilineTextAlignment(.trailing)
        } else {
            StatusBadge(MesMissionsPresentation.statut(mission.record.statut), tone: .neutral)
        }
    }

    @ViewBuilder
    private func resultat(_ ligne: LigneResultatSerie, mission: Mission) -> some View {
        InlineNotice(ligne.texte, title: ligne.titre, tone: ton(ligne.ton), identifier: "serie-resultat-\(mission.id)")
        if ligne.lienDetail {
            JoleneButton(T.ouvrirDetail, style: .secondary) { contexte.ouvrir(.mission(id: mission.id)) }
                .accessibilityIdentifier("serie-detail-\(mission.id)")
        }
    }

    /// Action de la série (web l.518-530) : proposée tant qu'une mission est ouverte.
    @ViewBuilder private var action: some View {
        if !model.ouvertes.isEmpty {
            JoleneButton(model.libelleAction, isLoading: model.enCours) {
                confirmationOuverte = true
            }
            .disabled(!model.peutAccepter)
            .accessibilityIdentifier("serie-accepter")
        }
    }

    // MARK: - Confirmation

    private var configurationConfirmation: ConfirmationSheet.Configuration {
        ConfirmationSheet.Configuration(title: T.confirmationTitre, message: T.confirmationDescription,
                                        confirmTitle: T.accepterTous, cancelTitle: T.annuler,
                                        identifier: "serie-confirmation")
    }

    /// La feuille se referme et la boucle part (web l.283-284) : les issues s'affichent sur l'écran, mission par mission.
    private func confirmer() {
        confirmationOuverte = false
        Task { await model.accepter() }
    }

    // MARK: - Outils

    private func planning(_ mission: Mission) -> PlanningCandidat {
        PlanningCandidatRules.construirePlanningCandidat(PlanningCandidatInput(mission: mission))
    }

    private func ton(_ ton: BilanSerie.Ton) -> InlineNotice.Tone {
        switch ton {
        case .succes: return .success
        case .partiel: return .warning
        case .echec: return .error
        }
    }

    private func ton(_ ton: LigneResultatSerie.Ton) -> InlineNotice.Tone {
        switch ton {
        case .succes: return .success
        case .attention: return .warning
        case .erreur: return .error
        case .information: return .info
        }
    }
}
