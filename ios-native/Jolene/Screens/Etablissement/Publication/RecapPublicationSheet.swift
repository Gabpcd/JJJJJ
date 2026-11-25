import SwiftUI
import JoleneCore
import JoleneDesign

/// Récapitulatif avant publication (lot 5, T9), port de `ModalRecapMission.tsx` réduit au périmètre natif, sur
/// `ConfirmationSheet` : informations de la mission (intitulé, profession, service, mode de sélection, urgence,
/// description), taux saisi (seul montant affiché, D15), durée et liste des créneaux dérivés du brouillon figé.
/// Fermeture et confirmation interdites pendant l'envoi ; confirmation désactivée sans créneau.
///
/// Non portés : coût estimé, frais et TVA (D15), configuration du pointage, mode d'exercice résolu par le serveur.
/// La mention du type de contrat (`PublicationPresentation.mentionContrat`, texte du web à portée juridique) est
/// affichée mot pour mot, texte validé explicitement par la fondatrice le 24/11/2026 (`DECISIONS_LOT5.md`, intégration
/// de la vague D, point 1, référence de la PR) ; si elle redevenait `nil`, `publier-recap-contrat` ne serait pas rendu.
///
/// Identifiants : `publier-recap` (+ `-title`, `-message`, `-confirm`, `-cancel`), `publier-recap-infos`,
/// `publier-recap-contrat`, `publier-recap-taux`, `publier-recap-total`, `publier-recap-creneaux` (lignes
/// `publier-recap-creneau-<n>`, n à partir de 1).
struct RecapPublicationSheet: View {
    let recap: PublicationModel.Recapitulatif
    let enCours: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private typealias P = PublicationPresentation

    static let configuration = ConfirmationSheet.Configuration(
        title: PublicationPresentation.recapTitre, message: PublicationPresentation.recapMessage,
        confirmTitle: PublicationPresentation.recapPublier, cancelTitle: PublicationPresentation.recapModifier,
        identifier: "publier-recap")

    var body: some View {
        ConfirmationSheet(Self.configuration, isLoading: enCours, isConfirmEnabled: !recap.creneaux.isEmpty,
                          onCancel: { if ConfirmationSheet.Configuration.canDismiss(isLoading: enCours) { onCancel() } },
                          onConfirm: onConfirm) {
            VStack(alignment: .leading, spacing: JoleneSpacing.md) {
                informations
                if let mention = P.mentionContrat {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mention.libelle)
                            .font(JoleneFont.callout.weight(.semibold))
                            .foregroundStyle(JoleneColor.midnight)
                        Text(mention.description)
                            .font(JoleneFont.caption)
                            .foregroundStyle(JoleneColor.bubblegum)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("publier-recap-contrat")
                }
                Text("\(P.resumeRecap(creneaux: recap.creneaux.count)) · \(P.recapDuree) \(P.duree(heures: recap.totalHeures))")
                    .font(JoleneFont.callout.weight(.semibold))
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("publier-recap-total")
                SlotList(items: items, identifier: "publier-recap-creneaux", itemPrefix: "publier-recap")
            }
        }
    }

    private var informations: some View {
        let brouillon = recap.brouillon
        return VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            ligne(P.recapIntitule, brouillon.intitule)
            ligne(P.recapProfession, MissionPresentation.professionLabel(brouillon.professionRequise))
            if let service = brouillon.service, !service.isEmpty { ligne(P.service, service) }
            ligne(P.modeSelection, P.recapMode(brouillon.modeAttribution))
            if brouillon.estUrgente { ligne(P.recapUrgence, P.libelleNiveau(brouillon.niveauUrgence)) }
            ligne(P.recapTaux, P.tauxAffiche(brouillon.tauxHoraireBase))
                .accessibilityIdentifier("publier-recap-taux")
            if let description = PublicationPayload.description(brouillon.description) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(P.description).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
                    Text(description)
                        .font(JoleneFont.callout)
                        .foregroundStyle(JoleneColor.midnight)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("publier-recap-infos")
    }

    private func ligne(_ titre: String, _ valeur: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.sm) {
            Text(titre).font(JoleneFont.caption).foregroundStyle(JoleneColor.bubblegum)
            Spacer(minLength: 0)
            Text(valeur)
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.midnight)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var items: [SlotList.Item] {
        recap.creneaux.enumerated().map { index, creneau in
            SlotList.Item(id: "creneau-\(index + 1)", label: P.ligneRecap(creneau) ?? "\(creneau.debut) → \(creneau.fin)", isPause: false)
        }
    }
}
