import SwiftUI
import JoleneCore
import JoleneDesign

/// Panneau de contestation d'une présence (lot 2, T5b, HARD STOP n°4 ; parité soignant de `PanneauContestation.tsx`) :
/// vue de `ContestationModel` (JoleneCore), qui porte toutes les règles (`ContestationModelTests`). Monté sous la date de
/// `PresenceValideeRow` et sous les contrôles de `DetailPresencesScreen`.
///
/// - Bouton « Contester cette présence » (`contestation-ouvrir-<presenceId>`) seulement si le serveur dit la fenêtre
///   ouverte (`fn_fenetre_contestation_ouverte`) ; rien sinon, ni pendant la lecture, ni sur erreur (fail-closed).
/// - Litige relu : en-tête « Contestation » et libellé de statut du web (`contestation-statut-<presenceId>`) ; réponse et
///   clôture restent sur le web (lot 4) : « Voir ou signaler un litige » (`contestation-litiges-web`), rendu seulement avec
///   le présentateur des renvois web (jamais un bouton sans effet).
/// - **Aucun texte de délai** (Q9, D12 : la garde `ANCRES_Q9` les refuse) : ni « 72h pour répondre », ni l'escalade, ni
///   la fenêtre de 72 h du formulaire du web. Un refus du serveur s'affiche tel quel dans la feuille (envoi désactivé),
///   puis dans le panneau à la place du bouton (`contestation-refus-<presenceId>`). Une erreur de transport laisse la
///   feuille ouverte avec son message, « Envoyer » verrouillé pendant la relecture du litige.
struct ContestationPanneau: View {
    @StateObject private var model: ContestationModel
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    init(presenceId: String, missionId: String, valideLe: String?, session: SessionStore, snapshot: SessionSnapshot) {
        _model = StateObject(wrappedValue: ContestationModel(presenceId: presenceId, missionId: missionId, valideLe: valideLe,
                                                              controller: session.controller, snapshot: snapshot))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            switch model.etat {
            case .chargement, .masque:
                // Vue de taille nulle (et non `EmptyView`) : la `.task` de lecture doit s'exécuter.
                Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            case .contestable:
                JoleneButton(LibellesWeb.Contestation.contester, style: .secondary) { model.ouvrirFormulaire() }
                    .accessibilityIdentifier("contestation-ouvrir-\(model.presenceId)")
            case let .refusee(message):
                // Refus du serveur à l'envoi, tel quel : plus de bouton jusqu'à la prochaine lecture (revue B8, m3).
                InlineNotice(message, tone: .error, identifier: "contestation-refus-\(model.presenceId)")
            case let .litige(litige):
                statut(litige)
            }
        }
        .task { await model.charger() }
        .sheet(isPresented: Binding(get: { model.formulaireOuvert }, set: { if !$0 { model.annuler() } })) {
            ContestationSheet(model: model)
        }
    }

    private func statut(_ litige: LitigePresence) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            HStack(spacing: JoleneSpacing.sm) {
                Image(systemName: "text.bubble").foregroundStyle(JoleneColor.rose700).accessibilityHidden(true)
                Text(LibellesWeb.Contestation.titre)
                    .font(JoleneFont.caption.weight(.semibold))
                    .foregroundStyle(JoleneColor.midnight)
                Spacer(minLength: JoleneSpacing.sm)
                JoleneBadge(model.libelleStatut ?? "", tone: Self.ton(litige.statut))
                    .accessibilityIdentifier("contestation-statut-\(model.presenceId)")
            }
            if let presentateurRenvoiWeb, let route = PresencesRenvois.litiges {
                JoleneButton(LibellesWeb.LignePresence.voirOuSignalerLitige, style: .secondary) { presentateurRenvoiWeb.presenter(route) }
                    .accessibilityIdentifier("contestation-litiges-web")
            }
        }
        .padding(JoleneSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: JoleneRadius.field).strokeBorder(JoleneColor.rose100, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contestation-panneau-\(model.presenceId)")
    }

    /// Tons du web (`STATUT_CONFIG[…].color`, l.48-62) : ouvert en avertissement, résolutions en succès, le reste neutre.
    private static func ton(_ statut: String?) -> JoleneBadge.Tone {
        guard let statut else { return .info }
        if statut == "OUVERT" { return .warning }
        if statut.hasPrefix("RESOLU") { return .success }
        return .info
    }
}

/// Formulaire d'ouverture (`PanneauContestation.tsx` l.369-396, sans le texte de délai de l.393-395) : motif (500
/// caractères au plus, nettoyé), « Envoyer la contestation » (« Envoi… » pendant l'envoi), « Annuler ».
struct ContestationSheet: View {
    @ObservedObject var model: ContestationModel
    @FocusState private var motifActif: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                    Text(LibellesWeb.Contestation.titre)
                        .font(JoleneFont.title)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                    TextField(LibellesWeb.Contestation.placeholderSoignant,
                              text: Binding(get: { model.motif }, set: { model.saisirMotif($0) }), axis: .vertical)
                        .lineLimit(3...8)
                        .font(.system(size: 16))
                        .focused($motifActif)
                        .boutonOKClavier($motifActif, actif: !model.envoiEnCours)
                        .padding(JoleneSpacing.md)
                        .background(JoleneColor.cloud)
                        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                        .disabled(model.envoiEnCours)
                        .accessibilityLabel(LibellesWeb.Contestation.titre)
                        .accessibilityIdentifier("contestation-motif")
                    if let erreur = model.erreur {
                        InlineNotice(erreur, tone: .error, identifier: "contestation-erreur", announcesOnAppear: true)
                    }
                    JoleneButton(model.envoiEnCours ? LibellesWeb.Contestation.envoi : LibellesWeb.Contestation.envoyer,
                                 style: .destructive, isLoading: model.envoiEnCours) {
                        motifActif = false
                        Task { await model.envoyer() }
                    }
                    .disabled(!model.peutEnvoyer)
                    .accessibilityIdentifier("contestation-envoyer")
                    JoleneButton(LibellesWeb.Contestation.annuler, style: .secondary) { model.annuler() }
                        .disabled(model.envoiEnCours)
                        .accessibilityIdentifier("contestation-annuler")
                }
                .padding(JoleneSpacing.lg)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(JoleneColor.lavender.ignoresSafeArea())
        }
        .interactiveDismissDisabled(model.envoiEnCours)
        .accessibilityIdentifier("contestation-sheet")
    }
}
