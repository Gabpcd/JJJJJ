import SwiftUI
import JoleneCore
import JoleneDesign

/// Contestation d'une présence à valider par l'établissement (lot 5, T8, B9), port du formulaire de
/// `CarteValidation.tsx` (l.266-284) : motif libre (3 caractères au moins après nettoyage, comme
/// `fn_contester_presence`), « Envoyer la contestation ». Le refus du serveur s'affiche tel quel dans la feuille restée
/// ouverte ; le succès n'est annoncé qu'après relecture de `motif_litige`. Aucun texte de délai ni de procédure : la
/// contestation d'une présence déjà validée et les litiges restent sur jolene.app (§1.2).
///
/// Nom distinct de `ContestationSheet` (espace soignant, lot 2). Identifiants : `etab-contestation-feuille`,
/// `etab-contestation-motif`, `etab-contestation-erreur`, `etab-contestation-envoyer`, `etab-contestation-annuler`.
struct ContestationEtabSheet: View {
    @ObservedObject var model: PresencesEtabModel
    @FocusState private var motifActif: Bool

    private typealias P = PresencesEtabPresentation

    var body: some View {
        let enCours = model.enCours != nil
        // Pile de navigation propre à la feuille : sans elle, la barre `placement: .keyboard` de `boutonOKClavier` n'est
        // jamais rendue (aucun « OK » au-dessus du clavier, run 45446351274, iPad portrait et paysage, iOS 26.2 ; reproduit
        // sur iOS 18.6). Même structure que `ContestationSheet` (espace soignant) et les autres feuilles à saisie libre.
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                    Text(P.contestationTitre)
                        .font(JoleneFont.title)
                        .foregroundStyle(JoleneColor.midnight)
                        .accessibilityAddTraits(.isHeader)
                    TextField(P.contestationPlaceholder,
                              text: Binding(get: { model.contestation?.motif ?? "" }, set: { model.saisirMotif($0) }), axis: .vertical)
                        .lineLimit(3...8)
                        .font(.system(size: 16))
                        .focused($motifActif)
                        .boutonOKClavier($motifActif, actif: !enCours)
                        .padding(JoleneSpacing.md)
                        .background(JoleneColor.lavender)
                        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                        .disabled(enCours)
                        .accessibilityLabel(P.contestationTitre)
                        .accessibilityIdentifier("etab-contestation-motif")
                    if let erreur = model.contestation?.erreur {
                        InlineNotice(erreur, tone: .error, identifier: "etab-contestation-erreur", announcesOnAppear: true)
                    } else if model.motifTropCourt {
                        // Revue B8 des textes de la vague D (mineur 8) : le bouton désactivé dit pourquoi, texte du serveur.
                        Text(P.motifTropCourt)
                            .font(JoleneFont.caption)
                            .foregroundStyle(JoleneColor.bubblegum)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("etab-contestation-motif-court")
                    }
                    JoleneButton(P.contestationEnvoyer, style: .destructive, isLoading: enCours) {
                        motifActif = false
                        Task { await model.envoyerContestation() }
                    }
                    .disabled(!model.peutEnvoyerContestation)
                    .accessibilityIdentifier("etab-contestation-envoyer")
                    JoleneButton(P.annuler, style: .secondary) { model.annulerContestation() }
                        .disabled(enCours)
                        .accessibilityIdentifier("etab-contestation-annuler")
                }
                .padding(JoleneSpacing.xl)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(JoleneColor.cloud.ignoresSafeArea())
        }
        .interactiveDismissDisabled(enCours)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etab-contestation-feuille")
    }
}
