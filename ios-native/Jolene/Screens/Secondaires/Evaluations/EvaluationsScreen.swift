import SwiftUI
import Charts
import JoleneCore
import JoleneDesign

/// « Mes évaluations » (`/soignant/evaluations`, L4-T9), port de `EvaluationsContent`
/// (`src/pages/EvaluationsSoignant.tsx`), empilé sur le Profil par `SecondaryRouter` une fois son coupe-circuit
/// `ios_natif_evaluations_actif` lu (fail-open). Vue de `EvaluationsModel` (JoleneCore), qui porte les règles
/// (relecture qui confirme, refus verbatim, délai, epoch, filtres et page dérivés de la page lue) ; la vue n'ajoute
/// aucune logique.
///
/// Filtre de visibilité centralisé (`CLAUDE.md`, « Publication différée ») : l'écran n'affiche que la page servie par
/// la RPC filtrée — une notation non publiée n'y figure pas, et la note moyenne, le total, la part de cinq étoiles et
/// l'évolution sont les valeurs du serveur, écrites telles quelles. Rien n'est additionné ni moyenné ici
/// (`EvaluationsSourceGuardTests`).
///
/// - Statistiques, graphique des six derniers mois (Swift Charts), filtres (période, note minimale, établissement),
///   nombre d'évaluations, cartes, pages de 20.
/// - Signalement : feuille (motif de dix caractères au moins) ; la carte ne montre « Déjà signalée » que sur la page
///   relue. Sans `signale` lisible, le signalement n'est pas proposé.
/// - Non porté : « Éditer » (chemin mort du web, D11).
///
/// Identifiants : `evaluations-screen` ; `evaluations-stats` (`evaluations-stat-moyenne`, `-total`, `-pct5`,
/// `-evolution`), `evaluations-evolution` ; `evaluations-periode-<TOUT|3M|6M|12M>`, `evaluations-note-<toutes|5|4|3>`,
/// `evaluations-etablissement` ; `evaluations-total` ; `evaluation-<id>`, `evaluation-note-<id>`,
/// `evaluation-signaler-<id>`, `evaluation-signalee-<id>` ; `evaluations-vide`, `evaluations-page`,
/// `evaluations-precedent`, `evaluations-suivant` ; `evaluations-chargement`, `evaluations-erreur` (+ `-reessayer`),
/// `evaluations-action-erreur`, `evaluations-confirmation`, `evaluations-session-check` ; feuille
/// `evaluation-signalement` (`-rappel`, `-explication`, `-motif`, `-compteur`, `-erreur`, `-envoyer`, `-annuler`).
struct EvaluationsScreen: View {
    let contexte: ContexteSecondaire
    @StateObject private var model: EvaluationsModel
    @ObservedObject private var session: SessionStore
    @State private var aSignaler: NotationRecue?

