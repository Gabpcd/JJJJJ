import SwiftUI
import JoleneCore
import JoleneDesign

/// Mémoire « note déjà proposée » injectée à la racine (`RootView`) : en mémoire en démo, `UserDefaults` sinon.
private struct MemoireNotationKey: EnvironmentKey {
    static let defaultValue: (any MemoireNotation)? = nil
}

extension EnvironmentValues {
    var memoireNotation: (any MemoireNotation)? {
        get { self[MemoireNotationKey.self] }
        set { self[MemoireNotationKey.self] = newValue }
    }
}

extension AppContainer {
    private static let memoireNotationDemo = MemoireNotationEnMemoire()

    /// Monde démo : mémoire de processus (rien n'est persisté) ; Staging et Production : `UserDefaults`.
    var memoireNotation: any MemoireNotation {
        isDemo ? Self.memoireNotationDemo : MemoireNotationDefaults()
    }
}

extension View {
    /// Point d'extension de la zone de pointage (T4b) : propose la notation rapide quand `PointageModel.notationAProposer`
    /// passe à vrai (FERMETURE relue, lot 2 T5a, décision 10), une fois par mission et par utilisateur, après relecture
    /// de la fin prévue (`NotationModel.proposer`). Une ligne dans la zone de T4b :
    /// `.notationAuDepart(pointage: model, contexte: contexte)`.
    func notationAuDepart(pointage: PointageModel, contexte: ZonePointageContexte) -> some View {
        modifier(NotationAuDepart(pointage: pointage, missionId: contexte.missionId, session: contexte.session,
                                  snapshot: contexte.snapshot))
    }
}

/// Lit la mémoire injectée puis monte l'hôte qui possède le `NotationModel` (un `@StateObject` ne lit pas
/// l'environnement à son init).
struct NotationAuDepart: ViewModifier {
    @ObservedObject var pointage: PointageModel
    let missionId: String
    let session: SessionStore
    let snapshot: SessionSnapshot
    @Environment(\.memoireNotation) private var memoire

    func body(content: Content) -> some View {
        NotationAuDepartHote(content: content, pointage: pointage, missionId: missionId, session: session, snapshot: snapshot,
                             memoire: memoire ?? MemoireNotationDefaults())
    }
}

private struct NotationAuDepartHote<Contenu: View>: View {
    let content: Contenu
    @ObservedObject var pointage: PointageModel
    @StateObject private var notation: NotationModel

    init(content: Contenu, pointage: PointageModel, missionId: String, session: SessionStore, snapshot: SessionSnapshot,
         memoire: any MemoireNotation) {
        self.content = content
        self.pointage = pointage
        _notation = StateObject(wrappedValue: NotationModel(missionId: missionId, controller: session.controller, snapshot: snapshot,
                                                            memoire: memoire))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            content
            if notation.retour == .remerciement {
                InlineNotice(LibellesDetailPresences.Notation.remerciement, tone: .success, identifier: "notation-remerciement",
                             announcesOnAppear: true)
            }
        }
        .onChange(of: pointage.notationAProposer) { proposer in
            if proposer { Task { await notation.proposer() } }
        }
        .sheet(isPresented: Binding(get: { notation.ouverte }, set: { if !$0 { notation.plusTard() } })) {
            NotationSheet(model: notation)
        }
    }
}

/// Feuille de notation rapide (`SheetNotationRapide`, `NotationRapide.tsx` l.143-216) : note globale en un tap, détail
/// optionnel des quatre critères, « Envoyer ma note », « Plus tard ». Règles dans `NotationModel` (JoleneCore,
/// `NotationModelTests`) ; textes : `LibellesWeb.Notation` (verbatim) et `LibellesDetailPresences.Notation` (vouvoyés).
/// Aucune note n'est jamais lue ni affichée (écriture seule, filtre centralisé `evaluations_publiees`).
struct NotationSheet: View {
    @ObservedObject var model: NotationModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                    Text(LibellesWeb.Notation.titre)
                        .font(JoleneFont.title)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(LibellesDetailPresences.Notation.description)
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .fixedSize(horizontal: false, vertical: true)
                    Etoiles(valeur: model.note, taille: 32, identifiant: { "notation-etoile-\($0)" }, libelle: LibellesWeb.Notation.groupeNote,
                            actif: !model.envoiEnCours) { model.choisirNote($0) }
                        .frame(maxWidth: .infinity)
                    Button(model.detailOuvert ? LibellesWeb.Notation.masquerDetail : LibellesWeb.Notation.detailler) {
                        model.basculerDetail()
                    }
                    .font(JoleneFont.caption.weight(.semibold))
                    .foregroundStyle(JoleneColor.rose800)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("notation-detail")
                    if model.detailOuvert, let criteres = model.criteres {
                        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                            ForEach(Array(LibellesDetailPresences.Notation.criteres.enumerated()), id: \.offset) { index, libelle in
                                ViewThatFits(in: .horizontal) {
                                    HStack {
                                        Text(libelle).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
                                        Spacer(minLength: JoleneSpacing.sm)
                                        etoilesCritere(index, libelle: libelle, valeur: criteres[index])
                                    }
                                    VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                                        Text(libelle).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
                                        etoilesCritere(index, libelle: libelle, valeur: criteres[index])
                                    }
                                }
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("notation-criteres")
                    }
                    if case let .erreur(message) = model.retour {
                        InlineNotice(message, tone: .error, identifier: "notation-erreur", announcesOnAppear: true)
                    }
                    JoleneButton(LibellesWeb.Notation.envoyer, isLoading: model.envoiEnCours) {
                        Task { await model.envoyer() }
                    }
                    .disabled(!model.peutEnvoyer)
                    .accessibilityIdentifier("notation-envoyer")
                    JoleneButton(LibellesWeb.Notation.plusTard, style: .secondary) { model.plusTard() }
                        .disabled(model.envoiEnCours)
                        .accessibilityIdentifier("notation-plus-tard")
                }
                .padding(JoleneSpacing.lg)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(JoleneColor.lavender.ignoresSafeArea())
        }
        .interactiveDismissDisabled(model.envoiEnCours)
        .accessibilityIdentifier("notation-sheet")
    }

    private func etoilesCritere(_ index: Int, libelle: String, valeur: Int) -> some View {
        Etoiles(valeur: valeur, taille: 22, identifiant: { "notation-critere-\(index + 1)-\($0)" }, libelle: libelle,
                actif: !model.envoiEnCours) { model.choisirCritere(index, $0) }
    }
}

/// Rangée d'étoiles 1-5 (`EtoilesNotation`, l.77-101) : une cible de 44 pt par étoile, l'étoile choisie porte le trait
/// « sélectionné », libellé vocalisé « 4 étoiles ».
private struct Etoiles: View {
    let valeur: Int
    let taille: CGFloat
    let identifiant: (Int) -> String
    let libelle: String
    let actif: Bool
    let choisir: (Int) -> Void

    var body: some View {
        HStack(spacing: JoleneSpacing.xs) {
            ForEach(1...NotationModel.noteMaximale, id: \.self) { n in
                Button { choisir(n) } label: {
                    Image(systemName: n <= valeur ? "star.fill" : "star")
                        .font(.system(size: taille))
                        .foregroundStyle(n <= valeur ? JoleneColor.butter700 : JoleneColor.bubblegum)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!actif)
                .accessibilityLabel(LibellesDetailPresences.Notation.etoiles(n))
                .accessibilityAddTraits(valeur == n ? .isSelected : [])
                .accessibilityIdentifier(identifiant(n))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(libelle)
    }
}
