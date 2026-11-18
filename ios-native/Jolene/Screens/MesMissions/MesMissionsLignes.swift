import SwiftUI
import JoleneCore
import JoleneDesign

/// Ligne de « Mes missions » : pavé de date (candidatures, à venir), pastilles, intitulé,
/// établissement, horaire ou période, taux ou montant. Chaînes déjà formatées par
/// `MesMissionsPresentation` ; aucune règle ni aucun montant calculé ici.
struct MesMissionLigneVue: View {
    let ligne: MesMissionsPresentation.Ligne

    var body: some View {
        HStack(alignment: .center, spacing: JoleneSpacing.md) {
            if let jour = ligne.jour {
                AccueilPaveDate(jour: jour)
            }
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                if !ligne.badges.isEmpty {
                    // Trois pastilles (« ⏳ En attente de réponse », « ★ Priorité historique », contrat)
                    // ne tiennent pas sur une ligne d'iPhone étroit : empilées si besoin.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: JoleneSpacing.xs) { pastilles }
                        VStack(alignment: .leading, spacing: JoleneSpacing.xs) { pastilles }
                    }
                }
                Text(ligne.titre)
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.midnight)
                    .multilineTextAlignment(.leading)
                Text(ligne.lieu)
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                Text(ligne.horaire)
                    .font(JoleneFont.caption)
                    .foregroundStyle(ligne.horaireAConfirmer ? JoleneColor.butter800 : JoleneColor.midnight)
                if let remuneration = ligne.remuneration {
                    Text(remuneration)
                        .font(JoleneFont.callout.weight(.semibold))
                        .foregroundStyle(JoleneColor.rose700)
                }
                if let montant = ligne.montant {
                    Text(montant)
                        .font(JoleneFont.callout.weight(.bold))
                        .foregroundStyle(JoleneColor.rose700)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var pastilles: some View {
        ForEach(Array(ligne.badges.enumerated()), id: \.offset) { _, badge in
            JoleneBadge(badge.texte, tone: Self.ton(badge.ton))
        }
    }

    static func ton(_ ton: MesMissionsPresentation.TonBadge) -> JoleneBadge.Tone {
        switch ton {
        case .succes: return .success
        case .attention: return .warning
        case .erreur: return .error
        case .info: return .info
        }
    }
}