    init(contexte: ContexteSecondaire) {
        self.contexte = contexte
        self.session = contexte.session
        _model = StateObject(wrappedValue: EvaluationsModel(controller: contexte.session.controller, snapshot: contexte.snapshot))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    Text(EvaluationsTextes.enTete)
                        .font(JoleneFont.title)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                    Text(EvaluationsTextes.sousTitre)
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if aSignaler == nil { avis }
                if model.sessionExpiree {
                    JoleneButton("Vérifier ma session", style: .secondary) { Task { await model.verifierSession(session) } }
                        .accessibilityIdentifier("evaluations-session-check")
                }
                contenu
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.charger() }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(EvaluationsTextes.titre)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("evaluations-screen")
        // À chaque apparition, comme le web au montage.
        .task { await model.charger() }
        .sheet(item: $aSignaler) { notation in
            SignalementEvaluationSheet(notation: notation, model: model) { aSignaler = nil }
        }
    }

    // MARK: - Contenu

    @ViewBuilder private var avis: some View {
        if let erreur = model.erreur {
            InlineNotice(erreur, tone: .error, identifier: "evaluations-action-erreur", announcementID: model.jeton)
        } else if let confirmation = model.confirmation {
            InlineNotice(confirmation, tone: .success, identifier: "evaluations-confirmation", announcementID: model.jeton)
        }
    }

    @ViewBuilder private var contenu: some View {
        switch model.etat {
        case .chargement:
            SkeletonCard(identifier: "evaluations-chargement")
        case let .echec(message):
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                InlineNotice(message, tone: .error, identifier: "evaluations-erreur")
                if !model.sessionExpiree {
                    JoleneButton(EvaluationsTextes.reessayer, style: .secondary) { Task { await model.charger() } }
                        .accessibilityIdentifier("evaluations-erreur-reessayer")
                }
            }
        case let .prete(page):
            if let stats = page.stats { statistiques(stats, evolution: page.evolution) }
            graphique(page.evolution)
            filtres(page)
            Text(EvaluationsTextes.compte(page.total))
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityIdentifier("evaluations-total")
            if page.notations.isEmpty {
                EmptyState(systemImage: "star", title: EvaluationsTextes.videTitre, message: EvaluationsTextes.videDescription,
                           identifier: "evaluations-vide")
            } else {
                ForEach(page.notations) { carte($0) }
            }
            pagination
        }
    }

    // MARK: - Statistiques (valeurs serveur)

    private func statistiques(_ stats: StatsEvaluations, evolution: [PointEvolutionNotes]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: JoleneSpacing.md), GridItem(.flexible(), spacing: JoleneSpacing.md)],
                  spacing: JoleneSpacing.md) {
            if (stats.totalEvaluations ?? 0) > 0 {
                tuile(EvaluationsTextes.noteMoyenne, valeur: EvaluationsPresentation.note(stats.noteMoyenneGlobale),
                      identifiant: "evaluations-stat-moyenne", symbole: "star.fill")
            } else {
                tuile(EvaluationsTextes.noteMoyenne, valeur: EvaluationsTextes.pasEncoreDEvaluation,
                      identifiant: "evaluations-stat-moyenne", discret: true)
            }
            tuile(EvaluationsTextes.totalEvaluations,
                  valeur: stats.totalEvaluations.map { "\($0)" } ?? EvaluationsTextes.noteIndisponible,
                  identifiant: "evaluations-stat-total")
            tuile(EvaluationsTextes.pct5Etoiles, valeur: EvaluationsPresentation.pourcentage(stats.pct5Etoiles),
                  identifiant: "evaluations-stat-pct5")
            tuile(EvaluationsTextes.evolution6m, valeur: EvaluationsPresentation.noteDernierMois(evolution),
                  identifiant: "evaluations-stat-evolution", legende: EvaluationsTextes.dernierMois)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("evaluations-stats")
    }

    private func tuile(_ titre: String, valeur: String, identifiant: String, symbole: String? = nil, discret: Bool = false,
                       legende: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(titre)
                .font(JoleneFont.caption.weight(.semibold))
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.xs) {
                Text(valeur)
                    .font(discret ? JoleneFont.callout : JoleneFont.title)
                    .foregroundStyle(discret ? JoleneColor.bubblegum : JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(identifiant)
                if let symbole {
                    Image(systemName: symbole)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.butter800)
                        .accessibilityHidden(true)
                }
            }
            if let legende {
                Text(legende)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
            }
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
    }

    // MARK: - Évolution

    /// Barre d'un mois : libellé du mois et note moyenne servie (un mois sans note servie n'a pas de barre).
    private struct Barre: Identifiable {
        let id: String
        let mois: String
        let note: Double
    }

    @ViewBuilder private func graphique(_ evolution: [PointEvolutionNotes]) -> some View {
        let barres = evolution.compactMap { point -> Barre? in
            guard let note = point.noteMoyenne else { return nil }
            return Barre(id: point.mois, mois: EvaluationsPresentation.moisCourt(point.mois), note: note)
        }
        if !barres.isEmpty {
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                Text(EvaluationsTextes.graphiqueTitre)
                    .font(JoleneFont.caption.weight(.semibold))
                    .foregroundStyle(JoleneColor.midnight)
                Chart(barres) { barre in
                    BarMark(x: .value("Mois", barre.mois), y: .value(EvaluationsTextes.noteMoyenne, barre.note))
                        .foregroundStyle(JoleneColor.rose700)
                }
                .chartYScale(domain: 0...5)
                .frame(height: 120)
                .accessibilityLabel(EvaluationsTextes.graphiqueTitre)
                .accessibilityIdentifier("evaluations-evolution")
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JoleneColor.cloud)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        }
    }

    // MARK: - Filtres

    private static let colonnesFiltres = [GridItem(.adaptive(minimum: 140), spacing: JoleneSpacing.sm, alignment: .leading)]

    private func filtres(_ page: PageEvaluations) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            LazyVGrid(columns: Self.colonnesFiltres, alignment: .leading, spacing: JoleneSpacing.sm) {
                ForEach(PeriodeEvaluations.allCases, id: \.self) { periode in
                    FilterChip(EvaluationsTextes.libelle(periode), isSelected: model.filtre.periode == periode,
                               identifier: "evaluations-periode-\(periode.rawValue)") {
                        Task { await model.choisir(periode: periode) }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(EvaluationsTextes.filtrePeriode)
            LazyVGrid(columns: Self.colonnesFiltres, alignment: .leading, spacing: JoleneSpacing.sm) {
                FilterChip(EvaluationsTextes.toutesNotes, isSelected: model.filtre.noteMin == nil,
                           identifier: "evaluations-note-toutes") {
                    Task { await model.choisir(noteMin: nil) }
                }
                ForEach(EvaluationsTextes.notesMin, id: \.self) { note in
                    FilterChip(EvaluationsTextes.libelle(noteMin: note), isSelected: model.filtre.noteMin == note,
                               identifier: "evaluations-note-\(note)") {
                        Task { await model.choisir(noteMin: note) }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(EvaluationsTextes.filtreNote)
            if !page.etablissements.isEmpty {
                Picker(EvaluationsTextes.filtreEtablissement, selection: etablissementChoisi) {
                    Text(EvaluationsTextes.tousEtablissements).tag("")
                    ForEach(page.etablissements) { etablissement in
                        Text(etablissement.nom).tag(etablissement.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(JoleneColor.rose800)
                .frame(minHeight: 44)
                .accessibilityIdentifier("evaluations-etablissement")
            }
        }
        .disabled(model.lectureEnCours)
    }

    /// Sélection du filtre établissement : la valeur affichée est celle du modèle (page lue), jamais un état local.
    private var etablissementChoisi: Binding<String> {
        Binding(get: { model.filtre.etablissementId ?? "" },
                set: { identifiant in Task { await model.choisir(etablissementId: identifiant) } })
    }

    // MARK: - Carte d'une évaluation

    private func carte(_ notation: NotationRecue) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            HStack(alignment: .center, spacing: JoleneSpacing.sm) {
                if let note = notation.noteMoyenne {
                    StarRow(note: note, identifier: "evaluation-note-\(notation.id)")
                } else {
                    Text(EvaluationsTextes.noteIndisponible)
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .accessibilityIdentifier("evaluation-note-\(notation.id)")
                }
                Spacer(minLength: JoleneSpacing.sm)
                if let date = EvaluationsPresentation.date(notation.creeLe) {
                    Label(date, systemImage: "calendar")
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                }
            }
            if let intitule = notation.missionIntitule, !intitule.isEmpty {
                Text(intitule)
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.midnight)
                    .lineLimit(2)
            }
            if let etablissement = notation.etablissementNom, !etablissement.isEmpty {
                Label(etablissement, systemImage: "building.2")
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
            }
            if let commentaire = notation.commentaire, !commentaire.isEmpty {
                Text(EvaluationsTextes.commentaire(commentaire))
                    .font(JoleneFont.callout.italic())
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
            }
            signalement(notation)
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("evaluation-\(notation.id)")
    }

    /// « Signaler cette évaluation » / « Déjà signalée » (l.317-321) selon `signale` servi ; rien si le serveur ne le sert pas.
    @ViewBuilder private func signalement(_ notation: NotationRecue) -> some View {
        if notation.signale == true {
            StatusPill(EvaluationsTextes.dejaSignalee, tone: .neutral, systemImage: "flag.fill",
                       identifier: "evaluation-signalee-\(notation.id)")
        } else if notation.signale == false {
            Button {
                model.effacerMessages()
                aSignaler = notation
            } label: {
                Label(EvaluationsTextes.signalerCetteEvaluation, systemImage: "flag")
                    .font(JoleneFont.caption.weight(.semibold))
                    .foregroundStyle(JoleneColor.rose800)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.signalementEnCours != nil)
            .accessibilityIdentifier("evaluation-signaler-\(notation.id)")
        }
    }

    // MARK: - Pages

    @ViewBuilder private var pagination: some View {
        if model.nombreDePages > 1 {
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                Text(EvaluationsTextes.page(model.page, sur: model.nombreDePages))
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("evaluations-page")
                HStack(spacing: JoleneSpacing.sm) {
                    JoleneButton(EvaluationsTextes.precedent, style: .secondary) { Task { await model.pagePrecedente() } }
                        .disabled(!model.aPagePrecedente || model.lectureEnCours)
                        .accessibilityIdentifier("evaluations-precedent")
                    JoleneButton(EvaluationsTextes.suivant, style: .secondary) { Task { await model.pageSuivante() } }
                        .disabled(!model.aPageSuivante || model.lectureEnCours)
                        .accessibilityIdentifier("evaluations-suivant")
                }
            }
        }
    }
}

/// « Signaler cette évaluation » (`ModaleSignaler`, `src/components/NotationsRecues.tsx` l.132-204, modale jumelle
/// déjà vouvoyée de celle de `EvaluationsSoignant.tsx`) : rappel de la mission et de la note servie, explication du
/// web, motif de dix caractères au moins. Se referme sur une relecture qui montre la notation signalée ; sinon le
/// message (refus du serveur tel quel) reste affiché et la feuille ouverte.
struct SignalementEvaluationSheet: View {
    let notation: NotationRecue
    @ObservedObject var model: EvaluationsModel
    let fermer: () -> Void
    @State private var motif = ""
    @FocusState private var motifActif: Bool

    private var enCours: Bool { model.signalementEnCours == notation.id }
    /// `disabled={loading || motif.trim().length < 10}` (l.196).
    private var peutEnvoyer: Bool { !enCours && EvaluationsPresentation.motifValide(motif) != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                    Text(EvaluationsTextes.signalementTitre)
                        .font(JoleneFont.title)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                        if let intitule = notation.missionIntitule, !intitule.isEmpty {
                            Text(intitule)
                                .font(JoleneFont.callout.weight(.semibold))
                                .foregroundStyle(JoleneColor.midnight)
                        }
                        Text(EvaluationsTextes.noteMoyenneSur5(EvaluationsPresentation.note(notation.noteMoyenne)))
                            .font(JoleneFont.caption)
                            .foregroundStyle(JoleneColor.bubblegum)
                    }
                    .padding(JoleneSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(JoleneColor.cloud)
                    .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("evaluation-signalement-rappel")
                    Text(EvaluationsTextes.signalementExplication)
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("evaluation-signalement-explication")
                    VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                        Text(EvaluationsTextes.signalementMotif)
                            .font(JoleneFont.caption.weight(.semibold))
                            .foregroundStyle(JoleneColor.midnight)
                        TextField(EvaluationsTextes.signalementPlaceholder, text: $motif, axis: .vertical)
                            .lineLimit(4...8)
                            .font(.system(size: 16))
                            .focused($motifActif)
                            .boutonOKClavier($motifActif, actif: !enCours)
                            .padding(JoleneSpacing.md)
                            .background(JoleneColor.cloud)
                            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                            .disabled(enCours)
                            .accessibilityLabel(EvaluationsTextes.signalementMotif)
                            .accessibilityIdentifier("evaluation-signalement-motif")
                        Text(EvaluationsTextes.compteurMotif(motif.count))
                            .font(JoleneFont.caption)
                            .foregroundStyle(JoleneColor.bubblegum)
                            .accessibilityIdentifier("evaluation-signalement-compteur")
                    }
                    if let erreur = model.erreur {
                        InlineNotice(erreur, tone: .error, identifier: "evaluation-signalement-erreur", announcementID: model.jeton)
                    }
                    VStack(spacing: JoleneSpacing.sm) {
                        JoleneButton(EvaluationsTextes.signaler, style: .destructive, isLoading: enCours) {
                            motifActif = false
                            Task {
                                // La feuille ne se referme qu'après une relecture qui montre le signalement.
                                if await model.signaler(notation, motif: motif) { fermer() }
                            }
                        }
                        .disabled(!peutEnvoyer)
                        .accessibilityIdentifier("evaluation-signalement-envoyer")
                        JoleneButton(EvaluationsTextes.annuler, style: .secondary, action: fermer)
                            .disabled(enCours)
                            .accessibilityIdentifier("evaluation-signalement-annuler")
                    }
                }
                .padding(JoleneSpacing.lg)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(JoleneColor.lavender.ignoresSafeArea())
        }
        .interactiveDismissDisabled(enCours)
        .accessibilityIdentifier("evaluation-signalement")
    }
}
