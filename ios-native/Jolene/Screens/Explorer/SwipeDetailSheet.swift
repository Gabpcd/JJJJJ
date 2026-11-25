import SwiftUI
import JoleneCore
import JoleneDesign

/// Détail d'une carte du paquet de swipe (lot 4, T3b), port de `ModalDetailMissionSwipe.tsx` : établissement,
/// conditions, rémunération, dates et horaires travaillés, « Pourquoi ce match », puis « Suivant » (passer) et
/// « Vérifier et postuler » (récapitulatif exact, jamais un envoi direct). Vue de `SwipePresentation` (JoleneCore).
///
/// Valeurs du serveur affichées telles quelles. Écart assumé avec le web : les lignes qu'il **calcule** côté client
/// (brut de base, cumul des majorations, IFM + ICP, total avant cotisations reconstitué) ne sont pas portées, seules
/// les colonnes servies le sont ; les phrases de délai de versement du web ne sont pas reprises (aucun texte de délai
/// hors de la revue HARD STOP n°4). L'astérisque du net salarié estimé garde sa note, celle de l'Accueil
/// (`AccueilPresentation.noteNetEstime`, verbatim de `NoteNetEstime.tsx`).
///
/// Identifiants : `swipe-detail-feuille` ; `swipe-detail-titre`, `swipe-detail-score`, `swipe-detail-etablissement`,
/// `swipe-detail-condition-<profession|service|tarif|duree>`, `swipe-detail-remuneration`, `swipe-detail-planning`,
/// `swipe-detail-raison-<clé>`, `swipe-detail-postuler`, `swipe-detail-suivant`.
struct SwipeDetailSheet: View {
    let carte: CarteSwipe
    /// Une action est en vol sur le paquet : les deux boutons attendent.
    let occupe: Bool
    let onSuivant: () -> Void
    let onPostuler: () -> Void

    var body: some View {
        let planning = SwipePresentation.planning(carte)
        ScrollView {
            VStack(alignment: .leading, spacing: JoleneSpacing.lg) {
                Text(carte.mission.record.intitule)
                    .font(JoleneFont.title)
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("swipe-detail-titre")
                HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                    ScoreBadge(score: carte.score, style: .detail, identifier: "swipe-detail-score")
                    Spacer(minLength: 0)
                    if carte.mission.record.estUrgente { StatusPill(SwipeTextes.urgent, tone: .warning, size: .sm) }
                    if SwipePresentation.paiementRapide(carte) { StatusPill(SwipeTextes.paiementRapide, tone: .success, size: .sm) }
                }
                bloc(SwipeTextes.etablissement) { etablissement }
                bloc(SwipeTextes.conditions) {
                    ForEach(SwipePresentation.conditions(carte)) { ligne in
                        self.ligne(ligne, identifiant: "swipe-detail-condition-\(ligne.id)")
                    }
                }
                if let remuneration = SwipePresentation.remuneration(carte) {
                    bloc(remuneration.libelle) { self.remuneration(remuneration) }
                }
                bloc(SwipeTextes.datesEtHoraires) {
                    SlotList(planning: planning, identifier: "swipe-detail-planning", libelle: MissionPresentation.creneauCandidat)
                }
                let raisons = SwipePresentation.raisonsDetail(carte)
                if !raisons.isEmpty {
                    bloc(SwipeTextes.pourquoiCeMatch) {
                        ForEach(raisons) { raison in
                            self.ligne(raison, identifiant: "swipe-detail-raison-\(raison.id)")
                        }
                    }
                }
                VStack(spacing: JoleneSpacing.sm) {
                    JoleneButton(SwipeTextes.verifierEtPostuler, action: onPostuler)
                        .disabled(!planning.exact || occupe)
                        .accessibilityIdentifier("swipe-detail-postuler")
                    JoleneButton(SwipeTextes.suivant, style: .secondary, action: onSuivant)
                        .disabled(occupe)
                        .accessibilityIdentifier("swipe-detail-suivant")
                }
                .padding(.top, JoleneSpacing.sm)
            }
            .padding(JoleneSpacing.xl)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(JoleneColor.lavender.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("swipe-detail-feuille")
    }

    private var etablissement: some View {
        HStack(alignment: .top, spacing: JoleneSpacing.sm) {
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                Text(SwipePresentation.etablissement(carte))
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.midnight)
                    .fixedSize(horizontal: false, vertical: true)
                Text(SwipePresentation.lieu(carte))
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let note = SwipePresentation.scoreEtablissementDetail(carte.etablissementScore) {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill").accessibilityHidden(true)
                    Text(note)
                }
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.rose800)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("swipe-detail-etablissement")
    }

    @ViewBuilder
    private func remuneration(_ remuneration: SwipePresentation.Remuneration) -> some View {
        if let montant = remuneration.montant {
            Text(montant)
                .font(.system(.title, design: .rounded).weight(.heavy))
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityIdentifier("swipe-detail-remuneration")
        }
        ForEach(remuneration.lignes) { ligne in
            self.ligne(ligne, identifiant: "swipe-detail-montant-\(ligne.id)")
        }
        if remuneration.noteNetEstime {
            Text(AccueilPresentation.noteNetEstime)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("swipe-detail-note-net")
        }
    }

    private func ligne(_ ligne: SwipePresentation.Ligne, identifiant: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.sm) {
            Text(ligne.libelle)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: JoleneSpacing.sm)
            Text(ligne.valeur)
                .font(JoleneFont.callout.weight(.semibold))
                .foregroundStyle(JoleneColor.midnight)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ligne.libelle) : \(ligne.valeur)")
        .accessibilityIdentifier(identifiant)
    }

    private func bloc<Contenu: View>(_ titre: String, @ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            Text(titre)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.midnight)
                .accessibilityAddTraits(.isHeader)
            contenu()
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
    }
}
