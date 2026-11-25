import SwiftUI
import JoleneCore
import JoleneDesign

/// « Ne plus travailler ensemble » (`BoutonExclusion` puis `fn_exclure_utilisateur`, `DetailMissionSoignant.tsx`
/// l.1174, l.1181), L4-T11 : posé par `ActionsEtablissementMission` au bas du bloc de l'établissement, pour toute mission
/// qui a un établissement (`p_exclu_id` = `mission.etablissement_id`, `p_type = 'SOIGNANT'`). Feuille de confirmation aux
/// textes verbatim du web (`TextesWeb.Exclusion`, HARD STOP n°4) : titre, effet annoncé, motif optionnel (500 caractères),
/// « Annuler » / « Confirmer l'exclusion » ; « Exclusion enregistrée. Les missions ne seront plus visibles. » seulement
/// après relecture des exclusions envoyées qui montre l'établissement ; refus verbatim (« Exclusion déjà existante »…).
/// Mission ouverte non assignée : rangé avec « Signaler » sous le repli « Autres actions » d'`ActionsEtablissementMission`,
/// comme le web (l.1160-1172 ; décision e de l'intégration de la vague D) ; à plat sinon.
///
/// Identifiants : `mission-exclure`, `mission-exclure-confirmation` ; feuille `mission-exclusion` (`-titre`, `-effet`,
/// `-motif`, `-annuler`, `-confirmer`, `-erreur`).
struct MissionExclusionButton: View {
    let mission: Mission
    @Environment(\.contexteSecondaire) private var contexte

    var body: some View {
        if let contexte, !mission.record.etablissementId.isEmpty {
            MissionExclusionAction(etablissementId: mission.record.etablissementId, contexte: contexte)
        }
    }
}

private struct MissionExclusionAction: View {
    let etablissementId: String
    @StateObject private var model: ExclusionsModel
    @State private var feuille = false
    @State private var motif = ""

    init(etablissementId: String, contexte: ContexteSecondaire) {
        self.etablissementId = etablissementId
        _model = StateObject(wrappedValue: ExclusionsModel(controller: contexte.session.controller, snapshot: contexte.snapshot))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Button {
                model.effacerMessages()
                motif = ""
                feuille = true
            } label: {
                Text(TextesWeb.Exclusion.bouton)
                    .font(JoleneFont.caption.weight(.semibold))
                    .foregroundStyle(JoleneColor.rose700)
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("mission-exclure")
            if !feuille, let confirmation = model.confirmation {
                InlineNotice(confirmation, tone: .success, identifier: "mission-exclure-confirmation", announcementID: model.jeton)
            }
        }
        .sheet(isPresented: $feuille) { contenuFeuille }
    }

    private var contenuFeuille: some View {
        let occupe = model.occupe(etablissementId)
        return ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                Text(TextesWeb.Exclusion.titre)
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("mission-exclusion-titre")
                Text(TextesWeb.Exclusion.effet)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mission-exclusion-effet")
                Text(ExclusionsTextes.motifLibelle)
                    .font(JoleneFont.caption.weight(.semibold))
                    .foregroundStyle(JoleneColor.midnight)
                TextField(ExclusionsTextes.motifPlaceholder,
                          text: Binding(get: { motif }, set: { motif = String($0.prefix(ExclusionsRegles.motifLongueurMax)) }),
                          axis: .vertical)
                    .lineLimit(3...6)
                    .font(.system(size: 16))
                    .padding(JoleneSpacing.md)
                    .background(JoleneColor.cloud)
                    .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                    .disabled(occupe)
                    .accessibilityLabel(ExclusionsTextes.motifLibelle)
                    .accessibilityIdentifier("mission-exclusion-motif")
                if let erreur = model.erreur {
                    InlineNotice(erreur, tone: .error, identifier: "mission-exclusion-erreur", announcementID: model.jeton)
                }
                HStack(spacing: JoleneSpacing.sm) {
                    JoleneButton(ExclusionsTextes.annuler, style: .secondary) { if !occupe { feuille = false } }
                        .accessibilityIdentifier("mission-exclusion-annuler")
                    JoleneButton(occupe ? ExclusionsTextes.enCours : TextesWeb.Exclusion.confirmer, style: .destructive,
                                 isLoading: occupe) {
                        Task {
                            // La feuille ne se referme qu'après une relecture qui montre l'exclusion.
                            if await model.exclure(etablissementId: etablissementId, motif: motif) { feuille = false }
                        }
                    }
                    .disabled(occupe)
                    .accessibilityIdentifier("mission-exclusion-confirmer")
                }
            }
            .padding(JoleneSpacing.lg)
        }
        .interactiveDismissDisabled(occupe)
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("mission-exclusion")
    }
}
