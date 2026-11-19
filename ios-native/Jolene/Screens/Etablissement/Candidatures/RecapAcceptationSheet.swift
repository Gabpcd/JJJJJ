import SwiftUI
import JoleneCore
import JoleneDesign

/// Récapitulatif d'acceptation d'une candidature (lot 5, T6), port de la boîte « Confirmer l’acceptation » de
/// `ListeCandidatures.tsx` (l.531-608) sur `ConfirmationSheet` : candidat (nom à l'initiale) et intitulé, nombre de
/// créneaux et total d'heures dérivés des instants relus, liste des créneaux (`SlotList`), note du web, alerte (planning
/// modifié, refus serveur verbatim). Fermeture et confirmation interdites pendant l'envoi ; confirmation désactivée sans
/// créneau. Aucune case juridique (cadre étudiant renvoyé au web, D10) ; aucun statut d'internat.
///
/// Identifiants : `etab-recap` (+ `-title`, `-message`, `-confirm`, `-cancel`), `etab-recap-candidat`, `etab-recap-total`,
/// `etab-recap-creneaux` (+ lignes `creneau-<n>`), `etab-recap-note`, `etab-recap-alerte`.
struct RecapAcceptationSheet: View {
    let recap: CandidaturesEtabModel.Recapitulatif
    let intitule: String?
    let enCours: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private typealias P = CandidaturesEtabPresentation

    static let configuration = ConfirmationSheet.Configuration(
        title: CandidaturesEtabPresentation.recapTitre, message: CandidaturesEtabPresentation.recapMessage,
        confirmTitle: CandidaturesEtabPresentation.recapConfirmer, cancelTitle: CandidaturesEtabPresentation.recapAnnuler,
        identifier: "etab-recap")

    var body: some View {
        ConfirmationSheet(Self.configuration, isLoading: enCours, isConfirmEnabled: !recap.creneaux.isEmpty,
                          onCancel: { if ConfirmationSheet.Configuration.canDismiss(isLoading: enCours) { onCancel() } },
                          onConfirm: onConfirm) {
            VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(P.nom(recap.candidature.soignant))
                        .font(JoleneFont.headline)
                        .foregroundStyle(JoleneColor.midnight)
                    if let intitule, !intitule.isEmpty {
                        Text(intitule).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("etab-recap-candidat")
                Text(P.resumeRecap(recap.creneaux))
                    .font(JoleneFont.callout.weight(.semibold))
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityIdentifier("etab-recap-total")
                SlotList(items: items, identifier: "etab-recap-creneaux")
                Text(P.recapNote)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("etab-recap-note")
                if let alerte = recap.alerte {
                    InlineNotice(alerte, tone: .warning, identifier: "etab-recap-alerte", announcesOnAppear: true)
                }
            }
        }
    }

    private var items: [SlotList.Item] {
        recap.creneaux.enumerated().map { index, creneau in
            SlotList.Item(id: "creneau-\(index + 1)", label: P.ligneRecap(creneau) ?? creneau.debut, isPause: false)
        }
    }
}
