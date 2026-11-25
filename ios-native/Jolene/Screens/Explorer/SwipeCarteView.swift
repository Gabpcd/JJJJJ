import SwiftUI
import JoleneCore
import JoleneDesign

/// Carte d'une mission dans le paquet de swipe (lot 4, T3b), port de `CardMissionSwipe.tsx` (« la carte qui vend » :
/// établissement et lieu, puis l'accroche — montant, durée, moment —, planning, étiquettes, « Pourquoi N ? »). Vue de
/// `SwipePresentation` (JoleneCore), qui porte toute la mise en forme ; la vue n'ajoute aucune logique. Valeurs du
/// serveur affichées telles quelles : sans score servi, ni pastille ni « Pourquoi ? » (jamais « 0/100 » fabriqué).
///
/// La carte est montée dans `SwipeCardStack`, dont le geste capte les glissements : elle ne défile pas. Elle se rend
/// donc en deux variantes (`ViewThatFits`) — complète, puis réduite sans planning ni étiquettes quand la hauteur manque
/// (petit écran, grande taille de texte) —, le détail complet passant par la feuille de détail (`swipe-detail`).
/// Un toucher sur la carte ou « Voir le détail » ouvre cette feuille, comme le web.
///
/// Identifiants (enfants de `swipe-card-<missionId>`, exposés par le paquet en mode `.contain`) :
/// `swipe-score-<id>`, `swipe-etablissement-<id>`, `swipe-lieu-<id>`, `swipe-accroche-<id>`, `swipe-duree-<id>`,
/// `swipe-urgent-<id>`, `swipe-paiement-rapide-<id>`, `swipe-planning-<id>`, `swipe-pourquoi-<id>`, `swipe-detail`.
struct SwipeCarteView: View {
    let carte: CarteSwipe
    /// Carte du dessus : seule à rendre le bouton « Voir le détail ». Sur une carte de fond, le même libellé est dessiné
    /// sans contrôle et masqué à l'accessibilité (même apparence, rien d'atteignable par VoiceOver ni XCUITest ; revue
    /// fraîche de la vague D, M1, `DECISIONS_LOT4.md` précision 22).
    var dessus: Bool = true
    let ouvrirDetail: () -> Void

    private static let rayon: CGFloat = 24

    var body: some View {
        ViewThatFits(in: .vertical) {
            contenu(complet: true)
            contenu(complet: false)
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: Self.rayon))
        .overlay(RoundedRectangle(cornerRadius: Self.rayon).strokeBorder(JoleneColor.rose200, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: Self.rayon))
        .onTapGesture(perform: ouvrirDetail)
    }

    private func contenu(complet: Bool) -> some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            entete
            Text(SwipePresentation.etablissement(carte))
                .font(JoleneFont.title)
                .foregroundStyle(JoleneColor.midnight)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("swipe-etablissement-\(carte.id)")
            lieu
            accroche
            Text(SwipePresentation.dureeMoment(carte))
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.rose800)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("swipe-duree-\(carte.id)")
            if complet {
                SlotList(planning: SwipePresentation.planning(carte), identifier: "swipe-planning-\(carte.id)",
                         libelle: MissionPresentation.creneauCandidat, limit: 2, mentionJoursNonTravailles: false)
                etiquettes
            }
            if let score = carte.score, let raisons = SwipePresentation.raisons(carte) {
                (Text(SwipeTextes.pourquoi(score)).bold() + Text(" ") + Text(raisons))
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("swipe-pourquoi-\(carte.id)")
            }
            Spacer(minLength: 0)
            if dessus {
                Button(action: ouvrirDetail) {
                    libelleDetail
                }
                .buttonStyle(.plain)
                .accessibilityHint(SwipePresentation.libelleAccessibilite(carte))
                .accessibilityIdentifier("swipe-detail")
            } else {
                libelleDetail.accessibilityHidden(true)
            }
        }
    }

    /// Libellé « Voir le détail », commun au bouton de la carte du dessus et à son dessin inerte sur une carte de fond.
    private var libelleDetail: some View {
        Text(SwipeTextes.voirDetail)
            .font(JoleneFont.callout.weight(.semibold))
            .foregroundStyle(JoleneColor.rose800)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }

    /// Pastille de score à gauche (rien sans score servi), urgence et paiement rapide à droite.
    private var entete: some View {
        HStack(alignment: .top, spacing: JoleneSpacing.sm) {
            ScoreBadge(score: carte.score, identifier: "swipe-score-\(carte.id)")
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: JoleneSpacing.xs) {
                if carte.mission.record.estUrgente {
                    StatusPill(SwipeTextes.urgent, tone: .warning, identifier: "swipe-urgent-\(carte.id)")
                }
                if SwipePresentation.paiementRapide(carte) {
                    StatusPill(SwipeTextes.paiementRapide, tone: .success, identifier: "swipe-paiement-rapide-\(carte.id)")
                }
            }
        }
    }

    private var lieu: some View {
        HStack(spacing: JoleneSpacing.xs) {
            Image(systemName: "mappin.and.ellipse")
                .accessibilityHidden(true)
            Text(SwipePresentation.lieu(carte))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("swipe-lieu-\(carte.id)")
            Spacer(minLength: 0)
            if let note = SwipePresentation.scoreEtablissement(carte.etablissementScore) {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill").accessibilityHidden(true)
                    Text(note)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("swipe-note-etablissement-\(carte.id)")
            }
        }
        .font(JoleneFont.callout)
        .foregroundStyle(JoleneColor.bubblegum)
    }

    /// L'élément le plus gros de la carte : montant du serveur (ou taux horaire) et son unité.
    private var accroche: some View {
        let accroche = SwipePresentation.accroche(carte)
        return HStack(alignment: .firstTextBaseline, spacing: JoleneSpacing.xs) {
            Text(accroche.montant)
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(JoleneColor.midnight)
            Text(accroche.unite)
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.bubblegum)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accroche.texte)
        .accessibilityIdentifier("swipe-accroche-\(carte.id)")
    }

    /// Profession, service et contrat recherché : en ligne si tout tient, sinon en colonne (jamais tronqués).
    @ViewBuilder private var etiquettes: some View {
        let etiquettes = SwipePresentation.etiquettes(carte)
        if !etiquettes.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: JoleneSpacing.xs) { pastilles(etiquettes) }
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) { pastilles(etiquettes) }
            }
        }
    }

    private func pastilles(_ etiquettes: [String]) -> some View {
        ForEach(Array(etiquettes.enumerated()), id: \.offset) { _, etiquette in
            StatusPill(etiquette, tone: .neutral, size: .sm)
        }
    }
}
