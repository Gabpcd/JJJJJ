import SwiftUI
import JoleneCore
import JoleneDesign

/// « Écrire à l'établissement » (L4-T7b, correction 20 et D25 de `LOT4_PLAN.md`) : pour le soignant assigné, statuts
/// ASSIGNEE, EN_COURS, TERMINEE, ABSENCE, LITIGE (`DetailMissionSoignant.tsx` l.1550, où le web incruste le fil),
/// `fn_user_id_pour_etablissement` puis `fn_obtenir_conversation(p_autre_id, p_mission_id)` (`ContactMissionModel`),
/// puis fil de la mission dans la messagerie native. Échec : « Impossible d'ouvrir la conversation. » (web
/// `useOuvrirConversation.ts` l.46). Remplace le stub de T1c sans retoucher `MissionDetailScreen`.
///
/// Identifiants : `mission-contact`, `mission-contact-erreur`.
struct MissionContactButton: View {
    let mission: Mission
    @Environment(\.contexteSecondaire) private var contexte

    var body: some View {
        if let contexte, EcranSecondaire.messagerie(conversationId: nil).estLivre,
           ContactMissionModel.propose(mission.record, userId: contexte.snapshot.user.id) {
            Contenu(mission: mission, contexte: contexte)
        }
    }

    private struct Contenu: View {
        let mission: Mission
        let contexte: ContexteSecondaire
        @StateObject private var model: ContactMissionModel

        init(mission: Mission, contexte: ContexteSecondaire) {
            self.mission = mission
            self.contexte = contexte
            _model = StateObject(wrappedValue: ContactMissionModel(controller: contexte.session.controller, snapshot: contexte.snapshot))
        }

        var body: some View {
            VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                JoleneButton(MessagerieTextes.ecrireEtablissement, style: .secondary, isLoading: model.enCours) {
                    Task {
                        guard let id = await model.ouvrir(mission.record) else { return }
                        contexte.ouvrir(.secondaire(.messagerie(conversationId: id)))
                    }
                }
                .disabled(model.enCours)
                .accessibilityIdentifier("mission-contact")
                if let erreur = model.erreur {
                    InlineNotice(erreur, tone: .error, identifier: "mission-contact-erreur")
                }
            }
        }
    }
}
