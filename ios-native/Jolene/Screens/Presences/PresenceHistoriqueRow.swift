import SwiftUI
import JoleneCore
import JoleneDesign

/// Ligne de l'onglet Historique (`PresencesSoignant.tsx` l.662-758) : intitulé, établissement, date de la mission,
/// badge Validée / Non validée, arrivée, départ et méthode, heures travaillées (segments EFFECTIF fermés d'abord,
/// `ResumeLignePresence`), et pour une ligne reconstruite depuis les segments, l'avertissement du web et « Voir ou
/// signaler un litige ». Textes : `LibellesWeb.LignePresence`, `LibellesPresences.Ligne`.
///
/// Écarts consignés : le code de pointage de la présence (« Code : … », l.722-726) n'est pas affiché (aucune colonne
/// `code_*` n'est lue, gap B1-ter) ; « Détail » (l.695-698) et la ligne elle-même ouvrent le détail natif à T5a, d'ici
/// là le renvoi web `/soignant/presences/mission/:id` ; « Voir ou signaler un litige » renvoie vers `/soignant/litiges`
/// (lot 4). Ces renvois ne sont rendus qu'avec le présentateur injecté par T10 : jamais un bouton sans effet.
/// Point d'extension T5b : le panneau de contestation d'une présence non validée (l.728-738) se monte sous la grille,
/// après le go HARD STOP n°4 de Gabrielle (Q9).
struct PresenceHistoriqueRow: View {
    let ligne: LigneHistoriquePresence
    let mission: MissionDeLigne
    @Environment(\.presentateurRenvoiWeb) private var presentateurRenvoiWeb

    var body: some View {
        let resume = ligne.resume
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                    if let intitule = mission.intitule {
                        Text(intitule)
                            .font(JoleneFont.callout.weight(.semibold))
                            .foregroundStyle(JoleneColor.midnight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    LigneEtablissement(texte: LibellesPresences.Liste.etablissement(ligne.etablissement))
                    if let date = LibellesPresences.Ligne.dateMission(mission.debutLe) {
                        HStack(spacing: JoleneSpacing.xs) {
                            Image(systemName: "calendar")
                                .accessibilityHidden(true)
                            Text(date)
                        }
                        .font(JoleneFont.caption)
                        .foregroundStyle(JoleneColor.bubblegum)
                    }
                }
                Spacer(minLength: JoleneSpacing.sm)
                VStack(alignment: .trailing, spacing: JoleneSpacing.xs) {
                    if ligne.valideParEtablissement {
                        JoleneBadge(LibellesWeb.LignePresence.badgeValidee, tone: .success)
                    } else {
                        JoleneBadge(LibellesWeb.LignePresence.badgeNonValidee, tone: .warning)
                    }
                    detail
                }
            }
            grille(resume)
            if ligne.origineEffectifsSansPresence {
                reconstruite
            }
        }
        .padding(JoleneSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.cloud)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("presence-historique-\(ligne.id)")
    }

    private func grille(_ resume: ResumeLignePresence) -> some View {
        let web = LibellesWeb.LignePresence.self
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .topLeading)], alignment: .leading,
                         spacing: JoleneSpacing.sm) {
            cellule(web.arrivee, valeur: LibellesPresences.Ligne.horodatage(resume.arrivee),
                    methode: LibellesPresences.Ligne.methode(ligne.methodeArrivee))
            cellule(web.depart, valeur: LibellesPresences.Ligne.horodatage(resume.depart),
                    methode: LibellesPresences.Ligne.methode(ligne.methodeDepart))
            cellule(web.heures, valeur: LibellesPresences.Ligne.heures(resume.heures), methode: nil)
        }
        .padding(JoleneSpacing.sm)
        .background(JoleneColor.lavender)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
    }

    private func cellule(_ titre: String, valeur: String, methode: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: JoleneSpacing.xs) {
                Text(titre)
                    .font(JoleneFont.caption.weight(.medium))
                    .foregroundStyle(JoleneColor.midnight)
                Text(valeur)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
            }
            if let methode {
                Text(methode)
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.bubblegum)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reconstruite: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
            Text(LibellesWeb.LignePresence.releveReconstruit)
                .font(JoleneFont.caption)
                .foregroundStyle(JoleneColor.bubblegum)
                .fixedSize(horizontal: false, vertical: true)
            if let presentateurRenvoiWeb, let route = PresencesRenvois.litiges {
                Button(LibellesWeb.LignePresence.voirOuSignalerLitige) { presentateurRenvoiWeb.presenter(route) }
                    .font(JoleneFont.callout.weight(.semibold))
                    .foregroundStyle(JoleneColor.rose800)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("presence-historique-litige-\(ligne.id)")
            }
        }
        .padding(JoleneSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.butter100)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
    }

    @ViewBuilder private var detail: some View {
        if let presentateurRenvoiWeb, let missionId = ligne.missionId, let route = PresencesRenvois.detail(missionId: missionId) {
            Button {
                presentateurRenvoiWeb.presenter(route)
            } label: {
                HStack(spacing: JoleneSpacing.xs) {
                    Image(systemName: "eye")
                        .accessibilityHidden(true)
                    Text(LibellesWeb.LignePresence.detail)
                }
                .font(JoleneFont.caption.weight(.semibold))
                .foregroundStyle(JoleneColor.rose800)
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("presence-historique-detail-\(ligne.id)")
        }
    }
}
