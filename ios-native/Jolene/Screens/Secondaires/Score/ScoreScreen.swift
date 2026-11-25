import SwiftUI
import Charts
import JoleneCore
import JoleneDesign

/// « Mon score » (`/soignant/score`, alias `fiabilite`, `fiabilite-legacy`, L4-T9), port de `ScoreContent`
/// (`src/pages/PageScoreSoignant.tsx`), empilé sur le Profil par `SecondaryRouter` une fois son coupe-circuit
/// `ios_natif_score_actif` lu (fail-open). Vue de `ScoreModel` (JoleneCore), qui porte les règles (quatre lectures
/// ensemble, relecture qui confirme, refus verbatim, délai, epoch) ; la vue n'ajoute aucune logique.
///
/// Tout ce qui est chiffré vient du serveur et s'affiche tel quel : score, niveau, pourcentages et poids des
/// composantes, malus, bonus, points des événements, notes reçues. Sans score ou sans niveau servi, rien n'est affiché
/// à leur place (jamais 50 ni Bronze). Les notes reçues ne viennent que de la RPC filtrée (`ScorePort.notationsRecues`).
///
/// - Score et niveau (ou « Non noté » sous trois missions terminées, règle d'affichage du web), détail du calcul
///   replié par défaut, évolution sur six mois (Swift Charts), notations reçues récemment, événements des douze
///   derniers mois.
/// - Contestation d'un événement que le serveur dit contestable : feuille (motif parmi les six du web, explication de
///   vingt caractères au moins, **sans justificatif**, D10) ; l'événement n'est montré non contestable qu'après
///   relecture.
/// - Non portés : justificatif de contestation, lignes de référence du graphique, « Contribution : … pts », conseils
///   « Améliorez », signalement d'une notation depuis cette page (voir `ScoreTextes`).
///
/// Identifiants : `score-screen` ; `score-carte` (`score-valeur`, `score-niveau`, `score-non-note`,
/// `score-probatoire`) ; `score-calcul-bascule`, `score-breakdown` (`score-composante-<cle>`, `score-inactives`,
/// `score-malus-bonus`) ; `score-evolution` (`score-evolution-vide`) ; `score-notations` (`score-notation-<id>`,
/// `score-notations-vide`) ; `score-evenements` (`score-evenement-<id>`, `score-evenement-points-<id>`,
/// `score-contester-<id>`, `score-evenement-etat-<id>`), `score-evenements-vide` ;
/// `score-chargement`, `score-erreur` (+ `-reessayer`), `score-action-erreur`, `score-confirmation`,
/// `score-session-check` ; feuille `score-contestation` (`-rappel`, `-motif`, `-motif-<VALEUR>`, `-texte`, `-compteur`,
/// `-examen`, `-erreur`, `-envoyer`, `-annuler`).
struct ScoreScreen: View {
    let contexte: ContexteSecondaire
    @StateObject private var model: ScoreModel
    @ObservedObject private var session: SessionStore
    @State private var detailOuvert = false
    @State private var aContester: EvenementScore?

