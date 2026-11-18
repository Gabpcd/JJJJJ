import SwiftUI
import JoleneCore
import JoleneDesign

/// Bloc « Confirmez votre présence » du détail de mission (lot 1, T6c, HARD STOP n°4 : bouton, confirmation et état
/// repris à l'identique du web, `TextesWeb.ConfirmationPresence` ; titre et description vouvoyés,
/// `PresenceRules.Textes`). Visibilité dérivée de la mission relue (`PresenceRules.bloc`) ; bouton désactivé pendant
/// l'appel, masqué dès que `presence_confirmee_le` est relu. Cible du push `RAPPEL_MISSION` (`/soignant/missions/{id}`).
/// Issue incertaine (revue B8 delta de #1157, M1) : texte de relecture (`presence-incertaine`) et « Actualiser »
/// (`presence-relire`) à la place du bouton, jusqu'à une relecture qui conclut.
struct ConfirmationPresenceBloc: View {
    let mission: Mission
    /// Relecture de la mission par l'écran (`MissionDetailModel.load`) après la réponse serveur.
    let relireMission: () async -> Void

    @StateObject private var model: ConfirmationPresenceModel
    private typealias T = TextesWeb.ConfirmationPresence

    init(mission: Mission, session: SessionStore, snapshot: SessionSnapshot, relireMission: @escaping () async -> Void) {
        self.mission = mission
        self.relireMission = relireMission
        _model = StateObject(wrappedValue: ConfirmationPresenceModel(missionId: mission.id, controller: session.controller,
                                                                     snapshot: snapshot))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.md) {
            switch model.bloc(mission.record) {
            case .masque:
                EmptyView()
            case .aConfirmer:
                VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
                    Text(PresenceRules.Textes.titre).font(JoleneFont.headline).foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                    Text(PresenceRules.Textes.description).font(JoleneFont.callout).foregroundStyle(JoleneColor.bubblegum)
                    if model.relectureRequise {
                        // Revue B8 delta de #1157 (M1) : issue incertaine, aucun nouvel envoi tant qu'une relecture n'a
                        // pas conclu ; « Actualiser » relit la mission.
                        JoleneButton(PresenceRules.Textes.actualiser, style: .secondary, isLoading: model.enCours) {
                            Task { if await model.relire() { await relireMission() } }
                        }
                        .disabled(model.enCours)
                        .accessibilityIdentifier("presence-relire")
                    } else {
                        JoleneButton(T.bouton, isLoading: model.enCours) {
                            Task { if await model.confirmer() { await relireMission() } }
                        }
                        .disabled(model.enCours)
                        .accessibilityIdentifier("presence-confirmer")
                    }
                }
                .padding(JoleneSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(JoleneColor.cloud)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("presence-bloc")
            case .confirmee:
                Text(T.etatConfirme)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.midnight)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(JoleneSpacing.md)
                    .background(JoleneColor.lavender)
                    .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
                    .accessibilityIdentifier("presence-confirmee")
            }
            switch model.issue {
            case .confirmee?:
                InlineNotice(T.confirmation, tone: .success, identifier: "presence-confirmation", announcesOnAppear: true)
            case let .refus(message)?:
                InlineNotice(message, tone: .error, identifier: "presence-erreur", announcesOnAppear: true)
            case let .incertaine(message)?:
                // Une mission relue confirmée par l'écran lève l'incertitude : aucun message contradictoire.
                if model.bloc(mission.record) != .confirmee {
                    InlineNotice(message, tone: .warning, identifier: "presence-incertaine", announcesOnAppear: true)
                }
            case nil:
                EmptyView()
            }
        }
        .task { await model.charger() }
    }
}
