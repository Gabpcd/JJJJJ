import SwiftUI
import JoleneCore
import JoleneDesign

/// Ligne mission de l'Accueil : pavé de date du prochain créneau, statut, intitulé, établissement,
/// planning (ou « Planning détaillé à confirmer »). Chaînes déjà formatées par
/// `AccueilPresentation` ; taux horaire = valeur serveur.
struct AccueilMissionLigne: View {
    enum Mode { case prochaine, pourVous }

    let mission: AccueilMission
    let mode: Mode

    var body: some View {
        HStack(alignment: .center, spacing: JoleneSpacing.md) {
            AccueilPaveDate(jour: AccueilPresentation.jour(mission.planning))
            VStack(alignment: .leading, spacing: JoleneSpacing.xs) {
                if mode == .prochaine || mission.ligne.estUrgente {
                    HStack(spacing: JoleneSpacing.xs) {
                        if mode == .prochaine, let statut = mission.ligne.statut {
                            JoleneBadge(AccueilPresentation.statut(statut), tone: .success)
                        }
                        if mission.ligne.estUrgente { JoleneBadge("Urgente", tone: .warning) }
                    }
                }
                Text(mission.ligne.intitule)
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.midnight)
                    .multilineTextAlignment(.leading)
                Text(Self.lieu(mission, mode: mode))
                    .font(JoleneFont.callout)
                    .foregroundStyle(JoleneColor.bubblegum)
                let planning = Self.planning(mission, mode: mode)
                Text(planning)
                    .font(JoleneFont.caption)
                    .foregroundStyle(planning == AccueilPresentation.planningAConfirmer ? JoleneColor.butter800 : JoleneColor.midnight)
                if mode == .pourVous, let remuneration = AccueilPresentation.remuneration(mission.ligne.tauxHoraireBase) {
                    Text(remuneration)
                        .font(JoleneFont.callout.weight(.semibold))
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

    /// Établissement suivi de la ville (prochaines missions) ou du service (missions pour vous), comme le web.
    static func lieu(_ mission: AccueilMission, mode: Mode) -> String {
        let complement = mode == .prochaine ? mission.etablissementVille : mission.ligne.service
        return [mission.etablissementNom, complement].compactMap { $0 }.joined(separator: " · ")
    }

    static func planning(_ mission: AccueilMission, mode: Mode) -> String {
        mode == .prochaine ? AccueilPresentation.planningProchaine(mission.planning) : AccueilPresentation.planningPourToi(mission.planning)
    }

    /// Libellé VoiceOver (et preuve XCUITest) : tout ce que la ligne affiche, dans l'ordre.
    static func texteAccessible(_ mission: AccueilMission, mode: Mode) -> String {
        var parties: [String] = []
        if mode == .prochaine, let statut = mission.ligne.statut { parties.append(AccueilPresentation.statut(statut)) }
        if mission.ligne.estUrgente { parties.append("Urgente") }
        parties += [mission.ligne.intitule, lieu(mission, mode: mode), planning(mission, mode: mode)]
        if mode == .pourVous, let remuneration = AccueilPresentation.remuneration(mission.ligne.tauxHoraireBase) {
            parties.append(remuneration)
        }
        return parties.joined(separator: ", ")
    }
}

/// Pavé de date (`EEE`, `d`, `MMM` du prochain créneau), ou icône d'avertissement sans planning vérifié.
struct AccueilPaveDate: View {
    let jour: AccueilPresentation.Jour?

    var body: some View {
        VStack(spacing: 0) {
            if let jour {
                Text(jour.semaine.uppercased()).font(JoleneFont.caption.weight(.semibold))
                Text(jour.jour).font(JoleneFont.title)
                Text(jour.mois).font(JoleneFont.caption)
            } else {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.butter800)
            }
        }
        .foregroundStyle(JoleneColor.rose800)
        .frame(minWidth: 52, minHeight: 58)
        .padding(.horizontal, JoleneSpacing.xs)
        .background(JoleneColor.rose100)
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.field))
        .accessibilityHidden(true)
    }
}

/// Carte d'une mission proposée (`CarteProposition` : urgence, intitulé, temps restant, période,
/// taux). Accepter ou refuser se fait depuis le détail de la mission (tranche T6b).
struct AccueilPropositionCarte: View {
    let proposition: AccueilProposition
    let restant: String

    var body: some View {
        VStack(alignment: .leading, spacing: JoleneSpacing.sm) {
            HStack(alignment: .top, spacing: JoleneSpacing.sm) {
                if proposition.proposition.mission.estUrgente { JoleneBadge("Urgente", tone: .error) }
                Text(proposition.proposition.mission.intitule)
                    .font(JoleneFont.headline)
                    .foregroundStyle(JoleneColor.midnight)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Text("⏳ \(restant)")
                    .font(JoleneFont.caption.weight(.semibold))
                    .foregroundStyle(JoleneColor.butter800)
            }
            Text(proposition.etablissementNom)
                .font(JoleneFont.callout)
                .foregroundStyle(JoleneColor.bubblegum)
            if let periode = Self.periode(proposition) {
                Label(periode, systemImage: "calendar")
                    .font(JoleneFont.caption)
                    .foregroundStyle(JoleneColor.midnight)
            }
            if let remuneration = AccueilPresentation.remuneration(proposition.proposition.mission.tauxHoraireBase) {
                Text(remuneration)
                    .font(JoleneFont.callout.weight(.semibold))
                    .foregroundStyle(JoleneColor.rose700)
            }
        }
        .padding(JoleneSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JoleneColor.butter100)
        .overlay(RoundedRectangle(cornerRadius: JoleneRadius.card).strokeBorder(JoleneColor.butter700, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: JoleneRadius.card))
        .contentShape(Rectangle())
    }

    /// Période de la mission relue (`MissionPresentation.periode`), absente si la fiche n'a pas pu être relue.
    static func periode(_ proposition: AccueilProposition) -> String? {
        proposition.mission.map(MissionPresentation.periode)
    }

    static func texteAccessible(_ proposition: AccueilProposition, restant: String) -> String {
        var parties: [String] = []
        if proposition.proposition.mission.estUrgente { parties.append("Urgente") }
        parties += [proposition.proposition.mission.intitule, "Expire dans \(restant)", proposition.etablissementNom]
        if let periode = periode(proposition) { parties.append(periode) }
        if let remuneration = AccueilPresentation.remuneration(proposition.proposition.mission.tauxHoraireBase) {
            parties.append(remuneration)
        }
        return parties.joined(separator: ", ")
    }
}
