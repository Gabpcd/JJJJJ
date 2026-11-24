import SwiftUI
import JoleneCore
import JoleneDesign

/// Bloquer / Débloquer l'interlocuteur (L4-T7b, HARD STOP n°4, exigence Apple 1.2), port de
/// `src/components/BloquerUtilisateur.tsx` (variante lien) : statut relu, blocage en deux temps (« Bloquer
/// l’établissement ? » Confirmer / Annuler), déblocage direct, textes verbatim (`MessagerieTextes.Blocage`). Vue de
/// `BlocageModel` ; le message de l'action est affiché par l'en-tête du fil (`chat-moderation-confirmation`).
///
/// Identifiants : `chat-bloquer` (libellé « Bloquer » ou « Débloquer »), `chat-bloquer-question`, `chat-bloquer-confirmer`,
/// `chat-bloquer-annuler`, `chat-bloquer-indisponible`, `chat-bloquer-reessayer`.
struct BlocageControle: View {
    @ObservedObject var model: BlocageModel

    var body: some View {
        switch model.statut {
        case .lecture:
            EmptyView() // web : rien tant que le statut n'est pas lu
        case .indisponible:
            HStack(spacing: JoleneSpacing.sm) {
                Text(MessagerieTextes.Blocage.statutIndisponible)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .accessibilityIdentifier("chat-bloquer-indisponible")
                lien(MessagerieTextes.Blocage.reessayerStatut, identifiant: "chat-bloquer-reessayer") {
                    Task { await model.lire() }
                }
            }
        case let .lu(bloque):
            if !bloque && model.confirmation {
                HStack(spacing: JoleneSpacing.sm) {
                    Text(MessagerieTextes.Blocage.question(cible: model.libelleCible))
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .accessibilityIdentifier("chat-bloquer-question")
                    lien(MessagerieTextes.Blocage.confirmer, identifiant: "chat-bloquer-confirmer", teinte: JoleneColor.rose700,
                         gras: true) {
                        Task { await model.confirmer() }
                    }
                    .disabled(model.enCours)
                    lien(MessagerieTextes.Blocage.annuler, identifiant: "chat-bloquer-annuler") { model.annuler() }
                }
            } else {
                Button {
                    Task { await model.demander() }
                } label: {
                    Label(bloque ? MessagerieTextes.Blocage.debloquer : MessagerieTextes.Blocage.bloquer,
                          systemImage: bloque ? "checkmark.shield" : "nosign")
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(model.enCours)
                .accessibilityLabel(bloque ? MessagerieTextes.Blocage.debloquer : MessagerieTextes.Blocage.bloquer)
                .accessibilityIdentifier("chat-bloquer")
            }
        }
    }

    private func lien(_ titre: String, identifiant: String, teinte: Color = JoleneColor.bubblegum, gras: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titre)
                .font(gras ? JoleneFont.caption.weight(.semibold) : JoleneFont.caption)
                .underline(!gras)
                .foregroundStyle(teinte)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifiant)
    }
}

/// « Signaler à Jolene » (L4-T7b, HARD STOP n°4, exigence Apple 1.2), port de la modale de
/// `src/components/SignalerUtilisateur.tsx` : introduction, motif (liste fermée du web, dans son ordre), précision
/// obligatoire de 10 caractères au moins, « Annuler » / « Envoyer le signalement ». Vue de `SignalementModel` ; se
/// referme sur un signalement accepté par le serveur (`fermer(true)`), sinon le message reste et la saisie est gardée.
/// Utilisée depuis le fil et depuis le détail d'une mission (`MissionSignalerButton`).
///
/// Identifiants : `signalement-sheet`, `signalement-categorie`, `signalement-motif`, `signalement-erreur`,
/// `signalement-annuler`, `signalement-envoyer`.
struct SignalementSheet: View {
    @StateObject private var model: SignalementModel
    let fermer: (Bool) -> Void

    init(cible: ModerationConversation.CibleSignalement, contexte: ContexteSecondaire, fermer: @escaping (Bool) -> Void) {
        _model = StateObject(wrappedValue: SignalementModel(controller: contexte.session.controller, snapshot: contexte.snapshot,
                                                            cible: cible))
        self.fermer = fermer
    }

    private typealias S = MessagerieTextes.Signalement

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                Label(S.titre, systemImage: "flag")
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityAddTraits(.isHeader)
                Text(S.introduction)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    Text(S.motif).font(JoleneFont.caption.weight(.medium)).foregroundStyle(JoleneColor.midnight)
                    Picker(S.motif, selection: $model.categorie) {
                        ForEach(S.categories, id: \.valeur) { categorie in
                            Text(categorie.libelle).tag(categorie.valeur)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(JoleneColor.rose800)
                    .disabled(model.enCours)
                    .accessibilityIdentifier("signalement-categorie")
                }
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    Text(S.precisez).font(JoleneFont.caption.weight(.medium)).foregroundStyle(JoleneColor.midnight)
                    ZStack(alignment: .topLeading) {
                        if model.motif.isEmpty {
                            Text(S.placeholder)
                                .font(JoleneFont.body)
                                .foregroundStyle(JoleneColor.bubblegum)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .accessibilityHidden(true)
                        }
                        TextEditor(text: $model.motif)
                            .font(JoleneFont.body) // 16 pt au moins : pas de zoom au focus
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 110)
                            .disabled(model.enCours)
                            .accessibilityLabel(S.precisez)
                            .accessibilityIdentifier("signalement-motif")
                    }
                    .padding(JoleneSpacing.xs)
                    .background(JoleneColor.lavender)
                    .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                }
                if let erreur = model.erreur {
                    InlineNotice(erreur, tone: .error, identifier: "signalement-erreur")
                }
                VStack(spacing: JoleneSpacing.sm) {
                    JoleneButton(model.enCours ? S.envoi : S.envoyer, style: .destructive, isLoading: model.enCours) {
                        Task { if await model.envoyer() { fermer(true) } }
                    }
                    .disabled(!model.envoiPossible)
                    .accessibilityIdentifier("signalement-envoyer")
                    JoleneButton(S.annuler, style: .secondary) { fermer(false) }
                        .disabled(model.enCours)
                        .accessibilityIdentifier("signalement-annuler")
                }
            }
            .padding(JoleneSpacing.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(JoleneColor.cloud.ignoresSafeArea())
        .interactiveDismissDisabled(model.enCours)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("signalement-sheet")
    }
}
