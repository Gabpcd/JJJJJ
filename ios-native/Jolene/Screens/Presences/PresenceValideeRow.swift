import SwiftUI
import JoleneCore
import JoleneDesign

/// Ligne de la section « Présences validées récemment » de l'onglet Aujourd'hui (`PresencesSoignant.tsx` l.616-650) :
/// intitulé, établissement (`m?.etablissements?.nom`, sans repli, l.629), badge « Validée », date de validation.
///
/// T5b : le panneau de contestation (`PanneauContestation`, l.637-646) se monte sous la date (`ContestationPanneau`,
/// identifiants `contestation-ouvrir-<presenceId>`, `contestation-statut-<presenceId>`…) ; bouton décidé par le serveur,
/// aucun texte de délai (HARD STOP n°4, Q9, D12). Sans `mission_id` lisible, rien n'est monté.
struct PresenceValideeRow: View {
    let presence: PresenceLue
    let etablissement: EtablissementSummary?
    let session: SessionStore
    let snapshot: SessionSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    if let intitule = presence.mission?.intitule {
                        Text(intitule)
                            .font(JoleneFont.callout.weight(.semibold))
                            .foregroundStyle(JoleneColor.midnight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let nom = etablissement?.nom, !nom.isEmpty {
                        Text(nom)
                            .font(JoleneFont.caption)
                            .foregroundStyle(JoleneColor.bubblegum)
                    }
                }
                Spacer(minLength: JoleneSpacing.sm)
                JoleneBadge(LibellesWeb.ListePresences.validee, tone: .success)
            }
            if let date = LibellesPresences.Liste.dateValidation(presence.valideLe) {
                Text(date)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
            }
            if let missionId = presence.missionId {
                ContestationPanneau(presenceId: presence.id, missionId: missionId, valideLe: presence.valideLe,
                                    session: session, snapshot: snapshot)
                    .id(presence.id + (presence.valideLe ?? ""))
            }
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: JoleneRadius.card).strokeBorder(JoleneColor.rose100, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("presence-validee-\(presence.id)")
    }
}
