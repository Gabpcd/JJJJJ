import SwiftUI
import JoleneCore
import JoleneDesign

/// Clôture d'un segment ouvert par l'établissement (lot 5, T8, B9), port du repli « oubli de scan / sans téléphone » de
/// `AffichageCodeRotatifEtab.tsx` (l.369-403) : heure de fin réelle, en **heure de Paris** quel que soit le fuseau de
/// l'appareil, bornée à [début du segment ouvert, maintenant] — le serveur ne refuse pas une heure future (D28), le
/// sélecteur ne la propose donc jamais et `ClotureSegment` la refuse avant tout envoi. La saisie est rendue au modèle
/// comme celle du web (`YYYY-MM-DDTHH:mm`, `DateHeureParis.valeurSaisie`) ; refus du serveur dans la feuille, succès
/// seulement après relecture du segment.
///
/// Identifiants : `etab-cloture-feuille`, `etab-cloture-heure`, `etab-cloture-erreur`, `etab-cloture-confirmer`,
/// `etab-cloture-annuler`.
struct ClotureSegmentSheet: View {
    @ObservedObject var model: PresencesEtabModel
    @State private var heure: Date

    init(model: PresencesEtabModel) {
        self.model = model
        // Heure proposée : maintenant, comme le web (`nowLocalInput()`, l.375).
        _heure = State(initialValue: model.cloture?.bornes.fin ?? Date())
    }

    private typealias P = PresencesEtabPresentation

    var body: some View {
        let enCours = model.enCours != nil
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                Text(P.cloturer)
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .accessibilityAddTraits(.isHeader)
                Text(P.clotureMessage)
                    .font(JoleneFont.body)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                if let bornes = model.cloture?.bornes {
                    DatePicker(P.clotureHeure, selection: $heure, in: bornes.debut...bornes.fin,
                               displayedComponents: [.date, .hourAndMinute])
                        .environment(\.timeZone, DateHeureParis.fuseau)
                        .environment(\.locale, Locale(identifier: "fr_FR"))
                        .disabled(enCours)
                        .accessibilityIdentifier("etab-cloture-heure")
                }
                if let erreur = model.cloture?.erreur {
                    InlineNotice(erreur, tone: .error, identifier: "etab-cloture-erreur", announcesOnAppear: true)
                }
                JoleneButton(P.cloturer, style: .primary, isLoading: enCours) {
                    let saisie = DateHeureParis.valeurSaisie(heure)
                    Task { await model.confirmerCloture(saisie: saisie) }
                }
                .disabled(enCours)
                .accessibilityIdentifier("etab-cloture-confirmer")
                JoleneButton(P.annuler, style: .secondary) { model.annulerCloture() }
                    .disabled(enCours)
                    .accessibilityIdentifier("etab-cloture-annuler")
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
        .accessibilityIdentifier("etab-cloture-feuille")
    }
}
