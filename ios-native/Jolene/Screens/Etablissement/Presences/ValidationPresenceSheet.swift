import SwiftUI
import JoleneCore
import JoleneDesign

/// Validation d'une présence avec sa note (lot 5, T8, B9), port de la boîte « Noter … pour valider » de
/// `PresencesEtablissement.tsx` (l.617-649) : note de 1 à 5 obligatoire en un toucher (`StarRating`), puis « Valider et
/// noter ». La feuille ne décide rien : `PresencesEtabModel` relit les créneaux, envoie une seule validation, et ne
/// ferme la feuille qu'après l'issue ; bouton et fermeture sont neutralisés pendant l'envoi. Aucun montant.
///
/// Identifiants : `etab-validation-feuille`, `etab-validation-titre`, `etab-presence-note-{1…5}`,
/// `etab-presence-confirmer`, `etab-presence-annuler`.
struct ValidationPresenceSheet: View {
    @ObservedObject var model: PresencesEtabModel

    private typealias P = PresencesEtabPresentation

    var body: some View {
        let note = model.validation?.note ?? 0
        let enCours = model.enCours != nil
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                Text(P.validationTitre(prenom: model.validation?.prenom))
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("etab-validation-titre")
                Text(P.validationMessage)
                    .font(JoleneFont.body)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                StarRating(value: note, label: P.groupeNote, starLabel: { P.etoiles($0) },
                           identifier: { "etab-presence-note-\($0)" }, isEnabled: !enCours) { model.choisirNote($0) }
                    .frame(maxWidth: .infinity)
                JoleneButton(note == 0 ? P.noterPourValider : P.validerEtNoter, style: .primary, isLoading: enCours) {
                    Task { await model.confirmerValidation() }
                }
                .disabled(!model.peutConfirmerValidation)
                .accessibilityIdentifier("etab-presence-confirmer")
                JoleneButton(P.annuler, style: .secondary) { model.annulerValidation() }
                    .disabled(enCours)
                    .accessibilityIdentifier("etab-presence-annuler")
            }
            .padding(JoleneSpacing.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(JoleneColor.cloud.ignoresSafeArea())
        .interactiveDismissDisabled(enCours)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etab-validation-feuille")
    }
}
