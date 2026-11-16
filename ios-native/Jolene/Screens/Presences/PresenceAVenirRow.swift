import SwiftUI
import JoleneCore
import JoleneDesign

/// Ligne de l'onglet « À venir » (`PresencesSoignant.tsx` l.528-556) : pavé de date du prochain créneau (ou alerte du
/// planning à confirmer), statut, intitulé, établissement et ville, horaire et durée. Textes et assemblages :
/// `LibellesWeb.ListePresences`, `LibellesPresences.Liste`. La ligne n'ouvre pas le détail de la mission (points
/// d'entrée : T5a), comme les blocs de pointage.
struct PresenceAVenirRow: View {
    let ligne: MissionPresenceAVenir<MissionPresenceLue, EtablissementSummary>

    var body: some View {
        HStack(alignment: .center, spacing: JoleneSpacing.md) {
            pave
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                JoleneBadge(LibellesPresences.Liste.statut(ligne.mission.statut), tone: .info)
                if let intitule = ligne.mission.intitule {
                    Text(intitule)
                        .font(JoleneFont.headline)
                        .foregroundStyle(JoleneColor.midnight)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LigneEtablissement(texte: LibellesPresences.Liste.etablissementEtVille(ligne.etablissement))
                if ligne.planningAConfirmer {
                    Text(LibellesWeb.ListePresences.planningAConfirmer)
                        .font(JoleneFont.caption.weight(.medium))
                        .foregroundStyle(JoleneColor.butter700)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let horaire = LibellesPresences.Liste.horaire(debut: ligne.dateAffichage, fin: ligne.prochainCreneau?.fin,
                                                                         dureeHeures: ligne.dureeAffichageHeures) {
                    HStack(spacing: JoleneSpacing.xs) {
                        Image(systemName: "clock")
                            .accessibilityHidden(true)
                        Text(horaire)
                    }
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("presence-avenir-\(ligne.mission.id)")
    }

    @ViewBuilder private var pave: some View {
        if !ligne.planningAConfirmer, let jour = LibellesPresences.Liste.jour(ligne.dateAffichage) {
            VStack(spacing: 0) {
                // `uppercase` du web (l.536), comme le pavé de l'Accueil.
                Text(jour.semaine.uppercased())
                    .font(JoleneFont.caption.weight(.semibold))
                Text(jour.jour)
                    .font(JoleneFont.headline)
                Text(jour.mois)
                    .font(JoleneFont.caption)
            }
            .foregroundStyle(JoleneColor.rose700)
            .frame(minWidth: 52, minHeight: 56)
            .background(JoleneColor.rose100)
            .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
        } else {
            Image(systemName: "exclamationmark.triangle")
                .font(JoleneFont.headline)
                .foregroundStyle(JoleneColor.butter700)
                .frame(minWidth: 52, minHeight: 56)
                .background(JoleneColor.butter100)
                .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
                .accessibilityHidden(true)
        }
    }
}