    init(contexte: ContexteSecondaire) {
        self.contexte = contexte
        self.session = contexte.session
        _model = StateObject(wrappedValue: ScoreModel(controller: contexte.session.controller, snapshot: contexte.snapshot))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    Text(ScoreTextes.enTete)
                        .font(JoleneFont.title)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                    Text(ScoreTextes.sousTitre)
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if aContester == nil { avis }
                if model.sessionExpiree {
                    JoleneButton("Vérifier ma session", style: .secondary) { Task { await model.verifierSession(session) } }
                        .accessibilityIdentifier("score-session-check")
                }
                contenu
            }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.charger() }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .navigationTitle(ScoreTextes.titre)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("score-screen")
        // À chaque apparition, comme le web au montage.
        .task { await model.charger() }
        .sheet(item: $aContester) { evenement in
            ContestationScoreSheet(evenement: evenement, model: model) { aContester = nil }
        }
    }

    // MARK: - Contenu

    @ViewBuilder private var avis: some View {
        if let erreur = model.erreur {
            InlineNotice(erreur, tone: .error, identifier: "score-action-erreur", announcementID: model.jeton)
        } else if let confirmation = model.confirmation {
            InlineNotice(confirmation, tone: .success, identifier: "score-confirmation", announcementID: model.jeton)
        }
    }

    @ViewBuilder private var contenu: some View {
        switch model.etat {
        case .chargement:
            SkeletonCard(identifier: "score-chargement")
        case let .echec(message):
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                InlineNotice(message, tone: .error, identifier: "score-erreur")
                if !model.sessionExpiree {
                    JoleneButton(ScoreTextes.reessayer, style: .secondary) { Task { await model.charger() } }
                        .accessibilityIdentifier("score-erreur-reessayer")
                }
            }
        case let .pret(lu):
            carteScore(lu.breakdown)
            calcul(lu.breakdown)
            evolution(lu.evolution)
            notations(lu.notations)
            evenements(lu.evenements)
        }
    }

    private func carte<Contenu: View>(_ identifiant: String, @ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) { contenu() }
            .padding(JoleneSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(JoleneColor.cloud)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifiant)
    }

    private func titreSection(_ titre: String) -> some View {
        Text(titre)
            .font(JoleneFont.headline)
            .foregroundStyle(JoleneColor.midnight)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Score (valeurs serveur)

    private func carteScore(_ breakdown: BreakdownScore) -> some View {
        carte("score-carte") {
            if ScorePresentation.nonNote(breakdown) {
                // Sous trois missions terminées (l.100, l.119-126) : aucun score affiché.
                StatusPill(ScoreTextes.nonNote, tone: .neutral, identifier: "score-non-note")
                Text(ScoreTextes.scoreAbsent)
                    .font(JoleneFont.hero)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("score-valeur")
                if let restantes = ScorePresentation.missionsRestantes(breakdown) {
                    Text(ScoreTextes.scoreDisponibleApres(restantes))
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                if let niveau = ScoreTextes.niveau(breakdown.niveau) {
                    StatusPill(niveau, tone: .info, identifier: "score-niveau")
                }
                if let score = ScorePresentation.score(breakdown) {
                    (Text(score).font(JoleneFont.hero).foregroundColor(JoleneColor.rose800)
                        + Text(ScoreTextes.sur100).font(JoleneFont.headline).foregroundColor(JoleneColor.bubblegum))
                        .accessibilityIdentifier("score-valeur")
                } else {
                    // Aucun score servi : jamais une valeur par défaut.
                    Text(ScoreTextes.scoreAbsent)
                        .font(JoleneFont.hero)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .accessibilityIdentifier("score-valeur")
                }
                if breakdown.enPeriodeProbatoire == true {
                    Label(ScoreTextes.periodeProbatoireIndicatif, systemImage: "exclamationmark.triangle")
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.butter800)
                        .accessibilityIdentifier("score-probatoire")
                }
            }
        }
    }

    // MARK: - Détail du calcul

    private func calcul(_ breakdown: BreakdownScore) -> some View {
        carte("score-calcul") {
            Button {
                detailOuvert.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.sm) {
                    Text(ScoreTextes.calculTitre)
                        .font(JoleneFont.headline)
                        .foregroundStyle(JoleneColor.midnight)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: JoleneSpacing.sm)
                    Text(detailOuvert ? ScoreTextes.masquer : ScoreTextes.voirLeDetail)
                        .font(JoleneFont.caption.weight(.semibold))
                        .foregroundStyle(JoleneColor.rose800)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("score-calcul-bascule")
            if detailOuvert { detail(breakdown) }
        }
    }

    private func detail(_ breakdown: BreakdownScore) -> some View {
        let actives = breakdown.composantes.filter(\.estActive)
        let inactives = breakdown.composantes.filter { !$0.estActive }
        let malusEtBonus = ScorePresentation.malusEtBonus(breakdown)
        return VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            if breakdown.enPeriodeProbatoire == true {
                InlineNotice(ScoreTextes.periodeProbatoireTexte, title: ScoreTextes.periodeProbatoire, tone: .warning)
            }
            if !inactives.isEmpty {
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    Text(ScoreTextes.inactivesTitre)
                        .font(JoleneFont.callout.weight(.semibold))
                        .foregroundStyle(JoleneColor.midnight)
                    Text(ScoreTextes.inactivesTexte(inactives.count))
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(inactives) { composante in
                        Text(ScoreTextes.inactive(composante))
                            .font(JoleneFont.caption)
                            .foregroundStyle(JoleneColor.bubblegum)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("score-inactives")
            }
            ForEach(actives) { composante in ligne(composante) }
            if !malusEtBonus.isEmpty {
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    Text(ScoreTextes.malusBonusTitre)
                        .font(JoleneFont.callout.weight(.semibold))
                        .foregroundStyle(JoleneColor.midnight)
                    ForEach(malusEtBonus, id: \.self) { texte in
                        Text(texte)
                            .font(JoleneFont.caption)
                            .foregroundStyle(JoleneColor.midnight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("score-malus-bonus")
            }
            Text(ScoreTextes.formule)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                ForEach(ScoreTextes.calculRegles, id: \.self) { regle in
                    Text("• \(regle)")
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("score-breakdown")
    }

    /// Composante active : libellé et description du web, pourcentage et poids servis.
    @ViewBuilder private func ligne(_ composante: ComposanteScore) -> some View {
        let textes = ScoreTextes.composante(composante.cle)
        if let pct = composante.pct {
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(textes.label)
                            .font(JoleneFont.callout.weight(.semibold))
                            .foregroundStyle(JoleneColor.midnight)
                        Text(textes.description)
                            .font(JoleneFont.caption)
                            .foregroundStyle(JoleneColor.bubblegum)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: JoleneSpacing.sm)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(ScorePresentation.pourcentage(pct))
                            .font(JoleneFont.headline)
                            .foregroundStyle(JoleneColor.midnight)
                        if let poids = composante.poids {
                            Text(ScoreTextes.poids(poids))
                                .font(JoleneFont.caption)
                                .foregroundStyle(JoleneColor.bubblegum)
                        }
                    }
                }
                ProgressView(value: ScorePresentation.progression(pct))
                    .tint(JoleneColor.rose700)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("score-composante-\(composante.cle.rawValue)")
        }
    }

    // MARK: - Évolution

    /// Point de la courbe : libellé du mois et score servi (un mois sans score servi n'a pas de point).
    private struct PointCourbe: Identifiable {
        let id: String
        let mois: String
        let score: Double
    }

    private func evolution(_ evolution: [PointEvolutionScore]) -> some View {
        let points = evolution.compactMap { point -> PointCourbe? in
            guard let score = point.score else { return nil }
            return PointCourbe(id: point.mois, mois: EvaluationsPresentation.moisCourt(point.mois), score: score)
        }
        return carte("score-evolution") {
            if points.isEmpty {
                Text(ScoreTextes.pasEncoreDHistorique)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("score-evolution-vide")
                Text(ScoreTextes.evolutionApparaitra)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                titreSection(ScoreTextes.evolutionTitre)
                if points.count < 2 {
                    Text(ScoreTextes.donneesLimitees(points.count))
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Chart(points) { point in
                    LineMark(x: .value("Mois", point.mois), y: .value(ScoreTextes.serieScore, point.score))
                        .foregroundStyle(JoleneColor.rose700)
                    PointMark(x: .value("Mois", point.mois), y: .value(ScoreTextes.serieScore, point.score))
                        .foregroundStyle(JoleneColor.rose700)
                }
                .chartYScale(domain: 0...100)
                .frame(height: 180)
                .accessibilityLabel(ScoreTextes.evolutionTitre)
                .accessibilityIdentifier("score-evolution-courbe")
            }
        }
    }

    // MARK: - Notations reçues (RPC filtrée)

    private func notations(_ notations: [NotationRecue]) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            titreSection(ScoreTextes.notationsTitre)
            if notations.isEmpty {
                carte("score-notations-vide") {
                    Text(ScoreTextes.aucuneNotation)
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.bubblegum)
                }
            } else {
                ForEach(notations) { notation in
                    carte("score-notation-\(notation.id)") {
                        HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                if let intitule = notation.missionIntitule, !intitule.isEmpty {
                                    Text(intitule)
                                        .font(JoleneFont.callout.weight(.semibold))
                                        .foregroundStyle(JoleneColor.midnight)
                                        .lineLimit(2)
                                }
                                Text(ScorePresentation.metaNotation(notation))
                                    .font(JoleneFont.caption)
                                    .foregroundStyle(JoleneColor.bubblegum)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: JoleneSpacing.sm)
                            Text(ScoreTextes.noteSur5(EvaluationsPresentation.note(notation.noteMoyenne)))
                                .font(JoleneFont.caption.weight(.semibold))
                                .foregroundStyle(JoleneColor.midnight)
                        }
                        ForEach(Array(ScoreTextes.criteres.enumerated()), id: \.offset) { rang, libelle in
                            HStack(spacing: JoleneSpacing.sm) {
                                Text(libelle)
                                    .font(JoleneFont.caption)
                                    .foregroundStyle(JoleneColor.bubblegum)
                                Spacer(minLength: JoleneSpacing.sm)
                                critere(notation, rang: rang)
                            }
                        }
                        if let commentaire = notation.commentaire, !commentaire.isEmpty {
                            Text(commentaire)
                                .font(JoleneFont.caption)
                                .foregroundStyle(JoleneColor.midnight)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("score-notations")
    }

    /// Étoiles d'un critère servi (`Stars`, `NotationsRecues.tsx` l.31-39) ; « — » si le critère n'est pas servi.
    @ViewBuilder private func critere(_ notation: NotationRecue, rang: Int) -> some View {
        if rang < notation.criteres.count, let valeur = notation.criteres[rang] {
            StarRow(note: Double(valeur), showsValue: false)
        } else {
            Text(EvaluationsTextes.noteIndisponible)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
        }
    }

    // MARK: - Événements et contestation

    @ViewBuilder private func evenements(_ evenements: [EvenementScore]) -> some View {
        if evenements.isEmpty {
            carte("score-evenements-vide") {
                titreSection(ScoreTextes.aucunEvenementTitre)
                Text(ScoreTextes.aucunEvenementTexte)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                titreSection(ScoreTextes.evenementsTitre)
                ForEach(evenements) { evenement in ligne(evenement) }
                // Phrase d'engagement « … sous 72h » (`PageScoreSoignant.tsx` l.223) non affichée par prudence : aucun
                // mécanisme serveur ne garantit ce délai (`DECISIONS_LOT4.md`, précision 16). Le web l'affiche sur le
                // profil du soignant (`SectionEvenementsScore.tsx` l.121).
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("score-evenements")
        }
    }

    private func ligne(_ evenement: EvenementScore) -> some View {
        carte("score-evenement-\(evenement.id)") {
            Text(evenement.typeEvenement)
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.midnight)
            if let motif = evenement.motif, !motif.isEmpty {
                Text(motif)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let date = ScorePresentation.dateEvenement(evenement.creeLe) {
                Text(date)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
            }
            if let decision = evenement.decisionAdmin, !decision.isEmpty {
                Text(ScoreTextes.decisionAdmin(decision))
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.rose800)
            }
            HStack(alignment: .center, spacing: JoleneSpacing.md) {
                if let points = evenement.pointsAffiches {
                    Text(ScoreTextes.points(points))
                        .font(JoleneFont.headline)
                        .foregroundStyle(points < 0 ? JoleneColor.rose800 : JoleneColor.cyan900)
                        .accessibilityIdentifier("score-evenement-points-\(evenement.id)")
                }
                Spacer(minLength: JoleneSpacing.sm)
                // `contestable` est la valeur calculée par le serveur : jamais déduite ici.
                if evenement.contestable {
                    Button {
                        model.effacerMessages()
                        aContester = evenement
                    } label: {
                        Text(ScoreTextes.contester)
                            .font(JoleneFont.caption.weight(.semibold))
                            .foregroundStyle(JoleneColor.rose800)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.contestationEnCours != nil)
                    .accessibilityIdentifier("score-contester-\(evenement.id)")
                } else {
                    Text(ScorePresentation.etatNonContestable(evenement))
                        .font(JoleneFont.caption.italic())
                        .foregroundStyle(JoleneColor.bubblegum)
                        .accessibilityIdentifier("score-evenement-etat-\(evenement.id)")
                }
            }
        }
    }
}

/// « Contester cet événement de score » (`ModaleReclamationScore.tsx`), **sans justificatif** (D10 : un motif « urgence
/// médicale » avec pièce jointe inviterait à déposer un document de santé) : rappel de l'événement, motif parmi les
/// six du web (liste à choix unique, à la place du menu), explication de vingt caractères au moins, information du
/// web sur l'examen de la réclamation. Se referme sur une relecture qui montre l'événement non contestable ; sinon le
/// message (refus du serveur tel quel) reste affiché et la feuille ouverte.
struct ContestationScoreSheet: View {
    let evenement: EvenementScore
    @ObservedObject var model: ScoreModel
    let fermer: () -> Void
    @State private var motif: MotifContestationScore?
    @State private var texte = ""
    @FocusState private var texteActif: Bool

    private var enCours: Bool { model.contestationEnCours == evenement.id }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                    Text(ScoreTextes.contestationTitre)
                        .font(JoleneFont.title)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                        Text(evenement.typeEvenement)
                            .font(JoleneFont.callout.weight(.semibold))
                            .foregroundStyle(JoleneColor.midnight)
                        if let rappel = evenement.motif, !rappel.isEmpty {
                            Text(rappel)
                                .font(JoleneFont.caption)
                                .foregroundStyle(JoleneColor.bubblegum)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let points = evenement.pointsAffiches {
                            Text(ScoreTextes.pointsEvenement(points))
                                .font(JoleneFont.caption.monospacedDigit())
                                .foregroundStyle(JoleneColor.rose800)
                        }
                    }
                    .padding(JoleneSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(JoleneColor.cloud)
                    .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("score-contestation-rappel")
                    motifs
                    explication
                    InlineNotice(ScoreTextes.examenParAdmin, tone: .warning, identifier: "score-contestation-examen")
                    if let erreur = model.erreur {
                        InlineNotice(erreur, tone: .error, identifier: "score-contestation-erreur", announcementID: model.jeton)
                    }
                    VStack(spacing: JoleneSpacing.sm) {
                        JoleneButton(ScoreTextes.envoyer, isLoading: enCours) {
                            texteActif = false
                            Task {
                                // La feuille ne se referme qu'après une relecture qui montre l'événement non contestable.
                                if await model.contester(evenement, motif: motif, texte: texte) { fermer() }
                            }
                        }
                        .disabled(enCours)
                        .accessibilityIdentifier("score-contestation-envoyer")
                        JoleneButton(ScoreTextes.annuler, style: .secondary, action: fermer)
                            .disabled(enCours)
                            .accessibilityIdentifier("score-contestation-annuler")
                    }
                }
                .padding(JoleneSpacing.lg)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(JoleneColor.lavender.ignoresSafeArea())
        }
        .interactiveDismissDisabled(enCours)
        .accessibilityIdentifier("score-contestation")
    }

    /// Les six motifs de `MOTIFS` (l.22-29), dans l'ordre du web, à choix unique.
    private var motifs: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(ScoreTextes.contestationMotif)
                .font(JoleneFont.caption.weight(.semibold))
                .foregroundStyle(JoleneColor.midnight)
            ForEach(MotifContestationScore.allCases) { choix in
                Button {
                    motif = choix
                } label: {
                    HStack(spacing: JoleneSpacing.sm) {
                        Image(systemName: motif == choix ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(motif == choix ? JoleneColor.rose800 : JoleneColor.bubblegum)
                            .accessibilityHidden(true)
                        Text(ScoreTextes.libelle(choix))
                            .font(JoleneFont.callout)
                            .foregroundStyle(JoleneColor.midnight)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(enCours)
                .accessibilityAddTraits(motif == choix ? .isSelected : [])
                .accessibilityIdentifier("score-contestation-motif-\(choix.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("score-contestation-motif")
    }

    private var explication: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(ScoreTextes.contestationTexte)
                .font(JoleneFont.caption.weight(.semibold))
                .foregroundStyle(JoleneColor.midnight)
            TextField(ScoreTextes.contestationPlaceholder, text: $texte, axis: .vertical)
                .lineLimit(5...10)
                .font(.system(size: 16))
                .focused($texteActif)
                .boutonOKClavier($texteActif, actif: !enCours)
                .padding(JoleneSpacing.md)
                .background(JoleneColor.cloud)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                .disabled(enCours)
                .accessibilityLabel(ScoreTextes.contestationTexte)
                .accessibilityIdentifier("score-contestation-texte")
            Text(ScoreTextes.compteurTexte(texte.count))
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityIdentifier("score-contestation-compteur")
        }
    }
}
